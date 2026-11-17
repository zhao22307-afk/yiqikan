// 单条「未来弹幕」探针：pos = 当前播放位置 + OFFSET 秒，用来验「未来弹幕不被裁」。
// 用法：node scripts/future_probe.mjs <room> <text> <offsetSec>
const BASE = 'http://127.0.0.1:8080';
const [, , code, text, offsetArg] = process.argv;
const offset = Number(offsetArg || 20);
const t0 = Date.now();
const ts = () => ((Date.now() - t0) / 1000).toFixed(2).padStart(6);

const r = await fetch(`${BASE}/api/rooms/${code}/join`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ name: 'future', nickname: 'future' }),
});
const j = await r.json();
const token = (j.member && j.member.token) || (j.data && j.data.member && j.data.member.token) || j.member_token;
const ws = new WebSocket(`ws://127.0.0.1:8080/ws?room=${encodeURIComponent(code)}&token=&member_token=${encodeURIComponent(token)}`);
ws.onopen = () => ws.send(JSON.stringify({ type: 'hello', name: 'future', nickname: 'future' }));
ws.onmessage = (ev) => {
  let f; try { f = JSON.parse(ev.data); } catch { return; }
  if (f.type === 'state' && f.state && typeof f.state.position === 'number') {
    const pos = f.state.position + offset;
    console.log(ts(), 'send future pos=', pos.toFixed(2), 'text=', text);
    ws.send(JSON.stringify({ type: 'danmaku', text, pos, color: 16777215, size: 1, mode: 'scroll' }));
    setTimeout(() => { try { ws.close(); } catch {} process.exit(0); }, 800);
  }
};
setTimeout(() => process.exit(1), 15000);
