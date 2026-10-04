"""Automation entry point: publish only the current verified local release.

Run after the existing snapshot, cache-signature, ZIP and installer gates pass.
No game writes. No process launch/termination. No remote artifact deletion.
"""
import argparse,datetime,hashlib,json,os,re,subprocess,sys
from pathlib import Path
import build_catalog as builder
import make_client
from publish_ghcr import publish

ROOT=Path(__file__).parent
def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def client_source_sha():
    return hashlib.sha256(b''.join((ROOT/n).read_bytes() for n in ('Update.ps1','Online-Core.psm1','Language.psm1','make_client.py'))).hexdigest()
def _main(base,gh,python=sys.executable):
    base=Path(base).absolute()
    builder.no_reparse_ancestors(base)
    state_path=base/'release-state.json'
    state=json.loads(state_path.read_text('utf-8-sig'))
    release=builder._validate_release(state['release'])
    archive=Path(state['archive'])
    if archive.parent.absolute()!=base.parent.parent or archive.name not in (release+'.zip','TGCNV-TGO.zip'):
        raise ValueError('Local release archive is outside the distribution root')
    if sha(archive)!=state['sha256']:raise ValueError('Local release ZIP differs from release-state')
    manifest_path=base/'manifests'/(release+'.json')
    pack=base/'builds'/release[6:]/release
    if sha(pack/'manifest.json')!=sha(manifest_path):raise ValueError('Published manifest differs from snapshot')
    online=base/'online';online.mkdir(exist_ok=True)
    online_state_path=online/'online-state.json'
    previous=None
    if online_state_path.exists():
        previous=json.loads(online_state_path.read_text('utf-8'))
        if previous.get('transport')=='ghcr-v2' and previous['release']==release and previous['local_archive_sha256']==state['sha256'] and previous.get('client_source_sha256')==client_source_sha():
            print('Online channel already matches the current local release.');return
    out=online/'ghcr-releases'/release
    previous_catalog=None if previous is None else online/('ghcr-releases' if previous.get('transport')=='ghcr-v2' else 'releases')/previous['release']/'catalog.json'
    if previous_catalog and previous.get('transport')!='ghcr-v2':
        # Preserve the file-to-object mapping; only replace immutable storage URLs.
        builder._load_previous_catalog(previous_catalog,'Yukino-Chan/TGC-Anime-Total-Overhaul-Korean')
        old=json.loads(previous_catalog.read_text('utf-8'))
        for oid,asset in old['assets'].items():asset['url']='https://ghcr.io/v2/yukino-chan/tgcnv-patches/blobs/sha256:'+oid
        migrated=online/'migration-v2-previous.json'
        migrated.write_text(json.dumps(old,ensure_ascii=False,sort_keys=True,separators=(',',':')),encoding='utf-8')
        previous_catalog=migrated
    if not (out/'catalog.json').exists():
        if out.exists():raise ValueError('Partial build exists; preserve and diagnose before retrying with a fresh output')
        builder.build(pack,'Yukino-Chan/TGC-Anime-Total-Overhaul-Korean',out,previous_catalog)
    else:
        # A resumable build must still match every selected source file.
        entries,_=builder._snapshot(pack)
        catalog=json.loads((out/'catalog.json').read_text('utf-8'))
        if set(entries)!={f['path'] for f in catalog['files']}:raise ValueError('Resumed snapshot paths changed')
        for f in catalog['files']:
            if entries[f['path']]['sha256']!=f['sha256'] or entries[f['path']]['bytes']!=f['bytes']:raise ValueError('Resumed snapshot bytes changed')
    ps=Path(os.environ['SystemRoot'])/'System32/WindowsPowerShell/v1.0/powershell.exe'
    env=dict(os.environ,PSModulePath=str(ps.parent/'Modules'))
    def psrun(script,*args):
        subprocess.run([str(ps),'-NoProfile','-ExecutionPolicy','Bypass','-File',str(ROOT/script),*map(str,args)],env=env,check=True)
    psrun('Sign-Channel.ps1','-CatalogPath',out/'catalog.json','-KeyDirectory',base/'private-online-signing','-OutputDirectory',out/'channel')
    # Never silently rotate the public key pinned in the distributed client.
    trust=json.loads((out/'channel/trust.json').read_text('utf-8'))
    trust_id=hashlib.sha256(trust['public_key_xml'].encode()).hexdigest()
    if previous and previous['public_key_sha256']!=trust_id:raise ValueError('Signing key changed; explicit client migration required')
    bootstrap=out/'TGC-Online-Installer.zip'
    make_client.build(out/'channel/trust.json',bootstrap)
    manifest=json.loads(manifest_path.read_text('utf-8-sig'))
    notes=out/'release-notes.md'
    engine_display=re.sub(r'\+[0-9]{8}(?:-[0-9]{6})?(?=-|$)','',manifest['engine_version'])
    changes='\n'.join('- '+line for line in manifest.get('change_notes',[]))
    notes.write_text(f"# TGC - Anime Total Overhaul (Korean)\n\n배포: TGCNV + TGO / 엔진: {engine_display}\n\nTGC-Online-Installer.zip을 압축 해제하고 Update.cmd를 실행하세요. TGCNV와 TGO를 설치·갱신합니다. Check-Updates.cmd로 변경을 확인합니다. 모드·캐시·DLL·런처는 백업 없이 덮어씁니다. 설치 중단 시 같은 Update.cmd를 다시 실행하세요. 이전 상태 복원은 제공하지 않습니다.\n\n{changes}\n\n파일·설치 도구 검증과 실제 게임 안정성 검증은 별개입니다. 이 배포의 stability_certified 값: {manifest.get('stability_certified',False)}. 남은 실제 게임 검증 항목은 manifest.json을 확인하세요.\n\n릴리스에는 인스톨러만 제공됩니다. 전체 팩 파일명은 TGCNV-TGO.zip으로 고정됩니다. 실제 패치 데이터는 GitHub Packages(GHCR)에서 자동으로 받습니다. 기존 온라인 인스톨러 사용자는 이 새 ZIP을 한 번 다시 받아 실행하세요. GitHub 로그인이나 Docker 설치는 필요하지 않습니다.\n\n[TGC](https://github.com/The-Grand-Combination/The-Grand-Combo) · [TGO](https://github.com/The-Grand-Combination/The-Grand-Orchestra) 제작자 및 음악 출처 표기는 배포 내 문서에 보존됩니다.\n",encoding='utf-8')
    with notes.open('a',encoding='utf-8') as handle:
        handle.write('\n[최신 인스톨러 다운로드 / Download latest installer](https://github.com/'+trust['repository']+'/releases/download/installer/TGC-Online-Installer.zip?sha256='+sha(bootstrap)+')\n')
    psrun('Verify-Publication.ps1','-Directory',out)
    publish(gh,out,bootstrap,notes,[online/'releases',online/'ghcr-releases'])
    psrun('Verify-Remote.ps1','-TrustPath',out/'channel/trust.json','-ExpectedRelease',release)
    # Re-read state to avoid overwriting newer local publication while uploading.
    current=json.loads(state_path.read_text('utf-8-sig'))
    record={'schema':2,'transport':'ghcr-v2','client_source_sha256':client_source_sha(),'release':release,'local_archive_sha256':state['sha256'],'catalog_sha256':sha(out/'catalog.json'),'public_key_sha256':trust_id,'published_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'repository':trust['repository'],'publication_record':str(out/'publication.json'),'public_verified':True,'local_release_changed_during_upload':current['release']!=release}
    temp=online_state_path.with_suffix('.json.tmp')
    temp.write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8');temp.replace(online_state_path)
    print(json.dumps(record,ensure_ascii=False))

def main(base,gh,python=sys.executable):
    import msvcrt
    lock=Path(base)/'online/publish.lock'
    with lock.open('a+b') as handle:
        if handle.tell()==0:handle.write(b'0');handle.flush()
        handle.seek(0)
        try:msvcrt.locking(handle.fileno(),msvcrt.LK_NBLCK,1)
        except OSError:raise RuntimeError('Another online publisher is running') from None
        try:return _main(base,gh,python)
        finally:handle.seek(0);msvcrt.locking(handle.fileno(),msvcrt.LK_UNLCK,1)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--base',required=True,type=Path);p.add_argument('--gh',required=True,type=Path)
    a=p.parse_args();main(a.base,a.gh)
