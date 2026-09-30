"""publish_ghcr.py -- publish one verified update to GHCR, GitHub Releases and the feed branch.

Inputs produced by the existing orchestrator (build_catalog / make_client):
    out/catalog.json              catalog schema 1; object asset URLs are fixed GHCR blobs
    out/channel/channel.json      one RSA-signed channel envelope (opaque here)
    out/TGC-Online-Installer.zip  bootstrap installer attached to the release

Phase order. A failure in any phase leaves every later phase untouched:
    1. preflight        gh identity, public fork, required inputs, release name, tag
    2. store scan       locate objects-<id>.zip under the given store roots, hash/size
    3. registry         resumable blob upload + immutable per-release manifest push
    4. anonymous gate   head/get manifest plus HEAD on every blob, before any release
    5. release          draft only if absent; validated asset update; publish
    6. feed             atomic channel.json commit on ``update-feed`` + raw URL check
    7. publication.json written only after every phase and the public feed check pass

Notes on intentional constraints:
  * OCI versions are never overwritten; a colliding tag aborts instead.
  * Old releases are never deleted. That is a separate one-time migration gate.
  * No credential or token value is read, printed or persisted by this module. The
    only credential use is delegated to ghcr_store.Registry (``gh auth token``) and
    to the ``gh`` CLI itself. Public fetches carry no credentials and no redirects
    outside GitHub.

Catalogs are validated against the exact production schema before upload.
"""

from __future__ import annotations

import base64
import datetime
import hashlib
import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import ghcr_store
import build_catalog as builder

__all__ = ["publish", "PublishError", "PublicUnavailable"]

REPOSITORY = "Yukino-Chan/TGC-Anime-Total-Overhaul-Korean"
GHCR_NAMESPACE = "yukino-chan/tgcnv-patches"
PARENT_REPOSITORY = "The-Grand-Combination/The-Grand-Combo"
EXPECTED_LOGIN = "Yukino-Chan"

INSTALLER_RELEASE_TAG = "installer"
INSTALLER_ASSET_NAME = "TGC-Online-Installer.zip"
INSTALLER_RELEASE_NAME = "TGC Online Installer"

FEED_BRANCH = "update-feed"
FEED_BASE_BRANCH = "master"
FEED_PATH = "channel.json"
RAW_CHANNEL_URL = (
    "https://raw.githubusercontent.com/"
    + REPOSITORY
    + "/"
    + FEED_BRANCH
    + "/"
    + FEED_PATH
)

PUBLICATION_NAME = "publication.json"

MAX_BOOTSTRAP_BYTES = 512 * 1024 * 1024
MAX_CHANNEL_BYTES = 4 * 1024 * 1024
MAX_REDIRECTS = 5
ASSET_VERIFY_ATTEMPTS = 2
FEED_VERIFY_ATTEMPTS = 6
FEED_VERIFY_BASE_DELAY = 2.0
FEED_CAS_ATTEMPTS = 4

_OBJECT_NAME_RE = re.compile(r"^objects-(?P<oid>[A-Za-z0-9][A-Za-z0-9._-]{0,127})\.zip$")
_TOKEN_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
_TAG_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{0,127}$")
_RELEASE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$")
_HEX40_RE = re.compile(r"^[0-9a-f]{40}$")
_SHA256_RE = re.compile(r"^(?:sha256:)?[0-9a-f]{64}$")
_HEX256_RE = re.compile(r"^[0-9a-f]{64}$")
_GHCR_BLOB_RE = re.compile(r"^https://ghcr\.io/v2/(?P<ns>[^/]+/[^/]+)/blobs/sha256:(?P<hex>[0-9a-f]{64})$")
_GH_STATUS_RE = re.compile(r"\(HTTP (\d{3})\)")
_SECRET_RE = re.compile(r"(?:gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|Bearer\s+[A-Za-z0-9._-]{16,})")

_ID_KEYS = {"id", "object", "objectid", "asset", "assetid", "archive", "archiveid", "file", "name"}
_DIGEST_KEYS = {"sha256", "digest", "hash", "checksum", "sha256hex", "blobdigest"}
_SIZE_KEYS = {"bytes", "size", "length", "bytelen", "sizebytes", "filesize"}

_REDIRECT_CODES = (301, 302, 303, 307, 308)


class PublishError(RuntimeError):
    """Any failure that must abort publication before later phases run."""


class PublicUnavailable(PublishError):
    """The pushed artifact is not anonymously readable; nothing downstream changed."""


# --------------------------------------------------------------------------- gh


def _redact(text):
    return _SECRET_RE.sub("<redacted>", text or "")


def _gh_run(gh, args, *, stdin_bytes=None, cwd=None, timeout=180):
    argv = [str(gh)] + list(args)
    kwargs = {"capture_output": True, "timeout": timeout}
    if cwd is not None:
        kwargs["cwd"] = str(cwd)
    if stdin_bytes is None:
        kwargs["stdin"] = subprocess.DEVNULL
    else:
        kwargs["input"] = stdin_bytes
    try:
        return subprocess.run(argv, **kwargs)
    except (OSError, subprocess.SubprocessError):
        raise PublishError("the gh CLI could not be executed") from None


def _gh_status(proc):
    match = _GH_STATUS_RE.search(proc.stderr.decode("utf-8", "replace"))
    return int(match.group(1)) if match else None


def _gh_failure(proc, what):
    status = _gh_status(proc)
    lines = _redact(proc.stderr.decode("utf-8", "replace")).strip().splitlines()
    detail = lines[0] if lines else "no detail"
    suffix = " (HTTP %d)" % status if status is not None else ""
    return PublishError("%s failed%s: %s" % (what, suffix, detail))


def _gh_call(gh, args, *, stdin_obj=None, allow_status=(), timeout=180):
    """Run ``gh api ...``; JSON payloads go through stdin, never through argv."""
    payload = None
    if stdin_obj is not None:
        payload = json.dumps(stdin_obj, ensure_ascii=True).encode("utf-8")
    proc = _gh_run(gh, args, stdin_bytes=payload, timeout=timeout)
    if proc.returncode != 0:
        if _gh_status(proc) in allow_status:
            return None
        raise _gh_failure(proc, "the gh API call")
    out = proc.stdout.decode("utf-8", "replace").strip()
    if not out:
        return None
    try:
        return json.loads(out)
    except ValueError:
        raise PublishError("the gh API returned an unexpected response") from None


def _gh_text(gh, args, *, what, timeout=60):
    proc = _gh_run(gh, args, timeout=timeout)
    if proc.returncode != 0:
        raise _gh_failure(proc, what)
    return proc.stdout.decode("utf-8", "replace").strip()


# ----------------------------------------------------------------- public fetch


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _host_allowed(host):
    if not host:
        return False
    host = host.lower()
    return host == "github.com" or host == "raw.githubusercontent.com" or host.endswith(".githubusercontent.com")


def _fetch_public_bytes(url, *, max_bytes, expected_sha256=None, expected_size=None):
    """Bounded, credential-free HTTPS GET with a manual redirect whitelist."""
    opener = urllib.request.build_opener(_NoRedirect)
    current = url
    redirects = 0
    while True:
        parts = urllib.parse.urlsplit(current)
        if parts.scheme != "https" or not _host_allowed(parts.hostname) or parts.username or parts.password or parts.port not in (None,443) or parts.fragment:
            raise PublishError("refusing to fetch from an unapproved public host")
        request = urllib.request.Request(
            current,
            method="GET",
            headers={"User-Agent": "tgc-update-publisher", "Accept": "application/octet-stream", "Cache-Control":"no-cache"},
        )
        try:
            with opener.open(request, timeout=60) as response:
                status = response.status
                data = response.read(max_bytes + 1)
        except urllib.error.HTTPError as exc:
            if exc.code in _REDIRECT_CODES:
                target = exc.headers.get("Location") if exc.headers else None
                code = exc.code
                exc.close()
                if not target:
                    raise PublishError("public fetch redirect carried no location") from None
                redirects += 1
                if redirects > MAX_REDIRECTS:
                    raise PublishError("public fetch exceeded the redirect limit") from None
                current = urllib.parse.urljoin(current, target)
                continue
            code = exc.code
            exc.close()
            raise PublishError("public fetch failed (HTTP %d)" % code) from None
        except (urllib.error.URLError, TimeoutError, OSError):
            raise PublishError("public fetch failed (network)") from None
        if status != 200:
            raise PublishError("public fetch failed (HTTP %d)" % status)
        if len(data) > max_bytes:
            raise PublishError("public fetch exceeded the size limit")
        if expected_size is not None and len(data) != int(expected_size):
            raise PublishError("public fetch size mismatch")
        if expected_sha256 is not None and hashlib.sha256(data).hexdigest() != expected_sha256:
            raise PublishError("public fetch hash mismatch")
        return data


def _fetch_public_with_retries(url, *, max_bytes, expected_sha256=None, expected_size=None,
                               attempts=1, base_delay=1.0, cap=16.0):
    attempts = max(1, int(attempts))
    last = None
    for attempt in range(attempts):
        try:
            return _fetch_public_bytes(
                url,
                max_bytes=max_bytes,
                expected_sha256=expected_sha256,
                expected_size=expected_size,
            )
        except PublishError as exc:
            last = exc
            if attempt + 1 >= attempts:
                break
            time.sleep(min(base_delay * (2 ** attempt), cap))
    raise last


# -------------------------------------------------------------------- store scan


def _plan_objects(catalog):
    plan={}
    for oid,asset in catalog['assets'].items():
        if not re.fullmatch('[0-9a-f]{64}',oid) or asset['sha256']!=oid or asset['url']!='https://ghcr.io/v2/'+GHCR_NAMESPACE+'/blobs/sha256:'+oid:
            raise PublishError('Noncanonical registry object in catalog')
        if type(asset['bytes']) is not int or not 0<asset['bytes']<2147483648:
            raise PublishError('Invalid catalog object size')
        plan[oid]={'sha256':oid,'bytes':asset['bytes']}
    if not plan:raise PublishError('No assets in catalog')
    return plan


def _within(base, path):
    try:
        base_abs = os.path.abspath(str(base))
        path_abs = os.path.abspath(str(path))
        return os.path.commonpath([base_abs, path_abs]) == base_abs
    except ValueError:
        return False


def _walk_files(base):
    """Recursive listing that never follows symlinks/junctions out of the root."""
    stack = [base]
    while stack:
        current = stack.pop()
        try:
            with os.scandir(current) as entries:
                for entry in entries:
                    try:
                        if entry.is_symlink() or getattr(entry.stat(follow_symlinks=False),"st_file_attributes",0)&0x400:
                            continue
                        if entry.is_dir(follow_symlinks=False):
                            stack.append(Path(entry.path))
                        elif entry.is_file(follow_symlinks=False):
                            candidate = Path(entry.path)
                            if _within(base, candidate):
                                yield candidate
                    except OSError:
                        continue
        except OSError:
            raise PublishError("a store root could not be read") from None


def _locate_object_files(roots, plan):
    found = {}
    for root in roots:
        root = Path(root)
        if not root.is_dir():
            raise PublishError("a store root is not a readable directory")
        assets = root / "assets"
        base = assets if assets.is_dir() else root
        for path in _walk_files(base):
            match = _OBJECT_NAME_RE.match(path.name)
            if not match or match.group("oid") not in plan:
                continue
            found.setdefault(match.group("oid"), []).append(path)
    missing = sorted(set(plan) - set(found))
    if missing:
        shown = ", ".join("objects-%s.zip" % oid for oid in missing[:5])
        more = " (+%d more)" % (len(missing) - 5) if len(missing) > 5 else ""
        raise PublishError("store roots are missing %d object archive(s): %s%s" % (len(missing), shown, more))
    return found


def _hash_file(path):
    digest = hashlib.sha256()
    size = 0
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
            size += len(chunk)
    return digest.hexdigest(), size


def _resolve_objects(plan, found):
    resolved = []
    for oid in sorted(plan):
        candidates = sorted(found[oid], key=lambda item: str(item).lower())
        hashed = []
        for path in candidates:
            sha_hex, size = _hash_file(path)
            hashed.append((path, sha_hex, size))
        first_path, first_sha, first_size = hashed[0]
        for _path, sha_hex, size in hashed[1:]:
            if (sha_hex, size) != (first_sha, first_size):
                raise PublishError("store roots contain different files named objects-%s.zip" % oid)
        declared_sha = plan[oid]["sha256"]
        declared_size = plan[oid]["bytes"]
        if declared_sha is not None and declared_sha != first_sha:
            raise PublishError("objects-%s.zip does not match the digest recorded in catalog.json" % oid)
        if declared_size is not None and declared_size != first_size:
            raise PublishError("objects-%s.zip does not match the size recorded in catalog.json" % oid)
        if declared_sha is None:
            print("[store] objects-%s.zip has no digest in catalog.json; validating locally only" % oid)
        resolved.append({
            "oid": oid,
            "path": first_path,
            "digest": "sha256:" + first_sha,
            "sha256": first_sha,
            "bytes": first_size,
        })
    return resolved


# ---------------------------------------------------------------------- registry


def _publish_registry(registry, tag, objects, catalog_path, catalog_sha, catalog_size):
    layers = []
    for item in objects:
        result = registry.upload_file(str(item["path"]), item["digest"], item["bytes"])
        print("[ghcr] %-8s objects-%s.zip (%d bytes)" % (result["status"], item["oid"], item["bytes"]))
        layers.append({
            "mediaType": ghcr_store.ZIP_MEDIA_TYPE,
            "digest": item["digest"],
            "size": item["bytes"],
            "annotations": {"org.opencontainers.image.title": "objects-%s.zip" % item["oid"]},
        })
    catalog_digest = "sha256:" + catalog_sha
    result = registry.upload_file(str(catalog_path), catalog_digest, catalog_size)
    print("[ghcr] %-8s catalog.json (%d bytes)" % (result["status"], catalog_size))
    layers.append({
        "mediaType": ghcr_store.JSON_MEDIA_TYPE,
        "digest": catalog_digest,
        "size": catalog_size,
        "annotations": {"org.opencontainers.image.title": "catalog.json"},
    })
    manifest = registry.push_manifest(tag, layers)
    print("[ghcr] %-8s tag %s (%s)" % (manifest["status"], manifest["tag"], manifest["digest"]))
    return manifest, layers


def _verify_anonymous(registry, tag, manifest_digest, layers):
    hint = (
        "GHCR package '%s' is not anonymously readable and verified yet. Set the package "
        "visibility to public in the GitHub package settings and re-run; no release or feed "
        "change was made." % GHCR_NAMESPACE
    )
    try:
        head = registry.head_manifest(tag)
        if head is None:
            raise PublicUnavailable(hint)
        if head.get("digest") != manifest_digest:
            raise PublicUnavailable(hint)
        fetched = registry.get_manifest(tag)
        if fetched.get("digest") != manifest_digest:
            raise PublicUnavailable(hint)
        for layer in layers:
            if not registry.head_blob(layer["digest"], layer["size"], auth=False):
                raise PublicUnavailable(hint)
    except PublicUnavailable:
        raise
    except ghcr_store.RegistryError:
        raise PublicUnavailable(hint) from None
    print("[ghcr] anonymous manifest and all %d blob heads verified" % len(layers))


# ----------------------------------------------------------------------- release


def _release_by_tag(gh):
    path = "repos/%s/releases/tags/%s" % (REPOSITORY, urllib.parse.quote(INSTALLER_RELEASE_TAG, safe=""))
    return _gh_call(gh, ["api", path], allow_status=(404,))


def _assets_of(gh, release):
    return _gh_call(gh, ["api", "repos/%s/releases/%s/assets" % (REPOSITORY, release.get("id"))]) or []


def _find_asset(gh, release, name):
    for asset in _assets_of(gh, release):
        if isinstance(asset, dict) and asset.get("name") == name:
            return asset
    return None


def _asset_digest(asset):
    value = asset.get("digest")
    if isinstance(value, str) and _SHA256_RE.match(value):
        return value.split(":", 1)[1]
    return None


def _asset_matches(asset, sha_hex, size):
    return _asset_digest(asset) == sha_hex and asset.get("size") == size


def _create_draft_release(gh, notes_text):
    payload = {
        "tag_name": INSTALLER_RELEASE_TAG,
        "name": INSTALLER_RELEASE_NAME,
        "body": notes_text,
        "draft": True,
        "prerelease": False,
    }
    release = _gh_call(
        gh,
        ["api", "--method", "POST", "repos/%s/releases" % REPOSITORY, "--input", "-"],
        stdin_obj=payload,
    )
    if not isinstance(release, dict) or not isinstance(release.get("id"), int):
        raise PublishError("the installer draft release could not be created")
    print("[release] created draft release '%s'" % INSTALLER_RELEASE_TAG)
    return release


def _upload_asset(gh, bootstrap, clobber):
    # gh mishandles absolute paths containing '#WIP', so upload the basename and
    # set the working directory to the folder that actually holds the file.
    args = ["release", "upload", INSTALLER_RELEASE_TAG, bootstrap.name, "--repo", REPOSITORY]
    if clobber:
        args.append("--clobber")
    proc = _gh_run(gh, args, cwd=bootstrap.parent)
    if proc.returncode != 0:
        raise _gh_failure(proc, "gh release upload")


def _public_asset_url(url, sha_hex):
    if len(sha_hex) != 64 or any(c not in '0123456789abcdef' for c in sha_hex):
        raise PublishError('Invalid installer SHA-256')
    parts = urllib.parse.urlsplit(url)
    query = [(k, v) for k, v in urllib.parse.parse_qsl(parts.query) if k != 'sha256']
    query.append(('sha256', sha_hex))
    return urllib.parse.urlunsplit(parts._replace(query=urllib.parse.urlencode(query)))


def _download_public_asset(url, sha_hex, size):
    data = _fetch_public_with_retries(
        _public_asset_url(url, sha_hex),
        max_bytes=MAX_BOOTSTRAP_BYTES,
        expected_sha256=sha_hex,
        expected_size=size,
        attempts=ASSET_VERIFY_ATTEMPTS,
    )
    return len(data)


def _publish_release(gh, bootstrap, notes_text, bootstrap_sha, bootstrap_size):
    asset_url = "https://github.com/%s/releases/download/%s/%s" % (
        REPOSITORY, INSTALLER_RELEASE_TAG, INSTALLER_ASSET_NAME)

    release = _release_by_tag(gh)
    created = False
    if release is None:
        release = _create_draft_release(gh, notes_text)
        created = True
    release_id = release.get("id")
    if not isinstance(release_id, int):
        raise PublishError("the installer release is missing an id")

    if any(a["name"]!=INSTALLER_ASSET_NAME for a in _assets_of(gh,release)):
        raise PublishError("Unexpected asset in stable installer release")
    is_draft = bool(release.get("draft"))
    asset = _find_asset(gh, release, INSTALLER_ASSET_NAME)
    needs_upload = asset is None or not _asset_matches(asset, bootstrap_sha, bootstrap_size)

    public_checked = False
    if asset is not None and not is_draft:
        # Baseline of the bytes we are about to replace: never clobber blind.
        remote_sha = _asset_digest(asset)
        if remote_sha is None:
            raise PublishError("the published installer asset does not expose a sha256 digest")
        _download_public_asset(asset_url, remote_sha, asset.get("size"))
        public_checked = not needs_upload
        print("[release] the currently public installer matches its API digest")

    if needs_upload:
        if asset is None:
            print("[release] attaching %s" % INSTALLER_ASSET_NAME)
        else:
            print("[release] replacing %s (--clobber)" % INSTALLER_ASSET_NAME)
        _upload_asset(gh, bootstrap, clobber=asset is not None)
        release = _release_by_tag(gh) or release
        asset = _find_asset(gh, release, INSTALLER_ASSET_NAME)
        if asset is None:
            raise PublishError("the installer asset is missing after upload")
        remote_sha = _asset_digest(asset)
        if remote_sha is None:
            raise PublishError("The API did not report the required asset digest")
        elif remote_sha != bootstrap_sha or asset.get("size") != bootstrap_size:
            raise PublishError("the uploaded installer does not match the local bootstrap")
    else:
        print("[release] the public installer already matches the local bootstrap; upload skipped")

    patch = {}
    if is_draft:
        patch["draft"] = False
        patch["make_latest"] = "true"
    if notes_text and (release.get("body") or "") != notes_text:
        patch["body"] = notes_text
    if patch:
        _gh_call(
            gh,
            ["api", "--method", "PATCH", "repos/%s/releases/%d" % (REPOSITORY, release_id), "--input", "-"],
            stdin_obj=patch,
        )
        release = _release_by_tag(gh) or release
        if release.get("draft"):
            raise PublishError("the installer release is still a draft after publishing")
        print("[release] the installer release is public")

    if not public_checked:
        _download_public_asset(asset_url, bootstrap_sha, bootstrap_size)
        print("[release] the anonymous installer download matches the local bootstrap")

    return {
        "tag": INSTALLER_RELEASE_TAG,
        "release_id": release_id,
        "asset_name": INSTALLER_ASSET_NAME,
        "asset_url": _public_asset_url(asset_url, bootstrap_sha),
        "canonical_asset_url": asset_url,
        "sha256": bootstrap_sha,
        "bytes": bootstrap_size,
        "draft": bool(release.get("draft")),
        "created": created,
    }


# -------------------------------------------------------------------------- feed


def _ref_sha(ref):
    sha = ((ref or {}).get("object") or {}).get("sha")
    if not isinstance(sha, str) or not _HEX40_RE.match(sha):
        raise PublishError("a git ref returned an unexpected object id")
    return sha


def _tree_blob_sha(gh, tree_sha, path):
    tree = _gh_call(gh, ["api", "repos/%s/git/trees/%s" % (REPOSITORY, tree_sha)])
    if not isinstance(tree, dict):
        raise PublishError("the feed branch tree could not be read")
    for entry in tree.get("tree") or []:
        if isinstance(entry, dict) and entry.get("path") == path and entry.get("type") == "blob":
            sha = entry.get("sha")
            if isinstance(sha, str) and _HEX40_RE.match(sha):
                return sha
            raise PublishError("the feed branch file has an unexpected object id")
    return None


def _blob_bytes(gh, blob_sha):
    blob = _gh_call(gh, ["api", "repos/%s/git/blobs/%s" % (REPOSITORY, blob_sha)])
    if not isinstance(blob, dict):
        raise PublishError("the feed branch file could not be read")
    content = blob.get("content")
    encoding = blob.get("encoding")
    if not isinstance(content, str):
        raise PublishError("the feed branch file could not be read")
    if encoding == "base64":
        try:
            data = base64.b64decode(content)
        except ValueError:
            raise PublishError("the feed branch file could not be decoded") from None
    elif encoding in (None, "utf-8"):
        data = content.encode("utf-8")
    else:
        raise PublishError("the feed branch file uses an unsupported encoding")
    if len(data) > MAX_CHANNEL_BYTES:
        raise PublishError("the feed branch file is unexpectedly large")
    return data


def _feed_commit(gh, channel_bytes, release):
    channel_sha = hashlib.sha256(channel_bytes).hexdigest()
    message = "feed: publish %s channel envelope" % release

    for attempt in range(FEED_CAS_ATTEMPTS):
        ref = _gh_call(gh, ["api", "repos/%s/git/ref/heads/%s" % (REPOSITORY, FEED_BRANCH)], allow_status=(404,))
        creating = ref is None
        if creating:
            base_ref = _gh_call(
                gh,
                ["api", "repos/%s/git/ref/heads/%s" % (REPOSITORY, FEED_BASE_BRANCH)],
                allow_status=(404,),
            )
            if base_ref is None:
                raise PublishError("the feed base branch '%s' does not exist" % FEED_BASE_BRANCH)
            base_sha = _ref_sha(base_ref)
        else:
            base_sha = _ref_sha(ref)

        commit = _gh_call(gh, ["api", "repos/%s/git/commits/%s" % (REPOSITORY, base_sha)])
        base_tree = ((commit or {}).get("tree") or {}).get("sha")
        if not isinstance(base_tree, str) or not _HEX40_RE.match(base_tree):
            raise PublishError("the feed commit tree could not be read")

        current_blob = _tree_blob_sha(gh, base_tree, FEED_PATH)
        if current_blob is not None:
            prior_envelope=_blob_bytes(gh,current_blob)
            old_channel=json.loads(base64.b64decode(json.loads(prior_envelope)['channel'],validate=True))
            new_channel=json.loads(base64.b64decode(json.loads(channel_bytes)['channel'],validate=True))
            if old_channel['sequence']>new_channel['sequence'] or (old_channel['sequence']==new_channel['sequence'] and old_channel['catalog_sha256']!=new_channel['catalog_sha256']):
                raise PublishError('Refusing channel rollback or same-sequence catalog replacement')
        if current_blob is not None and _blob_bytes(gh, current_blob) == channel_bytes:
            print("[feed] %s already matches the signed envelope; no commit created" % FEED_PATH)
            return {
                "branch": FEED_BRANCH,
                "path": FEED_PATH,
                "commit": base_sha,
                "changed": False,
                "sha256": channel_sha,
                "public_url": RAW_CHANNEL_URL,
            }

        blob = _gh_call(
            gh,
            ["api", "--method", "POST", "repos/%s/git/blobs" % REPOSITORY, "--input", "-"],
            stdin_obj={"content": base64.b64encode(channel_bytes).decode("ascii"), "encoding": "base64"},
        )
        blob_sha = (blob or {}).get("sha")
        if not isinstance(blob_sha, str) or not _HEX40_RE.match(blob_sha):
            raise PublishError("the feed blob could not be created")

        tree = _gh_call(
            gh,
            ["api", "--method", "POST", "repos/%s/git/trees" % REPOSITORY, "--input", "-"],
            stdin_obj={
                "base_tree": base_tree,
                "tree": [{"path": FEED_PATH, "mode": "100644", "type": "blob", "sha": blob_sha}],
            },
        )
        tree_sha = (tree or {}).get("sha")
        if not isinstance(tree_sha, str) or not _HEX40_RE.match(tree_sha):
            raise PublishError("the feed tree could not be created")

        new_commit = _gh_call(
            gh,
            ["api", "--method", "POST", "repos/%s/git/commits" % REPOSITORY, "--input", "-"],
            stdin_obj={"message": message, "tree": tree_sha, "parents": [base_sha]},
        )
        new_sha = (new_commit or {}).get("sha")
        if not isinstance(new_sha, str) or not _HEX40_RE.match(new_sha):
            raise PublishError("the feed commit could not be created")

        if creating:
            result = _gh_call(
                gh,
                ["api", "--method", "POST", "repos/%s/git/refs" % REPOSITORY, "--input", "-"],
                stdin_obj={"ref": "refs/heads/" + FEED_BRANCH, "sha": new_sha},
                allow_status=(409, 422),
            )
        else:
            result = _gh_call(
                gh,
                ["api", "--method", "PATCH", "repos/%s/git/refs/heads/%s" % (REPOSITORY, FEED_BRANCH), "--input", "-"],
                stdin_obj={"sha": new_sha, "force": False},
                allow_status=(409, 422),
            )
        if result is None:
            print("[feed] the feed branch moved while publishing; retrying")
            time.sleep(1.0 * (attempt + 1))
            continue

        print("[feed] committed %s to %s on top of %s" % (FEED_PATH, FEED_BRANCH, base_sha[:12]))
        return {
            "branch": FEED_BRANCH,
            "path": FEED_PATH,
            "commit": new_sha,
            "changed": True,
            "sha256": channel_sha,
            "public_url": RAW_CHANNEL_URL,
        }

    raise PublishError("the feed branch kept changing or rejected the update; no feed change was made")


def _verify_feed_public(channel_bytes):
    _fetch_public_with_retries(
        RAW_CHANNEL_URL,
        max_bytes=MAX_CHANNEL_BYTES,
        expected_sha256=hashlib.sha256(channel_bytes).hexdigest(),
        expected_size=len(channel_bytes),
        attempts=FEED_VERIFY_ATTEMPTS,
        base_delay=FEED_VERIFY_BASE_DELAY,
    )
    print("[feed] the public channel URL serves exactly the signed envelope")


# ------------------------------------------------------------------------ shared


def _load_json(data, name):
    try:
        return json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        raise PublishError("%s is not valid UTF-8 JSON" % name) from None


def _read_text(path):
    if path is None:
        return ""
    path = Path(path)
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8")


def _store_roots(store_roots):
    if store_roots is None:
        raise PublishError("no store roots were provided")
    if isinstance(store_roots, (str, bytes, os.PathLike)):
        roots = [store_roots]
    else:
        roots = list(store_roots)
    if not roots:
        raise PublishError("no store roots were provided")
    return [Path(root) for root in roots]


def _release_name(catalog, out):
    value = None
    for key in ("release", "release_name", "releaseName", "version"):
        candidate = catalog.get(key)
        if isinstance(candidate, str) and candidate.strip():
            value = candidate.strip()
            break
    if value is None:
        value = out.name
    if not _RELEASE_RE.match(value):
        raise PublishError("the release name has an unexpected form")
    return value


def _registry_tag(release):
    tag = release.strip().lower()
    if not _TAG_RE.match(tag):
        raise PublishError("the release name cannot be used as a registry tag")
    return tag


def _preflight(gh):
    login = _gh_text(gh, ["api", "user", "--jq", ".login"], what="the gh identity check")
    if login != EXPECTED_LOGIN:
        raise PublishError("gh is authenticated as an unexpected account; expected the project owner")
    repo = _gh_call(gh, ["api", "repos/%s" % REPOSITORY])
    if not isinstance(repo, dict):
        raise PublishError("the target repository could not be read")
    if repo.get("private"):
        raise PublishError("the target repository is not public")
    parent = (repo.get("parent") or {}).get("full_name")
    if repo.get("fork") is not True or parent != PARENT_REPOSITORY:
        raise PublishError("the target repository is not the expected public fork of " + PARENT_REPOSITORY)


def _write_publication(out, record):
    target = out / PUBLICATION_NAME
    temp = target.with_name(target.name + ".tmp")
    temp.write_text(json.dumps(record, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temp, target)
    print("[ghcr] wrote " + PUBLICATION_NAME)


# ----------------------------------------------------------------------- publish


def publish(gh, out, bootstrap, notes, store_roots):
    """Publish one verified release. Returns the publication record on success.

    Raises PublishError/PublicUnavailable on failure. Nothing downstream of the
    failing phase is changed, and out/publication.json is only written when every
    phase -- including the public feed verification -- has succeeded.
    """
    out = Path(out)
    bootstrap = Path(bootstrap)

    catalog_path = out / "catalog.json"
    channel_path = out / "channel" / "channel.json"
    for required in (catalog_path, channel_path, bootstrap):
        if not required.is_file():
            raise PublishError("a required publication input is missing: " + str(required.name))

    if bootstrap.name != INSTALLER_ASSET_NAME:
        raise PublishError("the installer bootstrap must be named " + INSTALLER_ASSET_NAME)
    builder.no_reparse_ancestors(out)
    builder.no_reparse_ancestors(bootstrap)
    bootstrap_sha, bootstrap_size = _hash_file(bootstrap)
    if bootstrap_size > MAX_BOOTSTRAP_BYTES or bootstrap_size == 0:
        raise PublishError("the installer bootstrap is unexpectedly sized")

    builder._load_previous_catalog(catalog_path,REPOSITORY)
    catalog_bytes = catalog_path.read_bytes()
    catalog = _load_json(catalog_bytes, "catalog.json")
    if not isinstance(catalog, dict):
        raise PublishError("catalog.json must contain a JSON object")
    catalog_sha = hashlib.sha256(catalog_bytes).hexdigest()

    channel_bytes = channel_path.read_bytes()
    if not channel_bytes or len(channel_bytes) > MAX_CHANNEL_BYTES:
        raise PublishError("the channel envelope has an unexpected size")

    notes_text = _read_text(notes)

    print("[ghcr] preflight: verifying gh identity and repository state")
    _preflight(gh)

    release = _release_name(catalog, out)
    tag = _registry_tag(release)
    print("[ghcr] release '%s' -> registry tag '%s'" % (release, tag))

    roots = _store_roots(store_roots)
    plan = _plan_objects(catalog)
    objects = _resolve_objects(plan, _locate_object_files(roots, plan))
    print("[store] validated %d object archive(s) across %d store root(s)" % (len(objects), len(roots)))

    registry = ghcr_store.Registry(gh_path=str(gh))
    try:
        manifest, layers = _publish_registry(
            registry, tag, objects, catalog_path, catalog_sha, len(catalog_bytes))
    except ghcr_store.ImmutableTagCollision:
        raise PublishError(
            "registry tag '%s' already exists with different content; existing OCI versions are "
            "never overwritten, publish this content under a new release instead" % tag
        ) from None

    print("[ghcr] verifying anonymous read access before any release or feed change")
    _verify_anonymous(registry, tag, manifest["digest"], layers)
    ps=Path(os.environ['SystemRoot'])/'System32/WindowsPowerShell/v1.0/powershell.exe'
    subprocess.run([str(ps),'-NoProfile','-ExecutionPolicy','Bypass','-File',str(Path(__file__).parent/'Verify-Registry.ps1'),'-Directory',str(out),'-CacheDirectory',str(out.parent.parent/'registry-public-cache')],check=True,env=dict(os.environ,PSModulePath=str(ps.parent/'Modules')))


    release_info = _publish_release(gh, bootstrap, notes_text, bootstrap_sha, bootstrap_size)

    feed_info = _feed_commit(gh, channel_bytes, release)
    _verify_feed_public(channel_bytes)

    record = {
        "schema": 2,
        "transport": "ghcr-v2",
        "public_payload_verified": True,
        "release": release,
        "repository": REPOSITORY,
        "published_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "registry": {
            "namespace": GHCR_NAMESPACE,
            "tag": tag,
            "manifest_digest": manifest["digest"],
            "manifest_size": manifest["size"],
            "layers": [
                {
                    "title": (layer.get("annotations") or {}).get("org.opencontainers.image.title", ""),
                    "media_type": layer["mediaType"],
                    "digest": layer["digest"],
                    "size": layer["size"],
                }
                for layer in layers
            ],
            "previous_versions_preserved": True,
        },
        "catalog": {"path": "catalog.json", "sha256": catalog_sha, "bytes": len(catalog_bytes)},
        "release_asset": release_info,
        "feed": feed_info,
    }
    _write_publication(out, record)
    print("[ghcr] publication complete for release '%s'" % release)
    return record
