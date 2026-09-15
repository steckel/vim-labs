import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';
import { randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const runtimeDir = () => process.env.VIM9_MCP_RUNTIME || path.join(os.tmpdir(), `vim9-mcp-${process.getuid()}`);
export const socketPath = () => path.join(runtimeDir(), 'broker.sock');
export const MAX_FRAME = 8 * 1024 * 1024;
export function frames(socket, receive) {
  socket.setEncoding('utf8');
  let pending = '';
  socket.on('data', chunk => {
    pending += chunk;
    if (Buffer.byteLength(pending) > MAX_FRAME) { socket.destroy(); return; }
    let at;
    while ((at = pending.indexOf('\n')) !== -1) {
      const line = pending.slice(0, at); pending = pending.slice(at + 1);
      try { receive(JSON.parse(line)); } catch { socket.destroy(); return; }
    }
  });
}
export function send(socket, message) { if (!socket.destroyed) socket.write(JSON.stringify(message) + '\n'); }
export function connect() {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(socketPath());
    socket.once('connect', () => { socket.removeListener('error', reject); resolve(socket); });
    socket.once('error', reject);
  });
}
export async function ensureBroker() {
  try { (await connect()).end(); return; } catch {}
  const dir = runtimeDir();
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  const stat = fs.lstatSync(dir);
  if (!stat.isDirectory() || stat.uid !== process.getuid() || (stat.mode & 0o077)) throw new Error('Runtime directory must be owned by you with mode 0700');
  const child = spawn(process.execPath, [fileURLToPath(new URL('../bin/vim9-mcp.js', import.meta.url)), 'broker'], { detached: true, stdio: 'ignore', env: process.env });
  child.unref();
  for (let i = 0; i < 100; i++) {
    await new Promise(r => setTimeout(r, 30));
    try { (await connect()).end(); return; } catch {}
  }
  throw new Error('broker_unavailable: could not start local broker');
}
export class RpcClient {
  constructor(socket) {
    this.socket = socket; this.pending = new Map();
    frames(socket, response => {
      const p = this.pending.get(response.id);
      if (p) { clearTimeout(p.timer); this.pending.delete(response.id); p.resolve(response.result); }
    });
    socket.on('error', () => {});
    socket.on('close', () => {
      for (const [id, p] of this.pending) { clearTimeout(p.timer); p.resolve({ ok: false, code: 'connection_lost', outcome: 'unknown', request_id: id }); }
      this.pending.clear();
    });
    send(socket, { type: 'hello', role: 'client', protocol: 1 });
  }
  static async open() { await ensureBroker(); return new RpcClient(await connect()); }
  call(method, args = {}, id = randomUUID()) {
    if (this.socket.destroyed) return Promise.resolve({ ok: false, code: 'broker_disconnected', outcome: 'not_dispatched', request_id: id });
    return new Promise(resolve => {
      const timer = setTimeout(() => { this.pending.delete(id); resolve({ ok: false, code: 'client_timeout', outcome: 'unknown', request_id: id }); }, 20_000);
      this.pending.set(id, { resolve, timer });
      send(this.socket, { type: 'request', id, method, args });
    });
  }
  close() { this.socket.end(); }
}
