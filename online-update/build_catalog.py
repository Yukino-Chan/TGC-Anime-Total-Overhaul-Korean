#!/usr/bin/env python3
"""Build a TGCNV/TGO updater ``catalog.json`` from an existing verified release pack.

This module is a pure, offline, read-only-over-the-pack producer:

* It never writes into the release pack (game/source) and it never uploads.
* It only reads the pack and writes ZIP assets plus ``catalog.json`` and
  ``build-report.json`` into a fresh ``--output`` directory, refusing to
  overwrite an existing output directory.  Assets land in
  ``<output>/assets/objects-<sha256>.zip`` and are uploaded by the publisher.
* No network access, no signing keys, no remote deletions: the publisher wraps
  the catalog hash + URL into a signed channel afterwards.

The emitted catalog is canonical (UTF-8, sorted keys, compact separators) so
the publisher can hash and sign the exact bytes.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

# --- fixed policy -----------------------------------------------------------

SCHEMA = 1
# Identifies the updater engine / catalog producer revision.  It is deliberately
# NOT derived from the pack so the catalog stays independent of the client build.
ENGINE_VERSION = "1"  # producer revision, game version comes from manifest

RELEASE_RE = re.compile(r"^TGCNV-([0-9]{8})-([0-9]{6})$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
REPOSITORY_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$")
ASSET_FILENAME_RE = re.compile(r"^objects-[0-9a-f]{64}\.zip$")

GITHUB_DOWNLOAD_PREFIX = "https://github.com/{repository}/releases/download/"
GITHUB_DOWNLOAD_URL = "https://github.com/{repository}/releases/download/{release}/{filename}"

GROUP_MAX_BYTES = 256 * 1024 * 1024
FILE_MAX_BYTES = 2 * 1024 * 1024 * 1024
ZIP_MAX_BYTES = 2 * 1024 * 1024 * 1024

PAYLOAD_DIR = "payload"
MANIFEST_NAME = "manifest.json"
SUMS_NAME = "SHA256SUMS.txt"
METADATA_NAMES = ("Setup.ps1", "Setup.cmd", "Restore.cmd", "Verify.cmd", "설치 안내.txt")
ROOT_FILES = frozenset((MANIFEST_NAME, SUMS_NAME) + METADATA_NAMES)
OPTIONAL_ROOT_FILES = frozenset(("Language.psm1",))

CATALOG_KEYS = frozenset({"schema", "release", "engine_version", "manifest_sha256", "files", "assets"})
FILE_KEYS = frozenset({"path", "bytes", "sha256", "asset"})
ASSET_KEYS = frozenset({"url", "bytes", "sha256"})

_REPARSE_FLAG = 0x400
_RESERVED_DEVICE_NAMES = frozenset(
    ["CON", "PRN", "AUX", "NUL"]
    + ["COM%d" % number for number in range(1, 10)]
    + ["LPT%d" % number for number in range(1, 10)]
)

_READ_CHUNK = 1024 * 1024


# --- small filesystem / validation helpers ----------------------------------


def _stat_no_follow(path: Path):
    try:
        return os.stat(path, follow_symlinks=False)
    except (NotImplementedError, TypeError, ValueError):
        return os.lstat(path)


def _is_link_or_reparse(path: Path) -> bool:
    """True for symlinks, junctions and any other Windows reparse point."""
    if os.path.islink(path):
        return True
    try:
        info = _stat_no_follow(path)
    except OSError:
        return False
    return bool(getattr(info, "st_file_attributes", 0) & _REPARSE_FLAG)


def canonical_path(path, what="path") -> str:
    """Validate a pack-relative forward-slash path and return it unchanged."""
    if not isinstance(path, str) or not path:
        raise ValueError(f"{what}: expected a non-empty string, got {path!r}")
    if path != path.strip():
        raise ValueError(f"{what}: leading/trailing whitespace: {path!r}")
    if any(ord(ch) < 32 or ord(ch) == 127 or ch in '<>"|?*%' for ch in path):
        raise ValueError(f"{what}: control characters are not allowed: {path!r}")
    if "\\" in path:
        raise ValueError(f"{what}: backslash separators are not canonical: {path!r}")
    if path.startswith("/"):
        raise ValueError(f"{what}: absolute path: {path!r}")
    for part in path.split("/"):
        if part in ("", ".", ".."):
            raise ValueError(f"{what}: empty or dot path segment: {path!r}")
        if ":" in part:
            raise ValueError(f"{what}: drive letter or NTFS alternate data stream: {path!r}")
        if part[-1] in (".", " "):
            raise ValueError(f"{what}: segment with a trailing dot or space: {path!r}")
        if part.split(".")[0].upper() in _RESERVED_DEVICE_NAMES:
            raise ValueError(f"{what}: reserved Windows device name: {path!r}")
    return path


def _validate_release(release: str) -> str:
    match = RELEASE_RE.match(release or "")
    if match is None:
        raise ValueError("release name must match TGCNV-YYYYMMDD-HHMMSS, got %r" % (release,))
    try:
        datetime.datetime.strptime(match.group(1) + match.group(2), "%Y%m%d%H%M%S")
    except ValueError:
        raise ValueError("release name is not a valid timestamp: %r" % (release,)) from None
    return release


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(_READ_CHUNK), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _read_json_bytes(raw: bytes, what: str):
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise ValueError(f"{what} is not valid UTF-8: {exc}") from None
    try:
        def unique(pairs):
            d = {}
            for k, v in pairs:
                if k in d:
                    raise ValueError(f"duplicate JSON key: {k}")
                d[k] = v
            return d
        return json.loads(text, object_pairs_hook=unique)
    except json.JSONDecodeError as exc:
        raise ValueError(f"{what} is not valid JSON: {exc}") from None


def no_reparse_ancestors(path):
    for p in (path, *path.parents):
        if _is_link_or_reparse(p):
            raise ValueError(f"reparse ancestor: {p}")


def validate_paths(paths):
    seen, directories = set(), set()
    for path in paths:
        canonical_path(path)
        low = path.casefold()
        if low in seen or low in directories:
            raise ValueError(f"case or directory collision: {path}")
        parts = low.split('/')
        for i in range(1, len(parts)):
            prefix = '/'.join(parts[:i])
            if prefix in seen:
                raise ValueError(f"file ancestor collision: {path}")
            directories.add(prefix)
        seen.add(low)


def allowed_path(path):
    if path in ROOT_FILES | OPTIONAL_ROOT_FILES:
        return True
    p = path.lower().split('/')
    if any(x.startswith('.') or x == '_backups' for x in p):
        return False
    if p[:2] == ['payload', 'game']:
        if len(p) == 3:
            return p[2] in {'lua51.dll','lua51_ori.dll','tgcnv_memory_bridge.dll','tgcnv.exe'}
        if p[2] == 'mod':
            if len(p) == 4:
                return p[3] in {'tgcnv.mod','tgo.mod'}
            if p[3] == 'tgcnv':
                if len(p) == 5:
                    return p[4] in {'settings.txt','tgcnv_extension.json'}
                return p[4] in {'common','decisions','events','gfx','history','interface','inventions','localisation','map','news','poptypes','runtime','sound','technologies','units'}
            if p[3] == 'tgo':
                if len(p) == 5:
                    return p[4] in {'opening_music.md','victoria1_music.md','victoria1_music_manifest.json'}
                return p[4] in {'music','events'}
    return len(p) >= 5 and p[:4] == ['payload','profile','map','cache']


def _walk_pack(pack: Path) -> dict:
    """Map every regular file under ``pack`` to its path; fail on links/reparse."""
    if _is_link_or_reparse(pack):
        raise ValueError(f"pack root is a symlink or reparse point: {pack}")
    no_reparse_ancestors(pack)
    found = {}
    for dirpath, dirnames, filenames in os.walk(pack, followlinks=False):
        base = Path(dirpath)
        for name in list(dirnames):
            child = base / name
            if _is_link_or_reparse(child):
                raise ValueError(f"symlink or reparse point inside pack: {child}")
        for name in filenames:
            child = base / name
            if _is_link_or_reparse(child):
                raise ValueError(f"symlink or reparse point inside pack: {child}")
            if not child.is_file():
                raise ValueError(f"not a regular file inside pack: {child}")
            rel = child.relative_to(pack).as_posix()
            canonical_path(rel, what="pack file path")
            if rel in found:
                raise ValueError(f"duplicate pack path: {rel}")
            found[rel] = child
    validate_paths(found)
    return found


def _snapshot(pack: Path):
    """Return ({rel: {path,bytes,sha256}}, snapshot_sha256) for the whole pack."""
    files = _walk_pack(pack)
    entries = {}
    for rel in sorted(files):
        path = files[rel]
        size = path.stat().st_size
        digest = _sha256_file(path)
        if path.stat().st_size != size:
            raise ValueError(f"file changed while it was being read: {rel}")
        entries[rel] = {"path": path, "bytes": size, "sha256": digest}
    state = hashlib.sha256()
    for rel in sorted(entries):
        entry = entries[rel]
        state.update(rel.encode("utf-8"))
        state.update(b"\x00")
        state.update(str(entry["bytes"]).encode("ascii"))
        state.update(b"\x00")
        state.update(entry["sha256"].encode("ascii"))
        state.update(b"\n")
    return entries, state.hexdigest()


# --- pack verification ------------------------------------------------------


def _validate_manifest(manifest, release, entries, payload_paths):
    if not isinstance(manifest, dict):
        raise ValueError("manifest.json must be a JSON object")
    if manifest.get("schema") != SCHEMA:
        raise ValueError("manifest.json: unsupported schema")
    if manifest.get("release") != release:
        raise ValueError("manifest.json: release does not match the pack folder name")
    listed = manifest.get("files")
    if not isinstance(listed, list) or not listed:
        raise ValueError("manifest.json: files must be a non-empty list")

    declared = {}
    for index, entry in enumerate(listed):
        where = "manifest.json files[%d]" % index
        if not isinstance(entry, dict):
            raise ValueError(f"{where}: must be an object")
        for key in ("path", "bytes", "sha256"):
            if key not in entry:
                raise ValueError(f"{where}: missing {key}")
        rel = canonical_path(entry["path"], what=where + ".path")
        if rel in declared:
            raise ValueError(f"{where}: duplicate path {rel}")
        size = entry["bytes"]
        if not isinstance(size, int) or isinstance(size, bool) or not 0 <= size < FILE_MAX_BYTES:
            raise ValueError(f"{where}: bytes must be a non-negative integer")
        digest = entry["sha256"]
        if not isinstance(digest, str) or SHA256_RE.match(digest) is None:
            raise ValueError(f"{where}: sha256 must be 64 lowercase hex characters")
        declared[rel] = (size, digest)

    declared_paths = set(declared)
    if declared_paths != payload_paths:
        raise ValueError(
            "manifest.json does not describe exactly the files under payload/: missing=%s extra=%s"
            % (sorted(payload_paths - declared_paths)[:5], sorted(declared_paths - payload_paths)[:5])
        )
    for rel, (size, digest) in declared.items():
        actual = entries[rel]
        if actual["bytes"] != size or actual["sha256"] != digest:
            raise ValueError(f"payload entry failed verification: {rel}")
    return declared


def _verify_sums(sums_path: Path, entries) -> dict:
    """SHA256SUMS.txt must cover every pack file except itself, and nothing else.

    That is the six other root files (manifest.json plus the five templates) and
    every payload file; any extra or missing line is a hard failure.
    """
    try:
        text = sums_path.read_bytes().decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise ValueError(f"SHA256SUMS.txt is not valid UTF-8: {exc}") from None

    listed = {}
    for lineno, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            raise ValueError(f"SHA256SUMS.txt line {lineno}: blank lines are not canonical")
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        if match is None:
            raise ValueError(f"SHA256SUMS.txt line {lineno}: expected '<sha256>  <path>'")
        digest, rel = match.group(1), match.group(2)
        canonical_path(rel, what=f"SHA256SUMS.txt line {lineno}")
        if rel == SUMS_NAME:
            raise ValueError("SHA256SUMS.txt must not list itself")
        if rel in listed:
            raise ValueError(f"SHA256SUMS.txt: duplicate entry {rel}")
        if rel not in entries:
            raise ValueError(f"SHA256SUMS.txt: entry is not present in the pack: {rel}")
        if entries[rel]["sha256"] != digest:
            raise ValueError(f"SHA256SUMS.txt: digest mismatch for {rel}")
        listed[rel] = digest

    expected = set(entries) - {SUMS_NAME}
    if set(listed) != expected:
        raise ValueError(
            "SHA256SUMS.txt does not cover exactly the pack contents: missing=%s extra=%s"
            % (sorted(expected - set(listed))[:5], sorted(set(listed) - expected)[:5])
        )
    return listed


# --- previous catalog (strict, fail-closed) ---------------------------------


def _validate_asset_url(url, repository: str, sha256: str) -> str:
    if not isinstance(url, str):
        raise ValueError("asset url must be a string")
    if "?" in url or "#" in url:
        raise ValueError(f"asset url must not carry a query or fragment: {url!r}")
    if repository == "Yukino-Chan/TGC-Anime-Total-Overhaul-Korean" and url == "https://ghcr.io/v2/yukino-chan/tgcnv-patches/blobs/sha256:" + sha256:
        return url
    prefix = GITHUB_DOWNLOAD_PREFIX.format(repository=repository)
    if not url.startswith(prefix):
        raise ValueError(f"asset url is not a release download of {repository}: {url!r}")
    parts = url[len(prefix):].split("/")
    if len(parts) != 2:
        raise ValueError(f"asset url must be <release>/<filename>: {url!r}")
    release_tag, filename = parts
    if _validate_release(release_tag) != release_tag:
        raise ValueError(f"asset url release tag is not a TGCNV release name: {url!r}")
    if ASSET_FILENAME_RE.match(filename) is None:
        raise ValueError(f"asset url filename is not objects-<sha256>.zip: {url!r}")
    if filename != "objects-%s.zip" % sha256:
        raise ValueError(f"asset url filename does not match its sha256: {url!r}")
    return url


def _load_previous_catalog(path: Path, repository: str):
    """Validate a prior catalog against the exact schema this module emits."""
    if not path.is_file():
        raise ValueError(f"previous catalog is not a file: {path}")
    if _is_link_or_reparse(path):
        raise ValueError(f"previous catalog is a symlink or reparse point: {path}")
    document = _read_json_bytes(path.read_bytes(), "previous catalog")
    if not isinstance(document, dict) or set(document) != CATALOG_KEYS:
        raise ValueError("previous catalog: unexpected top-level keys")

    if document["schema"] != SCHEMA:
        raise ValueError("previous catalog: unsupported schema")
    release = document["release"]
    if not isinstance(release, str) or RELEASE_RE.match(release) is None:
        raise ValueError("previous catalog: invalid release name")
    _validate_release(release)
    engine_version = document["engine_version"]
    if not isinstance(engine_version, str) or not engine_version:
        raise ValueError("previous catalog: invalid engine_version")
    manifest_sha = document["manifest_sha256"]
    if not isinstance(manifest_sha, str) or SHA256_RE.match(manifest_sha) is None:
        raise ValueError("previous catalog: invalid manifest_sha256")

    raw_assets = document["assets"]
    if not isinstance(raw_assets, dict):
        raise ValueError("previous catalog: assets must be an object")
    assets = {}
    for asset_id, stored in raw_assets.items():
        if not isinstance(asset_id, str) or SHA256_RE.match(asset_id) is None:
            raise ValueError(f"previous catalog: invalid asset id {asset_id!r}")
        if not isinstance(stored, dict) or set(stored) != ASSET_KEYS:
            raise ValueError(f"previous catalog: asset {asset_id} has unexpected keys")
        if stored["sha256"] != asset_id:
            raise ValueError(f"previous catalog: asset {asset_id} sha256 mismatch")
        size = stored["bytes"]
        if not isinstance(size, int) or isinstance(size, bool) or not 0 < size < ZIP_MAX_BYTES:
            raise ValueError(f"previous catalog: asset {asset_id} bytes must be a positive integer")
        _validate_asset_url(stored["url"], repository, asset_id)
        assets[asset_id] = {"url": stored["url"], "bytes": size, "sha256": asset_id}

    raw_files = document["files"]
    if not isinstance(raw_files, list) or not raw_files:
        raise ValueError("previous catalog: files must be a non-empty list")
    previous = {}
    order = []
    for index, entry in enumerate(raw_files):
        where = "previous catalog files[%d]" % index
        if not isinstance(entry, dict) or set(entry) != FILE_KEYS:
            raise ValueError(f"{where}: unexpected keys")
        rel = canonical_path(entry["path"], what=where + ".path")
        size = entry["bytes"]
        if not isinstance(size, int) or isinstance(size, bool) or not 0 <= size < FILE_MAX_BYTES:
            raise ValueError(f"{where}: bytes must be a non-negative integer")
        digest = entry["sha256"]
        if not isinstance(digest, str) or SHA256_RE.match(digest) is None:
            raise ValueError(f"{where}: invalid sha256")
        asset_id = entry["asset"]
        if not isinstance(asset_id, str) or asset_id not in assets:
            raise ValueError(f"{where}: asset is not declared in assets")
        if rel in previous:
            raise ValueError(f"previous catalog: duplicate path {rel}")
        previous[rel] = (size, digest, asset_id)
        order.append(rel)
    validate_paths(previous)
    if len(previous) > 100000 or sum(v[0] for v in previous.values()) > 10*1024**3:
        raise ValueError("previous catalog limits")
    if not ROOT_FILES.issubset(previous) or previous['manifest.json'][1] != manifest_sha:
        raise ValueError("previous catalog metadata")
    if any(not allowed_path(p) for p in previous):
        raise ValueError("previous catalog path scope")
    if order != sorted(order):
        raise ValueError("previous catalog: files must be sorted by path")
    if {value[2] for value in previous.values()} != set(assets):
        raise ValueError("previous catalog: assets contains entries no file references")
    return previous, assets


# --- asset building ---------------------------------------------------------


def _group_members(members):
    """Split new/changed files into ZIP groups.

    Metadata root files are never mixed with payload files.  Payload groups are
    capped at GROUP_MAX_BYTES of raw member bytes, except that a single member
    larger than the cap keeps its own group (individual size is checked against
    FILE_MAX_BYTES separately).
    """
    metadata = sorted(
        (member for member in members if not member["path"].startswith(PAYLOAD_DIR + "/")),
        key=lambda member: member["path"],
    )
    payload = sorted(
        (member for member in members if member["path"].startswith(PAYLOAD_DIR + "/")),
        key=lambda member: member["path"],
    )
    groups = []
    if metadata:
        if sum(m["bytes"] for m in metadata) > GROUP_MAX_BYTES:
            raise ValueError("metadata exceeds limit")
        groups.append(metadata)
    current = []
    total = 0
    for member in payload:
        if current and total + member["bytes"] > GROUP_MAX_BYTES:
            groups.append(current)
            current = []
            total = 0
        current.append(member)
        total += member["bytes"]
    if current:
        groups.append(current)
    return groups


def _finalize_asset(tmp_dir: Path, index: int, members):
    """Write, verify, hash and rename one ZIP asset; return its descriptor."""
    for member in members:
        if member["bytes"] >= FILE_MAX_BYTES:
            raise ValueError(f"refusing to publish a file of 2 GiB or more: {member['path']}")

    staged = tmp_dir / ("asset-%04d.zip.part" % index)
    ordered = sorted(members, key=lambda member: member["path"])
    with zipfile.ZipFile(
        staged, "w", zipfile.ZIP_DEFLATED, compresslevel=9, allowZip64=True
    ) as archive:
        for member in ordered:
            info = zipfile.ZipInfo(member["path"], date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 0
            info.external_attr = 0o644 << 16
            with open(member["source"], "rb") as source, archive.open(info, "w") as sink:
                shutil.copyfileobj(source, sink, _READ_CHUNK)

    expected = [member["path"] for member in ordered]
    with zipfile.ZipFile(staged) as archive:
        if archive.namelist() != expected:
            raise ValueError("asset does not contain exactly the expected members")
        for member in ordered:
            if archive.getinfo(member["path"]).file_size != member["bytes"]:
                raise ValueError(f"asset member size mismatch: {member['path']}")
            with archive.open(member['path']) as src:
                h = hashlib.file_digest(src, 'sha256').hexdigest()
            if h != member['sha256']:
                raise ValueError(f"asset content drift: {member['path']}")
        if archive.testzip() is not None:
            raise ValueError("asset failed its CRC check")

    size = staged.stat().st_size
    if size >= ZIP_MAX_BYTES:
        raise ValueError("asset is 2 GiB or larger and cannot be published")
    digest = _sha256_file(staged)
    filename = "objects-%s.zip" % digest
    final = tmp_dir / filename
    os.replace(staged, final)
    return {
        "path": final,
        "filename": filename,
        "sha256": digest,
        "bytes": size,
        "members": expected,
    }


# --- public entry point -----------------------------------------------------


def build(pack, repository, output, previous_catalog=None):
    """Build catalog.json plus its ZIP assets for one verified release pack.

    Returns a summary dict (catalog, report, paths and hashes).  Raises on any
    verification failure, and never writes catalog.json unless every input was
    re-verified unchanged after the assets were built.
    """
    pack = Path(pack).absolute()
    output = Path(output).absolute()
    no_reparse_ancestors(output)
    previous_path = None if previous_catalog is None else Path(previous_catalog)

    if not isinstance(repository, str) or REPOSITORY_RE.match(repository) is None:
        raise ValueError("repository must be 'owner/repo'")
    if not pack.is_dir():
        raise ValueError(f"pack directory does not exist: {pack}")
    if _is_link_or_reparse(pack):
        raise ValueError(f"pack directory is a symlink or reparse point: {pack}")
    release = _validate_release(pack.name)
    if os.path.lexists(output):
        raise ValueError(f"output already exists; refusing to overwrite: {output}")

    entries, snapshot_before = _snapshot(pack)

    top_level = {rel.split("/", 1)[0] for rel in entries}
    if not (set(ROOT_FILES) | {PAYLOAD_DIR}).issubset(top_level) or not top_level.issubset(set(ROOT_FILES) | set(OPTIONAL_ROOT_FILES) | {PAYLOAD_DIR}):
        raise ValueError(
            "pack must contain exactly the release root files plus a payload/ tree; found: "
            + ", ".join(sorted(top_level))
        )
    missing_root = sorted(name for name in ROOT_FILES if name not in entries)
    if missing_root:
        raise ValueError(f"pack is missing required files: {missing_root}")
    for rel in sorted(entries):
        if not allowed_path(rel):
            raise ValueError(f"unexpected file in pack: {rel}")

    if len(entries) > 100000 or sum(e["bytes"] for e in entries.values()) > 10*1024**3:
        raise ValueError("pack limits exceeded")
    manifest_raw = (pack / MANIFEST_NAME).read_bytes()
    manifest_sha = hashlib.sha256(manifest_raw).hexdigest()
    manifest = _read_json_bytes(manifest_raw, MANIFEST_NAME)
    engine_version = manifest.get("engine_version")
    if not isinstance(engine_version, str) or not engine_version:
        raise ValueError("game engine version is missing")
    payload_paths = {rel for rel in entries if rel.startswith(PAYLOAD_DIR + "/")}
    if not payload_paths:
        raise ValueError("pack contains no payload files")
    _validate_manifest(manifest, release, entries, payload_paths)
    _verify_sums(pack / SUMS_NAME, entries)
    language_catalog = 'payload/game/mod/TGCNV/runtime/languages/catalog.json'
    if language_catalog in entries and 'Language.psm1' not in entries:
        raise ValueError('Language-enabled packs require Language.psm1.')
    if 'Language.psm1' in (pack / 'Setup.ps1').read_text(encoding='utf-8-sig') and 'Language.psm1' not in entries:
        raise ValueError('Setup imports Language.psm1 but the module is missing.')

    previous = {}
    previous_assets = {}
    if previous_path is not None:
        previous, previous_assets = _load_previous_catalog(previous_path, repository)

    # Plan: reuse a prior asset only for an identical path+bytes+sha256.
    plan = []
    new_members = []
    reused_files = 0
    reused_bytes = 0
    reused_asset_ids = set()
    for rel in sorted(entries):
        entry = entries[rel]
        asset_id = None
        prior = previous.get(rel)
        if prior is not None and prior[0] == entry["bytes"] and prior[1] == entry["sha256"]:
            asset_id = prior[2]
            reused_files += 1
            reused_bytes += entry["bytes"]
            reused_asset_ids.add(asset_id)
        else:
            new_members.append({"path": rel, "bytes": entry["bytes"], "source": entry["path"], "sha256": entry["sha256"]})
        plan.append(
            {"path": rel, "bytes": entry["bytes"], "sha256": entry["sha256"], "asset": asset_id}
        )
    by_path = {item["path"]: item for item in plan}

    groups = _group_members(new_members)
    output.mkdir(parents=True)
    tmp_dir = output / "assets"
    tmp_dir.mkdir()
    try:
        new_assets = {}
        for index, members in enumerate(groups):
            asset = _finalize_asset(tmp_dir, index, members)
            asset["url"] = "https://ghcr.io/v2/yukino-chan/tgcnv-patches/blobs/sha256:" + asset["sha256"]
            new_assets[asset["sha256"]] = asset
            for member in members:
                by_path[member["path"]]["asset"] = asset["sha256"]

        # Re-verify every input after the assets were built; drift aborts the build.
        entries_after, snapshot_after = _snapshot(pack)
        if snapshot_after != snapshot_before or set(entries_after) != set(entries):
            raise RuntimeError(
                "pack file set changed while the catalog was being built; nothing was published"
            )
        for rel, entry in entries.items():
            after = entries_after[rel]
            if after["bytes"] != entry["bytes"] or after["sha256"] != entry["sha256"]:
                raise RuntimeError(
                    f"pack file changed while the catalog was being built: {rel}"
                )

        # Assets dict carries only assets referenced by this catalog.
        assets = {}
        for asset_id in sorted(reused_asset_ids):
            assets[asset_id] = dict(previous_assets[asset_id])
        for asset_id in sorted(new_assets):
            asset = new_assets[asset_id]
            assets[asset_id] = {
                "url": asset["url"],
                "bytes": asset["bytes"],
                "sha256": asset["sha256"],
            }

        referenced = {}
        for item in plan:
            if item["asset"] is None or item["asset"] not in assets:
                raise RuntimeError(f"internal error: no asset for {item['path']}")
            referenced.setdefault(item["asset"], []).append(item["path"])
        for paths in referenced.values():
            paths.sort()

        catalog = {
            "schema": SCHEMA,
            "release": release,
            "engine_version": engine_version,
            "manifest_sha256": manifest_sha,
            "files": [
                {
                    "path": item["path"],
                    "bytes": item["bytes"],
                    "sha256": item["sha256"],
                    "asset": item["asset"],
                }
                for item in plan
            ],
            "assets": {asset_id: assets[asset_id] for asset_id in sorted(assets)},
        }
        catalog_bytes = (
            json.dumps(catalog, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
        ).encode("utf-8")
        catalog_sha = hashlib.sha256(catalog_bytes).hexdigest()

        required_assets = []
        for asset_id in sorted(assets):
            filename = assets[asset_id]["url"].rsplit("/", 1)[-1]
            required_assets.append(
                {
                    "sha256": asset_id,
                    "url": assets[asset_id]["url"],
                    "bytes": assets[asset_id]["bytes"],
                    "filename": filename,
                    "path": "assets/" + filename if asset_id in new_assets else None,
                    "referenced_by_files": referenced.get(asset_id, []),
                }
            )

        report = {
            "schema": SCHEMA,
            "release": release,
            "repository": repository,
            "engine_version": engine_version,
            "previous_catalog": None if previous_path is None else str(previous_path),
            "catalog_sha256": catalog_sha,
            "source_snapshot_sha256": snapshot_before,
            "source_stability_checked": True,
            "catalog_file_count": len(catalog["files"]),
            "payload_bytes": sum(item["bytes"] for item in plan),
            "catalog_json_bytes": len(catalog_bytes),
            "new": {
                "assets": len(new_assets),
                "files": len(new_members),
                "bytes": sum(member["bytes"] for member in new_members),
            },
            "reused": {
                "assets": len(reused_asset_ids),
                "files": reused_files,
                "bytes": reused_bytes,
            },
            "required_remote_assets": required_assets,
        }

        assets_dir = tmp_dir

        report_bytes = (
            json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
        ).encode("utf-8")
        (output / "build-report.json").write_bytes(report_bytes)
        # catalog.json is written last: a partial build is never publishable.
        (output / "catalog.json").write_bytes(catalog_bytes)

        return {
            "catalog": catalog,
            "report": report,
            "catalog_path": str(output / "catalog.json"),
            "report_path": str(output / "build-report.json"),
            "catalog_sha256": catalog_sha,
            "asset_paths": [
                str(assets_dir / new_assets[asset_id]["filename"]) for asset_id in sorted(new_assets)
            ],
        }
    finally:
        pass  # Preserve incomplete output for diagnosis; catalog is the readiness marker.


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Build a TGCNV/TGO updater catalog.json from a verified release pack."
    )
    parser.add_argument("--pack", required=True, type=Path, help="existing verified release folder")
    parser.add_argument("--repository", required=True, help="owner/repo hosting the release assets")
    parser.add_argument("--output", required=True, type=Path, help="fresh output directory")
    parser.add_argument(
        "--previous-catalog",
        default=None,
        type=Path,
        help="optional prior catalog.json whose unchanged assets may be reused",
    )
    args = parser.parse_args(argv)

    result = build(args.pack, args.repository, args.output, args.previous_catalog)
    print(
        json.dumps(
            {
                "catalog": result["catalog_path"],
                "catalog_sha256": result["catalog_sha256"],
                "assets": result["asset_paths"],
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
