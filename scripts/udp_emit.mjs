// D25 接收端验收用：从 PC 每 2 秒给手机单播一个六字段包
// 用法：node scripts/udp_emit.mjs --to=192.168.1.8 --code=777777 --name=测试房 --host=小明 --secs=12
//      加 --bad 就发 3 个非法包（验证 App 只打 drop、不崩）
import dgram from 'node:dgram';

const PORT = 45231;
const argv = process.argv.slice(2);
const arg = (name, def) => {
  const hit = argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : def;
};

const to = arg('to', '');
const code = arg('code', '777777');
const name = arg('name', '测试房');
const host = arg('host', '小明');
const secs = Number(arg('secs', '12')) || 12;
const bad = argv.includes('--bad');

if (!to) {
  console.log('[emit] need --to=<phone ip>');
  process.exit(1);
}

const sock = dgram.createSocket('udp4');
let n = 0;
const send = () => {
  n += 1;
  const body = bad
    ? n <= 3
      ? Buffer.from('{this is not json ' + n, 'utf8')
      : null
    : Buffer.from(
        JSON.stringify({
          v: 1,
          code,
          name,
          host,
          port: 8080,
          ts: Date.now(),
        }),
        'utf8',
      );
  if (!body) return;
  sock.send(body, PORT, to, (e) => {
    if (e) console.log(`[emit] fail ${e.message}`);
    else console.log(`[emit] -> ${to}:${PORT} bytes=${body.length} ${bad ? 'bad' : code}`);
  });
  if (bad && n >= 3) {
    sock.close();
    process.exit(0);
  }
};

send();
const timer = setInterval(send, 2000);
setTimeout(() => {
  clearInterval(timer);
  try {
    sock.close();
  } catch {
    /* ignore */
  }
  console.log('[emit] done');
  process.exit(0);
}, secs * 1000);
