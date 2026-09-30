"""Create a small portable online installer from an explicit public allowlist."""
from pathlib import Path
import argparse, hashlib, json, zipfile

ROOT=Path(__file__).parent
NAMES=('Update.ps1','Online-Core.psm1','Language.psm1')
GUIDE=r'''TGC - Anime Total Overhaul (Korean) — 온라인 설치·업데이트

1. 이 ZIP을 모두 압축 해제하세요. ZIP 안에서 바로 실행하지 마세요.
2. 게임과 런처를 종료하고 Update.cmd를 실행하세요.
3. 처음에는 Victoria II 설치 폴더의 v2game.exe를 선택하세요.
4. 설치가 끝나면 런처에서 TGC - Anime Total Overhaul (Korean)과
   TGO - The Grand Orchestra를 함께 선택하세요. 게임은 자동 실행하지 않습니다.

이미 배포 팩을 설치한 PC에서도 같은 Update.cmd를 사용할 수 있습니다.
변경 여부만 보려면 Check-Updates.cmd, 직전 설치를 되돌리려면
Restore-Update.cmd를 사용하세요. 복원은 인터넷 없이도 가능합니다.

필요 환경: 지원되는 정품 Victoria II 및 DLC 환경, 64비트 Windows,
Windows PowerShell 5.1, GitHub 및 ghcr.io에 연결 가능한 인터넷. Python, Git, Docker,
GitHub 계정은 받는 PC에 필요하지 않습니다. 자세한 게임 버전·경로 조건은
다운로드된 팩의 설치 안내.txt에서 확인하세요.

Release에는 이 인스톨러만 유지하고 실제 파일은 GitHub Packages(GHCR)에서 받습니다.
이전 온라인 인스톨러 사용자는 이번 새 ZIP을 한 번 다시 받아 실행하세요.
기존 설치 파일과 복원 기록은 그대로 사용할 수 있습니다.

처음에는 약 1.2GB를 받습니다. 다음 업데이트는 기존 파일의 해시를 비교하고
달라진 파일이 든 압축 묶음만 받습니다. 다운로드 중 끊겼다면 다시 실행하세요.
서명, 크기, SHA-256 검증이 실패하면 설치하지 않습니다. 배포 교체 직후
목록은 한 개의 서명된 파일로 확인합니다.

파일을 임시 복원하고 기존 모드·캐시를 백업하므로 게임과 캐시 드라이브에
충분한 공간이 필요합니다(기본 배포 기준 합계 약 8GB 이상 권장).
기존 TGCNV/TGO 폴더의 개인 수정은 백업에 남고 배포본으로 교체됩니다.
세이브 파일은 변경하지 않지만 새 엔진과 기존 세이브의 호환성을 보증하지 않습니다.

다운로드 캐시 및 서명된 복원 도구: %LOCALAPPDATA%\TGCNV-Updater
설치 백업: 게임 폴더와 TGCNV 문서 프로필의 TGCNV_Backups
복원이 필요할 동안 위 캐시와 백업을 보존하세요. 이 도구는 게임을 실행하거나
강제로 종료하지 않고, 개인 설정·세이브를 서버로 전송하지 않습니다.

문서 폴더가 기본 위치와 다르면 다음처럼 실행하세요.
Update.cmd -GamePath "D:\Games\Victoria 2" -DocumentsPath "D:\Documents"
쓰기 권한 오류가 나면 현재 Windows 계정에서 관리자 권한으로 실행하세요.
다른 계정으로 실행하면 문서 폴더와 다운로드 캐시가 달라집니다.

서명 공개키는 이 도구에 고정되어 있습니다. 업데이트 도구 자체는 자동으로
교체하지 않습니다. 도구의 새 버전이 안내되면 같은 공식 저장소에서 받으세요.
개인 GitHub 토큰·비밀번호·서명 개인키는 포함하지 않습니다.

저장소: https://github.com/Yukino-Chan/TGC-Anime-Total-Overhaul-Korean
원본 TGC: https://github.com/The-Grand-Combination/The-Grand-Combo
TGO: https://github.com/The-Grand-Combination/The-Grand-Orchestra
모드 및 음악의 기존 제작자·출처 표기는 각 모드 문서를 확인하세요.
'''

def build(trust_path,output):
    trust=Path(trust_path).read_bytes()
    t=json.loads(trust)
    if '<D>' in t['public_key_xml'] or t['repository']!='Yukino-Chan/TGC-Anime-Total-Overhaul-Korean': raise ValueError('Invalid public trust config')
    files={name:(ROOT/name).read_bytes() for name in NAMES}
    for name,data in files.items():
        if b'TGCNV_QA_' in data or b'PRIVATE FIXTURE' in data: raise ValueError('Fixture code in client')
        if not data.startswith(b'\xef\xbb\xbf'): raise ValueError('PowerShell source needs UTF-8 BOM')
    for name,action in [('Update.cmd','Update'),('Check-Updates.cmd','Check'),('Restore-Update.cmd','Restore')]:
        files[name]=(f'@echo off\r\nsetlocal\r\n"%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Update.ps1" -Action {action} %*\r\nset "result=%errorlevel%"\r\npause\r\nexit /b %result%\r\n').encode('ascii')
    files['Change-Language.cmd']=('@echo off\r\nsetlocal\r\n"%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Update.ps1" -Action Update -ChooseLanguage %*\r\nset "result=%errorlevel%"\r\npause\r\nexit /b %result%\r\n').encode('ascii')
    files['trust.json']=trust
    files['온라인 설치 안내.txt']=(GUIDE+'\n언어 선택: 처음 설치할 때 한국어 / English를 선택합니다. 이후 업데이트에도 유지됩니다. 변경하려면 게임 종료 후 Change-Language.cmd를 실행하세요.\n명령줄: Update.cmd -Language en 또는 Update.cmd -Language ko\n').encode('utf-8-sig')
    files['README-English.txt']=('TGC - Anime Total Overhaul\r\n\r\nExtract the entire ZIP. Close the game and launcher, then run Update.cmd. Select v2game.exe in your Victoria II folder. When the release includes language files, choose Korean or English. Your choice is retained across updates. Run Change-Language.cmd to choose again, or use Update.cmd -Language en. Select TGC - Anime Total Overhaul (English) and TGO - The Grand Orchestra in the launcher. Keep the base game language set to English.\r\n\r\nCheck-Updates.cmd checks updates. Restore-Update.cmd restores the previous installation, including its language choice, offline. Language changes use the same signed update feed and require internet access. Downloads and files are verified before install. Saves are preserved. Backups reside in TGCNV_Backups; updater cache is in %LOCALAPPDATA%\\TGCNV-Updater.\r\nRequires supported Victoria II/DLC, 64-bit Windows and Windows PowerShell 5.1. No Python, Git, Docker or GitHub account is needed.\r\n').encode('utf-8')
    files['SHA256SUMS.txt']=''.join(f'{hashlib.sha256(data).hexdigest()}  {name}\n' for name,data in sorted(files.items())).encode('utf-8')
    output=Path(output)
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for name,data in sorted(files.items()):
            info=zipfile.ZipInfo('TGC-Online-Installer/'+name,date_time=(2026,9,26,0,0,0))
            info.compress_type=zipfile.ZIP_DEFLATED
            z.writestr(info,data)
    with zipfile.ZipFile(output) as z:
        if z.testzip():raise ValueError('Client ZIP CRC')
        for name,data in files.items():
            if z.read('TGC-Online-Installer/'+name)!=data:raise ValueError('Client ZIP content')
    digest=hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(output.suffix+'.sha256').write_text(digest+'  '+output.name+'\n',encoding='utf-8')
    return {'path':str(output),'sha256':digest,'bytes':output.stat().st_size}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--trust',required=True);p.add_argument('--output',required=True)
    a=p.parse_args();print(json.dumps(build(a.trust,a.output)))
