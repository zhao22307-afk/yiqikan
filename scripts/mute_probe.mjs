// mute_probe.mjs —— 进房后等自己被移交成房主，然后禁言 TARGET，打印服务端回应。
// 用法: node mute_probe.mjs <code> <targetMemberId> [seconds=70]
// 依赖: Node 22+（全局 WebSocket / fetch）；设备端需 `adb forward tcp:8080 tcp:8080`。
const BASE = 'http://127.0.0.1:8080';
const [, , code, target, secsArg] = process.argv;
if (!code || !target) {
  console.error('usage: node mute_probe.mjs <code> <targetMemberId> [seconds]');
  process.exit(2);
}
const secs = Number(secsArg || 70);
// 变体：MUTE_OFF_AFTER=<秒> 时，禁言后等这么多秒再解禁（验收「解除禁言后能正常发」）。
const offAfter = Number(process.env.MUTE_OFF_AFTER || 0);
const t0 = Date.now();
const ts = () => ((Date.now() - t0) / 1000).toFixed(2).padStart(6);
const log = (...a) => console.log(ts(), ...a);

const joinRes = await fetch(`${BASE}/api/rooms/${code}/join`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ name: 'muter', nickname: 'muter' }),
});
const joinJson = await joinRes.json();
const token =
  (joinJson.member && joinJson.member.token) ||
  (joinJson.data && joinJson.data.member && joinJson.data.member.token);
if (!token) { console.error('!! no token'); process.exit(1); }

const ws = new WebSocket(
  `ws://127.0.0.1:8080/ws?room=${encodeURIComponent(code)}&token=&member_token=${encodeURIComponent(token)}`);

let myId = null;
let sent = false;

ws.onmessage = (ev) => {
  let f; try { f = JSON.parse(ev.data); } catch { return; }
  if (f.type === 'connected') {
    myId = f.memberId;
    log('connected as', myId, 'online=', f.online);
  } else if (f.type === 'members' || f.type === 'hello') {
    const members = f.members || (f.room && f.room.members) || [];
    const hostId = f.hostId || f.host || (f.room && f.room.hostId);
    const self = members.find((m) => m.id === myId);
    log('members host=', hostId, 'selfRole=', self && self.role);
    if (!sent && self && (self.role === 'host' || myId === hostId)) {
      sent = true;
      log('>>> setMuted target=', target, 'muted=true');
      ws.send(JSON.stringify({ type: 'setMuted', memberId: target, muted: true, rid: 'r1' }));
      if (offAfter > 0) {
        setTimeout(() => {
          log('>>> setMuted target=', target, 'muted=false');
          ws.send(JSON.stringify({ type: 'setMuted', memberId: target, muted: false, rid: 'r2' }));
        }, offAfter * 1000);
      }
    }
  } else if (f.type === 'muted') {
    log('<<< muted broadcast memberId=', f.memberId, 'muted=', f.muted);
  } else if (f.type === 'error') {
    log('<<< error code=', f.code, 'msg=', f.message || f.msg, 'rid=', f.rid || '');
  }
};
ws.onopen = () => log('WS OPEN');
ws.onerror = (e) => log('WS ERROR', e.message || e.type);
ws.onclose = () => log('WS CLOSE');

setTimeout(() => { log('SUMMARY sent=' + sent); ws.close(); process.exit(0); }, secs * 1000);
