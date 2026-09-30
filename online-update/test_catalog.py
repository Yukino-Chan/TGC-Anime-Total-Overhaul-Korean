import hashlib
import json
import shutil
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

import build_catalog


ROOT_METADATA = (
    "Setup.ps1",
    "Setup.cmd",
    "Restore.cmd",
    "Verify.cmd",
    "설치 안내.txt",
)


def sha256_hex(data):
    return hashlib.sha256(data).hexdigest()


def make_pack(root, release, payload):
    """Create a tiny verified release pack using only temporary files."""
    pack = Path(root) / release
    pack.mkdir(parents=True)

    for name in ROOT_METADATA:
        (pack / name).write_bytes(("metadata:" + name).encode("utf-8"))

    for rel, data in payload.items():
        path = pack / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    manifest_files = [
        {"path": rel, "bytes": len(payload[rel]), "sha256": sha256_hex(payload[rel])}
        for rel in sorted(payload)
    ]
    manifest = {
        "schema": 1,
        "release": release,
        "engine_version": "game-engine-1.0",
        "files": manifest_files,
    }
    (pack / "manifest.json").write_bytes(
        json.dumps(manifest, ensure_ascii=False).encode("utf-8")
    )

    sums_lines = []
    for path in sorted(pack.rglob("*"), key=lambda item: item.as_posix()):
        if not path.is_file():
            continue
        rel = path.relative_to(pack).as_posix()
        if rel == "SHA256SUMS.txt":
            continue
        sums_lines.append(f"{sha256_hex(path.read_bytes())}  {rel}")

    (pack / "SHA256SUMS.txt").write_bytes(
        ("\n".join(sums_lines) + "\n").encode("utf-8")
    )
    return pack


class BuildCatalogTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)

    def _build_valid_catalog(self):
        release = "TGCNV-20240102-030405"
        payload = {
            "payload/game/mod/TGCNV/common/a.txt": b"alpha",
            "payload/game/mod/TGO/music/b.txt": b"beta",
        }
        pack = make_pack(self.root, release, payload)
        out = self.root / "base"
        build_catalog.build(pack, "Yukino-Chan/TGC-Anime-Total-Overhaul-Korean", out)
        return pack, out / "catalog.json"

    def test_first_build_writes_catalog_and_expected_zip_members(self):
        release = "TGCNV-20240102-030405"
        payload = {
            "payload/game/mod/TGCNV/common/a.txt": b"alpha",
            "payload/game/mod/TGCNV/common/b.txt": b"beta",
            "payload/game/mod/TGO/music/song.txt": b"music",
        }
        pack = make_pack(self.root, release, payload)
        out = self.root / "out"

        result = build_catalog.build(pack, "Yukino-Chan/TGC-Anime-Total-Overhaul-Korean", out)
        catalog = result["catalog"]

        self.assertEqual(catalog["schema"], 1)
        self.assertEqual(catalog["release"], release)
        self.assertEqual(catalog["engine_version"], "game-engine-1.0")

        paths = [entry["path"] for entry in catalog["files"]]
        self.assertEqual(paths, sorted(paths))
        self.assertEqual(set(paths), set(payload) | set(build_catalog.ROOT_FILES))

        asset_members = {}
        for entry in catalog["files"]:
            asset_members.setdefault(entry["asset"], []).append(entry["path"])

        for asset_id, asset in catalog["assets"].items():
            self.assertRegex(asset_id, r"^[0-9a-f]{64}$")
            self.assertEqual(asset["sha256"], asset_id)
            self.assertTrue(
                asset["url"].startswith(
                    "https://ghcr.io/v2/yukino-chan/tgcnv-patches/blobs/sha256:"
                )
            )

            zip_path = out / "assets" / f"objects-{asset_id}.zip"
            self.assertTrue(zip_path.is_file())
            with zipfile.ZipFile(zip_path) as archive:
                self.assertEqual(archive.namelist(), sorted(asset_members[asset_id]))
                self.assertIsNone(archive.testzip())

    def test_second_release_reuses_unchanged_assets_and_rebuilds_changed(self):
        release1 = "TGCNV-20240102-030405"
        release2 = "TGCNV-20240103-030405"

        keep_rel = "payload/game/mod/TGCNV/common/keep.txt"
        change_rel = "payload/game/mod/TGCNV/common/change.txt"
        delete_rel = "payload/game/mod/TGCNV/common/delete.txt"
        add_rel = "payload/game/mod/TGO/music/new.txt"

        payload1 = {
            keep_rel: b"keep",
            change_rel: b"before",
            delete_rel: b"delete me",
        }
        pack1 = make_pack(self.root, release1, payload1)
        out1 = self.root / "out1"
        result1 = build_catalog.build(pack1, "Yukino-Chan/TGC-Anime-Total-Overhaul-Korean", out1)
        catalog1 = result1["catalog"]

        def asset_for(catalog, rel):
            for entry in catalog["files"]:
                if entry["path"] == rel:
                    return entry["asset"]
            raise AssertionError(f"missing catalog path: {rel}")

        keep_asset1 = asset_for(catalog1, keep_rel)
        change_asset1 = asset_for(catalog1, change_rel)
        setup_asset1 = asset_for(catalog1, "Setup.ps1")

        payload2 = {
            keep_rel: b"keep",
            change_rel: b"after",
            add_rel: b"new",
        }
        pack2 = make_pack(self.root, release2, payload2)
        out2 = self.root / "out2"
        result2 = build_catalog.build(
            pack2, "Yukino-Chan/TGC-Anime-Total-Overhaul-Korean", out2, out1 / "catalog.json"
        )
        catalog2 = result2["catalog"]

        self.assertEqual(asset_for(catalog2, keep_rel), keep_asset1)
        self.assertEqual(asset_for(catalog2, "Setup.ps1"), setup_asset1)
        self.assertNotEqual(asset_for(catalog2, change_rel), change_asset1)

        catalog2_paths = {entry["path"] for entry in catalog2["files"]}
        self.assertIn(add_rel, catalog2_paths)
        self.assertNotIn(delete_rel, catalog2_paths)

        expected_new = {"manifest.json", "SHA256SUMS.txt", change_rel, add_rel}
        self.assertEqual(result2["report"]["new"]["files"], len(expected_new))
        self.assertEqual(
            result2["report"]["reused"]["files"],
            len(catalog2["files"]) - len(expected_new),
        )

    def test_unchanged_rebuild_reuses_every_file(self):
        release = "TGCNV-20240102-030405"
        payload = {
            "payload/game/mod/TGCNV/common/a.txt": b"alpha",
            "payload/game/mod/TGO/music/b.txt": b"beta",
        }
        pack = make_pack(self.root, release, payload)

        out1 = self.root / "out1"
        result1 = build_catalog.build(pack, "Yukino-Chan/TGC-Anime-Total-Overhaul-Korean", out1)

        out2 = self.root / "out2"
        result2 = build_catalog.build(
            pack, "Yukino-Chan/TGC-Anime-Total-Overhaul-Korean", out2, out1 / "catalog.json"
        )

        self.assertEqual(result2["report"]["new"]["files"], 0)
        self.assertEqual(result2["report"]["new"]["assets"], 0)
        self.assertEqual(
            result2["report"]["reused"]["files"], len(result1["catalog"]["files"])
        )
        self.assertEqual(result2["catalog"], result1["catalog"])
        self.assertEqual(
            (out2 / "catalog.json").read_bytes(),
            (out1 / "catalog.json").read_bytes(),
        )
        self.assertEqual(list((out2 / "assets").iterdir()), [])

    def test_manifest_tamper_is_rejected(self):
        release = "TGCNV-20240102-030405"
        payload = {"payload/game/mod/TGCNV/common/a.txt": b"alpha"}
        pack = make_pack(self.root, release, payload)

        manifest_path = pack / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["engine_version"] = "tampered"
        manifest_path.write_text(
            json.dumps(manifest, ensure_ascii=False), encoding="utf-8"
        )

        with self.assertRaises(ValueError):
            build_catalog.build(pack, "Yukino-Chan/TGC-Anime-Total-Overhaul-Korean", self.root / "out")

    def test_sums_tamper_is_rejected(self):
        release = "TGCNV-20240102-030405"
        payload = {"payload/game/mod/TGCNV/common/a.txt": b"alpha"}
        pack = make_pack(self.root, release, payload)

        sums_path = pack / "SHA256SUMS.txt"
        lines = sums_path.read_text(encoding="utf-8").splitlines()
        _, rel = lines[0].split("  ", 1)
        lines[0] = "0" * 64 + "  " + rel
        sums_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

        with self.assertRaises(ValueError):
            build_catalog.build(pack, "Yukino-Chan/TGC-Anime-Total-Overhaul-Korean", self.root / "out")

    def test_existing_output_is_rejected(self):
        release = "TGCNV-20240102-030405"
        payload = {"payload/game/mod/TGCNV/common/a.txt": b"alpha"}
        pack = make_pack(self.root, release, payload)

        out = self.root / "out"
        out.mkdir()

        with self.assertRaises(ValueError):
            build_catalog.build(pack, "Yukino-Chan/TGC-Anime-Total-Overhaul-Korean", out)

    def test_forbidden_payload_path_is_rejected(self):
        release = "TGCNV-20240102-030405"
        payload = {
            "payload/game/mod/TGCNV/common/ok.txt": b"ok",
            "payload/game/mod/TGCNV/private/secret.txt": b"no",
        }
        pack = make_pack(self.root, release, payload)

        with self.assertRaises(ValueError):
            build_catalog.build(pack, "Yukino-Chan/TGC-Anime-Total-Overhaul-Korean", self.root / "out")

    def test_path_validation_rejects_noncanonical_names(self):
        bad_paths = [
            "../evil.txt",
            r"payload\game\mod\TGCNV\common\a.txt",
            "payload/game/mod/TGCNV/common/CON.txt",
            "/absolute.txt",
            "payload/game/mod/TGCNV/common/a.txt/..",
        ]
        for path in bad_paths:
            with self.subTest(path=path):
                with self.assertRaises(ValueError):
                    build_catalog.canonical_path(path)

    def test_validate_paths_rejects_case_collisions(self):
        with self.assertRaises(ValueError):
            build_catalog.validate_paths(
                [
                    "payload/game/mod/TGCNV/common/Readme.txt",
                    "payload/game/mod/TGCNV/common/readme.txt",
                ]
            )

    def test_previous_catalog_malformed_integer_is_rejected(self):
        pack, catalog_path = self._build_valid_catalog()
        document = json.loads(catalog_path.read_text(encoding="utf-8"))
        document["files"][0]["bytes"] = "not-an-integer"

        bad_path = self.root / "bad-integer.json"
        bad_path.write_text(
            json.dumps(document, ensure_ascii=False), encoding="utf-8"
        )

        with self.assertRaises(ValueError):
            build_catalog.build(pack, "Yukino-Chan/TGC-Anime-Total-Overhaul-Korean", self.root / "out2", bad_path)

    def test_previous_catalog_malformed_url_is_rejected(self):
        pack, catalog_path = self._build_valid_catalog()
        document = json.loads(catalog_path.read_text(encoding="utf-8"))
        asset_id = next(iter(document["assets"]))
        document["assets"][asset_id]["url"] = (
            f"https://example.com/objects-{asset_id}.zip"
        )

        bad_path = self.root / "bad-url.json"
        bad_path.write_text(
            json.dumps(document, ensure_ascii=False), encoding="utf-8"
        )

        with self.assertRaises(ValueError):
            build_catalog.build(pack, "Yukino-Chan/TGC-Anime-Total-Overhaul-Korean", self.root / "out2", bad_path)

    def test_zip_assets_are_deterministic_across_output_dirs(self):
        release = "TGCNV-20240102-030405"
        payload = {
            "payload/game/mod/TGCNV/common/a.txt": b"alpha",
            "payload/game/mod/TGO/music/b.txt": b"beta",
        }
        pack = make_pack(self.root, release, payload)

        out1 = self.root / "out1"
        out2 = self.root / "out2"
        result1 = build_catalog.build(pack, "Yukino-Chan/TGC-Anime-Total-Overhaul-Korean", out1)
        result2 = build_catalog.build(pack, "Yukino-Chan/TGC-Anime-Total-Overhaul-Korean", out2)

        self.assertEqual(result1["catalog"], result2["catalog"])
        self.assertEqual(result1["catalog_sha256"], result2["catalog_sha256"])

        names1 = sorted(path.name for path in (out1 / "assets").iterdir())
        names2 = sorted(path.name for path in (out2 / "assets").iterdir())
        self.assertEqual(names1, names2)

        for name in names1:
            self.assertEqual(
                (out1 / "assets" / name).read_bytes(),
                (out2 / "assets" / name).read_bytes(),
            )

    def test_source_drift_during_compression_aborts_without_catalog(self):
        release = "TGCNV-20240102-030405"
        payload = {
            "payload/game/mod/TGCNV/common/a.txt": b"alpha",
            "payload/game/mod/TGCNV/common/b.txt": b"beta",
        }
        pack = make_pack(self.root, release, payload)
        out = self.root / "out"

        original_copyfileobj = shutil.copyfileobj
        copied = []

        def side_effect(src, dst, length=0):
            original_copyfileobj(src, dst, length)
            copied.append(Path(src.name))
            if len(copied) == 2:
                # The first source file is closed by now. Mutate it on disk so
                # the post-compression snapshot detects source drift.
                copied[0].write_bytes(b"drifted after snapshot")

        with mock.patch.object(
            build_catalog.shutil, "copyfileobj", side_effect=side_effect
        ):
            with self.assertRaises(RuntimeError):
                build_catalog.build(pack, "Yukino-Chan/TGC-Anime-Total-Overhaul-Korean", out)

        self.assertFalse((out / "catalog.json").exists())
        self.assertFalse((out / "build-report.json").exists())


if __name__ == "__main__":
    unittest.main()