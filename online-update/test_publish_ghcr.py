import base64,hashlib,json,tempfile,unittest,urllib.error
from pathlib import Path
from unittest.mock import patch,Mock
import publish_ghcr as p
import ghcr_store as g

class PublicationTests(unittest.TestCase):
    def test_feed_cannot_replace_newer_or_conflicting_catalog(self):
        def envelope(seq,digest):return json.dumps({'channel':base64.b64encode(json.dumps({'sequence':seq,'catalog_sha256':digest}).encode()).decode()}).encode()
        for incoming in (envelope(1,'a'),envelope(2,'b')):
            with patch.object(p,'_gh_call',side_effect=[{'object':{'sha':'a'*40}},{'tree':{'sha':'b'*40}}]) as api,patch.object(p,'_tree_blob_sha',return_value='c'*40),patch.object(p,'_blob_bytes',return_value=envelope(2,'a')):
                with self.assertRaises(p.PublishError):p._feed_commit('gh',incoming,'TGCNV-20260927-005752')
                self.assertEqual(api.call_count,2)

    def test_exact_registry_catalog_mapping(self):
        key='a'*64
        a={'sha256':key,'bytes':3,'url':'https://ghcr.io/v2/'+p.GHCR_NAMESPACE+'/blobs/sha256:'+key}
        self.assertEqual(p._plan_objects({'assets':{key:a}})[key],{'sha256':key,'bytes':3})
        for bad in [dict(a,url=a['url']+'?x'),dict(a,sha256='b'*64),dict(a,bytes=True),dict(a,url=a['url'].replace('tgcnv-patches','other'))]:
            with self.assertRaises(p.PublishError):p._plan_objects({'assets':{key:bad}})

    def test_source_tamper_refused(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);file=root/'objects-a.zip';file.write_bytes(b'bad')
            with self.assertRaises(p.PublishError):p._resolve_objects({'a':{'sha256':'0'*64,'bytes':3}},{'a':[file]})

    def test_anonymous_gate_refuses_missing_payload(self):
        r=Mock();r.head_manifest.return_value={'digest':'sha256:'+'a'*64};r.get_manifest.return_value=r.head_manifest.return_value
        r.head_blob.return_value=False
        with self.assertRaises(p.PublicUnavailable):p._verify_anonymous(r,'v','sha256:'+'a'*64,[{'digest':'sha256:'+'b'*64,'size':3}])

    def test_public_fetch_refuses_credentials_and_foreign_redirects(self):
        for url in ['https://user:password@github.com/x','https://github.com:444/x','http://github.com/x','https://evil.example/x']:
            with self.assertRaises(p.PublishError):p._fetch_public_bytes(url,max_bytes=3)
        opener=Mock();opener.open.side_effect=urllib.error.HTTPError('https://github.com/x',302,'redirect',{'Location':'https://evil.example/x'},None)
        with patch.object(p.urllib.request,'build_opener',return_value=opener):
            with self.assertRaises(p.PublishError):p._fetch_public_bytes('https://github.com/x',max_bytes=3)
        self.assertEqual(opener.open.call_count,1)

    def test_payload_failure_never_advances_release_feed_or_state(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'channel').mkdir();(root/'assets').mkdir()
            data=b'zip fixture';key=hashlib.sha256(data).hexdigest();(root/'assets'/('objects-'+key+'.zip')).write_bytes(data)
            catalog={'release':'TGCNV-20260927-005752','assets':{key:{'sha256':key,'bytes':len(data),'url':'https://ghcr.io/v2/'+p.GHCR_NAMESPACE+'/blobs/sha256:'+key}}}
            (root/'catalog.json').write_text(json.dumps(catalog));(root/'channel/channel.json').write_bytes(b'{}');(root/p.INSTALLER_ASSET_NAME).write_bytes(b'installer')
            with patch.object(p.builder,'_load_previous_catalog'),patch.object(p,'_preflight'),patch.object(p,'_publish_registry',return_value=({'digest':'sha256:'+'b'*64,'size':3},[])),patch.object(p,'_verify_anonymous',side_effect=p.PublicUnavailable('private')),patch.object(p,'_publish_release') as release,patch.object(p,'_feed_commit') as feed,patch.object(p,'_write_publication') as state:
                with self.assertRaises(p.PublicUnavailable):p.publish('gh',root,root/p.INSTALLER_ASSET_NAME,None,[root])
                release.assert_not_called();feed.assert_not_called();state.assert_not_called()

    def test_missing_asset_digest_blocks_publication(self):
        release={'id':1,'draft':True,'body':''}
        asset={'name':p.INSTALLER_ASSET_NAME,'size':3,'digest':None}
        with patch.object(p,'_release_by_tag',return_value=release),patch.object(p,'_assets_of',return_value=[asset]),patch.object(p,'_upload_asset'),patch.object(p,'_gh_call') as api:
            with self.assertRaises(p.PublishError):p._publish_release('gh',Path(p.INSTALLER_ASSET_NAME),'notes','a'*64,3)
            api.assert_not_called()

if __name__=='__main__':unittest.main()
