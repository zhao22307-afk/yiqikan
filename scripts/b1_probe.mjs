// b1_probe.mjs —— 验「缺参 claim 被拒，且不改房间状态」
// 用法: node b1_probe.mjs <code> <hostMemberToken>
// 依赖: Node 18+（内置 fetch 与 WebSocket，Node 22+ 才有全局 WebSocket）

const BASE = 'http://127.0.0.1:8080';
const [, , code, hostToken] = process.argv;
if (!code || !hostToken) {
  console.error('usage: node b1_probe.mjs <code> <hostMemberToken>');
  process.exit(2);
}

const t0 = Date.now();
const ts = () => ((Date.now() - t0) / 1000).toFixed(2).padStart(6);
const log = (...a) => console.log(ts(), ...a);

// ---------- 1. 拿一个 guest token ----------
const joinRes = await fetch(`${BASE}/api/rooms/${code}/join`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ name: 'b1guest', nickname: 'b1guest' }),
});
const joinJson = await joinRes.json();
log('join status', joinRes.status, JSON.stringify(joinJson).slice(0, 240));
const guestToken =
  (joinJson.member && joinJson.member.token) ||
  (joinJson.data && joinJson.data.member && joinJson.data.member.token);
if (!guestToken) {
  console.error('!! 没拿到 guest token，检查 /join 的响应体');
  process.exit(1);
}
log('guestToken', guestToken);

// ---------- 2. 基线快照：读一次 room 的 playback ----------
async function snapshot(tag) {
  const r = await fetch(`${BASE}/api/rooms/${code}`);
  const j = await r.json();
  const pb =
    (j.room && j.room.playback) ||
    (j.data && j.data.room && j.data.room.playback) ||
    null;
  log(`${tag} playback =`, pb ? JSON.stringify(pb) : 'null');
  return pb;
}
const before = await snapshot('BASELINE');

// ---------- 3. 双连接 ----------
function connect(token, label) {
  return new Promise((resolve, reject) => {
    const url = `ws://127.0.0.1:8080/ws?room=${encodeURIComponent(code)}&token=&member_token=${encodeURIComponent(token)}`;
    const ws = new WebSocket(url);
    ws.inbox = [];
    ws.onmessage = (ev) => {
      let f;
      try { f = JSON.parse(ev.data); } catch { return; }
      ws.inbox.push(f);
      const t = f.type;
      if (t === 'claim') {
        log(`[${label}] <<< claim rid=${f.rid} from=${f.from} action=${f.action} hasPos=${f.position !== undefined} hasRate=${f.rate !== undefined}`);
        log(`[${label}] >>> control{rid:${f.rid}, approve:true}`);
        ws.send(JSON.stringify({ type: 'control', rid: f.rid, approve: true }));
      } else if (t === 'error') {
        log(`[${label}] <<< ERROR code=${f.code} msg=${f.message || f.msg || f.reason} rid=${f.rid || ''}`);
      } else if (t === 'state') {
        const s = f.state || {};
        log(`[${label}] <<< state seq=${f.seq} pos=${s.position} rate=${s.rate} playing=${s.playing}`);
      } else if (t === 'hello') {
        const ms = (f.room && f.room.members) || [];
        log(`[${label}] <<< hello members=${ms.length}`);
      } else if (t === 'connected') {
        log(`[${label}] <<< connected memberId=${f.memberId}`);
      } else {
        log(`[${label}] <<< ${t}`);
      }
    };
    ws.onopen = () => { log(`[${label}] ws open`); ws.send(JSON.stringify({ type: 'hello', lastSeq: -1 })); resolve(ws); };
    ws.onerror = (e) => reject(new Error(`${label} ws error ${e.message || e}`));
  });
}

const host = await connect(hostToken, 'HOST');
const guest = await connect(guestToken, 'GUEST');
await new Promise((r) => setTimeout(r, 800));

// ---------- 4. 发两条缺参 claim ----------
log('--- CASE 1: seek 缺 position ---');
guest.send(JSON.stringify({ type: 'claim', action: 'seek', rate: 1.0 }));
await new Promise((r) => setTimeout(r, 2500));

log('--- CASE 2: rate 缺 rate ---');
guest.send(JSON.stringify({ type: 'claim', action: 'rate', position: 999 }));
await new Promise((r) => setTimeout(r, 2500));

// ---------- 5. 再读快照，比对 ----------
const after = await snapshot('AFTER');
log('--- 判定 ---');
const same = JSON.stringify(before) === JSON.stringify(after);
log('playback 未变 =', same);
if (!same) {
  log('before:', JSON.stringify(before));
  log('after :', JSON.stringify(after));
}

const errors = guest.inbox.filter((f) => f.type === 'error');
log('guest 收到的 error 帧数 =', errors.length);
errors.forEach((f) => log('  error:', JSON.stringify(f)));

const states = guest.inbox.filter((f) => f.type === 'state');
log('guest 收到的 state 帧数 =', states.length, states.length === 0 ? '(期望 0：被拒的 claim 不该广播 state)' : '(期望 0，实际有 → 拒了还广播了)');

log(errors.length >= 2 && same ? 'RESULT: PASS' : 'RESULT: FAIL');
host.close(); guest.close();
process.exit(0);
