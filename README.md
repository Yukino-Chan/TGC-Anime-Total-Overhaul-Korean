# TGC - Anime Total Overhaul (Korean)

Victoria II용 스탠드얼론 한국어·영어 애니메이션 오버홀 **TGCNV**와 음악 모드 **TGO**입니다. 이 브랜치에는 두 모드의 파일과 관련 설치·업데이트 소스가 있습니다. 검토한 통합 배포본의 모드 데이터를 제공하며, Git 크기 상한을 넘는 생성 캐시는 설치기가 별도로 받습니다. 전체 팩은 `TGCNV-TGO.zip`, 체크섬은 `TGCNV-TGO.zip.sha256`, 설치 안내는 `TGCNV-TGO-설치안내.txt` 이름을 계속 사용합니다.

설치기는 모드·캐시·DLL·런처를 **백업 없이 덮어씁니다.** 이전 버전 자동 복원은 제공하지 않으며, 설치가 중단되면 같은 설치기를 다시 실행하세요. 세이브와 개인 설정은 유지됩니다.

**직전 백업 없는 설치기를 받았다면 같은 Update.cmd를 실행하면 됩니다.** 설치기는 바뀌지 않았습니다. 그보다 오래된 설치기를 쓰는 경우 최신 ZIP을 받아 주세요.

## 설치와 업데이트

1. [온라인 설치 도구](https://github.com/Yukino-Chan/TGC-Anime-Total-Overhaul-Korean/releases/download/installer/TGC-Online-Installer.zip)를 받습니다.
2. ZIP 전체를 압축 해제하고 게임과 런처를 종료합니다.
3. **Update.cmd**를 실행하고, 처음에는 Victoria II 설치 폴더의 `v2game.exe`를 선택합니다. 처음 설치할 때 한국어 또는 English를 고릅니다.
4. 런처에서 **TGC - Anime Total Overhaul**과 **TGO - The Grand Orchestra**를 함께 선택합니다.

이후에는 Update.cmd로 갱신하고 Check-Updates.cmd로 확인합니다. 언어는 Change-Language.cmd로 바꿉니다. 받는 PC에는 GitHub 로그인, Python, Git, Docker가 필요하지 않습니다. 세이브는 유지됩니다.

이 저장소의 폴더를 게임에 직접 복사하는 방식은 지원하지 않습니다. 게임 폴더의 로더 DLL, `TGCNV.exe`, 검증된 지도 캐시, 언어 선택은 설치 도구가 함께 설치합니다.

## 저장소 구성

| 경로 | 내용 |
|---|---|
| `TGCNV/`, `TGCNV.mod` | TGCNV 모드 데이터, 확장 엔진(`runtime/`), 한국어·영어 문구 은행(`runtime/languages/`) |
| `TGO/`, `TGO.mod` | TGO 음악, 재생목록, 음악 설정 이벤트, 곡 출처 문서 |
| `online-update/` | 서명된 온라인 설치·언어 선택·업데이트·게시 도구와 검사 |

설치 도구와 실제 패치 파일은 [installer 릴리스](https://github.com/Yukino-Chan/TGC-Anime-Total-Overhaul-Korean/releases/tag/installer)와 [GitHub Packages](https://github.com/Yukino-Chan/TGC-Anime-Total-Overhaul-Korean/pkgs/container/tgcnv-patches)로 제공합니다. 서명된 업데이트 목록은 `update-feed` 브랜치에 있습니다. 원본 TGC 소스 트리는 이 브랜치의 이전 커밋 이력에 남아 있습니다.

## 배포 상태

현재 실험용 엔진은 **0.6.8.40**입니다. 엔진 0.6.8.40: 큰 지도 국가명이 흰 사각형으로 나오던 텍스처 파일 읽기 제한을 수정했습니다. 실제 읽기 버퍼와 최초 로드·재로드 제한을 함께 16MiB에서 33MiB로 늘렸습니다.

읽기 버퍼는 이전보다 17MiB 증가합니다. 원본 코드 서명이나 세 값이 맞지 않으면 적용을 거부하며, 부분 적용을 되돌리지 못한 상태에서는 시작을 진행하지 않습니다.

한글 11,172자와 자모 94자, 글꼴 42파일, 한국어/English, TGO, 지도 캐시와 백업 없는 설치기는 직전 배포와 같습니다. 배포용으로 바뀐 게임 파일은 DLL 1개뿐입니다.

읽기 용량·GUI 텍스처 진단·전체 한글 디코딩의 오프라인 검사 3종과 설치 해시를 확인했습니다. 실제 게임의 지도 글자 표시·저장 재로드·두 PC 멀티플레이는 아직 미검증입니다. 게임을 완전히 종료하고 갱신한 뒤 다시 실행하세요.

이전 배포에서 이어지는 기능으로, 군사·공군 시간 처리, 자정 단계 분산과 저장 변수의 반복 탐색 축소를 포함합니다. 변수 조회 객체 안에서 최근 경로만 재사용하고 현재 메모리·국가·날짜 및 저장 검사는 유지합니다. 소유 메모리 fixture 비교에서 변수 조회 비용이 17~48% 감소했지만 이 수치는 실게임 FPS나 전체 처리 시간의 개선율이 아닙니다.

**BA 캐릭터 117개 모델·1,275개 메시의 64비트 렌더러**가 활성화되어 있습니다. 별도 x64 작업자가 캐릭터를 그린 뒤 반환한 색상·깊이 타일을 기존 화면에 합성합니다. 초기 준비, 입력 불일치, 작업자 오류·지연 또는 처리 예산 초과 시 기존 그리기를 사용합니다. 게임 본체는 32비트이며 전체 지형·UI가 64비트로 전환된 것은 아닙니다. 자동 캡처와 shadow 검증은 기본 비활성화 상태입니다.

기술 300개·발명 325개의 최종 데이터와 관련 조정, 0.5 단위 수치 표시를 반영했습니다. 변경된 영문 설명 583키의 숫자·부호·참조 이름을 검사했고 한국어 원문과 스크립트 게임플레이 구조를 보존했습니다. 남미 대상 16개 주를 11개로 통합하고 15개 프로빈스를 재배정했으며, 타바팅가를 아마조나스–호라이마에 배정했습니다. 최종 주 표와 새 지도 캐시를 함께 설치합니다. **새 캠페인 기준**이며 개인 세이브 변환은 포함하지 않습니다.

해군 3D 모델 5종, 지상·해상·공중 전투 효과와 UI 효과음 WAV 12개를 포함합니다. TGO 신곡 15곡을 추가해 재생목록은 **121곡**입니다. `TGO/music/Anime/TRACKLIST.txt`와 `provenance.json`에 신곡 출처를, `TGCNV/sound/BA_UI_SFX_SOURCES.txt`에 효과음 출처를 기록했습니다. BA 3곡은 상록수의 비공식 오케스트라 편곡이며 나머지 12곡은 공식 OST/배포 음원 출처입니다. 기존 음악 출처 문서도 유지합니다.

설치 완료 기록과 선택 파일 해시, TGO 의존명, 캐시 5개 서명 및 한영 데이터 구조를 확인했습니다. 0.6.8.32의 검사 29개 묶음은 통과했습니다. 최종 통합 저장·재로드, 두 PC 멀티플레이/OOS, 전체 모델 표시와 장기 성능은 미검증입니다. 기존 좌표 차이 24곳과 검사 한계 9건은 유지합니다.

생성된 렌더러 캐시 `runtime/renderer64-live/cache/all.assets`는 127MB로 Git의 파일 크기 상한을 넘습니다. **전체 ZIP과 온라인 설치에는 이 파일이 포함됩니다.** 이 브랜치에는 대신 `online-update/large-assets.json`의 정확한 크기·SHA-256과 설치 경로 안내를 둡니다.

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
- 64-bit Windows with Windows PowerShell 5.1, Direct3D 11 and the D3DCompiler_47 system component for the character-renderer worker.
- An internet connection for the online installer and for update checks.
- Enough free space for the base game, installed mods, and temporary incoming files. The installer no longer keeps old-version backups.

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
| `Restore-Update.cmd` | Explains the overwrite-only policy; no rollback is performed. |

For an explicit language choice, use `Update.cmd -Language en` or `Update.cmd -Language ko`. The language option applies to installation/update, not to check or restore commands.

### Offline installation

When an offline package is provided, it is named **TGCNV-TGO.zip** and is published together with **TGCNV-TGO.zip.sha256** and **TGCNV-TGO-설치안내.txt**, which contains the Korean setup notes.

1. Check the archive against the accompanying `.sha256` file.
2. Extract the whole archive into a new, empty folder. Because the folder name is fixed, do not merge it with an older extracted pack.
3. Run `Verify.cmd` to check the extracted package files against their manifest.
4. Close the game and launcher, then run `Setup.cmd -Language en` (use `-Language ko` for Korean).
5. If installation is interrupted, close the game and rerun the same `Setup.cmd`. There is no automatic rollback.

All managed mods, cache, DLLs and launcher files are overwritten without backups, including older official `TGCNV.exe` versions. Unknown executables are still rejected without deleting them. Obsolete files and personal modifications inside the managed TGCNV/TGO and map-cache folders are removed. Saves, settings, other mods, and preexisting backup folders are preserved.

**Existing GHCR updater users can run Update.cmd directly.** The installer is unchanged from the preceding release. Download the current installer ZIP for a first installation or to replace an older client. Keep the existing cache, installation records and recovery data.

### Later updates

If you already downloaded the overwrite-only installer from the preceding release, run the same Update.cmd; the installer is unchanged. Users of older clients should download the current official ZIP. Later runs reuse matching installed files and verified downloads; the selected language is remembered. Temporary incoming files are cleaned up after each run, and a small current installation receipt remains at `TGCNV_Install/receipt.json`. If installation is interrupted, rerun the same installer to complete it. `tgcnv_lua51_ori.dll` is a required original Lua runtime dependency, not a previous-version backup; do not delete it. Update only while the game and launcher are closed.

### Source archives are not installers

The ZIPs and repository folders that contain the mod sources are not installers. Copying them into the Victoria II directory does not produce a working installation, because the loader, the verified map cache, and the language selection must be set up by the installer tools. Only the official installer release and the offline packages described above are supported; repackaged or third-party copies are not. Victoria II game files and DLC are not included in any package.

Do not open legacy events `16` or `19` through the console on a player country: their effect preview can crash the game. The previous manual `event 16` recommendation is withdrawn. This release uses map label synchronization and a separate automatic repair event.

### Compatibility and verification

The current experimental engine is **0.6.8.40**. It fixes the native texture-file read limit that rejected large full-Hangul font atlases and caused large country names on the map to appear as white squares. The read-buffer allocation, initial-load limit and reload limit are raised together from 16 MiB to 33 MiB before the native texture manager is constructed. This adds 17 MiB to the read buffer. Original-code signatures and all three values are checked; mismatched or partial patches are refused, and an incomplete rollback prevents startup.

Only the installed engine DLL changes. All 42 font files retain the full 11,172 modern Hangul syllables and 94 compatibility jamo. Korean/English text, TGO, the verified map cache and the overwrite-only installer remain unchanged. Close the game completely, update, then restart so the replacement DLL is loaded.

Three recorded offline suites passed: native texture read capacity, GUI texture diagnostics and full Hangul decoding. The new capacity test contains 730 checks. Installed-file hashes and the existing font contract were verified. Successful upload to a separate D3D9Ex test device does not certify in-game rendering. Actual map labels, save/reload and two-PC multiplayer still need confirmation.

Features inherited from the preceding package remain available. It includes the military/air scheduling changes and separates native midnight date, military and air work into successive frames while retaining once-only processing. Repeated native saved-variable lookups reuse a bounded path inside each lookup object. Current memory, owner/date and saved-value checks remain in place. A controlled owned-memory fixture measured 17–48% lower variable-lookup cost; this is **not a measured live-game FPS or total simulation improvement**.

The supplied configuration enables the **64-bit renderer for 117 Blue Archive character models and 1,275 meshes**. An external x64 worker returns color/depth tiles that are composed into the existing game view. Startup preparation, unsupported input, worker errors, delays or an exceeded frame budget fall back to native drawing. The game executable remains 32-bit; terrain and the entire UI have not been converted to a 64-bit game engine. Automatic observation captures and the former shadow pilot are disabled by default.

The update includes the final data for 300 technologies and 325 inventions, their related balancing changes and descriptions with half-unit display increments. All 583 changed English keys were checked for numeric values, signs and canonical references. Korean source bytes and gameplay tokens in localized scripts are preserved. In the affected South American area, 16 states become 11 and 15 provinces are reassigned; Tabatinga belongs to Amazonas–Roraima. The resulting state table and updated map cache ship together. **Start a new campaign.** No private-save conversions are included.

Five 3D naval model types, land/naval/air combat effects and 12 UI sound WAV files are included. TGO gains 15 tracks for a total playlist of **121 tracks**. New music sources are in `TGO/music/Anime/TRACKLIST.txt` and `provenance.json`; UI sound sources are in `TGCNV/sound/BA_UI_SFX_SOURCES.txt`. The three Blue Archive additions are unofficial orchestral arrangements by Sangnoksu; the other twelve entries cite official soundtrack/distribution sources. Earlier music attribution documents are retained.

The review matched installed-file hashes to completed deployment records, verified the TGO dependency name and five-file map-cache signature, and checked both language banks. The installed 0.6.8.32 build passed 29 recorded test suites. Final integrated save/reload, two-PC multiplayer/OOS, all-model visual parity and long-session performance remain unverified. The existing 24 coordinate differences and nine data/environment validation limitations remain documented; the package is not a general stability certification.

The generated `runtime/renderer64-live/cache/all.assets` file is 127 MB and exceeds Git's per-file size limit. **It is included in the complete offline pack and the online GHCR download.** This branch records its exact size and SHA-256 in `online-update/large-assets.json` instead of carrying the binary. Use the installer rather than copying GitHub source archives into the game.

This build also includes the R64-E1 duplicate-removal update and `actor_clones = 0`. It keeps the original actor for each type and disables the extra mesh-copying actor clone. The update passed 144 relocated-PE buffer checks for guarded matching, rejected configuration and repeated installation. The same build passed the 282 lazy-loading and 59 air-profile coexistence checks. Live animation, selection, battles and several units of the same type remain unverified.

Antwerp and Ghent positions, Low Countries place names and the west Limburg state (kept in Belgium, with the London Treaty event and decisions) are corrected, the Belgian capital moved, five Mongolian states regrouped (including the new Chahar state), and the map cache rebuilt to match. An earlier military-time fix (then displayed as 0.6.8.5) restores military time when a save was edited so that its unit count differs from the saved military journal: units outside the journal are adopted like newly created units, while battle records are still checked strictly. After a military-time failure the date panel now shows a restart notice.

This build also merges duplicate POP lines in 125 starting-population files, tops up soldier POPs and fixes the home state of 70 order-of-battle files, so starting regiments (for example the British Cape garrison) no longer vanish; this applies to new campaigns. It adds the government table for newly independent or released countries and the Hanover release timing, and it corrects English unit terms (Armored Car, Medium Tank) and short unit names.

Earlier map updates correct missing Pomeranian ports, the Poland/Russia river border, state membership and place names, and the Memel area. It adds 1,217 ocean-facing coastal port points and relocates 293 to their own coastlines. Twenty-seven English labels and the matching rebuilt cache are included. Use the package with a fresh campaign; final in-game visual checks remain outstanding.

The online updater authenticates signed metadata and checks downloaded file hashes before installation. For an offline archive, compare its SHA-256 with the trusted accompanying checksum and run Verify.cmd after extraction. If a check fails, keep the downloaded file and the error log, and do not hand-mix files from different packages; download again from the official release instead. If Windows denies write access, run the tool as administrator under the same Windows account so that its Documents profile stays the same.


### Character renderer / 캐릭터 렌더러

The live worker supports a target resolution up to 1920×1080 and returns tiles up to 512×512. It uses Direct3D 11 and D3DCompiler_47; the native game still uses its existing DirectX 9 path. Live-game visual parity, memory savings and FPS improvements have not been certified. Usage notes and the xxHash license are under `TGCNV/runtime/renderer64-live/`.

To disable this renderer, close the game, set `render = 0` in `TGCNV/runtime/data/tgcnv_renderer64_probe.txt`, then restart. The distributed defaults are `render = 1`, `observe = 0` and `shadow = 0`; changing language does not require enabling diagnostic capture. There is no automatic log upload.

끄려면 게임 종료 후 `TGCNV/runtime/data/tgcnv_renderer64_probe.txt`에서 `render = 0`으로 바꾸고 다시 실행하세요. 기본값은 캐릭터 렌더러 활성화, 진단 캡처·shadow 검증 비활성화입니다.

CheatPack V2.10 credits: Bob Bobington, with contributions by Lord Unhold and Dr.; base image credits: TGC/GFM.
