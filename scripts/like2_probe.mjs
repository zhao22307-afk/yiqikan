// 点赞验收探针 v2：按命令行给定的 id 点 N 次，并把收到的计数帧原样打出来。
//
// 用法：node scripts/like2_probe.mjs <room> <id> <count> [intervalMs=800] [lifeSec=40]
// 说明：Node 22+ 内置 WebSocket / fetch；连接后先发 hello（服务端才把它记为在线），
//       再按 intervalMs 间隔连点 count 次 danmaku-like。
const BASE = 'http://127.0.0.1:8080';
const [, , code, targetId, countArg, intervalArg, lifeArg] = process.argv;
if (!code || !targetId) {
  console.error('usage: node like2_probe.mjs <room> <id> <count> [intervalMs] [lifeSec]');
  process.exit(2);
}
const count = Number(countArg || 1);
const intervalMs = Number(intervalArg || 800);
const lifeSec = Number(lifeArg || 40);
const t0 = Date.now();
const ts = () => ((Date.now() - t0) / 1000).toFixed(2).padStart(6);
const log = (...a) => console.log(ts(), ...a);

const joinRes = await fetch(`${BASE}/api/rooms/${code}/join`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ name: 'liker', nickname: 'liker' }),
});
const j = await joinRes.json();
const token =
  (j.member && j.member.token) ||
  (j.data && j.data.member && j.data.member.token) ||
  j.member_token;
if (!token) {
  console.error('!! no guest token', JSON.stringify(j).slice(0, 200));
  process.exit(1);
}
log('join ok', j.member && j.member.id);

const ws = new WebSocket(
  `ws://127.0.0.1:8080/ws?room=${encodeURIComponent(code)}` +
    `&token=&member_token=${encodeURIComponent(token)}`,
);
const seen = new Set();
ws.onopen = () => {
  log('WS OPEN');
  ws.send(JSON.stringify({ type: 'hello', name: 'liker', nickname: 'liker' }));
};
ws.onerror = (e) => log('WS ERR', e.message || e.type);
ws.onmessage = (ev) => {
  let f;
  try { f = JSON.parse(ev.data); } catch { return; }
  if (!seen.has(f.type)) {
    seen.add(f.type);
    log('FIRST', f.type, JSON.stringify(f).slice(0, 120));
  }
  if (f.type === 'danmaku-likes' || f.type === 'danmaku-like') {
    log('<<<', JSON.stringify(f));
  }
};

// 连点：等连接稳定后开始，按 intervalMs 间隔
setTimeout(() => {
  let sent = 0;
  const tick = () => {
    if (sent >= count) return;
    sent++;
    log('>>> like', targetId, `#${sent}`);
    ws.send(JSON.stringify({ type: 'danmaku-like', id: targetId }));
    if (sent < count) setTimeout(tick, intervalMs);
  };
  tick();
}, 1500);

setTimeout(() => {
  try { ws.close(); } catch {}
  process.exit(0);
}, lifeSec * 1000);
