# 추가 설정과 추출 범위

2026-09-16에 실행 중인 환경에서 읽어 확인한 항목이다.
Wine의 `user.reg`·`system.reg` 전체를 배포하지 않고,
사용자·장치 식별자가 없는 관련 설정만 아래에 기록했다.
여기 적힌 값은 **현재 상태**이며, 모든 값의 필요성을 독립적으로 검증했다는 뜻은 아니다.

## Wine 내부 자동 실행

다음은 `user.reg`에서 확인한 값을 읽기 쉽게 풀어 쓴 것이다. 가져오기용 `.reg` 파일이 아니다.

| 항목 | 값 |
| --- | --- |
| 키 | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` |
| 값 이름 / 형식 | `Talk` / `REG_SZ` |
| 명령 | `"C:\users\steamuser\AppData\Local\Programs\Kakao\KakaoTalk\bin\KakaoTalkUI.exe" -bystartup` |

Wine의 시작 처리에서 실행될 수 있는 항목이며, Linux 로그인 시 Bottle을 실행하는 설정과는 별개다.
이 컴퓨터에서는 별도의 Linux 카카오톡 자동 실행 항목·개인 `.desktop` 실행기는 확인되지 않았다.
Run 항목이 실제로 언제 실행되는지까지 모든 시작 경로에서 검증한 것은 아니다.
자동 실행을 바꿀 때는 카카오톡의 관련 설정을 먼저 확인하고, 이 값을 무조건 덮어쓰지 않는다.

## URL 연결과 Windows 바로가기

`HKCU\Software\Classes` 아래에 다음 두 프로토콜이 등록되어 있었다.

| 키 | 값 |
| --- | --- |
| `kakaoopen` | `URL Protocol` = 빈 문자열 |
| `kakaoopen\shell\open\command` 기본값 | `"C:\users\steamuser\AppData\Local\Programs\Kakao\KakaoTalk\bin\KakaoTalkUI.exe" "%1"` |
| `kakaotalk` | `URL Protocol` = 빈 문자열 |
| `kakaotalk\shell\open\command` 기본값 | `"C:\users\steamuser\AppData\Local\Programs\Kakao\KakaoTalk\bin\KakaoTalkUI.exe" "%1"` |

이것은 **Wine 내부** URL 연결이다. Linux 브라우저에서 해당 주소를 Bottle로 전달하는
`x-scheme-handler` 등록이 있다는 뜻은 아니며, 그런 호스트 연결은 확인되지 않았다.
브라우저에서의 오픈채팅 링크 실행도 검증하지 않았다.

Windows 바로가기는 다음 위치에 있었다.

- `drive_c/users/<Wine 사용자>/Desktop/KakaoTalk.lnk`
- `drive_c/users/<Wine 사용자>/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/KakaoTalk.lnk`

바로가기에서 확인한 실행 파일은 위와 같은 `...\bin\KakaoTalkUI.exe`이고,
작업 디렉터리는 **`bin`이 아닌 상위 `C:\users\steamuser\AppData\Local\Programs\Kakao\KakaoTalk`**였다.
이 바이너리 바로가기는 개인 경로가 포함될 수 있어 저장소에 복사하지 않았다.

### `steamuser` 경로 매핑

현재 prefix에는 다음 심볼릭 링크가 있다.

```text
drive_c/users/steamuser -> <실제 Wine 사용자 디렉터리>
```

따라서 실제 EXE는 사용자 디렉터리에 있어도 `C:\users\steamuser\...`로 등록된 경로가 동작한다.
다른 컴퓨터의 사용자 이름으로 이 링크를 그대로 만들거나, 기존 `steamuser` 디렉터리를 삭제하면 안 된다.
새 설치에서는 설치 프로그램이 만든 현재 경로를 기준으로 확인한다.
기존 Bottle을 옮길 때는 심볼릭 링크를 보존하고, 링크 대상과 실행 파일이 모두 있는지 확인한다.

아래 명령은 파일 상태만 확인하며 Wine을 실행하지 않는다.

```bash
bottle="$HOME/.local/share/bottles/bottles/KakaoTalk"
ls -ld "$bottle/drive_c/users/steamuser"
readlink "$bottle/drive_c/users/steamuser"
test -f "$bottle/drive_c/users/steamuser/AppData/Local/Programs/Kakao/KakaoTalk/bin/KakaoTalkUI.exe"
```

`readlink`는 심볼릭 링크가 아닌 환경에서는 실패할 수 있다. 설치 경로가 다르면 실제 경로로 확인한다.
위 자동 실행·URL·바로가기 값은 설치 상태의 기록이지, 모든 환경에 일괄 적용할 필수 설정이 아니다.

## Wine 전역 DLL overrides

`HKCU\Software\Wine\DllOverrides`의 값은 다음과 같았다.
대부분 기존 설치·실행기·의존성 설치 과정에서 만들어진 값이다.
새 환경에서 전부 수동으로 강제해야 하는 필수 목록으로 해석하지 않는다.

```text
api-ms-win-crt-conio-l1-1-0 = native,builtin
api-ms-win-crt-heap-l1-1-0 = native,builtin
api-ms-win-crt-locale-l1-1-0 = native,builtin
api-ms-win-crt-math-l1-1-0 = native,builtin
api-ms-win-crt-runtime-l1-1-0 = native,builtin
api-ms-win-crt-stdio-l1-1-0 = native,builtin
api-ms-win-crt-time-l1-1-0 = native,builtin
atiadlxx = disabled
atl100 = native,builtin
atl110 = native,builtin
atl120 = native,builtin
atl140 = native,builtin
concrt140 = native,builtin
mscoree = native,builtin
msvcp100 = native,builtin
msvcp110 = native,builtin
msvcp120 = native,builtin
msvcp140 = native,builtin
msvcp140_1 = native,builtin
msvcp140_2 = native,builtin
msvcp140_atomic_wait = native,builtin
msvcp140_codecvt_ids = native,builtin
msvcr100 = native,builtin
msvcr110 = native,builtin
msvcr120 = native,builtin
msvcr140 = native,builtin
nvcuda = disabled
ucrtbase = native,builtin
vccorlib140 = native,builtin
vcomp100 = native,builtin
vcomp110 = native,builtin
vcomp120 = native,builtin
vcomp140 = native,builtin
vcruntime140 = native,builtin
vcruntime140_1 = native,builtin
winemenubuilder.exe = (빈 문자열)
```

위 목록의 마지막 값은 빈 문자열이다.
별도로 Bottles가 프로세스 환경에 `winebth.sys=;winemenubuilder=''`를 전달한다.
따라서 `user.reg`만 확인하면 새로 적용한 `winebth.sys` override를 놓칠 수 있다.

## 글꼴과 DPI

| 위치 | 값 |
| --- | --- |
| `HKCU\Software\Wine\Fonts\LogPixels` | `0x60` = 96 DPI |
| `HKCU\Software\Wine\Fonts\Codepages` | `1252,437` |
| `HKCU\Control Panel\Desktop\FontSmoothing` | 문자열 `2` |
| `FontSmoothingGamma` | `0x578` |
| `FontSmoothingOrientation` | `1` |
| `FontSmoothingType` | `2` |

`HKCU\Software\Wine\Fonts\Replacements`:

```text
Palatino Linotype = Times New Roman
Segoe UI = Times New Roman
Segoe UI Semibold = Times New Roman
Verdana = Times New Roman
```

이는 기존 Bottle에 있던 글꼴 대체 규칙이다.
카카오톡용으로 의도적으로 최적화한 규칙인지까지 확인하지 않았으므로
새 설치의 권장 기본값으로 제시하지 않는다.

`HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes`의 주요 값:

```text
Helv = MS Sans Serif
Helvetica = Arial
MS Shell Dlg = Tahoma
MS Shell Dlg 2 = Tahoma
Times = Times New Roman
Tms Rmn = MS Sans Serif
```

이외 Arial·Courier New·Times New Roman의 Baltic/CE/CYR/Greek/TUR 코드페이지 매핑은
일반 Wine 글꼴 설정으로 남아 있었다.
External Fonts와 FontLink에는 호스트 글꼴의 자동 열거 결과가 다수 있었으며 그대로 복사하지 않았다.
레지스트리에 글꼴 이름이 있다는 사실만으로 실제 글꼴 바이너리가 설치되어 있다고 판단하지 않는다.

Bottle의 실제 Fonts 디렉터리에는 다음 파일군이 있었다.

- `Arial.TTF`, `Arialbd.TTF`, `Arialbi.TTF`, `Ariali.TTF`
- `Times.TTF`, `Timesbd.TTF`, `Timesbi.TTF`, `Timesi.TTF`
- `cour.ttf`, `courbd.ttf`, `courbi.ttf`, `couri.ttf`
- `NotoSansCJK-Regular.ttc`, `NotoSansCJK-Bold.ttc`

## 입력·화면 관련 호스트 설정

- Omarchy의 기본 `xwayland.force_zero_scaling = true`.
- 개인 모니터 배율은 `1.6`. 진단 당시 노트북 2880×1800/90Hz, 외부 화면 3840×2160/60Hz.
- 키 반복 기본값은 `repeat_rate=40`, `repeat_delay=250`. 이를 이번에 바꾸지는 않았다.
- 키보드 옵션은 `ctrl:nocaps,compose:ralt,shift:both_capslock_cancel`.
  개인 취향 설정이며 카카오톡용 필수 조건이 아니다.
- 카카오톡 프로세스의 locale은 `LANG=en_US.UTF-8`, `LC_CTYPE=C.UTF-8`, `LC_ALL=C.UTF-8`였다.
  한글 입력을 위해 `LANG=ko_KR.UTF-8`로 강제한 구성이 아니다.
- 명시적인 `HKCU\Software\Wine\X11 Driver\InputStyle` 및 `Direct3D` 키는 확인되지 않았다.

모니터 이름·일련번호·배치와 전체 키 바인딩은 각 사용자의 환경에 의존하므로 복사하지 않았다.

## 추출 출처

| 로컬 경로 | 저장소에 반영한 내용 |
| --- | --- |
| `~/.local/share/bottles/bottles/KakaoTalk/bottle.yml` | 설정 스냅샷 |
| `~/.config/hypr/windows.lua` | 원본 규칙 스냅샷 |
| `~/.config/hypr/bindings.lua` | 한/영 전환 바인딩 발췌 |
| `~/.config/fcitx5/profile`, `config`, `conf/` | 입력 관련 파일 |
| `/usr/lib/environment.d/10-omarchy-fcitx.conf` | 배포판 기본 환경 변수 |
| `/usr/share/omarchy/default/hypr/envs.lua`, `input.lua` | 배율·키 반복 기본값 설명 |
| Bottle의 `user.reg` / `system.reg` | 비식별 설정만 이 문서에 선별 기록 |
| Bottle의 `drive_c/users/steamuser`와 Windows `.lnk` | 사용자 이름을 제외한 경로 매핑·바로가기 대상과 작업 디렉터리 |
| 실행 중인 프로세스 환경·로드 모듈 | 실제 실행기, XWayland, override 적용 확인 |

Wine prefix의 AppDefaults 게임별 기본값, 디바이스 GUID, Bluetooth 검색 기록,
오디오 장치 캐시, 개인 드라이브 매핑과 애플리케이션 계정 데이터는 추출 대상에서 제외했다.
