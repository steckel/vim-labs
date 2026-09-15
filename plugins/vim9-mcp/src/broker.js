import net from 'node:net';
import fs from 'node:fs';
import { randomUUID } from 'node:crypto';
import { frames, send, socketPath, runtimeDir, connect } from './transport.js';
import { validate } from './schema.js';

export async function startBroker({ requestTimeout = 15000 } = {}) {
  fs.mkdirSync(runtimeDir(), { recursive: true, mode: 0o700 });
  const st = fs.lstatSync(runtimeDir());
  if (!st.isDirectory() || st.uid !== process.getuid() || (st.mode & 0o077)) throw new Error('Unsafe runtime directory');
  // An exclusive lock prevents two starters from unlinking each other's socket.
  const lock = `${socketPath()}.lock`;
  let lockFd;
  try { lockFd = fs.openSync(lock, 'wx', 0o600); }
  catch {
    try {
      const pid = Number(fs.readFileSync(lock, 'utf8'));
      if (Number.isSafeInteger(pid) && pid > 0) { process.kill(pid, 0); return; }
      return; // Another starter may not have written its PID yet.
    } catch (e) {
      if (e.code !== 'ESRCH' && e.code !== 'ENOENT') return;
      fs.rmSync(lock, { force: true });
      return startBroker({ requestTimeout });
    }
  }
  fs.writeFileSync(lockFd, String(process.pid)); fs.closeSync(lockFd);
  try { (await connect()).end(); fs.rmSync(lock, { force: true }); return; } catch {}
  fs.rmSync(socketPath(), { force: true });
  const sessions = new Map();
  const records = new Map();
  const clients = new Set();
  const respond = (socket, id, data) => send(socket, { type: 'result', id, result: { ...data, request_id: id } });
  const finish = (record, data) => {
    clearTimeout(record.timer);
    record.result = { ...data, request_id: record.id };
    record.state = data.code === 'cancelled' ? 'cancelled' : 'completed';
    for (const waiter of record.waiters) respond(waiter, record.id, record.result);
    record.waiters.clear();
  };
  const server = net.createServer(socket => {
    clients.add(socket);
    let role = null, sessionId = null;
    const handshake = setTimeout(() => socket.destroy(), 5000);
    socket.on('error', () => {});
    frames(socket, message => {
      if (!role) {
        if (message.type !== 'hello' || message.protocol !== 1 || !['vim', 'client'].includes(message.role)) { socket.destroy(); return; }
        role = message.role; clearTimeout(handshake);
        if (role === 'vim') {
          sessionId = randomUUID();
          sessions.set(sessionId, { socket, id: sessionId, pid: message.pid, cwd: message.cwd, version: message.version, capabilities: message.capabilities || [] });
          send(socket, { type: 'welcome', session: sessionId, protocol: 1 });
        }
        return;
      }
      if (role === 'vim') {
        if (message.type === 'response') {
          const record = records.get(message.id);
          if (record && record.session === sessionId && record.state !== 'completed') finish(record, message.result);
        }
        return;
      }
      if (message.type !== 'request' || typeof message.id !== 'string' || message.id.length > 128) { socket.destroy(); return; }
      const { id, method, args = {} } = message;
      try {
        validate(method, args);
        if (method === 'list_sessions') {
          respond(socket, id, { ok: true, sessions: [...sessions.values()].map(({ socket: _, ...s }) => s) }); return;
        }
        if (method === 'request_status' || method === 'cancel_request') {
          const record = records.get(args.request_id);
          if (!record) { respond(socket, id, { ok: false, code: 'unknown_request' }); return; }
          if (method === 'cancel_request' && record.state === 'dispatched') {
            const session = sessions.get(record.session);
            if (session) send(session.socket, { type: 'cancel', id: record.id });
          }
          respond(socket, id, { ok: true, state: record.state, result: record.result || null, cancellation: method === 'cancel_request' ? 'requested_if_queued' : undefined }); return;
        }
        const session = sessions.get(args.session);
        if (!session) { respond(socket, id, { ok: false, code: 'session_not_found' }); return; }
        const fingerprint = JSON.stringify({ method, args });
        const existing = records.get(id);
        if (existing) {
          if (existing.fingerprint !== fingerprint) respond(socket, id, { ok: false, code: 'request_id_conflict' });
          else if (existing.result) respond(socket, id, existing.result);
          else existing.waiters.add(socket);
          return;
        }
        if (records.size >= 2000) {
          for (const [key, record] of records) { if (record.state !== 'dispatched') records.delete(key); if (records.size < 1500) break; }
          if (records.size >= 2000) { respond(socket, id, { ok: false, code: 'broker_busy' }); return; }
        }
        const definition = validate(method, args);
        const record = { id, session: args.session, fingerprint, state: 'dispatched', waiters: new Set([socket]), result: null };
        records.set(id, record);
        record.timer = setTimeout(() => {
          for (const waiter of record.waiters) respond(waiter, id, { ok: false, code: 'timeout', outcome: 'unknown' });
          record.waiters.clear();
          // Keep the record and accept a late response. Never resend.
        }, requestTimeout);
        send(session.socket, { type: 'request', id, method, args, mutation: definition.mutation });
      } catch (error) { respond(socket, message.id, { ok: false, code: 'invalid_arguments', message: error.message }); }
    });
    socket.on('close', () => {
      clearTimeout(handshake); clients.delete(socket);
      for (const record of records.values()) record.waiters.delete(socket);
      if (sessionId) {
        sessions.delete(sessionId);
        for (const record of records.values()) if (record.session === sessionId && record.state === 'dispatched') finish(record, { ok: false, code: 'editor_disconnected', outcome: 'unknown' });
      }
    });
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(socketPath(), resolve); });
  fs.chmodSync(socketPath(), 0o600);
  const close = () => {
    for (const record of records.values()) clearTimeout(record.timer);
    for (const socket of clients) socket.destroy();
    server.close();
    fs.rmSync(socketPath(), { force: true }); fs.rmSync(lock, { force: true });
  };
  process.once('SIGTERM', () => { close(); process.exit(0); });
  process.once('SIGINT', () => { close(); process.exit(0); });
  return { server, close };
}
