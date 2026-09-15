import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { RpcClient } from '../src/transport.js';
import { Service } from '../src/service.js';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

const root = fileURLToPath(new URL('..', import.meta.url));
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const q = value => `'${value.replaceAll("'", "''")}'`;
const pos = (line, byte) => ({ line, byte });

test('real Vim + broker + MCP composition', { timeout: 60000 }, async t => {
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'vim9-mcp-test-'));
  const runtime = path.join(temp, 'runtime');
  process.env.VIM9_MCP_RUNTIME = runtime;
  const project = path.join(temp, 'project');
  await fs.mkdir(project);
  await fs.writeFile(path.join(project, 'main.txt'), 'alpha beta\nsecond line\nthird\n');
  await fs.writeFile(path.join(project, 'other.txt'), 'disk needle\n');
  const stop = path.join(temp, 'stop');
  const script = path.join(temp, 'fixture.vim');
  await fs.writeFile(script, `vim9script
g:vim9_mcp_autoconnect = false
execute 'set runtimepath^=' .. fnameescape(${q(root)})
execute 'cd ' .. fnameescape(${q(project)})
edit main.txt
runtime plugin/vim9mcp.vim
import ${q(path.join(root, 'autoload/vim9mcp/editor.vim'))} as E
import ${q(path.join(root, 'autoload/vim9mcp/model.vim'))} as M
import ${q(path.join(root, 'autoload/vim9mcp/connection.vim'))} as Connection
def TestAction(input: dict<any>): dict<any>
  if get(input, 'command', '') != ''
    execute input.command
  endif
  return {ok: true, context: M.Context({}), errors: v:errors, registers: {search: getreg('/'), unnamed: getreg('"')}}
enddef
E.Register('test_action', {type: 'object', properties: {command: {type: 'string'}}, additionalProperties: false}, TestAction)
g:vim9_mcp_jobs = {check: {argv: [${q(process.execPath)}, '-e', "console.log('main.txt:1:1:problem')"], errorformat: '%f:%l:%c:%m'}}
g:vim9_mcp_workflows = {read_current: [{id: 'context', tool: 'get_context', arguments: {}}, {id: 'read', tool: 'read_buffer', arguments: {buffer: {'$ref': 'context#/current/buffer'}}}]}
VimMCPConnect
while !filereadable(${q(stop)})
  sleep 20m
  writefile([json_encode(Connection.Status())], ${q(path.join(temp, 'status.json'))})
endwhile
qa!
`);
  let logs = '';
  const vim = spawn(process.env.VIM || 'vim', ['-Nu', 'NONE', '-n', '-i', 'NONE', '-es', '-V1', '-S', script], { env: process.env });
  vim.stderr.on('data', data => { logs += data; });
  vim.stdout.on('data', data => { logs += data; });
  const rpc = await RpcClient.open();
  const service = new Service(rpc);
  t.after(async () => {
    await fs.writeFile(stop, 'stop');
    rpc.close();
    await pause(100);
    if (vim.exitCode === null) vim.kill('SIGKILL');
    try { process.kill(Number(await fs.readFile(path.join(runtime, 'broker.sock.lock'), 'utf8')), 'SIGTERM'); } catch {}
    await fs.rm(temp, { recursive: true, force: true });
  });
  let session;
  for (let i = 0; i < 100; i++) {
    const sessions = await rpc.call('list_sessions');
    if (sessions.sessions?.length) { session = sessions.sessions[0].id; break; }
    if (vim.exitCode !== null) break;
    await pause(30);
  }
  assert.ok(session, `Vim did not connect: ${logs} ${await fs.readFile(path.join(temp, 'status.json'), 'utf8').catch(() => '')}`);
  const call = async (name, args = {}) => service.execute(name, { session, ...args });
  const action = command => call('invoke_provider', { provider: 'test_action', input: { command } });
  let context = await call('get_context');
  assert.equal(context.ok, true, JSON.stringify(context));
  const buffer = context.current.buffer;
  const read = () => call('read_buffer', { buffer });
  const all = snap => ({ buffer, revision: snap.revision, start: pos(1, 0), end: pos(snap.line_count, Buffer.byteLength(snap.lines.at(-1))) });

  await t.test('snapshot → search → preview → edit → verify → undo preserves user state', async () => {
    await action(`call setreg('/', 'user-search') | call setreg('"', 'user-register')`);
    let snapshot = await read();
    const found = await call('search', { targets: [all(snapshot)], query: 'beta' });
    assert.equal(found.findings.length, 1, JSON.stringify(found));
    const location = found.findings[0].location;
    const prepared = await call('prepare_changes', { changes: [{ buffer, revision: snapshot.revision, edits: [{ start: location.start, end: location.end, text: 'BETA', expected: 'beta' }] }] });
    assert.equal(prepared.ok, true, JSON.stringify(prepared));
    assert.match(prepared.changes[0].diff, /alpha BETA/);
    assert.equal((await read()).lines[0], 'alpha beta');
    const applied = await call('apply_changes', { change_id: prepared.change_id });
    assert.equal(applied.ok, true, JSON.stringify(applied));
    assert.equal((await read()).lines[0], 'alpha BETA');
    assert.equal(await fs.readFile(path.join(project, 'main.txt'), 'utf8'), 'alpha beta\nsecond line\nthird\n');
    const state = await action('');
    assert.equal(state.registers.search, 'user-search');
    assert.equal(state.registers.unnamed, 'user-register');
    assert.equal((await call('undo_change', { change_id: prepared.change_id, buffer })).ok, true);
    assert.equal((await read()).lines[0], 'alpha beta');
  });

  await t.test('stale application and guarded undo refuse to overwrite later typing', async () => {
    let snapshot = await read();
    let prepared = await call('transform', { targets: [all(snapshot)], operation: 'uppercase' });
    assert.equal(prepared.ok, true, JSON.stringify(prepared));
    await action("call setline(2, 'user typed')");
    assert.equal((await call('apply_changes', { change_id: prepared.change_id })).code, 'stale_revision');
    snapshot = await read();
    prepared = await call('transform', { targets: [all(snapshot)], operation: 'uppercase' });
    assert.equal((await call('apply_changes', { change_id: prepared.change_id })).ok, true);
    await action("call setline(3, 'later typing')");
    assert.equal((await call('undo_change', { change_id: prepared.change_id, buffer })).code, 'stale_revision');
    await action('undo');
    assert.equal((await read()).lines[2], 'THIRD', 'manual undo must undo user typing alone');
    await action('undo');
    assert.equal((await read()).lines[1], 'user typed', 'second undo must undo agent edit alone');
  });

  await t.test('byte coordinates support Unicode and reject split code points and overlap', async () => {
    await action("call setline(1, 'a😀é\tend')");
    let snapshot = await read();
    const found = await call('search', { targets: [all(snapshot)], query: '😀' });
    assert.deepEqual(found.findings[0].location.start, pos(1, 1));
    assert.deepEqual(found.findings[0].location.end, pos(1, 5));
    const invalid = await call('prepare_changes', { changes: [{ buffer, revision: snapshot.revision, edits: [{ start: pos(1, 2), end: pos(1, 5), text: '' }] }] });
    assert.equal(invalid.code, 'invalid_byte_boundary', JSON.stringify(invalid));
    const overlap = await call('prepare_changes', { changes: [{ buffer, revision: snapshot.revision, edits: [{ start: pos(1, 1), end: pos(1, 5), text: '' }, { start: pos(1, 1), end: pos(1, 5), text: '' }] }] });
    assert.equal(overlap.code, 'overlapping_edits');
  });

  await t.test('partial hunks, inserted/deleted lines and single undo block', async () => {
    await action("call setline(1, 'first') | call setline(2, 'second') | call setline(3, 'third')");
    const snapshot = await read();
    const prepared = await call('prepare_changes', { changes: [{ buffer, revision: snapshot.revision, edits: [{ start: pos(1, 0), end: pos(2, 0), text: 'new\nextra\n' }, { start: pos(3, 0), end: pos(3, 5), text: 'LAST' }] }] });
    assert.equal(prepared.ok, true, JSON.stringify(prepared));
    const firstHunk = prepared.changes[0].hunks[0].hunk;
    assert.equal((await call('apply_changes', { change_id: prepared.change_id, hunks: [firstHunk] })).ok, true);
    assert.deepEqual((await read()).lines, ['new', 'extra', 'second', 'third']);
    assert.equal((await call('undo_change', { change_id: prepared.change_id, buffer })).ok, true);
    assert.deepEqual((await read()).lines, ['first', 'second', 'third']);
  });

  await t.test('quickfix ownership, navigation and change invalidation', async () => {
    const snapshot = await read();
    const findings = (await call('search', { targets: [all(snapshot)], query: 'second' })).findings;
    await action("call setqflist([], ' ', {'title': 'user list', 'items': []})");
    const published = await call('publish_findings', { findings, title: 'Agent review' });
    assert.equal(published.ok, true, JSON.stringify(published));
    assert.equal(published.count, 1);
    assert.equal((await call('navigate', { location: findings[0].location })).ok, true);
    assert.equal((await call('get_context')).cursor.line, 2);
    assert.equal((await call('navigate', { back: true })).ok, true);
    assert.ok((await call('get_events', { after: 0 })).events.length > 0);
    await action('colder');
    const check = await action("call assert_equal('user list', getqflist({'title': 0}).title) | call assert_equal([], v:errors)");
    assert.equal(check.ok, true);
    assert.deepEqual(check.errors, []);
  });

  await t.test('external disk conflicts, read-only protection, explicit save', async () => {
    await fs.writeFile(path.join(project, 'main.txt'), 'external writer\n');
    let snapshot = await read();
    assert.equal((await call('save_buffer', { buffer, revision: snapshot.revision })).code, 'external_file_changed');
    await action('edit!');
    context = await call('get_context');
    const currentBuffer = context.current.buffer;
    await action("call setline(1, 'saved content')");
    snapshot = await call('read_buffer', { buffer: currentBuffer });
    const saved = await call('save_buffer', { buffer: currentBuffer, revision: snapshot.revision });
    assert.equal(saved.ok, true, JSON.stringify(saved));
    assert.equal(await fs.readFile(path.join(project, 'main.txt'), 'utf8'), 'saved content\n');
    await action('setlocal readonly');
    snapshot = await call('read_buffer', { buffer: currentBuffer });
    assert.equal((await call('save_buffer', { buffer: currentBuffer, revision: snapshot.revision })).code, 'buffer_not_writable');
    await action('setlocal noreadonly');
  });

  await t.test('live buffers override project search disk content; providers and jobs compose', async () => {
    await action("call setline(1, 'unsaved needle')");
    const result = await call('project_search', { query: 'needle' });
    assert.equal(result.ok, true, JSON.stringify(result));
    assert.ok(result.findings.some(f => f.location && f.message === 'unsaved needle'));
    assert.ok(result.findings.some(f => f.disk_location?.path === 'other.txt'));
    const started = await call('start_job', { name: 'check' });
    assert.equal(started.ok, true, JSON.stringify(started));
    let job;
    for (let i = 0; i < 30; i++) { job = await call('get_job', { job_id: started.job_id }); if (job.status === 'completed') break; await pause(20); }
    assert.equal(job.exit_code, 0, JSON.stringify(job));
    assert.ok(job.findings.length > 0);
    await assert.rejects(call('invoke_provider', { provider: 'test_action', input: { bad: true } }), /invalid_provider_input/);
    assert.equal((await call('execute_ex', { command: 'echo 1' })).code, 'advanced_disabled');
    const help = await call('help', { topic: 'undo' });
    assert.equal(help.ok, true, JSON.stringify(help));
  });

  await t.test('duplicate request IDs never replay mutations', async () => {
    const id = randomUUID();
    const args = { session, provider: 'test_action', input: { command: "call setline(1, getline(1) .. 'X')" } };
    const first = await rpc.call('invoke_provider', args, id);
    const second = await rpc.call('invoke_provider', args, id);
    assert.deepEqual(first, second);
    assert.equal((await call('get_context')).context.lines[0], 'unsaved needleX');
    const status = await rpc.call('request_status', { request_id: id });
    assert.equal(status.state, 'completed');
    assert.equal((await rpc.call('invoke_provider', { ...args, input: { command: 'echo 2' } }, id)).code, 'request_id_conflict');
  });

  await t.test('official MCP client discovers tools/resources and composes workflow references', async () => {
    const transport = new StdioClientTransport({ command: process.execPath, args: [path.join(root, 'bin/vim9-mcp.js')], env: { ...process.env, VIM9_MCP_RUNTIME: runtime }, stderr: 'pipe' });
    const client = new Client({ name: 'test', version: '1.0.0' });
    await client.connect(transport);
    try {
      const list = await client.listTools();
      assert.ok(list.tools.some(t => t.name === 'prepare_changes'));
      const resources = await client.listResources();
      assert.ok(resources.resources.some(r => r.uri.includes(session)));
      const result = await client.callTool({ name: 'run_workflow', arguments: { steps: [{ id: 'context', tool: 'get_context', arguments: { session } }, { id: 'read', tool: 'read_buffer', arguments: { session, buffer: { $ref: 'context#/current/buffer' } } }] } });
      assert.equal(result.isError, false, JSON.stringify(result));
      assert.equal(result.structuredContent.steps.read.lines[0], 'unsaved needleX');
    } finally { await client.close(); }
  });

  await t.test('hidden/unnamed buffers, read limits, lifecycle invalidation and native diff review', async () => {
    const original = (await call('get_context')).current.buffer;
    const opened = await call('open_buffer', { unnamed: true });
    assert.equal(opened.ok, true, JSON.stringify(opened));
    const b = opened.buffer;
    let snapshot = await call('read_buffer', { buffer: b });
    const prepared = await call('prepare_changes', { changes: [{ buffer: b, revision: snapshot.revision, edits: [{ start: pos(1, 0), end: pos(1, 0), text: 'one\ntwo\nthree' }] }] });
    assert.equal(prepared.ok, true);
    assert.equal((await call('review_changes', { change_id: prepared.change_id })).ok, true);
    const reviewBuffer = (await call('get_context')).current.buffer;
    assert.equal((await call('apply_changes', { change_id: prepared.change_id })).ok, true);
    assert.equal((await call('get_context')).current.buffer, reviewBuffer, 'background apply must preserve wipe-on-hide diff scratch buffer');
    assert.deepEqual((await call('read_buffer', { buffer: b, start_line: 2, limit: 1 })).lines, ['two']);
    assert.equal((await call('read_buffer', { buffer: b, start_line: 2, limit: 1 })).next_line, 3);
    assert.equal((await call('undo_change', { change_id: prepared.change_id, buffer: b })).ok, true);
    assert.deepEqual((await call('read_buffer', { buffer: b })).lines, ['']);
    await action('tabclose');
    assert.equal((await call('get_context')).current.buffer, original);
    await action(`call setbufvar(${b.match(/^b(\d+)-/)[1]}, '&modified', 0)`);
    assert.equal((await call('workspace', { action: 'unload', buffer: b })).ok, true);
    assert.equal((await call('read_buffer', { buffer: b })).code, 'buffer_not_found');
    assert.equal((await call('open_buffer', { path: '../escape.txt' })).code, 'invalid_project_path');
    const listing = await call('discover_files', { limit: 1 });
    assert.equal(listing.files.length, 1);
    assert.ok(listing.next_offset > 0);
  });

  await t.test('regex/literal transformations and whole-buffer deletion share guarded changes', async () => {
    const current = (await call('get_context')).current.buffer;
    const snapshot = await call('read_buffer', { buffer: current });
    const target = { buffer: current, revision: snapshot.revision, start: pos(1, 0), end: pos(1, Buffer.byteLength(snapshot.lines[0])) };
    const changed = await call('transform', { targets: [target], operation: 'substitute', query: 'needle', replacement: '&literal' });
    assert.equal(changed.ok, true, JSON.stringify(changed));
    await call('apply_changes', { change_id: changed.change_id });
    assert.match((await call('read_buffer', { buffer: current })).lines[0], /&literal/);
    await call('undo_change', { change_id: changed.change_id, buffer: current });
    const fresh = await call('read_buffer', { buffer: current });
    target.revision = fresh.revision;
    const emptyMatch = await call('search', { targets: [target], query: '^', regex: true });
    assert.equal(emptyMatch.findings.length, 1);
    const expression = await call('transform', { targets: [target], operation: 'substitute', query: '.', replacement: '\\=system("bad")', regex: true });
    assert.equal(expression.code, 'expression_replacement_disabled');
    const deleted = await call('prepare_changes', { changes: [{ buffer: current, revision: fresh.revision, edits: [{ start: pos(1, 0), end: pos(fresh.line_count + 1, 0), text: '' }] }] });
    assert.equal((await call('apply_changes', { change_id: deleted.change_id })).ok, true);
    assert.deepEqual((await call('read_buffer', { buffer: current })).lines, ['']);
    assert.equal((await call('undo_change', { change_id: deleted.change_id, buffer: current })).ok, true);
  });

  await t.test('named recipes, editor inspection, macro storage and advanced output', async () => {
    const workflow = await service.execute('run_workflow', { session, name: 'read_current' });
    assert.equal(workflow.ok, true, JSON.stringify(workflow));
    assert.ok(workflow.steps.read.lines.length);
    const stopped = await service.execute('run_workflow', { session, steps: [{ id: 'context', tool: 'get_context', arguments: {} }, { id: 'bad', tool: 'read_buffer', arguments: { buffer: { $ref: 'context#/missing' } } }] });
    assert.equal(stopped.code, 'workflow_stopped');
    assert.equal(stopped.steps.context.ok, true);
    for (const kind of ['marks', 'jumps', 'folds', 'mappings', 'commands', 'registers', 'options']) {
      const result = await call('inspect_editor', { kind });
      assert.equal(result.ok, true, `${kind}: ${JSON.stringify(result)}`);
    }
    assert.equal((await call('record_macro', { register: 'q', keys: '0w' })).executed, false);
    assert.equal((await call('inspect_editor', { kind: 'registers', query: 'q' })).registers.q.text, '0w');
    const enabling = await action('g:vim9_mcp_advanced = v:true');
    assert.equal(enabling.ok, true, JSON.stringify(enabling));
    const output = await call('execute_ex', { command: 'echo "actual output"' });
    assert.equal(output.ok, true, JSON.stringify(output));
    assert.match(output.output, /actual output/);
    const bad = await call('execute_ex', { command: 'ThisCommandDoesNotExist' });
    assert.equal(bad.ok, false);
    assert.match(bad.message, /E492/);
    assert.equal((await call('execute_macro', { register: 'q' })).ok, true);
    await action('g:vim9_mcp_advanced = v:false');
    const check = await action('');
    assert.deepEqual(check.errors, []);
  });

  await t.test('job findings retain launch revisions and event gaps require resynchronization', async () => {
    const started = await call('start_job', { name: 'check' });
    await action("call setline(1, 'typed after the job started')");
    let job;
    for (let i = 0; i < 30; i++) {
      job = await call('get_job', { job_id: started.job_id });
      if (job.status === 'completed') break;
      await pause(20);
    }
    assert.equal(job.findings[0].stale, true, JSON.stringify(job));
    const now = await call('get_context');
    assert.notEqual(job.findings[0].location.revision, now.current.revision);
    assert.equal((await call('publish_findings', { title: 'Stale build', findings: job.findings.map(({ location, message, source, severity }) => ({ location, message, source, severity })) })).code, 'stale_revision');
    await action("for i in range(300) | doautocmd BufEnter | endfor");
    const events = await call('get_events', { after: 0 });
    assert.equal(events.gap, true);
    assert.equal(events.events.length, 256);
  });

  await t.test('large live reads remain bounded and no-op changes do not create undo steps', async () => {
    const opened = await call('open_buffer', { unnamed: true });
    const bulk = await call('prepare_changes', { changes: [{ buffer: opened.buffer, revision: opened.revision, edits: [{ start: pos(1, 0), end: pos(1, 0), text: Array(3000).fill('long enough line').join('\n') }] }] });
    const filled = await call('apply_changes', { change_id: bulk.change_id });
    assert.equal(filled.ok, true, JSON.stringify(filled));
    const page = await call('read_buffer', { buffer: opened.buffer, limit: 1000 });
    assert.equal(page.lines.length, 1000, JSON.stringify({ page, opened, filled }));
    assert.equal(page.next_line, 1001);
    assert.equal(page.line_count, 3000);
    const prepared = await call('prepare_changes', { changes: [{ buffer: opened.buffer, revision: page.revision, edits: [{ start: pos(1, 0), end: pos(1, 16), text: 'long enough line' }] }] });
    assert.equal(prepared.ok, true, JSON.stringify(prepared));
    const applied = await call('apply_changes', { change_id: prepared.change_id });
    assert.equal(applied.results[0].changed, false);
    assert.equal((await call('undo_change', { change_id: prepared.change_id, buffer: opened.buffer })).code, 'not_undoable');
  });
  assert.doesNotMatch(logs, /Error detected/, logs);
});
