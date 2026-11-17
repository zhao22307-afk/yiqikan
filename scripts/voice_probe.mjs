// 语音信令探针。join：进房 + voice join，只打印收到的帧。
// fake：收 offer 后先发 N 条 ice（在 answer 之前）再回 SDP；默认回**故意不合法**的 SDP，
// --echo 则把 offer SDP 改写成 answer（setup:actpass->active）用来验 flush。
// silent：进语音后对 offer/sdp 一律不回，用来造「成员表里在、但永远连不上」的对端。
// 用法：node scripts/voice_probe.mjs join|fake|silent --room <code> --name p1 [--secs 40]
const BASE = process.env.BASE || 'http://127.0.0.1:8080';
const arg = (name, dflt = '') => {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 && process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[i + 1] : dflt;
};
const log = (line) => console.log(`[${new Date().toISOString().slice(11, 23)}] ${line}`);

const mode = process.argv[2] || 'join';
const room = arg('room');
const name = arg('name', `${mode}_${Math.random().toString(36).slice(2, 7)}`);
const secs = Number(arg('secs', '40'));
const iceBefore = Number(arg('ice-before', '0'));
const echo = process.argv.includes('--echo');
const answerSdp = arg('answer');

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

ws.onopen = () => {
  log('WS OPEN');
  send({ type: 'hello', name, room });
  setTimeout(() => {
    send({ type: 'voice', action: 'join' });
    log('>>> voice join');
  }, 900);
};

ws.onmessage = (ev) => {
  let f;
  try {
    f = JSON.parse(ev.data);
  } catch {
    return;
  }
  if (f.type === 'offer' || f.type === 'sdp') {
    const sdp = String(f.sdp || '');
    log(`<<< ${f.type} to=${f.to} from=${f.from} sdpLen=${sdp.length} mAudio=${/m=audio/.test(sdp)} sendrecv=${/a=sendrecv/.test(sdp)}`);
    if (mode === 'silent') log(`>>> silent: 不回 ${f.type} from=${f.from}`);
  } else if (/^voice/.test(f.type) || f.type === 'ice') {
    log(`<<< ${f.type} ${JSON.stringify(f).slice(0, 260)}`);
  }
  if (mode === 'fake' && f.type === 'offer') {
    for (let i = 1; i <= iceBefore; i++) {
      send({ type: 'ice', to: f.from, candidate: { candidate: `candidate:${i} 1 udp 1 127.0.0.1 5000 typ host`, sdpMid: '0', sdpMLineIndex: 0 } });
      log(`>>> ice #${i} (before answer)`);
    }
    const bad = 'v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n';
    const ans = echo ? String(f.sdp || '').replace(/a=setup:actpass/g, 'a=setup:active') : (answerSdp || bad);
    send({ type: 'sdp', to: f.from, sdp: ans, type_: 'answer' });
    log(echo ? '>>> sdp answer (echo of offer)' : '>>> sdp answer (intentionally invalid)');
  }
};

ws.onclose = () => log('WS CLOSE');
ws.onerror = (e) => log(`WS ERROR ${e.message || ''}`);
setTimeout(() => process.exit(0), secs * 1000);
