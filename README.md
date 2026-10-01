# TGC - Anime Total Overhaul (Korean)

Victoria II용 스탠드얼론 한국어·영어 애니메이션 오버홀 **TGCNV**와 음악 모드 **TGO**입니다. 이 브랜치에는 두 모드의 파일과 관련 설치·업데이트 소스가 있습니다. 최신 통합 배포본과 같은 모드 데이터를 제공합니다. 전체 팩은 `TGCNV-TGO.zip`, 체크섬은 `TGCNV-TGO.zip.sha256`, 설치 안내는 `TGCNV-TGO-설치안내.txt` 이름을 계속 사용합니다.

## 설치와 업데이트

1. [온라인 설치 도구](https://github.com/Yukino-Chan/TGC-Anime-Total-Overhaul-Korean/releases/download/installer/TGC-Online-Installer.zip?sha256=e3cfe8a9fb0c2d2e5bfb1f4fb30db8f41abf7eab4038dc973dd8ccdead239910)를 받습니다.
2. ZIP 전체를 압축 해제하고 게임과 런처를 종료합니다.
3. **Update.cmd**를 실행하고, 처음에는 Victoria II 설치 폴더의 `v2game.exe`를 선택합니다. 처음 설치할 때 한국어 또는 English를 고릅니다.
4. 런처에서 **TGC - Anime Total Overhaul**과 **TGO - The Grand Orchestra**를 함께 선택합니다.

이후에는 Update.cmd로 갱신하고, Check-Updates.cmd로 확인하며, Restore-Update.cmd로 직전 설치를 되돌립니다. 언어는 Change-Language.cmd로 바꿉니다. 받는 PC에는 GitHub 로그인, Python, Git, Docker가 필요하지 않습니다. 세이브 파일은 건드리지 않습니다.

이 저장소의 폴더를 게임에 직접 복사하는 방식은 지원하지 않습니다. 게임 폴더의 로더 DLL, `TGCNV.exe`, 검증된 지도 캐시, 언어 선택은 설치 도구가 함께 설치합니다.

## 저장소 구성

| 경로 | 내용 |
|---|---|
| `TGCNV/`, `TGCNV.mod` | TGCNV 모드 데이터, 확장 엔진(`runtime/`), 한국어·영어 문구 은행(`runtime/languages/`) |
| `TGO/`, `TGO.mod` | TGO 음악, 재생목록, 음악 설정 이벤트, 곡 출처 문서 |
| `online-update/` | 서명된 온라인 설치·언어 선택·업데이트·게시 도구와 검사 |

설치 도구와 실제 패치 파일은 [installer 릴리스](https://github.com/Yukino-Chan/TGC-Anime-Total-Overhaul-Korean/releases/tag/installer)와 [GitHub Packages](https://github.com/Yukino-Chan/TGC-Anime-Total-Overhaul-Korean/pkgs/container/tgcnv-patches)로 제공합니다. 서명된 업데이트 목록은 `update-feed` 브랜치에 있습니다. 원본 TGC 소스 트리는 이 브랜치의 이전 커밋 이력에 남아 있습니다.

## 배포 상태

이벤트·신문 삽화 1,235개를 새 원화 110종으로 교체했고, 기존 해상도·압축·투명도를 보존했습니다. 게임 내 실제 표시 확인은 아직입니다. 이 배포는 사용자 승인 실험판입니다. DLL 0.6.8.4와 돌격대·병종 버튼·한영 명칭, 생필품 기본 수요, 세율·봉급·장인 적립금 보존과 선택 소비 대금 정산, 최신 중앙아시아·북유럽 경계 및 캐시를 포함합니다. 프로빈스 번호는 유지하지만 경계·주 배정·시작 소유권이 바뀌므로 새 캠페인으로 시작해 주세요. 개인 세이브는 배포하지 않습니다. 경제 통합본에서 첫날 추가 거래·매출은 확인됐지만 순이익 증가폭, 최종 0.6.8.4의 실제 저장 로드·시간 진행·재저장 및 장기 안정성은 미검증입니다. 기존 좌표 차이 24곳과 자료·환경 관련 검사 미통과 9건은 검토 기록에 유지했고 변경분의 새 좌표 불일치는 없습니다. 멀티플레이 참가자는 같은 배포를 설치해야 합니다.

기존 `event 16` 수동 호출 안내는 폐기합니다. 이벤트 16·19를 플레이어 국가에서 콘솔로 열면 크래시가 날 수 있습니다. 이번 배포는 지도 지명 동기화와 별도의 자동 복구를 사용합니다.

## 제작자, 출처와 권리

- 기반 모드: [The Grand Combination](https://github.com/The-Grand-Combination/The-Grand-Combo). 음악 모드: [The Grand Orchestra](https://github.com/The-Grand-Combination/The-Grand-Orchestra). 곡목과 연주 출처는 `TGO/OPENING_MUSIC.md`, `TGO/VICTORIA1_MUSIC.md`에 있습니다.
- Victoria II © Paradox Interactive. 원본 게임과 DLC는 포함하지 않습니다.
- 블루 아카이브의 캐릭터, 모델, UI 요소에 대한 권리는 NEXON Games Co., Ltd. 및 관련 권리자에게 있습니다. 국기와 초상에 쓰인 다른 작품의 캐릭터는 각 권리자에게 권리가 있습니다. 이 프로젝트는 비공식·비영리 팬 모드이며 권리자와 관계가 없습니다.
- 글꼴: 경기천년체 © 경기도.
- 일부 UI 아이콘: [game-icons.net](https://game-icons.net)의 Delapouite, Lorc, Skoll, Cathelineau, Sbed, Pierre Leducq, Guard13007, Zeromancer, John Colburn, Willdabeast, Andy Meneely, Quoting, Lucas 작품을 [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)으로 사용하고 색과 크기를 바꿨습니다.
- 기병의 말 모델: Quaternius, *Ultimate Animated Animal Pack* (Horse, White Horse), [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).

## English

### Overview

TGCNV is a standalone Korean/English anime overhaul for Victoria II: Heart of Darkness, built on top of [TGC — The Grand Combination](https://github.com/The-Grand-Combination/The-Grand-Combo). It combines anime-themed portraits, flags, interface assets and unit models with customized map and gameplay data, runtime extensions, and Korean/English localization. The package includes its loader, verified map cache and language files; a separate TGC download is not needed. [TGO — The Grand Orchestra](https://github.com/The-Grand-Combination/The-Grand-Orchestra) is an optional companion music mod that adds period music, playlists, and music-related events; it is included in the package, and you can leave it unchecked in the launcher when you do not want its music.

This repository holds the TGCNV and TGO mod data together with the installation, language, and update tools. It is an unofficial, non-commercial fan project with no connection to the rights holders. Attribution, licensing, and music sources are listed in the [credits section above](#제작자-출처와-권리).

### Requirements

- A legitimate copy of Victoria II with A House Divided and Heart of Darkness, updated to version 3.04, plus the game's DirectX 9 components.
- 64-bit Windows with Windows PowerShell 5.1 available.
- An internet connection for the online installer and for update checks.
- Enough free space for the base game, the mod files, and the backups the tools keep when they update or restore.

Prefer regular local game and Documents paths. Junction/symlink paths are rejected, and non-ASCII or OneDrive paths have not been fully validated.

No GitHub account, Python, Git, or Docker installation is required. The tools do not touch your save files.

### First installation

1. Download **TGC-Online-Installer.zip** from the official [installer release](https://github.com/Yukino-Chan/TGC-Anime-Total-Overhaul-Korean/releases/tag/installer).
2. Extract the entire ZIP to a new, empty folder. Do not run the tools from inside the archive.
3. Close Victoria II and its launcher.
4. Run **Update.cmd**.
5. Select `v2game.exe` in your Victoria II installation folder when prompted.
6. Choose **Korean** or **English** for the mod on the first install.
7. Leave the base game language setting at **English**; TGCNV supplies its own text.
8. In the launcher, enable **TGC - Anime Total Overhaul (English)** (or **(Korean)** if you selected Korean) and, optionally, **TGO - The Grand Orchestra**.

### Command reference

| Command | Purpose |
| --- | --- |
| `Update.cmd` | Installs or updates the bundled TGCNV and TGO files. The first run asks for `v2game.exe` and your language. |
| `Check-Updates.cmd` | Checks whether a newer signed update is available without changing installed files. |
| `Change-Language.cmd` | Runs an update with a new Korean/English choice. Close the game first; an internet connection is required. |
| `Restore-Update.cmd` | Returns the installation to the backup created before the previous update. |

For an explicit language choice, use `Update.cmd -Language en` or `Update.cmd -Language ko`. The language option applies to installation/update, not to check or restore commands.

### Offline installation

When an offline package is provided, it is named **TGCNV-TGO.zip** and is published together with **TGCNV-TGO.zip.sha256** and **TGCNV-TGO-설치안내.txt**, which contains the Korean setup notes.

1. Check the archive against the accompanying `.sha256` file.
2. Extract the whole archive into a new, empty folder. Because the folder name is fixed, do not merge it with an older extracted pack.
3. Run `Verify.cmd` to check the extracted package files against their manifest.
4. Close the game and launcher, then run `Setup.cmd -Language en` (use `-Language ko` for Korean).
5. Run `Restore.cmd` to return to the previous installation if something goes wrong.

### Later updates

After the first installation, updates reuse the tools and files you already have: run them again from the same folder, and the language you chose is remembered. Keep the backups and the updater's cached installation records; the supported offline restore uses both. Update only while the game and launcher are closed.

### Source archives are not installers

The ZIPs and repository folders that contain the mod sources are not installers. Copying them into the Victoria II directory does not produce a working installation, because the loader, the verified map cache, and the language selection must be set up by the installer tools. Only the official installer release and the offline packages described above are supported; repackaged or third-party copies are not. Victoria II game files and DLC are not included in any package.

Do not open legacy events `16` or `19` through the console on a player country: their effect preview can crash the game. The previous manual `event 16` recommendation is withdrawn. This release uses map label synchronization and a separate automatic repair event.

### Compatibility and verification

Event and newspaper illustrations have been replaced with 1,235 DDS assets drawn from 110 new Blue Archive-inspired scenes. The original dimensions, compression formats, transparency and aggregate texture size are preserved. Actual in-game rendering has not yet been checked. The current mod uses a rebuilt province layout. This experimental distribution includes engine 0.6.8.4, Sturmtruppe and refreshed unit buttons and labels, higher basic POP needs, revised tax limits and state pay, preservation of artisan input reserves, and optional domestic food-stock purchases with producer settlement. It includes the latest completed Central Asian and Nordic border updates and their matching cache. Province IDs are preserved, but borders, administrative state membership and starting ownership have changed: start a fresh campaign. Personal saves are not distributed or automatically converted. The economics integration build recorded extra first-day purchases and gross sales; a net-profit improvement has not been measured. The final 0.6.8.4 build passed isolated restoration tests using five real save journals, but live save loading, time advancement, resaving and long campaigns still need testing. Twenty-four inherited province-coordinate differences and nine data/environment-related test failures are retained in the review evidence; changed map inputs introduce no new inconsistencies. All multiplayer participants must use the same build. Victoria II remains a 32-bit game; helper processes do not turn the whole engine into a 64-bit application.

The online updater authenticates signed metadata and checks downloaded file hashes before installation. For an offline archive, compare its SHA-256 with the trusted accompanying checksum and run Verify.cmd after extraction. If a check fails, keep the downloaded file and the error log, and do not hand-mix files from different packages; download again from the official release instead. If Windows denies write access, run the tool as administrator under the same Windows account so that its Documents profile stays the same.
