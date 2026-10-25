# 노트북 리모컨 (켜기 / 끄기 / 최대 절전)

기준: Acer Predator Helios Neo 16 AI (PHN16-73-9797) + 랜선 연결 + ipTIME 공유기 + Windows

휴대폰(Flutter 앱) → Tailscale → 노트북 에이전트로 끄기 명령 전송.
켜기는 Wake-on-LAN(유선 랜선 필수).

## 구성
- `agent/agent.py`: Windows 에이전트 (완전 종료, 최대 절전, 절전, 재시작, 취소). 토큰 인증 + 사설망/Tailscale 대역만 허용. `/status`에 유선 MAC·브로드캐스트 주소 포함
- `agent/setup_wol.ps1`: 유선 어댑터 WoL 설정 + 빠른 시작 끄기 + MAC 출력 (Windows 미실행 상태, 아래 "검증 상태" 참고)
- `app/`: Flutter 앱. 상태 확인 시 MAC·브로드캐스트를 자동 저장

## 켜기 가능성 (먼저 확인)
- ipTIME: 공유기 WOL 기능 지원, 단 PC가 공유기에 유선 연결이어야 함 ([ipTIME FAQ](https://iptime.com/support/faq/26011) — WOL 등록·DDNS·원격 관리 포트·ipTIME WOL 앱 절차 안내)
- PHN16-73: 공식 확인 자료 없음 (확실하지 않음)
  - 같은 계열 PHN16S-71(Killer E3100G)에서 BIOS·드라이버 설정 후에도 슬립 중 LAN LED가 꺼지고 Magic Packet이 먹히지 않는다는 사례 있음 ([Acer 커뮤니티 글, 2026-07](https://community.acer.com/en/discussion/740281/wake-on-lan-ethernet-and-wi-fi-not-working-on-predator-helios-neo-16s-ai-phn16s-71-91aw))
  - 본 기종 동작 여부는 실제 시험 필요. 시험 순서: ① 완전 종료 → 켜기 ② 최대 절전 → 켜기 ③ 절전(Modern Standby) → 켜기
  - 시험에서 실패하면 대안: WoL 지원 USB-이더넷 어댑터 사용 (제품별 상이)

## 1. 노트북 설정 (Windows)
1. Python 3.9 이상 설치
2. `agent\config.example.json` → `agent\config.json` 복사 후 `token`을 긴 임의 문자열로 변경
3. 관리자 PowerShell에서 `powershell -ExecutionPolicy Bypass -File agent\setup_wol.ps1` 실행
   - 출력된 `powercfg /devicequery wake_armed` 목록에 유선 어댑터가 있어야 함
   - 출력된 MAC 주소를 메모
4. 재부팅 → F2 BIOS에서 Wake on LAN 계열 항목이 있으면 Enabled (Predator BIOS는 항목이 제한적일 수 있음, 확실하지 않음)
5. 에이전트 실행: `python agent\agent.py` (방화벽 TCP 8765 허용)
6. 자동 실행: `schtasks /create /tn LaptopRemote /sc onlogon /rl limited /tr "pythonw C:\경로\agent\agent.py"`

## 2. 공유기 설정 (ipTIME)
1. 공유기 관리 화면 → 특수 기능 → WOL 기능 → 노트북 유선 MAC 등록
2. 외부에서 켜려면: 보안 기능 → 공유기 접속/보안관리 → 원격 관리 포트 사용 + 특수 기능 → DDNS 설정
3. 외부 켜기는 ipTIME WOL 앱(공식)으로 수행: DDNS 주소 + 원격 관리 포트 + 공유기 계정 입력
   - 이유: 공유기 로그인(보안문자 포함) 절차 때문에 자체 앱에서 대신 호출하기 어려움
   - 자체 앱의 켜기 버튼은 같은 공유기(집 Wi-Fi) 안에서만 도달

## 3. 외부 끄기 (Tailscale)
- 노트북과 휴대폰에 Tailscale 설치, 같은 계정 로그인
- 앱 설정의 "노트북 주소"에 노트북 Tailscale IP(`100.x.x.x`) 입력
- 포트포워딩 불필요, Jump Desktop과 병행 가능

## 4. 앱 빌드
```
cd app
flutter create --platforms=android,ios .
flutter pub get
flutter run
```
- Android: `AndroidManifest.xml`의 `<application>`에 `android:usesCleartextTraffic="true"` 추가, INTERNET 권한 확인
- iOS: `Info.plist`에 로컬 네트워크 사용 설명 추가

## 5. 사용 흐름
- 집에서 켜기: 앱 "켜기" (또는 ipTIME WOL 앱)
- 외부에서 켜기: ipTIME WOL 앱
- 끄기/최대 절전: 앱 (집 Wi-Fi 또는 Tailscale)

## API
헤더 `X-Token: <토큰>` 필요
- `GET /status`
- `POST /shutdown?delay=10`, `/restart?delay=10`, `/hibernate`, `/sleep`, `/cancel`

## 검증 상태
- 에이전트: Linux dry-run으로 인증·라우팅 확인. Windows 실제 전원 명령, 유선 MAC 조회(PowerShell)는 미검증
- `setup_wol.ps1`: 미실행 (이 환경에 PowerShell 없음)
- 앱: Flutter 없음으로 빌드·실행 미검증
- PHN16-73 WoL: 실기기 시험 전까지 동작 여부 알 수 없음
