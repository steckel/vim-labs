import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { RpcClient } from '../src/transport.js';
const root = fileURLToPath(new URL('..', import.meta.url));
const pause = ms => new Promise(r => setTimeout(r, ms));
const q = s => `'${s.replaceAll("'", "''")}'`;

test('interactive Vim defers mutations during typing and captures selections', { timeout: 30000 }, async t => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'mcp9-interactive-'));
  process.env.VIM9_MCP_RUNTIME = path.join(dir, 'runtime');
  const script = path.join(dir, 'init.vim');
  await fs.writeFile(script, `vim9script
g:vim9_mcp_autoconnect = false
execute 'set rtp^=' .. fnameescape(${q(root)})
runtime plugin/vim9mcp.vim
set noswapfile shortmess+=I
setline(1, ['alpha beta', 'second row', 'third row'])
set nomodified
xnoremap S <Plug>(VimMCPShareSelection)
VimMCPConnect
`);
  const vim = spawn('python3', [path.join(root, 'test/terminal_runner.py'), process.env.VIM || 'vim', '-Nu', 'NONE', '-n', '-i', 'NONE', '-S', script], { env: { ...process.env, TERM: 'xterm' } });
  let logs = '';
  vim.stdout.on('data', d => { logs = (logs + d).slice(-8000); });
  vim.stderr.on('data', d => { logs += d; });
  const rpc = await RpcClient.open();
  t.after(async () => {
    vim.stdin.write('\x1b:qa!\r');
    await pause(150);
    vim.kill('SIGTERM'); rpc.close();
    try { process.kill(Number(await fs.readFile(path.join(dir, 'runtime/broker.sock.lock'), 'utf8')), 'SIGTERM'); } catch {}
    await fs.rm(dir, { recursive: true, force: true });
  });
  let session;
  for (let i = 0; i < 100; i++) {
    const result = await rpc.call('list_sessions');
    if (result.sessions.length) { session = result.sessions[0].id; break; }
    await pause(30);
  }
  assert.ok(session, logs);
  const call = (method, args = {}) => rpc.call(method, { session, ...args });
  const context = await call('get_context');
  const buffer = context.current.buffer;
  // Capture via actual user keystrokes, not synthetic marks.
  vim.stdin.write('gg0v4lS');
  await pause(120);
  let selection = (await call('get_context')).selection;
  assert.equal(selection.shape, 'character', JSON.stringify(selection));
  assert.deepEqual(selection.text, ['alpha']);
  vim.stdin.write('ggVjS');
  await pause(100);
  selection = (await call('get_context')).selection;
  assert.equal(selection.shape, 'line');
  assert.deepEqual(selection.text, ['alpha beta', 'second row']);
  vim.stdin.write('gg0\x16j2lS');
  await pause(100);
  selection = (await call('get_context')).selection;
  assert.equal(selection.shape, 'block');
  assert.equal(selection.targets.length, 2, JSON.stringify(selection));
  assert.deepEqual(selection.text, ['alp', 'sec']);
  let snapshot = await call('read_buffer', { buffer });
  const prepared = await call('prepare_changes', { changes: [{ buffer, revision: snapshot.revision, edits: [{ start: { line: 3, byte: 0 }, end: { line: 3, byte: 5 }, text: 'THIRD' }] }] });
  assert.equal(prepared.ok, true, JSON.stringify(prepared));
  vim.stdin.write('gg0iUSER ');
  await pause(100);
  assert.match((await call('get_context')).mode, /^i/, logs);
  const id = randomUUID();
  let completed = false;
  const pending = rpc.call('apply_changes', { session, change_id: prepared.change_id }, id).then(r => { completed = true; return r; });
  await pause(150);
  assert.equal(completed, false, 'must not mutate while user is inserting');
  assert.equal((await call('read_buffer', { buffer })).lines[0], 'USER alpha beta', 'read-only inspection must remain available behind a deferred edit');
  vim.stdin.write('\x1b');
  const refused = await pending;
  assert.equal(refused.code, 'stale_revision', JSON.stringify(refused));
  snapshot = await call('read_buffer', { buffer });
  assert.equal(snapshot.lines[0], 'USER alpha beta');
  // A queued edit can be cancelled without applying when normal mode returns.
  const next = await call('prepare_changes', { changes: [{ buffer, revision: snapshot.revision, edits: [{ start: { line: 3, byte: 0 }, end: { line: 3, byte: 5 }, text: 'THIRD' }] }] });
  vim.stdin.write('i');
  await pause(80);
  const cancelId = randomUUID();
  const cancelled = rpc.call('apply_changes', { session, change_id: next.change_id }, cancelId);
  await pause(80);
  await rpc.call('cancel_request', { request_id: cancelId });
  assert.equal((await cancelled).code, 'cancelled');
  vim.stdin.write('\x1b');
  assert.equal((await call('read_buffer', { buffer })).lines[2], 'third row');
  // A block that cuts through a tab is display text, not a whole-tab edit.
  vim.stdin.write(':call setline(1, ["abcd", "\\tZ"])\rgg0l\x16jS');
  await pause(150);
  selection = (await call('get_context')).selection;
  assert.equal(selection.shape, 'block');
  assert.equal(selection.editable, false, JSON.stringify(selection));
  assert.deepEqual(selection.targets, []);
  const second = spawn('python3', [path.join(root, 'test/terminal_runner.py'), process.env.VIM || 'vim', '-Nu', 'NONE', '-n', '-i', 'NONE', '-S', script], { env: { ...process.env, TERM: 'xterm' } });
  second.stdout.on('data', () => {}); second.stderr.on('data', () => {});
  t.after(async () => { second.stdin.write('\x1b:qa!\r'); await pause(100); second.kill('SIGTERM'); });
  let secondSession;
  for (let i = 0; i < 100; i++) {
    const sessions = await rpc.call('list_sessions');
    secondSession = sessions.sessions.find(s => s.id !== session)?.id;
    if (secondSession) break;
    await pause(30);
  }
  assert.ok(secondSession, 'two Vim processes must coexist');
  assert.equal((await rpc.call('get_context', { session: secondSession })).context.lines[0], 'alpha beta');
  vim.stdin.write(':VimMCPDisconnect\r');
  await pause(150);
  assert.equal((await call('get_context')).code, 'session_not_found');
  assert.equal((await rpc.call('list_sessions')).sessions.length, 1);
  vim.stdin.write(':VimMCPConnect\r');
  let reconnected;
  for (let i = 0; i < 100; i++) {
    const sessions = await rpc.call('list_sessions');
    reconnected = sessions.sessions.find(s => s.id !== secondSession)?.id;
    if (reconnected) break;
    await pause(30);
  }
  assert.ok(reconnected);
  assert.notEqual(reconnected, session, 'reconnect must invalidate old session targeting');
});
