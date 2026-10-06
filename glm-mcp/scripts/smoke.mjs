// 冒烟测试：不联网，只验证 MCP 握手与工具列表
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const child = spawn(process.execPath, [resolve(here, '..', 'index.js')], { stdio: ['pipe', 'pipe', 'inherit'] });

const pending = new Map();
let buffer = '';
child.stdout.setEncoding('utf8');
child.stdout.on('data', (chunk) => {
  buffer += chunk;
  let index = buffer.indexOf('\n');
  while (index >= 0) {
    const line = buffer.slice(0, index).trim();
    buffer = buffer.slice(index + 1);
    if (line) {
      const message = JSON.parse(line);
      const waiter = pending.get(message.id);
      if (waiter) {
        pending.delete(message.id);
        waiter(message);
      }
    }
    index = buffer.indexOf('\n');
  }
});

let nextId = 1;
function request(method, params) {
  const id = nextId++;
  return new Promise((done, fail) => {
    pending.set(id, done);
    child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`);
    setTimeout(() => fail(new Error(`timeout waiting for ${method}`)), 10000);
  });
}

const fail = (message) => {
  console.error(`FAIL: ${message}`);
  child.kill();
  process.exit(1);
};

const init = await request('initialize', {
  protocolVersion: '2025-06-18',
  capabilities: {},
  clientInfo: { name: 'smoke', version: '1.0.0' },
});
if (!init.result?.serverInfo?.name) fail('initialize 无 serverInfo');
child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' })}\n`);

const listed = await request('tools/list', {});
const names = (listed.result?.tools || []).map((tool) => tool.name);
if (!names.includes('glm_chat') || !names.includes('glm_vision')) fail(`工具列表异常: ${names.join(',')}`);

const call = await request('tools/call', { name: 'nope', arguments: {} });
if (call.result?.isError !== true) fail('未知工具应返回 isError');

console.log(`PASS: serverInfo=${init.result.serverInfo.name}@${init.result.serverInfo.version} tools=${names.join(',')}`);
child.kill();
process.exit(0);
