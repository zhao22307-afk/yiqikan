// 点赞验收探针：以 guest 身份进房，收到「长弹幕」那条后给它点一次赞，
// 并打印收到的 danmaku-like / danmaku-likes 帧（验 4：增量广播的字段形状）。
//
// 用 Node 内置 WebSocket / fetch（Node 22+），不依赖 ws 包。
// 用法：node scripts/like_probe.mjs <roomCode> [seconds]
const BASE = 'http://127.0.0.1:8080';
const code = process.argv[2];
const lifeSec = Number(process.argv[3] || 30);
if (!code) {
  console.error('usage: node like_probe.mjs <roomCode> [seconds]');
  process.exit(2);
}

async function main() {
  const res = await fetch(`${BASE}/api/rooms/${code}/join`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ name: 'liker' }),
  });
  const j = await res.json();
  const token =
    (j.member && j.member.token) ||
    (j.data && j.data.member && j.data.member.token) ||
    j.member_token ||
    j.memberToken;
  if (!token) {
    console.error('join failed', JSON.stringify(j).slice(0, 300));
    process.exit(1);
  }
  console.log(`join ok member=${j.memberId || j.member_id || '?'}`);
  const ws = new WebSocket(
    `ws://127.0.0.1:8080/ws?room=${encodeURIComponent(code)}&token=&member_token=${encodeURIComponent(token)}`,
  );
  let liked = '';
  const seen = new Set();
  ws.addEventListener('open', () => {
    console.log('WS OPEN');
    // 服务端把「发过 hello 的连接」记为在线，relay 只发给在线成员
    ws.send(JSON.stringify({ type: 'hello', name: 'liker', nickname: 'liker' }));
  });
  ws.addEventListener('message', (ev) => {
    let f;
    try {
      f = JSON.parse(String(ev.data));
    } catch {
      return;
    }
    if (!seen.has(f.type)) {
      seen.add(f.type);
      console.log('FIRST', f.type, JSON.stringify(f).slice(0, 140));
    }
    if (f.type === 'danmaku' && !liked) {
      liked = f.id;
      console.log(`>>> like ${f.id}`);
      setTimeout(() => {
        ws.send(JSON.stringify({ type: 'danmaku-like', id: f.id }));
      }, 600);
      return;
    }
    if (f.type === 'danmaku-likes' || f.type === 'danmaku-like') {
      console.log('<<<', JSON.stringify(f));
    }
  });
  ws.addEventListener('error', (e) => console.error('WS ERR', e.message));
  setTimeout(() => {
    try { ws.close(); } catch {}
    process.exit(0);
  }, lifeSec * 1000);
}

main();
