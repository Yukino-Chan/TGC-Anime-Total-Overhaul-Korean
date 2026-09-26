import hashlib
import json
import os
import tempfile
import unittest

import ghcr_store as gs


def _sha(data):
    return "sha256:" + hashlib.sha256(data).hexdigest()


def _tok(t="t"):
    return (200, {}, json.dumps({"token": t}).encode())


class FakeTransport:
    def __init__(self, responses):
        self.responses = list(responses)
        self.calls = []

    def request(self, method, path, headers, body=None, max_body=1 << 20):
        self.calls.append((method, path, dict(headers)))
        if not self.responses:
            raise AssertionError("unexpected request: %s %s" % (method, path))
        r = self.responses.pop(0)
        return r(method, path, headers, body) if callable(r) else r


class TestRegistry(unittest.TestCase):
    def test_relative_upload_location_and_scope(self):
        self.assertEqual(gs._validate_upload_location('/v2/yukino-chan/tgcnv-patches/blobs/upload/abc.1?state=x'),'/v2/yukino-chan/tgcnv-patches/blobs/upload/abc.1?state=x')
        with self.assertRaises(gs.RegistryError):gs._validate_upload_location('/v2/yukino-chan/tgcnv-patches/blobs/upload/abc?digest=x')

    def test_expired_token_and_401_retry_are_bounded(self):
        d=_sha(b'abc');head=(200,{'content-length':'3','docker-content-digest':d},b'')
        reg,t=self._reg([_tok('one'),head,_tok('two'),(401,{},b''),_tok('three'),head])
        self.assertTrue(reg.head_blob(d,3));reg._tokens[(gs.SCOPE_PULL,False)]=('expired',0)
        self.assertTrue(reg.head_blob(d,3))
        self.assertNotIn('Authorization',t.calls[0][2]);self.assertEqual(t.calls[-1][2]['Authorization'],'Bearer three')
        reg,t=self._reg([_tok(),(401,{},b''),_tok(),(401,{},b'')])
        with self.assertRaises(gs.RegistryError):reg.head_blob(d,3)
        self.assertEqual(len(t.calls),4)

    def _reg(self, responses):
        t = FakeTransport(responses)
        r = gs.Registry(transport=t)
        r._identity_ok = True
        r._auth_token = "tok"
        return r, t

    def _tmp(self, data):
        f = tempfile.NamedTemporaryFile(delete=False)
        f.write(data)
        f.close()
        self.addCleanup(lambda: os.unlink(f.name))
        return f.name

    def test_head_blob_missing_returns_false(self):
        d = _sha(b"abc")
        reg, _ = self._reg([_tok(), (404, {}, b"")])
        self.assertFalse(reg.head_blob(d))

    def test_head_blob_mismatch(self):
        d = _sha(b"abc")
        reg, _ = self._reg([_tok(), (200, {"content-length": "4", "docker-content-digest": d}, b"")])
        with self.assertRaises(gs.BlobMismatch):
            reg.head_blob(d, 3)
        reg, _ = self._reg([_tok(), (200, {"content-length": "3", "docker-content-digest": "sha256:" + "0" * 64}, b"")])
        with self.assertRaises(gs.BlobMismatch):
            reg.head_blob(d, 3)

    def test_upload_file_rejects_bad_local_hash(self):
        reg, _ = self._reg([])
        p = self._tmp(b"hello")
        with self.assertRaises(gs.BlobMismatch):
            reg.upload_file(p, _sha(b"other"))

    def test_malicious_location(self):
        data = b"hello"
        d = _sha(data)
        bads = [
            "https://evil.example/v2/yukino-chan/tgcnv-patches/blobs/uploads/x",
            "https://ghcr.io/v2/other/blobs/uploads/x",
            "https://user:pass@ghcr.io/v2/yukino-chan/tgcnv-patches/blobs/uploads/x",
            "https://ghcr.io/v2/yukino-chan/tgcnv-patches/blobs/uploads/x#frag",
            "https://ghcr.io/v2/yukino-chan/tgcnv-patches/blobs/uploads/../manifests/x",
        ]
        for bad in bads:
            with self.subTest(bad=bad):
                reg, _ = self._reg([_tok(), (404, {}, b""), (202, {"location": bad}, b"")])
                p = self._tmp(data)
                with self.assertRaises(gs.RegistryError):
                    reg.upload_file(p, d, len(data))

    def test_immutable_tag_collision(self):
        reg, _ = self._reg([
            _tok(),
            (404, {}, b""),
            (202, {"location": "https://ghcr.io/v2/yukino-chan/tgcnv-patches/blobs/uploads/u1"}, b""),
            (201, {}, b""),
            (200, {"content-length": "2", "docker-content-digest": gs.EMPTY_CONFIG_DIGEST}, b""),
            (200, {"docker-content-digest": "sha256:" + "1" * 64}, b"{}"),
        ])
        with self.assertRaises(gs.ImmutableTagCollision):
            reg.push_manifest("v1", [{"mediaType": gs.JSON_MEDIA_TYPE,
                                      "digest": _sha(b"cat"), "size": 3}])


if __name__ == "__main__":
    unittest.main()
