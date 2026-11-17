// D28 探针（第 23 轮写回）：验证「成员带 bot 标记」这一条链路。
// 用法：node scripts/member_bot_probe.mjs --room=720119 --name=机器人甲
// 走 POST /api/rooms/{code}/join?name=…&bot=1（Api.java 的 join 分支只读 query，
// 传 body 里的 name/bot 是不生效的），连上后读 hello 快照，把成员表里自己那条的
// nickname 与 bot 字段打出来。
const room = (process.argv.find((a) => a.startsWith('--room=')) || '').slice(7);
const name = (process.argv.find((a) => a.startsWith('--name=')) || '--name=机器人甲').slice(7);
const base = (process.argv.find((a) => a.startsWith('--base=')) || '--base=http://127.0.0.1:8080').slice(7);
const j = await (await fetch(`${base}/api/rooms/${room}/join?name=${encodeURIComponent(name)}&bot=1`, { method: 'POST' })).json();
const tok = j?.member?.token;
if (!tok) { console.log('join fail', JSON.stringify(j)); process.exit(1); }
const ws = new WebSocket(`ws://127.0.0.1:8080/ws?room=${room}&token=&member_token=${tok}`);
ws.onopen = () => ws.send(JSON.stringify({ type: 'hello', since: 0 }));
ws.onmessage = (e) => {
  const f = JSON.parse(e.data);
  const me = f?.room?.members?.find((m) => m.id === j.member.id);
  if (me) { console.log(`nickname=${me.nickname} bot=${me.bot}`); ws.close(); }
};
setTimeout(() => process.exit(0), 6000);
