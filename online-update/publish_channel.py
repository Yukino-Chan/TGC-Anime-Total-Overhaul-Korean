"""Publish locally verified immutable payloads, then advance the signed channel.

Requires GitHub CLI login on the publishing PC. Never exports its credentials.
Old remote objects are retained because newer catalogs can reference them.
"""
import argparse
import datetime as dt
import hashlib
import json
import subprocess
import zipfile
from pathlib import Path

REPO = 'Yukino-Chan/TGC-Anime-Total-Overhaul-Korean'


def sha(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def publish(gh, directory, bootstrap, notes):
    directory = Path(directory)
    bootstrap, notes = Path(bootstrap), Path(notes)
    def cli(*args):
        p = subprocess.run([str(gh), *map(str, args)], capture_output=True, text=True, encoding='utf-8')
        if p.returncode:
            raise RuntimeError(f'gh {args[0]} failed: {p.stderr[:2000]}')
        return p.stdout
    def api(path):
        return json.loads(cli('api', path))
    if api('user')['login'] != 'Yukino-Chan':
        raise ValueError('Wrong publishing account')
    repo = api(f'repos/{REPO}')
    if repo['private'] or not repo['fork'] or repo['parent']['full_name'] != 'The-Grand-Combination/The-Grand-Combo':
        raise ValueError('Repository provenance or visibility changed')
    report = json.loads((directory/'build-report.json').read_text('utf-8'))
    catalog_path = directory/'catalog.json'
    if not report['source_stability_checked'] or sha(catalog_path) != report['catalog_sha256']:
        raise ValueError('Unverified catalog')
    catalog = json.loads(catalog_path.read_text('utf-8'))
    tag = catalog['release']
    from build_catalog import _load_previous_catalog, _validate_release
    _validate_release(tag)
    _load_previous_catalog(catalog_path, REPO)
    channel_path = directory/'channel/latest.json'
    channel = json.loads(channel_path.read_text('utf-8'))
    if channel['release'] != tag or channel['catalog_sha256'] != sha(catalog_path):
        raise ValueError('Channel/catalog mismatch')
    with zipfile.ZipFile(bootstrap) as z:
        if z.testzip(): raise ValueError('Bootstrap ZIP integrity failure')
        if json.loads(z.read('TGC-Online-Installer/trust.json')) != json.loads((directory/'channel/trust.json').read_text('utf-8')):
            raise ValueError('Bootstrap public key differs from channel key')
    # Verify the exact signed pointer and pinned public key independently of generation.
    verify_script = Path(__file__).with_name('Verify-Publication.ps1')
    ps = Path(__import__('os').environ['SystemRoot'])/'System32/WindowsPowerShell/v1.0/powershell.exe'
    ps_env=dict(__import__('os').environ,PSModulePath=str(ps.parent/'Modules'))
    subprocess.run([str(ps),'-NoProfile','-ExecutionPolicy','Bypass','-File',str(verify_script),'-Directory',str(directory)],check=True,env=ps_env)
    release_cache = {}
    def get_release(t):
        if t not in release_cache:
            release_cache[t] = api(f'repos/{REPO}/releases/tags/{t}')
        return release_cache[t]
    local_assets = []
    for ident, asset in catalog['assets'].items():
        asset_tag, name = asset['url'].split('/')[-2:]
        local = directory/'assets'/name
        if asset_tag == tag:
            if not local.is_file() or local.stat().st_size != asset['bytes'] or sha(local) != ident:
                raise ValueError(f'Invalid local asset: {name}')
            local_assets.append(local)
        else:
            rel = get_release(asset_tag)
            if rel['draft']: raise ValueError('Cannot reuse draft assets')
            remote = next((x for x in rel['assets'] if x['name'] == name), None)
            if not remote or remote['size'] != asset['bytes'] or remote.get('digest') != 'sha256:'+ident:
                raise ValueError(f'Reused remote object missing or changed: {name}')
    # Resumption is allowed only when existing asset bytes match exactly.
    p = subprocess.run([str(gh),'api',f'repos/{REPO}/releases/tags/{tag}'],capture_output=True,text=True,encoding='utf-8')
    if p.returncode:
        if '404' not in p.stderr: raise RuntimeError(p.stderr)
        cli('release','create',tag,'--repo',REPO,'--draft','--target','master','--title',f'TGC - Anime Total Overhaul (Korean) · {tag}','--notes-file',notes)
    else:
        release_cache[tag] = json.loads(p.stdout)
    rel = get_release(tag)
    to_upload = [*local_assets,catalog_path,bootstrap]
    existing = {a['name']:a for a in rel['assets']}
    for path in to_upload:
        digest, size = sha(path), path.stat().st_size
        if path.name in existing:
            a = existing[path.name]
            if a.get('digest') != 'sha256:'+digest or a['size'] != size:
                raise ValueError(f'Immutable release collision: {path.name}')
        else:
            if not rel['draft']: raise ValueError('Published release cannot gain new assets')
            print(f'Uploading {path.name} ({size:,} bytes)',flush=True)
            cli('release','upload',tag,path,'--repo',REPO)
    release_cache.pop(tag,None)
    rel=get_release(tag)
    for path in to_upload:
        a=next(x for x in rel['assets'] if x['name']==path.name)
        if a.get('digest')!='sha256:'+sha(path) or a['size']!=path.stat().st_size:
            raise ValueError('Uploaded asset verification failed')
    if rel['draft']:
        cli('release','edit',tag,'--repo',REPO,'--draft=false','--latest=true')
    # Back up a prior signed pointer locally before updating its stable release.
    p=subprocess.run([str(gh),'api',f'repos/{REPO}/releases/tags/update-channel'],capture_output=True,text=True,encoding='utf-8')
    if p.returncode:
        if '404' not in p.stderr: raise RuntimeError(p.stderr)
        channel_notes=directory/'channel-notes.md'
        channel_notes.write_text('Signed update channel. Download the installer from the latest dated release. Payload objects in dated releases are retained for differential updates.\n',encoding='utf-8')
        cli('release','create','update-channel','--repo',REPO,'--draft','--target','master','--title','Signed update channel','--notes-file',channel_notes)
        was_draft=True
    else:
        prior=json.loads(p.stdout)
        was_draft=prior['draft']
        backup=directory/'previous-channel'
        backup.mkdir(exist_ok=True)
        for name in ('latest.json','latest.sig'):
            if any(a['name']==name for a in prior['assets']):
                cli('release','download','update-channel','--repo',REPO,'--pattern',name,'--dir',backup,'--clobber')
    # During the two-file replacement window, clients fail signature verification.
    # Never publish the pointer before all immutable assets have passed checks.
    try:
        cli('release','upload','update-channel',channel_path,directory/'channel/latest.sig','--repo',REPO,'--clobber')
        channel_release=api(f'repos/{REPO}/releases/tags/update-channel')
        for path in (channel_path,directory/'channel/latest.sig'):
            a=next(x for x in channel_release['assets'] if x['name']==path.name)
            if a.get('digest')!='sha256:'+sha(path): raise ValueError('Channel upload verification failed')
    except Exception:
        if not was_draft and all((directory/'previous-channel'/n).is_file() for n in ('latest.json','latest.sig')):
            cli('release','upload','update-channel',directory/'previous-channel/latest.json',directory/'previous-channel/latest.sig','--repo',REPO,'--clobber')
        raise
    if was_draft: cli('release','edit','update-channel','--repo',REPO,'--draft=false','--latest=false')
    receipt={'schema':1,'repository':REPO,'release':tag,'catalog_sha256':sha(catalog_path),'published_utc':dt.datetime.now(dt.timezone.utc).isoformat(),'verified_remote_assets':len(to_upload),'bootstrap_sha256':sha(bootstrap),'release_url':f'https://github.com/{REPO}/releases/tag/{tag}'}
    (directory/'publication.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(receipt),flush=True)


if __name__=='__main__':
    p=argparse.ArgumentParser()
    for name in ('gh','directory','bootstrap','notes'): p.add_argument('--'+name,required=True,type=Path)
    a=p.parse_args()
    publish(a.gh,a.directory,a.bootstrap,a.notes)
