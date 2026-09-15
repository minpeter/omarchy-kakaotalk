# 지연 문제와 복구 기록

## 증상

카카오톡 입력이 느리고 일정한 주기로 화면이 멈추는 느낌이 있었다.
입력하지 않을 때도 크로미움으로 갔다 돌아오면 카카오톡 창 전체가 늦게 갱신됐다.
크로미움 자체는 빠르게 동작했다.

## 측정으로 확인한 내용

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

## 재발 여부 진단

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

## 이미 커진 레지스트리를 정리할 때

새 Bottle이라면 처음부터 드라이버를 차단하면 되고,
기존 Bottle에 대량 기록이 쌓였다면 백업 후 **해당 트리만** 정리해야 한다.

[오프라인 정리 도구](../tools/clean-winebth-registry.pl)는 이번 복구에 사용한 파서를 일반화한 것이다.
**백업 사본을 입력받아 새 파일만 만들며**, Wine 실행·프로세스 종료·실제 prefix 변경은 하지 않는다.
Perl과 표준 모듈만 사용한다.

Wine은 레지스트리를 메모리에 유지한다. **실행 중인 prefix의 reg 파일을 직접 바꾸면**
나중에 Wine이 저장하면서 수정이 덮어써지거나 충돌할 수 있다.

### 1. 차단 설정과 종료 준비

카카오톡 작업을 저장하고 종료한다. Bottles에서 해당 Bottle의 `winebth.sys` DLL override를
빈 값으로 설정하고 저장한 뒤 Bottles 창도 닫는다. 정리 완료 전까지 Bottle을 다시 열지 않는다.

아래는 **호스트 Bottles + Soda 11.0-5**용이다. 먼저 `bottle.yml`의 `Runner`를 확인한다.
다른 실행기라면 `wineserver_bin`을 그 실행기의 바이너리로 바꾼다.
실제로 시스템 Wine을 쓰는 Bottle만 `/usr/bin/wineserver`를 사용한다.
다른 Bottle까지 종료하는 `pkill wineserver`는 쓰지 않는다.

```bash
rg '^Runner:' "$HOME/.local/share/bottles/bottles/KakaoTalk/bottle.yml"
```

### 2. 대상 Bottle 종료 → 전체 백업 → 정리 후보 생성

**저장소 루트에서** 다음 블록을 실행한다. `-k`는 지정한 prefix의 Wine 프로세스를 종료하므로
경로와 실행기를 먼저 확인해야 한다. `-w`는 그 서버의 종료 완료를 기다린다.
오래 걸리면 새 터미널에서 대상 프로세스를 진단하고, 기다리는 중에 다음 단계로 넘어가지 않는다.
실패하면 블록이 중단되며, 이 단계는 실제 `system.reg`를 교체하지 않는다.

```bash
(
set -euo pipefail
bottle="$HOME/.local/share/bottles/bottles/KakaoTalk"
wineserver_bin="$HOME/.local/share/bottles/runners/soda-11.0-5/bin/wineserver"
test -f "$bottle/bottle.yml"
test -f "$bottle/system.reg"
test -x "$wineserver_bin"
test -f tools/clean-winebth-registry.pl
env WINEPREFIX="$bottle" "$wineserver_bin" -k
env WINEPREFIX="$bottle" "$wineserver_bin" -w

backup_dir="$(mktemp -d "$HOME/kakaotalk-backup-XXXXXX")"
cp -a --reflink=auto "$bottle" "$backup_dir/KakaoTalk"
perl tools/clean-winebth-registry.pl \
  "$backup_dir/KakaoTalk/system.reg" "$backup_dir/system.reg.cleaned"
stat -c '%s bytes %n' "$backup_dir/KakaoTalk/system.reg" "$backup_dir/system.reg.cleaned"
printf '백업과 정리 후보: %s\n' "$backup_dir"
)
```

백업은 대화·계정 정보가 포함된 개인 데이터다. 생성 디렉터리는 `mktemp` 기본 권한인 `700`이며,
공개 저장소에 넣지 않는다. 여유 공간은 전체 prefix 크기를 기준으로 확보한다.

도구는 Wine의 `WINE REGISTRY Version 2` 형식에만 사용한다. 처리 범위는 다음과 같다.

- `System\ControlSet001\Enum\WINEBTH`와 그 하위 섹션만 제거한다.
- `System\ControlSet001\Services\winebth`의 기존 `Start` DWORD를 `4`로 바꾼다.
- 다른 섹션·값과 줄바꿈을 보존한다. `WINEBTH_OTHER`나 `ControlSet002`는 제거하지 않는다.
- 원본 수정, 기존 출력 덮어쓰기, 심볼릭 링크 입력을 거부한다.
- 서비스 `Start` 누락·중복·예상 밖 형식이나 잘못된 섹션 헤더면 실패하고 최종 출력 파일을 남기지 않는다.
- 이미 정리되어 삭제할 섹션이 0개여도 정상이다. 이는 대량 누적이 있었다는 증거가 아니다.

출력은 검증을 통과한 뒤에만 권한 `600`으로 만들어진다.
모든 종류의 레지스트리 손상을 검사하는 범용 파서는 아니다.
예상과 다른 결과라면 **실제 prefix에 복사하지 말고** 백업을 보존한 채 원인을 확인한다.
`system.reg` 전체나 다른 `Enum` 트리를 삭제하지 않는다.

### 3. 검토한 정리 후보 적용과 재실행

아래 블록은 **실제 레지스트리를 교체하는 단계**다.
`backup_dir`를 앞에서 출력된 실제 디렉터리로 바꾸고, Bottle이 계속 종료된 상태인지 확인한다.
다시 종료를 기다린 후 백업 이후 원본이 달라졌으면 중단한다. 이 경우 새 백업부터 다시 진행한다.
**저장소 루트에서 실행한다.** 적용 직전에 백업에서 정리본을 다시 만들고, 앞서 검토한 후보와
바이트 단위로 비교한다. 후보가 비어 있거나 손상·변경됐으면 원본을 교체하지 않는다.
실제로 설치하는 파일도 기존 후보가 아니라 방금 재생성한 정리본이다.

```bash
(
set -euo pipefail
bottle="$HOME/.local/share/bottles/bottles/KakaoTalk"
wineserver_bin="$HOME/.local/share/bottles/runners/soda-11.0-5/bin/wineserver"
backup_dir="/앞에서/출력된/kakaotalk-backup-XXXXXX"
test -f "$backup_dir/system.reg.cleaned"
test ! -L "$backup_dir/system.reg.cleaned"
test -f "$backup_dir/KakaoTalk/system.reg"
test -f "$bottle/system.reg"
test ! -L "$bottle/system.reg"
test -f tools/clean-winebth-registry.pl
env WINEPREFIX="$bottle" "$wineserver_bin" -k
env WINEPREFIX="$bottle" "$wineserver_bin" -w
cmp -- "$bottle/system.reg" "$backup_dir/KakaoTalk/system.reg"
stage_dir="$(mktemp -d "$bottle/.system.reg.winebth-XXXXXXXX")"
trap 'rm -f -- "$stage_dir/system.reg"; rmdir -- "$stage_dir"' EXIT
perl tools/clean-winebth-registry.pl \
  "$backup_dir/KakaoTalk/system.reg" "$stage_dir/system.reg"
cmp -- "$stage_dir/system.reg" "$backup_dir/system.reg.cleaned"
cmp -- "$bottle/system.reg" "$backup_dir/KakaoTalk/system.reg"
mv -T -- "$stage_dir/system.reg" "$bottle/system.reg"
)
```

이 블록이 성공한 다음 Bottles에서 카카오톡을 실행한다.

```bash
bottles-cli programs -b KakaoTalk
bottles-cli run -b KakaoTalk -p KakaoTalkUI
```

프로그램 이름은 실제 목록에 맞춘다. Wine 초기화 과정에서 레지스트리가 조금 커질 수 있다.
1분 이상 화면 갱신·입력·CPU와 파일 크기를 관찰한다.

### 복구와 도구 테스트

복구할 때도 해당 Bottle을 먼저 완전히 종료한다.
현재 Bottle을 별도로 보관한 다음 백업 사본을 원래 경로에 복원한다.
옛 백업 복원은 그 이후의 앱 설정·로컬 데이터도 되돌릴 수 있다.
큰 레지스트리가 들어 있는 원본 전체를 복원하면 원래 성능 문제도 돌아올 수 있다.

도구 테스트는 임시 합성 레지스트리만 사용하며 실제 Bottle을 변경하지 않는다.
43개 테스트에서 원본 보존·정리 범위·줄바꿈·재실행·오류 시 출력 방지를 확인했다.
별도의 적용 절차 테스트는 이 문서의 실제 Bash 블록을 추출해 임시 경로와 가짜 종료 명령으로 실행한다.
정상 후보 적용, 빈 후보·잘린 후보·다른 내용의 후보 거부, 원본 변경 감지,
재생성 실패 시 원본 보존과 임시 파일 정리를 확인한다.
또한 당시 907,344,566바이트 백업을 읽기 전용 입력으로 처리한 결과가
원래 복구 때 검증한 4,250,629바이트 정리본과 바이트 단위로 일치했다.
이 검증은 새 환경에서 전체 설치·복구 과정을 다시 수행했다는 의미는 아니다.

```bash
perl -c tools/clean-winebth-registry.pl
prove -v tests/*.t
```

## 실행기를 Soda로 바꾼 이유

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

## 작은 창 규칙이 다시 안 맞을 때

실행기를 바꾸면 X11 창 클래스가 달라질 수 있다.
`hyprctl clients -j`에서 `pid`, `class`, `title`, `floating`을 확인한다.
개인 대화 제목이 포함될 수 있으므로 출력 전체를 공개 이슈에 붙이지 않는다.

이 환경에서 수정한 규칙은 **제목 없는 떠 있는** `explorer.exe` 또는 `steam_proton` 창을 대상으로 한다.
크기와 프로세스 경로를 검사하지 않으므로 다른 Proton 앱의 빈 창도 매칭될 수 있다.
이는 Hyprland 버그를 고친 것이 아니라 Wine 보조 창을 숨기는 우회 설정이다.

## 아직 검증하지 않은 범위

- 다른 Wine/Soda 버전, 다른 GPU, Flatpak Bottles의 동작
- 재부팅·장시간 사용·향후 카카오톡 업데이트 후의 재발 여부
- 음성·영상 통화, Bluetooth 이어폰 통화, 파일 전송 전반
- Soda에서 첨부파일 보조 창의 포커스 처리
- Qt 환경 변수 각각의 필요성과 성능 효과

현재 사용자 환경의 성공 사례와 관측한 한계를 함께 기록해 두는 것이 이 저장소의 목적이다.
