# omarchy-kakaotalk

Omarchy에서 Windows 카카오톡을 **Bottles + Soda + XWayland + Fcitx5**로 사용하는 설정 모음.
실제로 사용 중인 컴퓨터에서 설정을 추출하고, 화면 갱신 지연과 작은 빈 창 문제를 해결한 과정을 정리했다.

**설정 확인일: 2026-09-16.** 공식 카카오톡 Linux 클라이언트나 Omarchy 공식 설치 프로그램은 아니다.
현재 동작하는 환경의 기록이며, 새 컴퓨터에서 처음부터 설치하는 과정 전체를 재검증한 것은 아니다.

## 확인된 결과

- 한글·영문 입력과 다른 앱에서 돌아왔을 때의 화면 갱신이 정상적으로 빨라졌다.
- `wineserver`의 CPU 사용량이 코어 하나 기준 약 **98–100% → 1–3%**로 줄었다.
- `system.reg`가 약 **907MB → 5.8MB**로 줄었고, Wine 블루투스 장치 기록의 재누적을 차단했다.
- 화면에 남던 **100×13 크기의 빈 Wine 창**을 투명하게 만들고 포커스를 차단했다.

성능 수치는 이 컴퓨터에서 측정한 값이다. 레지스트리 정리와 실행기 변경을 함께 수행했으므로,
체감 개선 전부를 한 설정의 효과로 분리해서 측정한 결과는 아니다.

## 검증 환경

| 구성 요소 | 확인한 버전 / 설정 |
| --- | --- |
| Omarchy | `4.0.4rc2-1` |
| Hyprland | `0.56.2-2`, Lua 설정 |
| Linux kernel | `7.2.5-3-omarchy` |
| Bottles | `2:67.4-1`, 호스트 패키지 |
| 카카오톡 | `26.8.0.356`, `KakaoTalkUI.exe` |
| 실제 사용하는 Wine 실행기 | `soda-11.0-5` |
| 시스템 Wine | `11.17-1`, 현재 카카오톡 실행기로 사용하지 않음 |
| Bottle | `KakaoTalk`, Application, win64, Windows 10 |
| XWayland | `24.1.13-1` |
| Fcitx5 / Hangul | `5.1.22-1` / `5.1.11-1` |
| Fcitx5 GTK / Qt 모듈 | `5.1.7-1` / `5.1.15-1` |
| 한글 글꼴 | `noto-fonts-cjk 20240730-1` |

이 환경에는 Flatpak이 설치되어 있지 않다. 아래 경로와 명령은 **호스트 Bottles 설치** 기준이다.
Flatpak Bottles는 실행 명령, 파일 접근 권한, prefix 위치가 다르므로 그대로 적용하지 않는다.

## 저장소 구성

| 파일 | 용도 |
| --- | --- |
| [config/bottles/bottle.yml](config/bottles/bottle.yml) | 현재 Bottle 설정 전체의 참조용 스냅샷 |
| [config/hypr/windows.lua](config/hypr/windows.lua) | 실제 적용된 창 규칙 |
| [config/hypr/ime.lua](config/hypr/ime.lua) | Shift+Space 한/영 전환 바인딩 발췌 |
| [config/fcitx5/](config/fcitx5/) | 입력기 프로필, 단축키, Hangul·XCB·클립보드 설정 |
| [config/environment/10-omarchy-fcitx.conf](config/environment/10-omarchy-fcitx.conf) | Omarchy가 제공하는 입력기 환경 변수 참조 |
| [config/wine/disable-winebth.reg](config/wine/disable-winebth.reg) | Wine 블루투스 서비스 비활성화 보조 설정 |
| [docs/registry-reference.md](docs/registry-reference.md) | 자동 실행·URL 연결·경로 매핑과 DLL·글꼴·DPI 설정 |
| [docs/troubleshooting.md](docs/troubleshooting.md) | 지연 원인, 진단, 정리와 복구 절차 |
| [tools/clean-winebth-registry.pl](tools/clean-winebth-registry.pl) | 백업 레지스트리에서 WINEBTH만 정리해 새 파일을 만드는 오프라인 도구 |
| [tests/clean-winebth-registry.t](tests/clean-winebth-registry.t) | 정리 범위·원본 보존·실패 시 출력 방지 테스트 |
| [tests/apply-registry.t](tests/apply-registry.t) | 문서의 적용 명령이 손상된 후보를 거부하고 원본을 보존하는지 테스트 |

실행 파일, 글꼴 바이너리, 전체 레지스트리, 로그인 정보, 대화 DB, 친구 목록,
스크린샷, Bluetooth 주소와 개인 장치 매핑은 포함하지 않는다.
스냅샷에 들어 있는 모든 기본값이 필수 설정이라는 뜻은 아니다.

## 1. 준비와 설치

1. Bottles와 `fcitx5`, `fcitx5-hangul`, `fcitx5-gtk`, `fcitx5-qt`, `noto-fonts-cjk`를 준비한다.
   이미 설치된 Omarchy 패키지는 중복 설치할 필요가 없다.
2. Bottles에서 `KakaoTalk`이라는 **Application / 64-bit** Bottle을 만든다.
3. Bottles의 실행기 관리에서 `soda-11.0-5`를 설치하고 이 Bottle의 실행기로 선택한다.
   이 버전을 구할 수 없다면 다른 버전에서의 동작은 별도로 확인해야 한다.
4. 다음 절의 환경 변수와 DLL override를 적용한다. 특히 블루투스 차단은 처음부터 적용하는 편이 좋다.
5. [카카오톡 공식 페이지](https://www.kakaocorp.com/page/service/service/KakaoTalk)에서
   Windows 설치 파일을 받아 이 Bottle 안에서 실행한다.

현재 Bottle의 설치된 의존성 목록은 `arial32`, `times32`, `courie32`, `mono`, `gecko`이다.
각 항목을 하나씩 제거해 필수 여부를 검증한 것은 아니므로, 이는 재현을 위한 설치 이력이다.

설치 위치는 버전에 따라 달라질 수 있다. 이 환경에서는 다음 경로였다.

```text
C:\users\<Wine 사용자>\AppData\Local\Programs\Kakao\KakaoTalk\bin\KakaoTalkUI.exe
```

확인 및 실행:

```bash
bottles-cli programs -b KakaoTalk
bottles-cli run -b KakaoTalk -p KakaoTalkUI
```

`-p`에는 첫 명령이 출력한 실제 프로그램 이름을 쓴다.
목록에 없다면 Bottles에서 설치된 EXE를 직접 지정한다.
Linux 로그인용 카카오톡 자동 실행 항목이나 개인 `.desktop` 실행기는 확인되지 않았다.
다만 **Wine 내부에는 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`의 `Talk` 항목이 있으며**,
`KakaoTalkUI.exe -bystartup`을 가리킨다. Linux 자동 실행이 없다는 것과 Wine 내부 자동 실행이
없다는 것은 다르다.

설치 프로그램이 만든 `kakaotalk:`·`kakaoopen:` URL 처리 항목과 Windows 바로가기도 있다.
이 환경에서는 `drive_c/users/steamuser`가 실제 Wine 사용자 디렉터리를 가리키는 심볼릭 링크다.
이 경로 관계가 깨지면 EXE가 남아 있어도 등록된 실행 경로를 찾지 못할 수 있다.
실제 등록값과 복원 시 주의점은 [자동 실행·URL·경로 참조](docs/registry-reference.md)에 정리했다.

## 2. Bottle 설정

Bottles의 환경설정에서 아래 항목을 맞춘다.
실행기, Windows 버전, DLL override와 환경 변수는
[Bottles 환경설정](https://docs.usebottles.com/bottles/preferences)에서 관리할 수 있다.

| 항목 | 현재 값 |
| --- | --- |
| Runner | `soda-11.0-5` |
| Windows | `win10` |
| Renderer | `gl` |
| DXVK / VKD3D / D7VK | 모두 꺼짐 |
| Wine Wayland | 꺼짐 — XWayland 사용 |
| 가상 데스크톱 / Gamescope / FPS 제한 | 꺼짐 / 꺼짐 / `0` |
| DPI | `96` |
| Bottles Runtime | 꺼짐 |
| 동기화 설정 | `fsync` |
| 시스템 환경 변수 제한 | 켜짐, `XMODIFIERS` 상속 허용 |

동기화 항목은 **Bottles에 저장된 값**이다. 실제 Soda 시작 로그에서는
`ntsync: up and running.`이 확인됐다. `fsync` 설정만 보고 실제 동기화 방식도
반드시 fsync라고 단정하지 않는다.

환경 변수:

```yaml
Environment_Variables:
    QSG_RENDER_LOOP: threaded
    QSG_RHI_BACKEND: opengl
    QT_OPENGL: desktop
    QT_QUICK_BACKEND: rhi
    WAYLAND_DISPLAY: ''
```

Qt 화면 그리기를 OpenGL과 별도 렌더 스레드로 설정하고, Wine은 XWayland로 실행하는 구성이다.
`QSG_RENDER_LOOP`의 `threaded`와 `basic` 동작은
[Qt 문서](https://doc.qt.io/qt-6/qtquick-visualcanvas-scenegraph.html#scene-graph-and-rendering)를 참고한다.
이 변수들은 문제 해결 전부터 있던 값이며, 이번에 각각의 성능 효과를 따로 시험하지 않았다.

현재 프로세스에서는 `XMODIFIERS=@im=fcitx`, `DISPLAY`가 전달되고
`WAYLAND_DISPLAY`는 빈 값인 것을 확인했다.

**[bottle.yml](config/bottles/bottle.yml)을 다른 Bottle에 통째로 덮어쓰지 않는다.**
이 파일은 참조용이며 Bottle 이름·경로·실행기·설치 이력을 포함한다.
기존 Bottle에서는 필요한 항목만 병합하고, 파일을 직접 편집할 때는 해당 Bottle과 Bottles를 종료한다.

## 3. Wine 블루투스 드라이버 차단

이번 지연 문제에서 가장 큰 이상은 Wine에 쌓인 Bluetooth 장치 기록이었다.
카카오톡용 Bottle의 **DLL Overrides**에 `winebth.sys`를 추가하고 **비활성화**한다.
저장된 YAML은 다음과 같다.

```yaml
DLL_Overrides:
    winebth.sys: ''
```

빈 문자열은 Wine DLL 로더에서 이 드라이버를 로드하지 않도록 하는 설정이다.
실행 중인 프로세스에서는 다음 형태로 전달되는 것을 확인했다.

```text
WINEDLLOVERRIDES=winebth.sys=;winemenubuilder=''
```

보조적으로 Wine 내부 서비스도 비활성화했다.

```text
HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\winebth
Start = 4 (REG_DWORD)
```

[disable-winebth.reg](config/wine/disable-winebth.reg)는 **해당 Bottle의** 레지스트리 편집기에서 가져올 수 있다.

```bash
bottles-cli tools -b KakaoTalk regedit
```

`Start=4`만 적용했을 때는 드라이버가 다시 로드됐으므로 **DLL override가 핵심**이다.
설정 후에는 해당 Bottle의 Wine 프로세스를 완전히 종료하고 다시 실행해야 한다.
이미 쌓인 기록은 차단 설정만으로 없어지지 않는다. [기존 누적 기록 정리](docs/troubleshooting.md)를 참고한다.

이 설정은 카카오톡용 Wine 안에서 Windows 프로그램의 직접적인 Bluetooth 접근을 막는다.
Linux의 Bluetooth 서비스와 장치 연결 설정은 변경하지 않는다.
Linux 오디오 서버를 통해 전달되는 소리는 별도 경로지만, 이번 작업에서 Bluetooth 이어폰 통화까지
직접 검증한 것은 아니다.

## 4. 한글 입력과 글꼴

### Fcitx5

현재 입력기 프로필은 `keyboard-us`와 `hangul`이며, 한/영 전환은 **Shift+Space**이다.
[Fcitx5 프로필](config/fcitx5/profile)과 [단축키 설정](config/fcitx5/config)을 참고한다.

Hyprland의 `~/.config/hypr/bindings.lua`에는 다음 바인딩이 있다.

```lua
o.bind("SHIFT + SPACE", "Toggle Korean IME", "fcitx5-remote -t")
```

추가 전에 `omarchy menu keybindings --print`로 충돌을 확인한다.
이미 같은 조합에 바인딩이 있다면 기존 항목을 수정하거나 `hl.unbind("SHIFT + SPACE")` 후 등록한다.
`ime.lua`는 발췌 파일이므로 전체 개인 바인딩 파일을 덮어쓰지 않는다.

Omarchy는 `omarchy-fcitx5.service`와 다음 환경 변수를 제공하고 있다.

```text
INPUT_METHOD=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
```

```bash
systemctl --user status omarchy-fcitx5.service
```

이미 제공되는 서비스와 환경 파일을 중복 등록할 필요는 없다.
Bottle은 환경 상속을 제한하지만 `XMODIFIERS`는 허용한다.
Linux용 `QT_IM_MODULE`을 Windows Qt 앱에 무조건 추가하는 방식으로 구성하지 않았다.
개인 Fcitx5 설정을 바꿀 때도 기존 프로필·단축키를 백업하고 필요한 항목만 병합한다.

추가 확인 사항:

- `hangul.conf`의 세부 항목은 모두 주석 상태였다. 별도의 조합 옵션을 강제하지 않았다.
- `xcb.conf`는 `Allow Overriding System XKB Settings=False`.
- Fcitx5 클립보드의 `TriggerKey`, `PastePrimaryKey`는 빈 값이다. 한글 입력의 필수 조건으로 검증한 값은 아니다.
- Wine `X11 Driver\InputStyle=root`는 **설정되어 있지 않았다**. 이 환경에서는 그 설정 없이 한글 입력이 동작한다.

### 글꼴

현재 Bottle의 `drive_c/windows/Fonts/`에는 Arial·Times·Courier 글꼴 외에 다음 두 파일이 있다.

```text
NotoSansCJK-Regular.ttc
NotoSansCJK-Bold.ttc
```

이름이 같은 파일을 호스트 `noto-fonts-cjk` 패키지가 제공한다.
재현할 때는 해당 패키지의 파일을 Bottle의 Fonts 디렉터리에 복사할 수 있다.
`fc-match 'Noto Sans CJK KR'`로 글꼴 설치 상태와 실제 위치를 먼저 확인한다.
글꼴 바이너리는 이 저장소에 포함하지 않는다.

## 5. 작은 빈 창 숨기기

Wine의 `explorer.exe /desktop`이 **제목 없는 100×13 창**을 노출했다.
시스템 Wine에서는 클래스가 `explorer.exe`, Soda에서는 `steam_proton`이었다.
실행기 변경 뒤 기존 규칙이 적용되지 않아 다음과 같이 수정했다.

```lua
o.window({
  class = "^(explorer\\.exe|steam_proton)$",
  title = "^$",
  xwayland = true,
  float = true,
}, {
  tag = "-default-opacity",
  opacity = "0 0",
  border_size = 0,
  no_shadow = true,
  no_focus = true,
})
```

`o.window`는 Omarchy 헬퍼다. 순수 Hyprland에서는 그대로 사용할 수 없다.
위 규칙을 개인 `~/.config/hypr/windows.lua`에 병합하고,
`hyprland.lua`에서 `require("hypr.windows")`로 한 번 불러온다.

```bash
hyprctl reload
hyprctl configerrors
```

적용 후 보조 창의 `opacity=0`, `no_focus=true`, 본창의 `opacity=1`을 확인했다.
프로세스를 종료하거나 창을 제거하는 방식이 아니라 투명하게 만들고 포커스를 막는 방식이다.

**매칭 범위:** 이 규칙은 크기나 실행 파일 경로까지 검사하지 않는다.
`steam_proton`을 쓰는 다른 앱의 제목 없는 떠 있는 창에도 적용될 수 있다.
다른 Proton 앱을 함께 사용한다면 실제 창 속성을 확인해 범위를 더 좁혀야 한다.

[windows.lua 스냅샷](config/hypr/windows.lua)에는 예전 첨부파일 보조 창 규칙도 남아 있다.
이 항목은 `kakaotalkui.exe` 클래스를 대상으로 하므로 현재 Soda의 `steam_proton`에는 적용되지 않는다.
Soda용 첨부파일 규칙을 검증한 것으로 해석하지 않는다.
문법은 [Hyprland 창 규칙 문서](https://wiki.hypr.land/Configuring/Basics/Window-Rules/)를 참고한다.

## 6. 확인할 것

1. 카카오톡을 실행하고 한글·영문을 입력한다.
2. 크로미움 등 다른 앱으로 이동한 뒤 돌아와 화면이 바로 갱신되는지 확인한다.
3. 1분 이상 사용하면서 주기적인 멈춤과 `wineserver` CPU 급증이 재발하는지 살핀다.
4. 작은 빈 창이 보이거나 포커스를 가져가지 않는지 확인한다.

```bash
top -p "$(pgrep -d, -x wineserver)"
stat -c '%s bytes %n' "$HOME/.local/share/bottles/bottles/KakaoTalk/system.reg"
```

`top` 명령은 Wine 서버가 실행 중일 때 사용한다. 여러 Bottle을 쓰면 모든 서버가 표시되므로
PID별 `WINEPREFIX`를 확인해 카카오톡용 프로세스를 구분한다.

처음 시작하는 속도, 통화, 파일 전송, 다른 배율·GPU·Wine 버전까지 모두 검증한 것은 아니다.
현재 확인한 문제와 복구 방법은 [트러블슈팅 문서](docs/troubleshooting.md)에 정리했다.
