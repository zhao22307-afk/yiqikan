// dm_probe.mjs —— 冒充 guest 连进房间，只干一件事：把收到的 danmaku 帧原样打出来。
// 用法: node dm_probe.mjs <code> [seconds=25]
// 依赖: Node 22+（全局 WebSocket / fetch）。设备端需先 `adb forward tcp:8080 tcp:8080`。
const BASE = 'http://127.0.0.1:8080';
const [, , code, secsArg] = process.argv;
if (!code) {
  console.error('usage: node dm_probe.mjs <code> [seconds]');
  process.exit(2);
}
const secs = Number(secsArg || 25);
const t0 = Date.now();
const ts = () => ((Date.now() - t0) / 1000).toFixed(2).padStart(6);
const log = (...a) => console.log(ts(), ...a);

const joinRes = await fetch(`${BASE}/api/rooms/${code}/join`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ name: 'dmprobe', nickname: 'dmprobe' }),
});
const joinJson = await joinRes.json();
log('join', joinRes.status, JSON.stringify(joinJson).slice(0, 200));
const guestToken =
  (joinJson.member && joinJson.member.token) ||
  (joinJson.data && joinJson.data.member && joinJson.data.member.token);
if (!guestToken) {
  console.error('!! no guest token');
  process.exit(1);
}

const url = `ws://127.0.0.1:8080/ws?room=${encodeURIComponent(code)}&token=&member_token=${encodeURIComponent(guestToken)}`;
log('connect', url.replace(guestToken, guestToken.slice(0, 6) + '…'));
const ws = new WebSocket(url);
let danmakuCount = 0;
let chatCount = 0;

ws.onopen = () => log('WS OPEN');
ws.onerror = (e) => log('WS ERROR', e.message || e.type);
ws.onmessage = (ev) => {
  let f;
  try { f = JSON.parse(ev.data); } catch { return; }
  if (f.type === 'danmaku') {
    danmakuCount++;
    log(`<<< danmaku #${danmakuCount} pos=${f.pos} color=${f.color} size=${f.size} mode=${f.mode} text="${f.text}" from=${f.from} id=${f.id}`);
  } else if (f.type === 'chat') {
    chatCount++;
    log(`<<< chat #${chatCount} text="${f.text}"`);
  } else if (f.type !== 'sync' && f.type !== 'state' && f.type !== 'presence') {
    log('<<<', f.type, JSON.stringify(f).slice(0, 160));
  }
};
ws.onclose = () => log(`WS CLOSE  danmaku=${danmakuCount} chat=${chatCount}`);

setTimeout(() => {
  log(`SUMMARY danmaku=${danmakuCount} chat=${chatCount}`);
  ws.close();
  process.exit(0);
}, secs * 1000);
