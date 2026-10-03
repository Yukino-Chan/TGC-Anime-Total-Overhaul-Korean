# TGC - Anime Total Overhaul (Korean)

Victoria II용 스탠드얼론 한국어·영어 애니메이션 오버홀 **TGCNV**와 음악 모드 **TGO**입니다. 이 브랜치에는 두 모드의 파일과 관련 설치·업데이트 소스가 있습니다. 최신 통합 배포본과 같은 모드 데이터를 제공합니다. 전체 팩은 `TGCNV-TGO.zip`, 체크섬은 `TGCNV-TGO.zip.sha256`, 설치 안내는 `TGCNV-TGO-설치안내.txt` 이름을 계속 사용합니다.

이전 공식 `TGCNV.exe`에서 설치가 중단되던 오류를 수정했습니다. 해당 구버전 런처는 백업 없이 교체되며 복원해도 최신 런처가 유지됩니다. 이미 받은 온라인 설치 폴더에서 `Update.cmd`를 다시 실행하세요.

**기존 GHCR 온라인 도구에서는 Update.cmd를 실행하면 됩니다.** 이번 배포는 인스톨러 실행 파일이 이전 배포와 같습니다. 처음 설치하거나 오래된 도구를 사용하는 경우 최신 인스톨러 ZIP을 받으세요. 기존 캐시·설치 기록·복원 자료는 유지하세요.

## 설치와 업데이트

1. [온라인 설치 도구](https://github.com/Yukino-Chan/TGC-Anime-Total-Overhaul-Korean/releases/download/installer/TGC-Online-Installer.zip)를 받습니다.
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

현재 실험용 엔진은 **0.6.8.15**입니다. 0.6.8.14에서 보완한 위신 외교·평화 협상 요청의 만료, 오류 처리와 미결 요청 정리를 포함합니다. 위신을 사용하는 평화 협상은 기존 AI 수락 판단과 전쟁 목표 합법성을 따르며, 실제 수락 때만 한 번 결제하는 규칙을 유지합니다. 실제 협상 화면, AI 응답, 대기 중 저장 후 재개와 장기 플레이는 미검증입니다.

이번 빌드에는 자동 **Renderer64 shadow 검증 파일럿**이 들어 있습니다. 게임 시작 시 숨김 x86 관리 프로그램이 한 번 실행되어 해당 게임 프로세스의 관측 기록을 기다리고, 별도 x64 작업자가 Iori의 첫 8개 submesh를 최대 4개 캡처 프레임까지 재생해 반환된 영역·색상·깊이와 해시를 검사합니다. 관리 프로그램은 최대 10분 대기 후 종료하며, 게임 종료 시 소유한 하위 프로세스도 종료됩니다. 게임 화면은 기존 네이티브 D3D9 렌더링을 계속 사용합니다. 이 파일럿은 게임 전체의 64비트 전환이나 실게임 지형 합성 완료를 뜻하지 않으며, 실게임 FPS·메모리 개선은 검증되지 않았습니다. 사용과 종료 방법은 아래 렌더러 관측 안내를 참고하세요.

리투아니아·크림·트란실바니아·폴란드·우크라이나·벨라루스·루마니아·에스토니아·보헤미아의 새 대표 9명과 QNG의 각청을 반영해 **10개국의 정부별 깃발 110개**를 갱신했습니다. QNG의 기존 리월 국호는 유지합니다. 변경된 국호·정부명·국민 형용사의 **183개 키**를 한국어와 English 문구 은행에 반영했으며, 한국어 원문 바이트와 스크립트 게임플레이 토큰을 보존했습니다. 깃발과 국호의 실제 게임 표시는 아직 확인하지 않았습니다.

TGO에서는 현재 재생목록과 시작곡이 참조하지 않는 음원 11개를 배포에서 제외했습니다. **실제 음악 106곡**, 재생목록, 음악 설정 이벤트와 기존 곡 출처 문서 3개는 유지합니다. 지도와 검증된 지도 캐시는 직전 배포와 같습니다. 런처에서는 선택한 TGCNV 언어와 함께 제공된 TGO 설정을 사용하세요. 이 빌드의 실게임 멀티플레이 체크섬은 별도로 검증하지 않았습니다.

설치 영수증과 후보 파일 해시를 대조했으며, shadow 구성 요소 13개 시나리오와 회귀 테스트 15개 묶음, 각 아키텍처의 프로토콜 검사 152개·픽셀 검사 17,050개 통과 기록을 확인했습니다. 이러한 검사는 실게임 화면·성능·장기 플레이 검증을 대신하지 않습니다. 기존 지도 검증 한계와 새 캠페인 권장을 유지합니다.

복제본 제거 패치 R64-E1과 `actor_clones = 0` 설정도 포함합니다. 각 액터 타입의 원본은 유지하며 추가 메시 복제본 생성을 끕니다. 재배치된 실행 파일 사본의 창 보호·설정 거부·반복 적용 검사 144개가 통과했고 기존 지연 로딩 282개·공군 공존 59개 검사도 동일 빌드에서 통과했습니다. 실제 애니메이션·선택·전투 및 같은 타입의 여러 유닛 표시는 미검증입니다.

1836년 시작 인구 125개 파일의 중복 POP 줄을 합치고 군인 POP를 보충했으며, 부대 파일 70개의 주둔지 번호를 고쳐 시작 연대가 사라지던 문제(예: 영국 케이프 수비대)를 해결했습니다. 새 캠페인에만 적용됩니다. 독립·해방 국가의 정부 형태 표와 하노버 해방 시점도 반영했고, English 옵션의 장갑차(Armored Car)·중형전차(Medium Tank) 용어와 짧은 병종 이름을 바로잡았습니다.

이전 군사 시간 보완(당시 표시 버전 0.6.8.5)은 세이브를 편집해 부대 수가 군사 시간 기록과 달라지면 군사 시간이 켜지지 않던 문제를 고쳤습니다. 기록 밖의 부대는 새 부대처럼 편입하고 전투 기록 검사는 그대로 엄격합니다. 군사 시간이 멈춘 뒤에는 날짜 아래에 다시 실행 안내가 표시됩니다.

안트베르펜·헨트 위치와 벨기에·젤란트 주변 지명을 바로잡고, 서림뷔르흐 주를 벨기에에 남겼으며(런던 조약 이벤트·결정 연동), 벨기에 수도를 옮겼습니다. 몽골 지역의 주 5개를 재편하고 차하르 주 이름을 붙였습니다. 위치·주 경계가 바뀌어 지도 캐시를 다시 만들었습니다.

최근 지도 수정에는 포메라니아의 누락 항구, 폴란드·러시아 강 국경·주 배정·지명, 메멜 구획 교정이 포함됩니다. 대양과 연결된 해안 항구 1,217곳을 추가하고 293곳을 재배치했으며, 영문 지명 27개와 대응하는 캐시를 함께 갱신했습니다. 전체 팩은 새 캠페인 기준이며 실제 게임 화면 확인은 남아 있습니다.

기존 `event 16` 수동 호출 안내는 폐기합니다. 이벤트 16·19를 플레이어 국가에서 콘솔로 열면 크래시가 날 수 있습니다. 이번 배포는 지도 지명 동기화와 별도의 자동 복구를 사용합니다.

## 제작자, 출처와 권리

- 기반 모드: [The Grand Combination](https://github.com/The-Grand-Combination/The-Grand-Combo). 음악 모드: [The Grand Orchestra](https://github.com/The-Grand-Combination/The-Grand-Orchestra). 곡목과 연주 출처는 `TGO/OPENING_MUSIC.md`, `TGO/VICTORIA1_MUSIC.md`, `TGO/VICTORIA1_MUSIC_MANIFEST.json`에 있습니다.
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

Older official `TGCNV.exe` launchers are now accepted and replaced without a backup. Restoring this update keeps the new launcher. Unknown executables remain untouched and their SHA-256 is shown in the error. Run `Update.cmd` again from your existing online installer folder to receive the repair.

**Existing GHCR updater users can run Update.cmd directly.** The installer is unchanged from the preceding release. Download the current installer ZIP for a first installation or to replace an older client. Keep the existing cache, installation records and recovery data.

### Later updates

After the first installation, updates reuse the tools and files you already have: run them again from the same folder, and the language you chose is remembered. Keep the backups and the updater's cached installation records; the supported offline restore uses both. Update only while the game and launcher are closed.

### Source archives are not installers

The ZIPs and repository folders that contain the mod sources are not installers. Copying them into the Victoria II directory does not produce a working installation, because the loader, the verified map cache, and the language selection must be set up by the installer tools. Only the official installer release and the offline packages described above are supported; repackaged or third-party copies are not. Victoria II game files and DLC are not included in any package.

Do not open legacy events `16` or `19` through the console on a player country: their effect preview can crash the game. The previous manual `event 16` recommendation is withdrawn. This release uses map label synchronization and a separate automatic repair event.

### Compatibility and verification

The current experimental engine is **0.6.8.15**, including the prestige diplomacy and peace-request lifecycle fixes from **0.6.8.14**. Expiration, error handling and cleanup of unresolved requests are covered by these cumulative changes. Prestige-assisted peace demands still follow the game's AI acceptance and wargoal legality checks, and prestige is charged once only after acceptance. The feature does not force acceptance. Live negotiation UI, AI responses, saving and reloading a pending request, and long-running campaigns remain unverified.

This package adds an automatic **Renderer64 shadow-validation pilot**. On game startup, a hidden x86 controller waits for an observation capture belonging to that game process. A separate x64 worker replays the supported Iori model's first eight submeshes for at most four captured frames. The controller checks the returned image region, color/depth formats and hashes, then exits. It waits for at most ten minutes; its owned child processes also stop when the game exits. The supplied configuration enables this bounded pilot. Unsupported captures, invalid data and timeouts are rejected while normal game drawing continues.

The game's existing native D3D9 renderer remains responsible for the screen. The pilot does not establish full terrain composition, identical original GPU buffers or complete 64-bit game rendering. A successful shadow report verifies the captured replay and response contract, not pixel equivalence with a live game screenshot. **Live-game FPS gains and memory savings have not been verified.** See the renderer section below for the configuration file and how to disable the pilot.

Country presentation is refreshed for ten countries: nine new representatives cover Lithuania, Crimea, Transylvania, Poland, Ukraine, Belarus, Romania, Estonia and Bohemia, while QNG uses Keqing and keeps its existing Liyue country names. The update replaces **110 government-specific flags** and updates **183 country-name, government-name and demonym keys** in the Korean/English language banks. The Korean source bytes and gameplay tokens in localized scripts are preserved. Installed flag/localization hashes and the existing integration reports were checked; final in-game flag and text presentation remains unverified.

TGO keeps **106 real music tracks**, the current playlist and music-settings event. Eleven audio files that are not referenced by the playlist or title theme are omitted. The three existing source documents remain included: `TGO/OPENING_MUSIC.md`, `TGO/VICTORIA1_MUSIC.md` and `TGO/VICTORIA1_MUSIC_MANIFEST.json`. The map geometry and verified map cache are unchanged from the previous package. Use the bundled TGO descriptor alongside the chosen TGCNV language; this build's live multiplayer checksum has not been independently verified.

The release review checked installation receipts and candidate hashes. Recorded shadow validation covers 13 component scenarios and 15 regression suites, including 152 protocol checks and 17,050 pixel checks for each architecture, plus parent/child lifetime checks. Those bounded checks do not replace live gameplay, performance or long-session validation. Use a fresh campaign and retain the existing map-validation limitations.

This build also includes the R64-E1 duplicate-removal update and `actor_clones = 0`. It keeps the original actor for each type and disables the extra mesh-copying actor clone. The update passed 144 relocated-PE buffer checks for guarded matching, rejected configuration and repeated installation. The same build passed the 282 lazy-loading and 59 air-profile coexistence checks. Live animation, selection, battles and several units of the same type remain unverified.

Antwerp and Ghent positions, Low Countries place names and the west Limburg state (kept in Belgium, with the London Treaty event and decisions) are corrected, the Belgian capital moved, five Mongolian states regrouped (including the new Chahar state), and the map cache rebuilt to match. An earlier military-time fix (then displayed as 0.6.8.5) restores military time when a save was edited so that its unit count differs from the saved military journal: units outside the journal are adopted like newly created units, while battle records are still checked strictly. After a military-time failure the date panel now shows a restart notice.

This build also merges duplicate POP lines in 125 starting-population files, tops up soldier POPs and fixes the home state of 70 order-of-battle files, so starting regiments (for example the British Cape garrison) no longer vanish; this applies to new campaigns. It adds the government table for newly independent or released countries and the Hanover release timing, and it corrects English unit terms (Armored Car, Medium Tank) and short unit names.

The latest map update corrects missing Pomeranian ports, the Poland/Russia river border, state membership and place names, and the Memel area. It adds 1,217 ocean-facing coastal port points and relocates 293 to their own coastlines. Twenty-seven English labels and the matching rebuilt cache are included. Use the package with a fresh campaign; final in-game visual checks remain outstanding.

The online updater authenticates signed metadata and checks downloaded file hashes before installation. For an offline archive, compare its SHA-256 with the trusted accompanying checksum and run Verify.cmd after extraction. If a check fails, keep the downloaded file and the error log, and do not hand-mix files from different packages; download again from the official release instead. If Windows denies write access, run the tool as administrator under the same Windows account so that its Documents profile stays the same.


### Renderer observation / 렌더러 관측

The observer records at most 32 draws and eight shaders in a local capture of at most 305,600 bytes. It does not upload captures. The automatic shadow pilot described above consumes only supported captures and runs its x64 worker outside the game process; the native renderer continues to draw the game.

To disable the shadow pilot on the next launch, close the game and set `shadow = 0` in `TGCNV/runtime/data/tgcnv_renderer64_shadow.txt`. To disable observation captures as well, set `observe = 0` in `TGCNV/runtime/data/tgcnv_renderer64_probe.txt`. The package includes the pilot's usage notes and xxHash license under `TGCNV/runtime/renderer64-shadow/`. A `complete` shadow result reports successful bounded capture verification and does not certify a live-game performance improvement.

다음 실행부터 shadow 검증을 끄려면 게임을 종료하고 `TGCNV/runtime/data/tgcnv_renderer64_shadow.txt`의 `shadow = 0`을 설정하세요. 관측 기록도 끄려면 `tgcnv_renderer64_probe.txt`의 `observe = 0`을 설정합니다. `complete` 결과는 해당 캡처의 제한된 검증 성공을 뜻하며 실게임 화면 일치나 성능 개선을 보증하지 않습니다.

CheatPack V2.10 credits: Bob Bobington, with contributions by Lord Unhold and Dr.; TGC/GFM image credits are retained in `TGCNV/docs/TGCNV_CheatPack.ko.md`.
