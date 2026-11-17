// D14 共控限流探针：进房 → hello → 按给定间隔连发 count 条 claim。
// 用法：node scripts/claim_probe.mjs --room <code> --action play --count 5 --gap 50 [--pos 30] [--name p1]
//   --action 可以是逗号分隔的序列（例：play,seek，用来看「不同动作互不影响」）
//   --pos 只在 action 含 seek 时带上 position
const BASE = process.env.BASE || 'http://127.0.0.1:8080';
const arg = (name, dflt = '') => {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 && process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[i + 1] : dflt;
};
const log = (line) => console.log(`[${new Date().toISOString().slice(11, 23)}] ${line}`);

const room = arg('room');
const actions = arg('action', 'play').split(',').map((s) => s.trim()).filter(Boolean);
const count = Number(arg('count', '5'));
const gap = Number(arg('gap', '50'));
const pos = Number(arg('pos', '30'));
const name = arg('name', `cp_${Math.random().toString(36).slice(2, 7)}`);
const holdSec = Number(arg('secs', '3'));

const j = await (await fetch(`${BASE}/api/rooms/${room}/join`, {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ name }),
})).json();
const token = j?.member?.token || j?.data?.member?.token;
if (!token) {
  console.log('join fail', JSON.stringify(j).slice(0, 200));
  process.exit(1);
}
log(`join ok member=${j.member.id} name=${name}`);

const ws = new WebSocket(`ws://127.0.0.1:8080/ws?room=${room}&token=&member_token=${token}`);
const send = (o) => ws.send(JSON.stringify(o));
let sent = 0;

ws.onopen = () => {
  log('WS OPEN');
  send({ type: 'hello', name, room });
  setTimeout(() => {
    const timer = setInterval(() => {
      const action = actions[sent % actions.length];
      const f = { type: 'claim', action };
      if (action === 'seek') f.position = pos;
      if (action === 'rate') f.rate = 1.5;
      send(f);
      sent += 1;
      log(`>>> claim #${sent} action=${action}`);
      if (sent >= count) {
        clearInterval(timer);
        setTimeout(() => process.exit(0), holdSec * 1000);
      }
    }, gap);
  }, 900);
};

ws.onmessage = (ev) => {
  let f;
  try {
    f = JSON.parse(ev.data);
  } catch {
    return;
  }
  if (/^(claim|pending|members|state|hello)/.test(f.type)) {
    log(`<<< ${f.type} ${JSON.stringify(f).slice(0, 180)}`);
  }
};

ws.onclose = () => log('WS CLOSE');
ws.onerror = (e) => log(`WS ERROR ${e.message || ''}`);
setTimeout(() => process.exit(0), (count * gap) + holdSec * 1000 + 6000);
