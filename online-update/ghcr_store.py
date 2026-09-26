"""ghcr_store.py — stdlib-only OCI artifact publisher for GHCR."""
from __future__ import annotations

import base64
import hashlib
import http.client
import io
import json
import re
import subprocess
import urllib.parse
import time

REGISTRY = "ghcr.io"
NAMESPACE = "yukino-chan/tgcnv-patches"
REPO_URL = "https://github.com/Yukino-Chan/TGC-Anime-Total-Overhaul-Korean"
ARTIFACT_TYPE = "application/vnd.tgcnv.update.v1"
CONFIG_MEDIA_TYPE = "application/vnd.oci.empty.v1+json"
MANIFEST_MEDIA_TYPE = "application/vnd.oci.image.manifest.v1+json"
ZIP_MEDIA_TYPE = "application/zip"
JSON_MEDIA_TYPE = "application/json"
EMPTY_CONFIG_BYTES = b"{}"
EMPTY_CONFIG_DIGEST = "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
MAX_TOKEN_BYTES = 64 * 1024
SCOPE_PULL = "repository:yukino-chan/tgcnv-patches:pull"
SCOPE_PUSH = "repository:yukino-chan/tgcnv-patches:pull,push"
_TAG_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{0,127}$")
_DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
_UPLOAD_RE = re.compile(r"^/v2/yukino-chan/tgcnv-patches/blobs/uploads?/[A-Za-z0-9._~-]+$")


class RegistryError(Exception):
    pass


class BlobMismatch(RegistryError):
    pass


class ImmutableTagCollision(RegistryError):
    pass


def _sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _norm_digest(digest: str) -> str:
    d = digest
    if not isinstance(d,str) or not _DIGEST_RE.fullmatch(d):
        raise BlobMismatch("invalid digest")
    return d


def _validate_upload_location(location: str) -> str:
    if not isinstance(location, str):
        raise RegistryError("bad upload location")
    if any(ord(c) <= 32 for c in location):
        raise RegistryError("bad upload location")
    p = urllib.parse.urlsplit(urllib.parse.urljoin("https://ghcr.io",location))
    if p.scheme != "https" or p.netloc != REGISTRY or p.fragment or p.username or p.password:
        raise RegistryError("untrusted upload location")
    if not _UPLOAD_RE.fullmatch(p.path) or ".." in p.path or "digest" in dict(urllib.parse.parse_qsl(p.query)):
        raise RegistryError("untrusted upload path")
    return p.path + (("?" + p.query) if p.query else "")


class HttpTransport:
    """Real HTTPS transport fixed to ghcr.io; no redirect following."""

    def __init__(self, timeout: int = 180):
        self.timeout = timeout

    def request(self, method, path, headers, body=None, max_body=1 << 20):
        conn = http.client.HTTPSConnection(REGISTRY, timeout=self.timeout)
        try:
            conn.request(method, path, body=body, headers=headers)
            resp = conn.getresponse()
            data = resp.read(max_body + 1)
            if len(data) > max_body:
                raise RegistryError("response too large")
            return resp.status, {k.lower(): v for k, v in resp.getheaders()}, data
        finally:
            conn.close()


class Registry:
    def __init__(self, gh_path=None, transport=None):
        self._gh = gh_path or "gh"
        self._transport = transport or HttpTransport()
        self._tokens = {}
        self._identity_ok = False
        self._auth_token = None

    def _gh_out(self, args):
        try:
            p = subprocess.run([self._gh] + args, capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.SubprocessError):
            raise RegistryError("gh unavailable") from None
        if p.returncode != 0:
            raise RegistryError("gh command failed")
        return p.stdout.strip()

    def _ensure_identity(self):
        if self._identity_ok:
            return
        if self._gh_out(["api", "user", "--jq", ".login"]) != "Yukino-Chan":
            raise RegistryError("unexpected gh identity")
        token = self._gh_out(["auth", "token"])
        if not token:
            raise RegistryError("missing gh token")
        self._auth_token = token
        self._identity_ok = True

    def _basic(self):
        self._ensure_identity()
        raw = ("Yukino-Chan:" + self._auth_token).encode()
        return "Basic " + base64.b64encode(raw).decode()

    def _token(self, scope, auth):
        key = (scope, auth)
        if key in self._tokens and self._tokens[key][1] > time.monotonic():
            return self._tokens[key][0]
        q = urllib.parse.urlencode({"service": REGISTRY, "scope": scope},
                                   quote_via=urllib.parse.quote, safe="")
        headers = {"Accept": "application/json"}
        if auth:
            headers["Authorization"] = self._basic()
        status, _, body = self._transport.request("GET", "/token?" + q, headers,
                                                  max_body=MAX_TOKEN_BYTES)
        if status != 200:
            raise RegistryError(f"token request failed (HTTP {status})")
        try:
            data = json.loads(body)
            tok = data.get("token") or data.get("access_token")
        except Exception:
            raise RegistryError("bad token response") from None
        if not isinstance(tok, str) or not tok or len(tok)>4096 or any(ord(c)<=32 for c in tok):
            raise RegistryError("bad token response")
        self._tokens[key] = (tok,time.monotonic()+240)
        return tok

    def _request(self, method, path, headers=None, body=None, scope=SCOPE_PULL,
                 auth=False, max_body=1 << 20, retry=True):
        h = dict(headers or {})
        h["Authorization"] = "Bearer " + self._token(scope, auth)
        status, rh, rb = self._transport.request(method, path, h, body=body, max_body=max_body)
        if status == 401 and retry:
            self._tokens.pop((scope, auth), None)
            if hasattr(body, "seek"):
                body.seek(0)
            h["Authorization"] = "Bearer " + self._token(scope, auth)
            status, rh, rb = self._transport.request(method, path, h, body=body, max_body=max_body)
        return status, rh, rb

    def head_blob(self, digest, size=None, auth=False):
        d = _norm_digest(digest)
        status, rh, _ = self._request("HEAD", f"/v2/{NAMESPACE}/blobs/{d}",
                                      scope=SCOPE_PUSH if auth else SCOPE_PULL, auth=auth)
        if status == 404:
            return False
        if status != 200:
            raise RegistryError("blob head failed")
        cl = rh.get("content-length")
        if cl is None or not cl.isdigit():
            raise RegistryError("blob head missing length")
        if size is not None and int(cl) != size:
            raise BlobMismatch("blob size mismatch")
        if rh.get("docker-content-digest", "").lower() != d:
            raise BlobMismatch("blob digest mismatch")
        return True

    def _upload_stream(self, stream, size, d):
        self._ensure_identity()
        status, rh, _ = self._request("POST", f"/v2/{NAMESPACE}/blobs/uploads/",
                                      headers={"Content-Length": "0"},
                                      scope=SCOPE_PUSH, auth=True)
        if status != 202:
            raise RegistryError(f"upload start failed (HTTP {status})")
        loc = _validate_upload_location(rh.get("location", ""))
        sep = "&" if "?" in loc else "?"
        put = loc + sep + "digest=" + urllib.parse.quote(d, safe="")
        status, _, _ = self._request(
            "PUT", put,
            headers={"Content-Length": str(size), "Content-Type": "application/octet-stream"},
            body=stream, scope=SCOPE_PUSH, auth=True)
        if status != 201:
            raise RegistryError("blob upload failed")
        if not self.head_blob(d, size, auth=True):
            raise BlobMismatch("uploaded blob missing")
        return {"digest": d, "size": size, "status": "uploaded"}

    def upload_file(self, path, expected_sha, expected_size=None):
        d = _norm_digest(expected_sha)
        h = hashlib.sha256()
        n = 0
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
                n += len(chunk)
        if h.hexdigest() != d.split(":", 1)[1] or (expected_size is not None and n != expected_size):
            raise BlobMismatch("local file mismatch")
        if self.head_blob(d, n, auth=True):
            return {"digest": d, "size": n, "status": "exists"}
        with open(path, "rb") as f:
            result = self._upload_stream(f, n, d)
            f.seek(0)
            if hashlib.file_digest(f,"sha256").hexdigest() != d[7:]:
                raise BlobMismatch("source changed during upload")
            return result

    def upload_bytes(self, data, expected_sha=None):
        d = _norm_digest(expected_sha or "sha256:" + _sha256_hex(data))
        if _sha256_hex(data) != d.split(":", 1)[1]:
            raise BlobMismatch("byte blob mismatch")
        if self.head_blob(d, len(data), auth=True):
            return {"digest": d, "size": len(data), "status": "exists"}
        return self._upload_stream(io.BytesIO(data), len(data), d)

    def push_manifest(self, release, layers):
        tag = release.strip().lower()
        if not _TAG_RE.match(tag):
            raise RegistryError("invalid tag")
        self.upload_bytes(EMPTY_CONFIG_BYTES, EMPTY_CONFIG_DIGEST)
        descs = []
        for item in layers:
            if isinstance(item, dict):
                dsc = {"mediaType": item["mediaType"],
                       "digest": _norm_digest(item["digest"]),
                       "size": int(item["size"])}
                if "annotations" in item:
                    dsc["annotations"] = item["annotations"]
            else:
                mt, dg, sz = item
                dsc = {"mediaType": mt, "digest": _norm_digest(dg), "size": int(sz)}
            if dsc["mediaType"] not in (ZIP_MEDIA_TYPE, JSON_MEDIA_TYPE):
                raise RegistryError("bad layer media type")
            if dsc["size"] < 1:
                raise RegistryError("invalid layer size")
            descs.append(dsc)
        descs.sort(key=lambda x: (x["mediaType"], x["digest"]))
        manifest = {
            "schemaVersion": 2,
            "mediaType": MANIFEST_MEDIA_TYPE,
            "artifactType": ARTIFACT_TYPE,
            "config": {"mediaType": CONFIG_MEDIA_TYPE,
                       "digest": EMPTY_CONFIG_DIGEST,
                       "size": len(EMPTY_CONFIG_BYTES)},
            "layers": descs,
            "annotations": {"org.opencontainers.image.source": REPO_URL},
        }
        data = json.dumps(manifest, sort_keys=True, separators=(",", ":"),
                          ensure_ascii=True).encode()
        d = "sha256:" + _sha256_hex(data)
        path = f"/v2/{NAMESPACE}/manifests/{tag}"
        status, rh, rb = self._request("GET", path, headers={"Accept": MANIFEST_MEDIA_TYPE},
                                       scope=SCOPE_PUSH, auth=True)
        if status == 200:
            existing = rh.get("docker-content-digest", "").lower() or "sha256:" + _sha256_hex(rb)
            if existing != d or "sha256:" + _sha256_hex(rb) != d:
                raise ImmutableTagCollision("tag already exists with different digest")
            return {"tag": tag, "digest": d, "size": len(data), "status": "exists"}
        if status != 404:
            raise RegistryError("manifest lookup failed")
        self._ensure_identity()
        status, rh, _ = self._request(
            "PUT", path,
            headers={"Content-Type": MANIFEST_MEDIA_TYPE, "Content-Length": str(len(data))},
            body=data, scope=SCOPE_PUSH, auth=True)
        if status != 201:
            raise RegistryError("manifest upload failed")
        if rh.get("docker-content-digest", "").lower() != d:
            raise RegistryError("manifest digest mismatch")
        status, _, rb = self._request("GET", path, headers={"Accept": MANIFEST_MEDIA_TYPE},
                                      scope=SCOPE_PUSH, auth=True)
        if status != 200 or rb != data:
            raise RegistryError("manifest verify failed")
        return {"tag": tag, "digest": d, "size": len(data), "status": "pushed"}

    def head_manifest(self, release):
        tag = release.strip().lower()
        if not _TAG_RE.match(tag):
            raise RegistryError("invalid tag")
        status, rh, _ = self._request("HEAD", f"/v2/{NAMESPACE}/manifests/{tag}",
                                      headers={"Accept": MANIFEST_MEDIA_TYPE},
                                      scope=SCOPE_PULL, auth=False)
        if status == 404:
            return None
        if status != 200:
            raise RegistryError("manifest head failed")
        return {"tag": tag, "digest": _norm_digest(rh.get("docker-content-digest", "")),
                "size": int(rh.get("content-length", "0"))}

    def get_manifest(self, release):
        tag = release.strip().lower()
        if not _TAG_RE.match(tag):
            raise RegistryError("invalid tag")
        status, rh, rb = self._request("GET", f"/v2/{NAMESPACE}/manifests/{tag}",
                                       headers={"Accept": MANIFEST_MEDIA_TYPE},
                                       scope=SCOPE_PULL, auth=False)
        if status != 200:
            raise RegistryError("manifest fetch failed")
        d = _norm_digest(rh.get("docker-content-digest", ""))
        if "sha256:" + _sha256_hex(rb) != d:
            raise RegistryError("manifest digest mismatch")
        return {"tag": tag, "digest": d, "size": len(rb),
                "mediaType": rh.get("content-type", "")}
