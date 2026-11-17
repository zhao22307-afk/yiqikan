// 触发 Bot 回复：以客人身份进房，发一条含别名的话。
// 用法：node scripts/bot_trigger.mjs --room=222460 --text=@波涛 在吗
const room = (process.argv.find((a) => a.startsWith('--room=')) || '').slice(7);
const text = (process.argv.find((a) => a.startsWith('--text=')) || '--text=@bot hi').slice(7);
const base = (process.argv.find((a) => a.startsWith('--base=')) || '--base=http://127.0.0.1:8080').slice(7);
const j = await (await fetch(`${base}/api/rooms/${room}/join?name=${encodeURIComponent('触发者')}`, { method: 'POST' })).json();
const tok = j?.member?.token;
if (!tok) { console.log('join fail', JSON.stringify(j)); process.exit(1); }
const ws = new WebSocket(`ws://127.0.0.1:8080/ws?room=${room}&token=&member_token=${tok}`);
ws.onopen = () => {
  ws.send(JSON.stringify({ type: 'hello', since: 0 }));
  setTimeout(() => ws.send(JSON.stringify({ type: 'chat', kind: 'text', text })), 400);
};
ws.onmessage = (e) => {
  const f = JSON.parse(e.data);
  if (f.type === 'chat') console.log(`chat from=${f.name} bot=${f.bot === true} text=${f.text}`);
  if (f.type === 'bot-state') console.log(`bot-state enabled=${f.enabled} alias=${f.aliases}`);
};
setTimeout(() => process.exit(0), 6000);
