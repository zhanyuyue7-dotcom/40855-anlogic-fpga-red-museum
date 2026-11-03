"""Local, deduplicated browser dashboard for lab_ex_4 FPGA UART telemetry."""

from __future__ import annotations

import argparse
from collections import deque
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import re
import threading
import time
import webbrowser


PACKET_RE = re.compile(
    r"^@S,([0-9A-F]),([0-9A-F]),([0-9A-F]),([01]),([01]),([01]),([01]),([01]),([0-3]),([0-3])$"
)
FIELD_NAMES = (
    "state",
    "found",
    "image",
    "auto",
    "load",
    "display_valid",
    "sd_init",
    "scan_done",
    "disp_buf",
    "write_buf",
)
STATE_LABELS = {
    0: "复位或 SD 未初始化",
    1: "控制器空闲",
    2: "扫描扇区 / 读取 BMP 头",
    3: "等待 SDRAM 写请求应答",
    4: "加载 BMP 像素",
}


def utc_now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="milliseconds")


def parse_status_line(line: str) -> dict[str, int] | None:
    match = PACKET_RE.fullmatch(line.strip().upper())
    if not match:
        return None
    values = [int(value, 16) for value in match.groups()]
    return dict(zip(FIELD_NAMES, values, strict=True))


class StatusStore:
    def __init__(self, event_limit: int = 100) -> None:
        self._lock = threading.Lock()
        self._latest: dict[str, object] | None = None
        self._events: deque[dict[str, object]] = deque(maxlen=event_limit)
        self._received = 0
        self._duplicates = 0
        self._invalid = 0
        self._sequence = 0
        self._connected = False
        self._port: str | None = None
        self._reading_enabled = True

    def set_connection(self, connected: bool, port: str | None = None) -> None:
        with self._lock:
            self._connected = connected
            if port is not None:
                self._port = port

    def set_reading_enabled(self, enabled: bool) -> None:
        with self._lock:
            self._reading_enabled = enabled
            if not enabled:
                self._connected = False

    def reading_enabled(self) -> bool:
        with self._lock:
            return self._reading_enabled

    def invalid_packet(self) -> None:
        with self._lock:
            self._invalid += 1

    def update(self, fields: dict[str, int]) -> bool:
        with self._lock:
            self._received += 1
            timestamp = utc_now()
            comparable = {name: fields[name] for name in FIELD_NAMES}
            previous = None
            if self._latest is not None:
                previous = {name: self._latest[name] for name in FIELD_NAMES}
            if previous == comparable:
                self._duplicates += 1
                self._latest["last_seen"] = timestamp
                return False

            self._sequence += 1
            event: dict[str, object] = {
                **comparable,
                "state_label": STATE_LABELS.get(fields["state"], "未知状态"),
                "changed_at": timestamp,
                "last_seen": timestamp,
                "sequence": self._sequence,
            }
            self._latest = event
            self._events.appendleft(dict(event))
            return True

    def snapshot(self) -> dict[str, object]:
        with self._lock:
            return {
                "connected": self._connected,
                "port": self._port,
                "reading_enabled": self._reading_enabled,
                "latest": dict(self._latest) if self._latest else None,
                "stats": {
                    "received": self._received,
                    "duplicates_filtered": self._duplicates,
                    "invalid": self._invalid,
                    "changes_kept": len(self._events),
                },
            }

    def events(self) -> list[dict[str, object]]:
        with self._lock:
            return [dict(event) for event in self._events]


DASHBOARD_HTML = r"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>瞬应 · FPGA 状态台</title>
  <style>
    :root { --bg:#f4f0e8; --panel:#fffaf1; --ink:#292621; --muted:#756f66;
      --line:#d8d0c2; --accent:#c9653b; --ok:#477a5b; --warn:#a66a2c; }
    * { box-sizing:border-box; }
    body { margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui,"Microsoft YaHei",sans-serif; }
    main { max-width:1120px; margin:0 auto; padding:28px 20px 44px; }
    header { display:flex; justify-content:space-between; gap:20px; align-items:flex-start; margin-bottom:20px; }
    h1 { margin:0 0 4px; font-size:28px; letter-spacing:-.02em; }
    .sub { color:var(--muted); }
    .pill { border:1px solid var(--line); border-radius:999px; padding:7px 12px; background:var(--panel); }
    .ok { color:var(--ok); } .bad { color:#a23f35; }
    .controls { display:flex; align-items:center; gap:10px; margin:0 0 20px; flex-wrap:wrap; }
    button { border:1px solid var(--line); border-radius:8px; padding:9px 13px; background:var(--panel); color:var(--ink); font:inherit; cursor:pointer; }
    button:hover { border-color:var(--accent); }
    button:disabled { cursor:wait; opacity:.6; }
    .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(175px,1fr)); gap:12px; }
    .card { background:var(--panel); border:1px solid var(--line); border-radius:14px; padding:15px; box-shadow:0 2px 12px #4a3b2510; }
    .label { color:var(--muted); font-size:12px; text-transform:uppercase; letter-spacing:.08em; }
    .value { margin-top:5px; font-size:24px; font-weight:650; }
    .wide { grid-column:span 2; }
    section { margin-top:22px; }
    h2 { font-size:17px; margin:0 0 10px; }
    table { width:100%; border-collapse:collapse; background:var(--panel); border:1px solid var(--line); }
    th,td { text-align:left; padding:9px 10px; border-bottom:1px solid var(--line); white-space:nowrap; }
    th { color:var(--muted); font-size:12px; }
    .scroll { overflow:auto; border-radius:12px; }
    code { color:var(--accent); }
    @media(max-width:640px){ .wide{grid-column:span 1} header{display:block}.pill{display:inline-block;margin-top:12px} }
  </style>
</head>
<body><main>
  <header><div><h1>瞬应 · FPGA 状态台</h1><div class="sub">lab_ex_4 · 变化事件去重 · 1 秒心跳</div></div>
    <div id="connection" class="pill">等待数据…</div></header>
  <div class="controls"><button id="reading-toggle" type="button" onclick="toggleReading()">停止读取串口</button><span id="reading-note" class="sub">停止后 FPGA 仍继续运行，页面保留最后状态</span></div>
  <div class="grid">
    <div class="card wide"><div class="label">控制状态</div><div id="state" class="value">—</div></div>
    <div class="card"><div class="label">找到图片</div><div id="found" class="value">—</div></div>
    <div class="card"><div class="label">当前图片</div><div id="image" class="value">—</div></div>
    <div class="card"><div class="label">自动轮播</div><div id="auto" class="value">—</div></div>
    <div class="card"><div class="label">加载任务</div><div id="load" class="value">—</div></div>
    <div class="card"><div class="label">显示有效</div><div id="valid" class="value">—</div></div>
    <div class="card"><div class="label">SD 初始化 / 扫描</div><div id="sd" class="value">—</div></div>
    <div class="card"><div class="label">显示 / 写缓冲</div><div id="buffers" class="value">—</div></div>
  </div>
  <section><h2>本地过滤统计</h2><div id="stats" class="sub">—</div></section>
  <section><h2>最近状态变化（最多 100 条）</h2><div class="scroll"><table><thead><tr>
    <th>#</th><th>时间</th><th>状态</th><th>图片</th><th>找到</th><th>自动</th><th>加载</th><th>缓冲</th>
  </tr></thead><tbody id="events"></tbody></table></div></section>
</main><script>
const text=(id,v)=>document.getElementById(id).textContent=v;
const yn=v=>v?'ON':'OFF';
let readingEnabled=true;
let toggling=false;
async function refresh(){try{
  const [s,e]=await Promise.all([fetch('/api/status',{cache:'no-store'}),fetch('/api/events',{cache:'no-store'})]);
  const status=await s.json(), events=await e.json(), x=status.latest;
  const c=document.getElementById('connection');
  readingEnabled=Boolean(status.reading_enabled);
  if(!readingEnabled){ c.textContent='已停止读取（FPGA 仍运行）'; c.className='pill'; }
  else { c.textContent=status.connected?`已连接 ${status.port||''}`:'串口未连接'; c.className='pill '+(status.connected?'ok':'bad'); }
  const toggle=document.getElementById('reading-toggle');
  toggle.textContent=readingEnabled?'停止读取串口':'恢复读取串口';
  toggle.disabled=toggling || !status.port;
  text('reading-note',readingEnabled?'停止后 FPGA 仍继续运行，页面保留最后状态':'读取已停止；FPGA 和 HDMI 输出不受影响');
  if(x){ text('state',`${x.state} · ${x.state_label}`); text('found',x.found); text('image',x.image);
    text('auto',yn(x.auto)); text('load',yn(x.load)); text('valid',yn(x.display_valid));
    text('sd',`${yn(x.sd_init)} / ${yn(x.scan_done)}`); text('buffers',`${x.disp_buf} / ${x.write_buf}`); }
  const q=status.stats; text('stats',`收到 ${q.received} 包 · 过滤重复心跳 ${q.duplicates_filtered} · 无效 ${q.invalid} · 保留变化 ${q.changes_kept} · 浏览器仅请求本机接口`);
  document.getElementById('events').innerHTML=events.slice(0,30).map(v=>`<tr><td>${v.sequence}</td><td>${v.changed_at.slice(11,23)}</td><td>${v.state_label}</td><td>${v.image}</td><td>${v.found}</td><td>${yn(v.auto)}</td><td>${yn(v.load)}</td><td>${v.disp_buf}/${v.write_buf}</td></tr>`).join('');
}catch(err){document.getElementById('connection').textContent='本地服务异常';}}
async function toggleReading(){
  const button=document.getElementById('reading-toggle');
  if(toggling || button.disabled) return;
  toggling=true;
  try{
    const endpoint=readingEnabled?'/api/serial/stop':'/api/serial/start';
    await fetch(endpoint,{method:'POST'});
  } finally {
    toggling=false;
    await refresh();
  }
}
refresh(); setInterval(refresh,500);
</script></body></html>"""


def make_handler(store: StatusStore):
    class Handler(BaseHTTPRequestHandler):
        def _send_json(self, value: object) -> None:
            payload = json.dumps(value, ensure_ascii=False).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def do_POST(self) -> None:  # noqa: N802 - stdlib handler API
            if self.path == "/api/serial/stop":
                store.set_reading_enabled(False)
                self._send_json(store.snapshot())
                return
            if self.path == "/api/serial/start":
                store.set_reading_enabled(True)
                self._send_json(store.snapshot())
                return
            self.send_error(404)

        def do_GET(self) -> None:  # noqa: N802 - stdlib handler API
            if self.path == "/api/status":
                self._send_json(store.snapshot())
                return
            if self.path == "/api/events":
                self._send_json(store.events())
                return
            if self.path == "/":
                payload = DASHBOARD_HTML.encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return
            self.send_error(404)

        def log_message(self, _format: str, *_args: object) -> None:
            return

    return Handler


def detect_ch340_port() -> str:
    from serial.tools import list_ports

    candidates = []
    for port in list_ports.comports():
        description = (port.description or "").lower()
        if port.vid == 0x1A86 or "ch340" in description or "usb-serial" in description:
            candidates.append(port.device)
    if len(candidates) == 1:
        return candidates[0]
    if not candidates:
        raise RuntimeError("未发现 CH340；请连接开发板独立 USB-UART Type-C 数据口")
    raise RuntimeError(f"发现多个 CH340，请用 --port 指定：{', '.join(candidates)}")


def serial_worker(store: StatusStore, port: str, baud: int) -> None:
    import serial

    while True:
        if not store.reading_enabled():
            store.set_connection(False, port)
            time.sleep(0.1)
            continue
        try:
            with serial.Serial(port, baudrate=baud, timeout=0.25) as stream:
                store.set_connection(True, port)
                print(f"UART connected: {port} @ {baud}")
                while store.reading_enabled():
                    raw = stream.readline()
                    if not raw:
                        continue
                    if not store.reading_enabled():
                        break
                    line = raw.decode("ascii", errors="ignore").strip()
                    fields = parse_status_line(line)
                    if fields is None:
                        store.invalid_packet()
                        continue
                    if store.update(fields):
                        print(
                            f"CHANGE state={fields['state']} found={fields['found']} "
                            f"image={fields['image']} auto={fields['auto']} "
                            f"load={fields['load']} valid={fields['display_valid']}"
                        )
        except Exception as error:  # reconnect after cable replug
            store.set_connection(False, port)
            if store.reading_enabled():
                print(f"UART disconnected: {error}; retrying in 1s")
                time.sleep(1)


def demo_worker(store: StatusStore) -> None:
    states = [
        dict(zip(FIELD_NAMES, (0, 0, 0, 0, 0, 0, 0, 0, 0, 0), strict=True)),
        dict(zip(FIELD_NAMES, (2, 4, 0, 0, 1, 0, 1, 0, 0, 0), strict=True)),
        dict(zip(FIELD_NAMES, (4, 4, 0, 0, 1, 0, 1, 1, 0, 0), strict=True)),
        dict(zip(FIELD_NAMES, (1, 4, 0, 0, 0, 1, 1, 1, 0, 1), strict=True)),
        dict(zip(FIELD_NAMES, (1, 4, 1, 1, 0, 1, 1, 1, 1, 0), strict=True)),
    ]
    store.set_connection(True, "DEMO")
    while True:
        if not store.reading_enabled():
            store.set_connection(False, "DEMO")
            time.sleep(0.1)
            continue
        store.set_connection(True, "DEMO")
        for status in states:
            if not store.reading_enabled():
                break
            store.update(status)
            store.update(status)  # prove duplicate filtering in demo mode
            time.sleep(1)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", help="CH340 COM port; auto-detected when omitted")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--http-port", type=int, default=8765)
    parser.add_argument("--event-limit", type=int, default=100)
    parser.add_argument("--demo", action="store_true", help="run without hardware")
    parser.add_argument("--no-browser", action="store_true")
    args = parser.parse_args()

    store = StatusStore(args.event_limit)
    if args.demo:
        worker = threading.Thread(target=demo_worker, args=(store,), daemon=True)
    else:
        port = args.port or detect_ch340_port()
        worker = threading.Thread(target=serial_worker, args=(store, port, args.baud), daemon=True)
    worker.start()

    url = f"http://{args.host}:{args.http_port}/"
    server = ThreadingHTTPServer((args.host, args.http_port), make_handler(store))
    print(f"Local dashboard: {url}")
    print("No cloud API is used. Press Ctrl+C to stop.")
    if not args.no_browser:
        threading.Timer(0.4, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
