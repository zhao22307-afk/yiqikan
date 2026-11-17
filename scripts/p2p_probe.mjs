// 点对点校验探针（M8 7a）：只用来证明「不在语音的人发 SDP 会被挡」。
//
//   node p2p_probe.mjs <room> listen <secs>
//   node p2p_probe.mjs <room> offer <secs> <toMemberId>
//
// 两个模式都先 join 房间 + hello，但不发 voice join（即「在房间里、不在语音里」）。
// listen 打印收到的每一帧（含 offer），offer 发一条 offer 并打印自己收到的 voice-error。
const room = process.argv[2];
const mode = process.argv[3] || 'listen';
const secs = Number(process.argv[4] || 20);
const to = process.argv[5] || '';

const BASE = 'http://127.0.0.1:8080';
const WS = 'ws://127.0.0.1:8080/ws';
const t0 = Date.now();
const log = (...a) => console.log(((Date.now() - t0) / 1000).toFixed(2).padStart(6), ...a);

const tag = mode === 'listen' ? 'LSN' : 'OFF';
const name = `${tag}_${Date.now().toString(36).slice(-5)}`;

const r = await fetch(`${BASE}/api/rooms/${room}/join`, {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ name }),
});
const j = await r.json();
const token = j?.member?.token || j?.data?.member?.token || '';
const memberId = j?.member?.id || j?.data?.member?.id || '';
log('join ok', memberId);
if (!token) { log('no token, abort'); process.exit(1); }

const ws = new WebSocket(`${WS}?room=${room}&token=&member_token=${token}`);
ws.onopen = () => {
  log('WS OPEN');
  ws.send(JSON.stringify({ type: 'hello', room, memberId, member_token: token, name, resumeFrom: 0 }));
  setTimeout(() => {
    if (mode === 'offer') {
      log(`>>> offer to=${to}`);
      ws.send(JSON.stringify({ type: 'offer', to, sdp: 'x' }));
    }
  }, 1200);
};
ws.onmessage = (ev) => {
  let m; try { m = JSON.parse(ev.data); } catch (e) { return; }
  const t = String(m.type || '');
  if (t === 'progress' || t === 'state') return;
  log(`<<< ${t} ${JSON.stringify(m).slice(0, 240)}`);
};
ws.onclose = (e) => log('WS CLOSE', e.code);
setTimeout(() => { try { ws.close(); } catch (e) {} process.exit(0); }, secs * 1000);
