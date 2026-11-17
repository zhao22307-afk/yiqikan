// 弹幕刷屏探针：按固定间隔发 N 条 danmaku 帧，用来验「_items 会被裁掉」。
//
// 用法：node scripts/spam_probe.mjs <room> [count=120] [intervalMs=200]
// 说明：连上先 hello（服务端才把它记入在线），等收到 state 帧拿到当前播放位置，
//       然后每条弹幕的 pos 都用「发这一条时服务端的播放位置」，让它们全部落在过去。
const BASE = 'http://127.0.0.1:8080';
const [, , code, countArg, intervalArg] = process.argv;
if (!code) {
  console.error('usage: node spam_probe.mjs <room> [count] [intervalMs] [textPrefix]');
  process.exit(2);
}
const count = Number(countArg || 120);
const intervalMs = Number(intervalArg || 200);
const prefix = process.argv[5] || 'spam';
const t0 = Date.now();
const ts = () => ((Date.now() - t0) / 1000).toFixed(2).padStart(6);
const log = (...a) => console.log(ts(), ...a);

const joinRes = await fetch(`${BASE}/api/rooms/${code}/join`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ name: 'spammer', nickname: 'spammer' }),
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

let pos = 0;
let started = false;
const ws = new WebSocket(
  `ws://127.0.0.1:8080/ws?room=${encodeURIComponent(code)}` +
    `&token=&member_token=${encodeURIComponent(token)}`,
);
ws.onopen = () => {
  log('WS OPEN');
  ws.send(JSON.stringify({ type: 'hello', name: 'spammer', nickname: 'spammer' }));
};
ws.onerror = (e) => log('WS ERR', e.message || e.type);
ws.onmessage = (ev) => {
  let f;
  try { f = JSON.parse(ev.data); } catch { return; }
  if (f.type === 'state' && f.state && typeof f.state.position === 'number') {
    pos = f.state.position;
    if (!started) {
      started = true;
      log('state pos=', pos.toFixed(2), '→ 开刷', count, '条');
      let sent = 0;
      const tick = () => {
        if (sent >= count) {
          log('done sent=', sent);
          return;
        }
        sent++;
        ws.send(JSON.stringify({
          type: 'danmaku',
          text: `${prefix}${sent}`,
          pos,
          color: 16777215,
          size: 1,
          mode: 'scroll',
        }));
        if (sent % 20 === 0) log('sent', sent);
        setTimeout(tick, intervalMs);
      };
      tick();
    }
  }
  if (f.type === 'danmaku-likes') log('<<<', JSON.stringify(f).slice(0, 100));
};

setTimeout(() => {
  try { ws.close(); } catch {}
  process.exit(0);
}, (count * intervalMs + 12000));
