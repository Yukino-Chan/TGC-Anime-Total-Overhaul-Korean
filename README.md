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

설치된 실험용 DLL은 **0.6.8.8**입니다. 공중전·해전 선택 기반 창과 국가별 제해권 툴팁, 수요 기반 상세 재화 생산 특화와 아이콘, 종속국 열강 승격 제한, 2차대전 기술·발명 효과, 지형·해전 UI를 갱신했습니다. 한국어·English 문구도 현재 효과에 맞췄습니다. 최종 코드 723개 검사와 GUI 정적 검사, 생산 특화 28개 테스트·IPC 검사, 종속국 595개 검사 기록을 재사용하고 설치 파일을 대조했습니다. 공장 아이콘 유지 수정은 사용자 확인을 받았지만 최종 통합 빌드의 클릭·표시·장기 경제·저장 재로드는 미검증입니다. 새 캠페인 기준 실험판이며 기존 지도 좌표 차이 24곳과 자료·환경 제한 9건을 유지합니다. 네이티브 게임·렌더러는 32비트이고 일부 계산만 외부 64비트 작업자가 처리합니다. 미설치 렌더러·위신 연구와 개인 세이브는 포함하지 않습니다.

복제본 제거 패치 R64-E1과 `actor_clones = 0` 설정도 포함합니다. 각 액터 타입의 원본은 유지하며 추가 메시 복제본 생성을 끕니다. 재배치된 실행 파일 사본의 창 보호·설정 거부·반복 적용 검사 144개가 통과했고 기존 지연 로딩 282개·공군 공존 59개 검사도 동일 빌드에서 통과했습니다. 실제 애니메이션·선택·전투 및 같은 타입의 여러 유닛 표시는 미검증입니다.

1836년 시작 인구 125개 파일의 중복 POP 줄을 합치고 군인 POP를 보충했으며, 부대 파일 70개의 주둔지 번호를 고쳐 시작 연대가 사라지던 문제(예: 영국 케이프 수비대)를 해결했습니다. 새 캠페인에만 적용됩니다. 독립·해방 국가의 정부 형태 표와 하노버 해방 시점도 반영했고, English 옵션의 장갑차(Armored Car)·중형전차(Medium Tank) 용어와 짧은 병종 이름을 바로잡았습니다.

이번 재배포 엔진(e0562e91, 표시 버전 0.6.8.5)은 세이브를 편집해 부대 수가 군사 시간 기록과 달라지면 군사 시간이 켜지지 않던 문제를 고쳤습니다. 기록 밖의 부대는 새 부대처럼 편입하고 전투 기록 검사는 그대로 엄격합니다. 군사 시간이 멈춘 뒤에는 날짜 아래에 다시 실행 안내가 표시됩니다.

안트베르펜·헨트 위치와 벨기에·젤란트 주변 지명을 바로잡고, 서림뷔르흐 주를 벨기에에 남겼으며(런던 조약 이벤트·결정 연동), 벨기에 수도를 옮겼습니다. 몽골 지역의 주 5개를 재편하고 차하르 주 이름을 붙였습니다. 위치·주 경계가 바뀌어 지도 캐시를 다시 만들었습니다.

최근 지도 수정에는 포메라니아의 누락 항구, 폴란드·러시아 강 국경·주 배정·지명, 메멜 구획 교정이 포함됩니다. 대양과 연결된 해안 항구 1,217곳을 추가하고 293곳을 재배치했으며, 영문 지명 27개와 대응하는 캐시를 함께 갱신했습니다. 전체 팩은 새 캠페인 기준이며 실제 게임 화면 확인은 남아 있습니다.

기존 `event 16` 수동 호출 안내는 폐기합니다. 이벤트 16·19를 플레이어 국가에서 콘솔로 열면 크래시가 날 수 있습니다. 이번 배포는 지도 지명 동기화와 별도의 자동 복구를 사용합니다.

## 제작자, 출처와 권리

- 기반 모드: [The Grand Combination](https://github.com/The-Grand-Combination/The-Grand-Combo). 음악 모드: [The Grand Orchestra](https://github.com/The-Grand-Combination/The-Grand-Orchestra). 곡목과 연주 출처는 `TGO/OPENING_MUSIC.md`, `TGO/VICTORIA1_MUSIC.md`에 있습니다.
- Victoria II © Paradox Interactive. 원본 게임과 DLC는 포함하지 않습니다.
- 블루 아카이브의 캐릭터, 모델, UI 요소에 대한 권리는 NEXON Games Co., Ltd. 및 관련 권리자에게 있습니다. 국기와 초상에 쓰인 다른 작품의 캐릭터는 각 권리자에게 권리가 있습니다. 이 프로젝트는 비공식·비영리 팬 모드이며 권리자와 관계가 없습니다.
- 글꼴: 경기천년체 © 경기도.
- 일부 UI 아이콘: [game-icons.net](https://game-icons.net)의 Delapouite, Lorc, Skoll, Cathelineau, Sbed, Pierre Leducq, Guard13007, Zeromancer, John Colburn, Willdabeast, Andy Meneely, Quoting, Lucas 작품을 [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)으로 사용하고 색과 크기를 바꿨습니다.
- 기병의 말 모델: Quaternius, *Ultimate Animated Animal Pack* (Horse, White Horse), [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
- 하기아 소피아 모델: "[Miniature Mosque (Hagia Sophia)](https://sketchfab.com/3d-models/miniature-mosque-hagia-sophia-18b408db4e43425bb5667f5f1bf675ff)" by [typhoon476](https://sketchfab.com/typhoon476), [CC BY 4.0](http://creativecommons.org/licenses/by/4.0/). 색을 칠해 사용했습니다.
- 로딩 화면·메인 메뉴·게임 종료 화면: [ブルーアーカイブ 公式ファンキット](https://bluearchive.jp/fankit) (© NEXON Games Co., Ltd. / Yostar). 그림 속 © 표기는 그대로 두었습니다. 작가: 栗毛馬, Jell, TEDDY, 安曇アキタケ, ぼに～, 春夏冬ゆう, fame, マニュー, トモセシュンサク, モ誰 (5周年記念イラスト 포함).

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

The current experimental engine is **0.6.8.8**. It opens air and naval combat reports from active battle selections, adds country flags and naval-control shares to sea tooltips, and includes demand-based factory/RGO specialization, detailed goods icons, subject-country great-power restrictions, revised WWII technology effects, and terrain/naval UI updates. Korean and English descriptions match the revised effects. The release reuses 723 final code checks and separate GUI validation, 28 specialization tests plus x86/x64 IPC verification, and 595 subject-country checks, with installed hashes reconciled to their receipts. The factory-icon retention fix has user confirmation; final integrated battle interaction, rendering, long-term economic behavior and save/reload still require live validation. Specialization is learned again after loading. Use a fresh campaign. The inherited 24 coordinate differences and nine data/environment limitations remain. The native game and renderer are still 32-bit; external 64-bit workers handle selected calculations. Uninstalled renderer/prestige research and personal saves are excluded.

This build also includes the R64-E1 duplicate-removal update and `actor_clones = 0`. It keeps the original actor for each type and disables the extra mesh-copying actor clone. The update passed 144 relocated-PE buffer checks for guarded matching, rejected configuration and repeated installation. The same build passed the 282 lazy-loading and 59 air-profile coexistence checks. Live animation, selection, battles and several units of the same type remain unverified.

Antwerp and Ghent positions, Low Countries place names and the west Limburg state (kept in Belgium, with the London Treaty event and decisions) are corrected, the Belgian capital moved, five Mongolian states regrouped (including the new Chahar state), and the map cache rebuilt to match. The engine (e0562e91, still displayed as 0.6.8.5) restores military time when a save was edited so that its unit count differs from the saved military journal: units outside the journal are adopted like newly created units, while battle records are still checked strictly. After a military-time failure the date panel now shows a restart notice.

This build also merges duplicate POP lines in 125 starting-population files, tops up soldier POPs and fixes the home state of 70 order-of-battle files, so starting regiments (for example the British Cape garrison) no longer vanish; this applies to new campaigns. It adds the government table for newly independent or released countries and the Hanover release timing, and it corrects English unit terms (Armored Car, Medium Tank) and short unit names.

The latest map update corrects missing Pomeranian ports, the Poland/Russia river border, state membership and place names, and the Memel area. It adds 1,217 ocean-facing coastal port points and relocates 293 to their own coastlines. Twenty-seven English labels and the matching rebuilt cache are included. Use the package with a fresh campaign; final in-game visual checks remain outstanding.

The online updater authenticates signed metadata and checks downloaded file hashes before installation. For an offline archive, compare its SHA-256 with the trusted accompanying checksum and run Verify.cmd after extraction. If a check fails, keep the downloaded file and the error log, and do not hand-mix files from different packages; download again from the official release instead. If Windows denies write access, run the tool as administrator under the same Windows account so that its Documents profile stays the same.
