# TGC - Anime Total Overhaul (Korean)

Victoria II용 한국어 애니메이션 테마 오버홀 **TGCNV**와 음악 모드 **TGO**의 통합 배포입니다. 원본 [The Grand Combination](https://github.com/The-Grand-Combination/The-Grand-Combo)의 공개 포크입니다.

## 설치와 업데이트

1. [최신 온라인 설치 도구](https://github.com/Yukino-Chan/TGC-Anime-Total-Overhaul-Korean/releases/download/installer/TGC-Online-Installer.zip)를 받습니다.
2. ZIP을 모두 압축 해제하고 게임과 런처를 종료합니다.
3. **Update.cmd**를 실행하고 처음에는 Victoria II 설치 폴더의 `v2game.exe`를 선택합니다.
4. 설치 후 런처에서 **TGC - Anime Total Overhaul (Korean)**과 **TGO - The Grand Orchestra**를 함께 선택합니다.

이미 통합 배포 팩을 설치한 PC에서도 같은 도구를 사용할 수 있습니다. 이후에는 **Update.cmd**로 갱신합니다. 변경 여부만 확인하려면 **Check-Updates.cmd**, 직전 설치를 되돌리려면 **Restore-Update.cmd**를 실행합니다. 게임은 자동 실행하지 않습니다.

받는 PC에는 GitHub 로그인, Python, Git, Docker가 필요하지 않습니다. 지원되는 정품 Victoria II/DLC 환경과 64비트 Windows, Windows PowerShell 5.1이 필요합니다. 게임 버전·경로 조건은 도구와 배포 팩에 포함된 설치 안내를 확인하세요.

첫 다운로드는 약 1.2GB입니다. 이후에는 설치된 파일을 재사용하고 필요한 압축 묶음만 받습니다. 서명과 SHA-256 검증을 통과한 파일만 기존 설치 도구로 적용합니다. 기존 TGCNV/TGO 폴더의 개인 수정과 지도 캐시는 백업 후 배포본으로 교체됩니다. 세이브 파일은 건드리지 않습니다. 임시 파일과 백업을 포함해 충분한 디스크 공간을 확보하세요.

다운로드 캐시와 오프라인 복원 도구는 `%LOCALAPPDATA%\TGCNV-Updater`, 설치 백업은 게임 폴더와 TGCNV 문서 프로필의 `TGCNV_Backups`에 저장됩니다. 복원이 필요할 동안 보존하세요. 업데이트 도구 자체의 새 버전은 이 저장소에서 다시 받아야 합니다.

## 배포 상태

[통합 릴리스](https://github.com/Yukino-Chan/TGC-Anime-Total-Overhaul-Korean/releases/tag/installer)에서 엔진 버전과 변경 내역을 확인하세요. 파일·설치·복원 검증 완료가 캠페인 전체 안정성 검증을 의미하지는 않습니다. 각 배포의 실제 게임 검증 대기 항목은 릴리스 설명 및 `manifest.json`에 기록합니다.

릴리스는 **인스톨러 한 개**로 유지합니다. 실제 모드·음악·DLL·지도 캐시 데이터는 [GitHub Packages 보관소](https://github.com/Yukino-Chan/TGC-Anime-Total-Overhaul-Korean/pkgs/container/tgcnv-patches)에서 인스톨러가 자동으로 내려받습니다. 패치 목록은 `update-feed` 브랜치의 서명된 `channel.json`으로 확인합니다.

**이전 온라인 인스톨러 사용자는 새 ZIP을 한 번 다시 받아 실행하세요.** 기존 파일은 해시가 일치하면 재사용하고, 이전 설치의 오프라인 복원 기록도 유지합니다. 이후 같은 Update.cmd로 갱신할 수 있습니다. GitHub의 **Source code** ZIP은 설치 팩이 아닙니다.

이 포크의 기본 소스 트리는 원본 TGC 이력을 보존합니다. 배포용 TGCNV·TGO 데이터는 검증된 GHCR 객체에 보관하고, 온라인 배포·설치 도구 소스는 `online-update/`에서 제공합니다. 원본 안내는 [README.upstream.md](README.upstream.md)에 보존했습니다.

## 제작자와 출처

기반 모드: [The Grand Combination](https://github.com/The-Grand-Combination/The-Grand-Combo). 음악 모드: [The Grand Orchestra](https://github.com/The-Grand-Combination/The-Grand-Orchestra). 원본 제작자, 자산 및 음악의 출처 표기는 기존 모드 문서에 보존합니다. 배포 내 `OPENING_MUSIC.md`, `VICTORIA1_MUSIC.md` 및 음악 목록도 확인해 주세요. 이 프로젝트는 비공식 커뮤니티 모드입니다.
