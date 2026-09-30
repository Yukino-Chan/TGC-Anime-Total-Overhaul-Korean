# TGC - Anime Total Overhaul (Korean)

Victoria II용 스탠드얼론 한국어·영어 애니메이션 오버홀 **TGCNV**와 음악 모드 **TGO**입니다. 이 브랜치에는 두 모드의 파일과 관련 설치·업데이트 소스가 있습니다. 내용은 배포 **TGCNV-20260930-163538**(엔진 0.6.8.3+20260930-P35)과 같습니다.

## 설치와 업데이트

1. [온라인 설치 도구](https://github.com/Yukino-Chan/TGC-Anime-Total-Overhaul-Korean/releases/download/installer/TGC-Online-Installer.zip?sha256=8744f9c19e805c687aa709bb7154f5d5a4747edfaee755fe5838d870ecf305a2)를 받습니다.
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

이 배포는 사용자 승인 실험판입니다. 파일·서명·설치 도구 검증은 마쳤지만 장기 캠페인 안정성은 검증하지 않았습니다. 멀티플레이는 모든 참가자가 같은 배포를 설치해야 합니다. 프로빈스 번호가 바뀌었으므로 새 캠페인으로 시작해야 합니다. 기존 세이브는 호환되지 않으며 변환하지 않습니다.

## 제작자, 출처와 권리

- 기반 모드: [The Grand Combination](https://github.com/The-Grand-Combination/The-Grand-Combo). 음악 모드: [The Grand Orchestra](https://github.com/The-Grand-Combination/The-Grand-Orchestra). 곡목과 연주 출처는 `TGO/OPENING_MUSIC.md`, `TGO/VICTORIA1_MUSIC.md`에 있습니다.
- Victoria II © Paradox Interactive. 원본 게임과 DLC는 포함하지 않습니다.
- 블루 아카이브의 캐릭터, 모델, UI 요소에 대한 권리는 NEXON Games Co., Ltd. 및 관련 권리자에게 있습니다. 국기와 초상에 쓰인 다른 작품의 캐릭터는 각 권리자에게 권리가 있습니다. 이 프로젝트는 비공식·비영리 팬 모드이며 권리자와 관계가 없습니다.
- 글꼴: 경기천년체 © 경기도.
- 일부 UI 아이콘: [game-icons.net](https://game-icons.net)의 Delapouite, Lorc, Skoll, Cathelineau, Sbed, Pierre Leducq, Guard13007, Zeromancer, John Colburn, Willdabeast, Andy Meneely, Quoting, Lucas 작품을 [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)으로 사용하고 색과 크기를 바꿨습니다.
- 기병의 말 모델: Quaternius, *Ultimate Animated Animal Pack* (Horse, White Horse), [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).

## English

TGCNV is a standalone Korean/English anime overhaul for Victoria II: Heart of Darkness 3.04, bundled with the TGO music mod. Download the [online installer](https://github.com/Yukino-Chan/TGC-Anime-Total-Overhaul-Korean/releases/download/installer/TGC-Online-Installer.zip?sha256=8744f9c19e805c687aa709bb7154f5d5a4747edfaee755fe5838d870ecf305a2), extract it, close the game and run Update.cmd, then choose English on first install. This branch holds the TGCNV and TGO mod files plus related updater sources. The mod files match release TGCNV-20260930-163538; install through the installer rather than copying folders. Province IDs changed: start a new campaign; old saves are not compatible. Unofficial non-commercial fan project; Blue Archive and other characters belong to their respective owners.
