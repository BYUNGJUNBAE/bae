"""노트북 전원 제어 에이전트 (Windows, 표준 라이브러리만 사용)

엔드포인트 (헤더 `X-Token` 필요)
  GET  /status            상태 확인 (유선 어댑터 MAC / 브로드캐스트 주소 포함)
  POST /shutdown          완전 종료 (기본 10초 유예, ?delay=N)
  POST /hibernate         최대 절전
  POST /sleep             절전
  POST /restart           재시작 (기본 10초 유예)
  POST /cancel            예약된 종료/재시작 취소
"""
import hmac
import ipaddress
import json
import os
import platform
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.json")
DEFAULTS = {
    "host": "0.0.0.0",
    "port": 8765,
    "token": "",
    # 사설망 + Tailscale(100.64.0.0/10) 대역만 허용
    "allowed_networks": ["127.0.0.0/8", "192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12", "100.64.0.0/10"],
    "default_delay": 10,
}
IS_WINDOWS = platform.system() == "Windows"
DRY_RUN = os.environ.get("DRY_RUN") == "1"


def load_config():
    cfg = dict(DEFAULTS)
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, encoding="utf-8") as f:
            cfg.update(json.load(f))
    if not cfg["token"] or cfg["token"] == "CHANGE_ME":
        sys.exit("config.json 의 token 을 긴 임의 문자열로 설정하세요.")
    return cfg


def run(cmd):
    if DRY_RUN or not IS_WINDOWS:
        print("[dry-run]", " ".join(cmd))
        return 0
    return subprocess.call(cmd)


WIRED_QUERY = (
    "$a = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' -and $_.PhysicalMediaType -eq '802.3' } | Select-Object -First 1; "
    "if ($a) { $ip = Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 | Select-Object -First 1; "
    "@{mac=$a.MacAddress; ip=$ip.IPAddress; prefix=$ip.PrefixLength} | ConvertTo-Json -Compress }"
)


def wired_info():
    """유선 어댑터의 MAC / 브로드캐스트 주소 (Windows 전용, 실패 시 빈 값)"""
    if not IS_WINDOWS:
        return {}
    try:
        out = subprocess.check_output(
            ["powershell", "-NoProfile", "-Command", WIRED_QUERY], timeout=8, text=True
        ).strip()
        if not out:
            return {}
        d = json.loads(out)
        net = ipaddress.ip_network("%s/%s" % (d["ip"], d["prefix"]), strict=False)
        return {"mac": d["mac"].replace("-", ":"), "broadcast": str(net.broadcast_address)}
    except Exception as e:  # 조회 실패는 상태 응답을 막지 않는다
        print("wired_info failed:", e)
        return {}


def build_actions(delay):
    return {
        "shutdown": ["shutdown", "/s", "/t", str(delay)],
        "restart": ["shutdown", "/r", "/t", str(delay)],
        "hibernate": ["shutdown", "/h"],
        "sleep": ["rundll32.exe", "powrprof.dll,SetSuspendState", "0,1,0"],
        "cancel": ["shutdown", "/a"],
    }


class Handler(BaseHTTPRequestHandler):
    cfg = {}
    nets = []

    def _reply(self, code, body):
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _authorized(self):
        ip = ipaddress.ip_address(self.client_address[0])
        if not any(ip in n for n in self.nets):
            return False
        sent = self.headers.get("X-Token", "")
        return hmac.compare_digest(sent.encode(), self.cfg["token"].encode())

    def do_GET(self):
        if not self._authorized():
            return self._reply(401, {"ok": False, "error": "unauthorized"})
        if urlparse(self.path).path == "/status":
            body = {"ok": True, "host": platform.node(), "os": platform.system()}
            body.update(wired_info())
            return self._reply(200, body)
        self._reply(404, {"ok": False, "error": "not found"})

    def do_POST(self):
        if not self._authorized():
            return self._reply(401, {"ok": False, "error": "unauthorized"})
        url = urlparse(self.path)
        action = url.path.strip("/")
        try:
            delay = int(parse_qs(url.query).get("delay", [self.cfg["default_delay"]])[0])
        except ValueError:
            return self._reply(400, {"ok": False, "error": "invalid delay"})
        actions = build_actions(max(0, min(delay, 3600)))
        if action not in actions:
            return self._reply(404, {"ok": False, "error": "unknown action"})
        code = run(actions[action])
        self._reply(200 if code == 0 else 500, {"ok": code == 0, "action": action})

    def log_message(self, fmt, *args):
        print("%s %s" % (self.client_address[0], fmt % args))


def main():
    cfg = load_config()
    Handler.cfg = cfg
    Handler.nets = [ipaddress.ip_network(n) for n in cfg["allowed_networks"]]
    server = ThreadingHTTPServer((cfg["host"], cfg["port"]), Handler)
    print("listening on %s:%d (dry-run=%s)" % (cfg["host"], cfg["port"], DRY_RUN or not IS_WINDOWS))
    server.serve_forever()


if __name__ == "__main__":
    main()
