# 노트북 리모컨 (켜기 / 끄기 / 최대 절전)

휴대폰(Flutter 앱) → Tailscale → 노트북 에이전트(Windows)로 전원 명령을 보낸다.

## 구성
- `agent/agent.py`: Windows 에이전트 (Python 표준 라이브러리만 사용)
  - 완전 종료, 최대 절전, 절전, 재시작, 취소
  - 토큰 인증 + 사설망/Tailscale 대역만 접속 허용
- `app/`: Flutter 앱 (켜기 / 끄기 버튼, 상태 표시, 설정 화면)

## 한계 (먼저 확인)
- 완전 종료 상태에서 켜기(Wake-on-LAN)는 노트북이 Wi-Fi만 쓰면 대부분 동작하지 않음 (기종별 상이, 확실하지 않음)
  - 안정적 방법: USB-이더넷 어댑터(WoL 지원 칩셋) 또는 유선 LAN 연결
  - 최대 절전/절전은 Wi-Fi 어댑터가 Magic Packet 깨우기를 지원하면 가능 (기종별 상이)
- 앱의 켜기 신호는 브로드캐스트 UDP이므로 같은 Wi-Fi 안에서만 도달
  - 외부(LTE/5G)에서 켜려면 집 안에 항상 켜진 중계 기기(공유기 WoL 기능, 라즈베리파이 등)가 필요

## 1. 노트북 설정 (Windows)
1. Python 3.9 이상 설치
2. `agent/config.example.json` → `agent/config.json` 복사 후 `token`을 긴 임의 문자열로 변경
3. 실행: `python agent\agent.py`
4. 방화벽에서 TCP 8765 허용 (가능하면 Tailscale 대역 `100.64.0.0/10` 한정)
5. 로그인 시 자동 실행 (관리자 PowerShell):
   `schtasks /create /tn LaptopRemote /sc onlogon /rl limited /tr "pythonw C:\경로\agent\agent.py"`
6. 최대 절전 사용: `powercfg /h on`
7. 켜기 준비: 장치 관리자 → Wi-Fi/이더넷 어댑터 → 전원 관리 → "magic packet으로만 깨우기" 체크, BIOS의 Wake on LAN/WLAN 활성화, 고속 시작 끄기

## 2. 외부 접속 (Tailscale 권장)
- 이유: 공유기 포트포워딩 없이 암호화된 사설 연결 제공 (개인 무료 플랜 존재, 정책은 변동 가능)
- 노트북과 휴대폰에 Tailscale 설치 후 같은 계정으로 로그인
- 앱 설정의 "노트북 주소"에 노트북의 Tailscale IP (`100.x.x.x`) 입력
- Jump Desktop 원격 접속과 병행 사용 가능

## 3. 앱 빌드
```
cd app
flutter create --platforms=android,ios .
flutter pub get
flutter run
```
- Android: `android/app/src/main/AndroidManifest.xml`의 `<application>`에 `android:usesCleartextTraffic="true"` 추가, `<manifest>` 하위에 `<uses-permission android:name="android.permission.INTERNET"/>` 확인 (Tailscale 내부 HTTP 통신용)
- iOS: `Info.plist`에 `NSAppTransportSecurity` → `NSAllowsLocalNetworking` / 로컬 네트워크 사용 설명 추가

## 4. API
헤더 `X-Token: <토큰>` 필요
- `GET /status`
- `POST /shutdown?delay=10`, `/restart?delay=10`, `/hibernate`, `/sleep`, `/cancel`

## 검증 상태
- 에이전트: Linux에서 dry-run 모드로 인증·라우팅 확인 (Windows 실제 전원 명령은 미검증)
- 앱: 이 환경에 Flutter가 없어 빌드·실행 미검증
