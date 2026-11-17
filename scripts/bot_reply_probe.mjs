// D27 房间 Bot 验收探针（≤60 行）
// 建房拿房主身份（--create）或用客人身份加入（--room=CODE）
// node scripts/bot_probe.mjs --create --alias=小看
// node scripts/bot_probe.mjs --room=123456 --disable
const BASE = 'http://127.0.0.1:8080';
const argv = process.argv.slice(2);
const arg = (n, d) => {
  const hit = argv.find((a) => a.startsWith(`--${n}=`));
  return hit ? hit.slice(n.length + 3) : d;
};
const has = (n) => argv.includes(`--${n}`);
const alias = arg('alias', '小看');
const t0 = Date.now();
const log = (...a) => console.log(`[${((Date.now() - t0) / 1000).toFixed(2)}]`, ...a);

const post = async (path, body) => {
  const r = await fetch(BASE + path, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body || {}),
  });
  return r.json();
};

const main = async () => {
  let code = arg('room', '');
  let tok = arg('token', '');
  if (tok) {
    log('use given token room=' + code);
  } else if (has('create')) {
    const j = await post('/api/rooms', { title: 'bot房', video_url: '' });
    code = j.code || (j.room && j.room.code);
    tok = (j.member && j.member.token) || j.member_token;
    log('create ok room=' + code + ' host=' + ((j.member && j.member.id) || ''));
  } else {
    const j = await post(`/api/rooms/${code}/join`, { name: 'botprobe' });
    tok = (j.member && j.member.token) || j.member_token;
    log('join ok room=' + code + ' member=' + ((j.member && j.member.id) || ''));
  }
  const ws = new WebSocket(`ws://127.0.0.1:8080/ws?room=${code}&member_token=${tok}`);
  ws.onmessage = (e) => {
    let f;
    try {
      f = JSON.parse(e.data);
    } catch {
      return;
    }
    if (f.type === 'bot-state') log('<<< bot-state', JSON.stringify(f));
    if (f.type === 'chat' && f.bot === true) log('<<< BOT', JSON.stringify(f));
    if (f.type === 'error') log('<<< error', JSON.stringify(f));
    if (f.type === 'hello') log('<<< hello member=' + f.memberId);
  };
  ws.onopen = async () => {
    ws.send(JSON.stringify({ type: 'hello' }));
    await new Promise((r) => setTimeout(r, 400));
    if (has('disable')) {
      ws.send(JSON.stringify({ type: 'bot-config', enabled: false }));
    } else {
      ws.send(JSON.stringify({
        type: 'bot-config', aliases: `${alias},${alias}酱`, name: alias,
        reply: '我在，一起看', cooldownSec: 10, hourlyQuota: 3,
        occupySlot: true, enabled: true,
      }));
    }
    await new Promise((r) => setTimeout(r, 1000));
    const send = (obj) => {
      try {
        ws.send(JSON.stringify(obj));
      } catch (e) {
        log('send fail', e.message);
      }
    };
    send({ type: 'chat', text: `@${alias} 在吗` });
    await new Promise((r) => setTimeout(r, 100));
    send({ type: 'chat', text: `@${alias} 在吗` });
    send({ type: 'chat', text: `@${alias} 在吗` });
    log('sent 3 chats readyState=' + ws.readyState);
    setTimeout(() => {
      log('done');
      process.exit(0);
    }, Number(arg('secs', '6000')));
  };
};
main();
