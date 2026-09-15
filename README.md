# omarchy-kakaotalk

Omarchy에서 Windows 카카오톡을 **Bottles + Soda + XWayland + Fcitx5**로 사용하면서 얻은 설정·문제 해결 노하우.
실제로 사용 중인 컴퓨터에서 설정을 추출하고, 화면 갱신 지연과 작은 빈 창 문제를 해결한 과정을 정리했다.

**설정 확인일: 2026-09-16.** 공식 카카오톡 Linux 클라이언트나 Omarchy 공식 설치 프로그램은 아니다.
설치 프로그램·자동화 도구·로그인된 Bottle을 배포하지 않는다. 필요한 내용만 이 README에서 참고한다.
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

## 읽는 순서

- [화면이 주기적으로 멈췄던 원인](#lag)
- [동작한 Bottle 설정](#bottle)
- [Wine 블루투스 차단](#bluetooth)
- [한글 입력과 글꼴](#ime)
- [작은 빈 창 숨기기](#window)
- [진단·백업·복구](#recovery)
- [자동 실행·URL·경로와 추가 설정](#reference)
- [검증 범위](#limits)

코드 블록은 필요한 부분만 확인하고 적용하는 예시다. 기존 사용자 설정을 통째로 덮어쓰지 않는다.
실행 파일·전체 레지스트리·대화 DB·로그인 정보·글꼴 바이너리·개인 장치 식별자는 포함하지 않는다.

<a id="lag"></a>

## 화면이 주기적으로 멈췄던 원인

### 증상

카카오톡 입력이 느리고 일정한 주기로 화면이 멈추는 느낌이 있었다.
입력하지 않을 때도 크로미움으로 갔다 돌아오면 카카오톡 창 전체가 늦게 갱신됐다.
크로미움 자체는 빠르게 동작했다.

### 측정으로 확인한 내용

| 항목 | 정리 전 | 정리·재실행 후 |
| --- | --- | --- |
| `system.reg` | 907,344,566 bytes | 초기 정리 직후 4,250,629 bytes; 실행기 초기화 후 약 5.8MB |
| `WINEBTH` 기록 | 903,093,937 bytes, 141,592개 섹션 | 대량 누적분 제거, 드라이버 로딩 차단 |
| `wineserver` CPU | 1초 간격 측정에서 약 98–100% | 시작 부하가 가라앉은 뒤 대체로 약 1–3% |
| 포커스 복귀·입력 | 갱신 지연 | 사용자가 정상 속도로 개선됐음을 확인 |

CPU 수치는 코어 하나를 100%로 표시하는 `top` 기준이다.
전체 컴퓨터 CPU 사용률이 100%였다는 뜻이 아니다.

`perf`로 표본을 수집하고 설치된 wineserver 빌드에 맞는 디버그 심볼을 대조했을 때:

```text
main_loop
  → main_loop_epoll
    → get_next_timeout
      → periodic_save
        → save_branch
          → save_subkeys
            → dump_value / fprintf / fputc
```

실제 CPU 소비 지점이 레지스트리 저장 경로인 것을 확인했다.
Wine 11.17의 코드는 저장이 끝난 뒤 다음 자동 저장을 30초 후로 예약한다.
따라서 거대한 레지스트리의 직렬화가 Wine 요청 처리를 지연시키는 설명과 증상이 맞는다.
[Wine 11.17 레지스트리 코드](https://github.com/wine-mirror/wine/blob/wine-11.17/server/registry.c)

레지스트리의 약 99.5%는 다음 트리였다.

```text
HKEY_LOCAL_MACHINE\System\ControlSet001\Enum\WINEBTH
```

장치 루트 수와 하위 속성 섹션 수는 다르다.
초기 조사에서는 장치 루트 약 23,578개와 약 141,424개 섹션을 세었고,
완전히 종료한 뒤 실제 정리할 때는 141,592개 섹션이었다.
조사 중에도 기록이 변하고 있었으므로 이 숫자들을 같은 시점의 고정값으로 보지 않는다.

### 실행기를 Soda로 바꾼 이유

원래 카카오톡은 시스템 Wine 11.17에서 실행 중이었다.
복구 과정에서 완전히 종료한 뒤에는 창이 뜨기 전 초기화 단계에서 지연됐다.
드라이버를 다시 켜거나 실행 경로를 바꿔도 같은 현상이 있었다.

전체 Bottle의 별도 복사본을 만들어 설치되어 있던 Soda 11.0-5로 실행하니 정상 창이 떴다.
이후 실제 Bottle도 Soda로 변경하고 로그인된 화면과 입력·화면 갱신을 확인했다.

이는 **이 환경에서 재현한 결과**다. Wine 11.17이 모든 카카오톡 환경에서
실패한다는 뜻은 아니고, 시작 지연의 세부 원인까지 규명한 것은 아니다.
사용자도 이전부터 시작이 늦거나 재시도가 필요했을 가능성이 있다고 설명했다.

다른 환경에서 실행기를 바꾸기 전에는 전체 Bottle을 백업한다.
실행기 전환 시 Wine이 prefix의 파일과 레지스트리를 갱신할 수 있다.

<a id="bottle"></a>

## 동작한 Bottle 설정

아래는 이 컴퓨터에서 동작한 값이다. 모든 항목의 필요성을 독립적으로 검증한 것은 아니다.
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

**`bottle.yml`을 다른 Bottle에 통째로 덮어쓰지 않는다.**
이 파일에는 Bottle 이름·경로·실행기·설치 이력이 포함된다.
기존 Bottle에서는 필요한 항목만 병합하고, 파일을 직접 편집할 때는 해당 Bottle과 Bottles를 종료한다.

설치된 의존성 목록은 `arial32`, `times32`, `courie32`, `mono`, `gecko`였다.
이는 설치 이력이지, 하나씩 제거해 필수 여부를 검증한 목록은 아니다.
카카오톡 자체는 [공식 페이지](https://www.kakaocorp.com/page/service/service/KakaoTalk)의 Windows 버전을 사용했다.

실행 파일 위치는 다음과 같았으며, 설치 버전에 따라 달라질 수 있다.

```text
C:\users\<Wine 사용자>\AppData\Local\Programs\Kakao\KakaoTalk\bin\KakaoTalkUI.exe
```

등록된 프로그램 확인과 실행:

```bash
bottles-cli programs -b KakaoTalk
bottles-cli run -b KakaoTalk -p KakaoTalkUI
```

`-p`에는 첫 명령이 출력한 실제 이름을 쓴다. 목록에 없다면 Bottles에서 설치된 EXE를 지정한다.

<a id="bluetooth"></a>

## Wine 블루투스 차단

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

**해당 Bottle의** 레지스트리 편집기에서 위 키의 `Start` DWORD 값을 `4`로 설정했다.

```bash
bottles-cli tools -b KakaoTalk regedit
```

`Start=4`만 적용했을 때는 드라이버가 다시 로드됐으므로 **DLL override가 핵심**이다.
설정 후에는 해당 Bottle의 Wine 프로세스를 완전히 종료하고 다시 실행해야 한다.
이미 쌓인 기록은 차단 설정만으로 없어지지 않는다. [진단·백업·복구](#recovery)를 참고한다.

이 설정은 카카오톡용 Wine 안에서 Windows 프로그램의 직접적인 Bluetooth 접근을 막는다.
Linux의 Bluetooth 서비스와 장치 연결 설정은 변경하지 않는다.
Linux 오디오 서버를 통해 전달되는 소리는 별도 경로지만, 이번 작업에서 Bluetooth 이어폰 통화까지
직접 검증한 것은 아니다.

<a id="ime"></a>

## 한글 입력과 글꼴

### Fcitx5

현재 입력기 프로필은 `keyboard-us`와 `hangul`이며, 한/영 전환은 **Shift+Space**이다.
`~/.config/fcitx5/profile`의 관련 값:

```ini
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=hangul

[Groups/0/Items/0]
Name=keyboard-us

[Groups/0/Items/1]
Name=hangul
Layout=us

[GroupOrder]
0=Default
```

`~/.config/fcitx5/config`의 단축키 설정은 다음과 같다.
이 컴퓨터에서는 Ctrl+Space를 tmux에서 사용해 Shift+Space를 선택했다.

```ini
[Hotkey]
EnumerateWithTriggerKeys=True
EnumerateSkipFirst=False

[Hotkey/TriggerKeys]
0=Shift+space

[Hotkey/AltTriggerKeys]
0=

[Hotkey/EnumerateGroupForwardKeys]
0=

[Hotkey/EnumerateGroupBackwardKeys]
0=
```

Hyprland의 `~/.config/hypr/bindings.lua`에는 다음 바인딩이 있다.

```lua
o.bind("SHIFT + SPACE", "Toggle Korean IME", "fcitx5-remote -t")
```

추가 전에 `omarchy menu keybindings --print`로 충돌을 확인한다.
이미 같은 조합에 바인딩이 있다면 기존 항목을 수정하거나 `hl.unbind("SHIFT + SPACE")` 후 등록한다.
전체 개인 바인딩 파일을 덮어쓰지 않는다.

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
실제 글꼴 경로는 다음 명령으로 확인한다.

```bash
fc-match -f '%{file}\n' 'Noto Sans CJK KR'
```
글꼴 바이너리는 이 저장소에 포함하지 않는다.

<a id="window"></a>

## 작은 빈 창 숨기기

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

기존에는 다음 첨부파일 보조 창 규칙도 있었다.
이 항목은 `kakaotalkui.exe` 클래스를 대상으로 하므로 현재 Soda의 `steam_proton`에는 적용되지 않는다.
Soda용 첨부파일 규칙을 검증한 것으로 해석하지 않는다.

```lua
-- 이전 실행기용 참고 기록. 현재 Soda의 steam_proton에는 매칭되지 않는다.
o.window({
  class = "^kakaotalkui\\.exe$",
  title = "^KakaoTalkUI$",
  xwayland = true,
}, {
  no_initial_focus = true,
})
```

문법은 [Hyprland 창 규칙 문서](https://wiki.hypr.land/Configuring/Basics/Window-Rules/)를 참고한다.

창 규칙은 사용자 `~/.config/hypr/`에만 병합한다. 패키지 소유의 `/usr/share/omarchy/`는 수정하지 않는다.
실행기를 바꾸면 X11 클래스가 달라질 수 있으므로 `hyprctl clients -j`에서 `pid`·`class`·`title`·`floating`을 확인한다.
출력에 개인 대화 제목이 포함될 수 있으니 전체를 공개하지 않는다.

<a id="recovery"></a>

## 진단·백업·복구

### 재발 여부 진단

먼저 크기와 CPU를 확인한다. 아래 값만으로 모든 화면 갱신 문제를 같은 원인으로 단정하지 않는다.

```bash
stat -c '%s bytes %n' "$HOME/.local/share/bottles/bottles/KakaoTalk/system.reg"
ps -C wineserver -o pid,etime,pcpu,args
```

`ps`의 `%CPU`는 프로세스 실행 기간에 걸친 평균이므로 순간 부하는 `top`에서 추가로 본다.
여러 Wine 서버가 있으면 확인할 PID의 `WINEPREFIX`를 검사한다.
`12345`는 실제 PID로 바꾼다. 전체 환경 변수를 출력할 필요는 없다.

```bash
tr '\0' '\n' < /proc/12345/environ | rg '^WINEPREFIX='
top -p 12345
```

관련 설정 확인:

```bash
rg -n -A 2 'DLL_Overrides:' "$HOME/.local/share/bottles/bottles/KakaoTalk/bottle.yml"
tr '\0' '\n' < /proc/12345/environ | rg '^WINEDLLOVERRIDES='
```

Soda에서 Wine 드라이버를 비활성화하면
`ZwLoadDriver ... winebth ... c0000142` 같은 메시지가 나올 수 있다.
이번 구성에서는 의도한 드라이버 차단과 함께 관찰된 메시지이며, 이 한 줄만으로 카카오톡 실행 실패를 판단하지 않는다.

### 먼저 완전히 종료하고 전체 백업

드라이버 차단은 **재누적 방지**다. 이미 커진 레지스트리를 줄이려면 기존 기록 정리가 별도로 필요하다.
작업을 저장하고 카카오톡을 종료한 뒤 Bottles에서 `winebth.sys` 차단을 저장하고 Bottles 창도 닫는다.
아래 명령은 지정한 Bottle의 Wine 프로세스를 종료하므로 경로·실행기를 먼저 확인한다.

```bash
rg '^Runner:' "$HOME/.local/share/bottles/bottles/KakaoTalk/bottle.yml"
```

다음은 호스트 Bottles + Soda 11.0-5 기준이다. 다른 실행기라면 두 곳의 경로를 실제 환경에 맞춘다.
시스템 Wine을 쓰는 Bottle만 `/usr/bin/wineserver`를 쓴다. 다른 Bottle까지 종료하는 `pkill wineserver`는 쓰지 않는다.

```bash
(
set -euo pipefail
bottle="$HOME/.local/share/bottles/bottles/KakaoTalk"
wineserver_bin="$HOME/.local/share/bottles/runners/soda-11.0-5/bin/wineserver"
test -f "$bottle/bottle.yml"
test -f "$bottle/system.reg"
test -x "$wineserver_bin"
env WINEPREFIX="$bottle" "$wineserver_bin" -k
env WINEPREFIX="$bottle" "$wineserver_bin" -w

backup_dir="$(mktemp -d "$HOME/kakaotalk-backup-XXXXXX")"
cp -a --reflink=auto "$bottle" "$backup_dir/KakaoTalk"
printf '전체 백업: %s\n' "$backup_dir"
)
```

`-w`가 완료되기 전에는 다음 단계로 넘어가지 않는다. 정리·복구가 끝날 때까지 Bottle을 다시 실행하지 않는다.
백업 디렉터리는 `700` 권한으로 만들어진다. 백업에는 대화·계정 정보가 들어 있으므로 외부에 공유하지 않는다.
여유 공간은 전체 prefix 크기를 기준으로 확보한다.

### 실제 정리 대상과 안전 원칙

이번에는 Wine을 종료한 뒤 **백업의 `system.reg`를 입력으로 사용한 오프라인 처리**로 아래만 변경했다.

| 대상 | 처리 |
| --- | --- |
| `HKLM\System\ControlSet001\Enum\WINEBTH`와 그 하위 섹션 | 누적 장치 기록 제거 |
| `HKLM\System\ControlSet001\Services\winebth\Start` | DWORD `4` |
| 그 외 섹션·값 | 보존 |

이 README는 자동 삭제·적용 스크립트를 제공하지 않는다. 정리가 필요한 경우 위 범위를 정확히 처리할 수 있는
오프라인 레지스트리 도구로 **백업에서 새 후보 파일을 만들고** 다음 조건을 확인한다.
일반적인 텍스트 검색·줄 삭제만으로 처리하지 않는다. Wine 레지스트리는 섹션과 여러 줄 값이 있기 때문이다.

1. 실행 중인 prefix의 레지스트리를 직접 편집하지 않는다. Wine이 나중에 저장하면서 덮어쓸 수 있다.
2. `system.reg` 전체, 모든 `Enum` 트리, 이름이 비슷한 `WINEBTH_OTHER`나 다른 ControlSet까지 지우지 않는다.
3. 서비스 `Start` 값의 누락·중복·예상 밖 형식, 읽기·쓰기 실패는 성공으로 취급하지 않는다.
4. 정리 후보가 단지 존재하거나 크기가 작다는 이유만으로 적용하지 않는다.
   적용 직전에 같은 백업에서 정리본을 재생성해 후보와 바이트 단위로 비교한다.
   빈 파일·잘린 파일·내용이 바뀐 후보라면 중단한다.
5. 현재 원본도 백업의 원본과 동일한지 다시 비교한다. 달라졌다면 새 백업부터 진행한다.
6. 모든 검증을 통과한 **재생성 파일**만 같은 파일시스템의 임시 위치에서 원본 경로로 원자적으로 교체한다.
   실패 시 원본과 백업을 유지하고, 심볼릭 링크를 무심코 따라가거나 기존 출력 파일을 덮어쓰지 않는다.

당시 907,344,566바이트 백업에서 141,592개 섹션, 903,093,937바이트를 제거해
4,250,629바이트를 남겼다. 이는 해당 사례의 결과이지, 다른 환경에서 통과해야 할 고정 크기는 아니다.
레지스트리 구조를 확실히 구분하기 어렵다면 정리를 중단하고 백업을 보존한다.

### 복구와 재실행

복구할 때도 대상 Bottle을 먼저 완전히 종료한다.
현재 prefix를 별도로 보관한 다음 전체 백업을 원래 경로에 복원한다.
오래된 백업 복원은 그 이후의 앱 설정·로컬 데이터도 되돌리며, 큰 원본 레지스트리를 복원하면 성능 문제도 돌아올 수 있다.
`winebth.sys` 차단이 유지되는지 확인한다.

재실행 뒤 Wine 초기화로 레지스트리가 조금 커지는 것 자체는 이상이 아니다.
한글·영문 입력, 다른 앱에서 돌아왔을 때 갱신, 작은 빈 창 여부를 확인하고
1분 이상 CPU 급증과 파일 크기 증가가 반복되는지 관찰한다.
`ps`의 평균 CPU만 보지 말고 위 진단 절차의 `top`으로 순간 부하도 확인한다.

<a id="reference"></a>

## 자동 실행·URL·경로와 추가 설정

아래는 확인일 당시의 설정 기록이다. 설치 프로그램·실행기·의존성이 만든 값도 포함되며,
모두 수동으로 적용해야 하는 필수 목록은 아니다.

### Wine 내부 자동 실행

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

### URL 연결과 Windows 바로가기

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

#### `steamuser` 경로 매핑

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

### Wine 전역 DLL overrides

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

### 글꼴과 DPI

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

### 입력·화면 관련 호스트 설정

- Omarchy의 기본 `xwayland.force_zero_scaling = true`.
- 개인 모니터 배율은 `1.6`. 진단 당시 노트북 2880×1800/90Hz, 외부 화면 3840×2160/60Hz.
- 키 반복 기본값은 `repeat_rate=40`, `repeat_delay=250`. 이를 이번에 바꾸지는 않았다.
- 키보드 옵션은 `ctrl:nocaps,compose:ralt,shift:both_capslock_cancel`.
  개인 취향 설정이며 카카오톡용 필수 조건이 아니다.
- 카카오톡 프로세스의 locale은 `LANG=en_US.UTF-8`, `LC_CTYPE=C.UTF-8`, `LC_ALL=C.UTF-8`였다.
  한글 입력을 위해 `LANG=ko_KR.UTF-8`로 강제한 구성이 아니다.
- 명시적인 `HKCU\Software\Wine\X11 Driver\InputStyle` 및 `Direct3D` 키는 확인되지 않았다.

모니터 이름·일련번호·배치와 전체 키 바인딩은 각 사용자의 환경에 의존하므로 복사하지 않았다.

### 추출 출처

| 로컬 경로 | 저장소에 반영한 내용 |
| --- | --- |
| `~/.local/share/bottles/bottles/KakaoTalk/bottle.yml` | Bottle 값과 환경 변수 |
| `~/.config/hypr/windows.lua` | 작은 창·첨부파일 보조 창 규칙 |
| `~/.config/hypr/bindings.lua` | 한/영 전환 바인딩 발췌 |
| `~/.config/fcitx5/profile`, `config`, `conf/` | 입력기 프로필·단축키·세부 설정 설명 |
| `/usr/lib/environment.d/10-omarchy-fcitx.conf` | 배포판 기본 환경 변수 |
| `/usr/share/omarchy/default/hypr/envs.lua`, `input.lua` | 배율·키 반복 기본값 설명 |
| Bottle의 `user.reg` / `system.reg` | 비식별 설정만 이 문서에 선별 기록 |
| Bottle의 `drive_c/users/steamuser`와 Windows `.lnk` | 사용자 이름을 제외한 경로 매핑·바로가기 대상과 작업 디렉터리 |
| 실행 중인 프로세스 환경·로드 모듈 | 실제 실행기, XWayland, override 적용 확인 |

Wine prefix의 AppDefaults 게임별 기본값, 디바이스 GUID, Bluetooth 검색 기록,
오디오 장치 캐시, 개인 드라이브 매핑과 애플리케이션 계정 데이터는 추출 대상에서 제외했다.

<a id="limits"></a>

## 검증 범위

- 새 컴퓨터·새 Bottle에서의 처음부터 끝까지 설치 재현
- 다른 Wine/Soda 버전, 다른 GPU, Flatpak Bottles의 동작
- 재부팅·장시간 사용·향후 카카오톡 업데이트 후의 재발 여부
- 음성·영상 통화, Bluetooth 이어폰 통화, 파일 전송 전반
- Soda에서 첨부파일 보조 창의 포커스 처리
- Qt 환경 변수 각각의 필요성과 성능 효과

현재 사용자 환경의 성공 사례와 관측한 한계를 함께 기록해 두는 것이 이 저장소의 목적이다.
