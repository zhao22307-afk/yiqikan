// D25 验收用：监听手机广播出来的房间包（只收，不参与产品逻辑）
// 用法：node scripts/udp_listen.mjs --secs=30
import dgram from 'node:dgram';

const PORT = 45231;
const arg = process.argv.find((a) => a.startsWith('--secs='));
const secs = Number(arg ? arg.split('=')[1] : 30) || 30;

const sock = dgram.createSocket({ type: 'udp4', reuseAddr: true });

sock.on('message', (buf, rinfo) => {
  const from = `${rinfo.address}:${rinfo.port}`;
  let o = null;
  try {
    o = JSON.parse(buf.toString('utf8'));
  } catch {
    console.log(`[recv] bad json bytes=${buf.length} from=${from}`);
    return;
  }
  console.log(
    `[recv] from=${from} v=${o.v} code=${o.code} name=${o.name} host=${o.host} port=${o.port} ts=${o.ts}`,
  );
});

sock.on('error', (e) => console.log(`[recv] socket error ${e.message}`));

sock.bind(PORT, '0.0.0.0', () => {
  console.log(`[listening] udp 0.0.0.0:${PORT} for ${secs}s`);
});

setTimeout(() => {
  try {
    sock.close();
  } catch {
    /* ignore */
  }
  console.log('[done]');
  process.exit(0);
}, secs * 1000);
