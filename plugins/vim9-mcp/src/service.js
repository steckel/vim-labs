import fs from 'node:fs/promises';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { createTwoFilesPatch } from 'diff';
import { tools, validate, validateProvider } from './schema.js';
import { combineTargets } from './targets.js';

const excluded = new Set(['.git', '.hg', '.svn', 'node_modules', 'vendor', 'target', '.cache', 'coverage']);
async function discover(root) {
  const found = []; let examined = 0, truncated = false;
  async function walk(dir, depth = 0) {
    if (depth > 20) { truncated = true; return; }
    const entries = await fs.readdir(dir, { withFileTypes: true });
    entries.sort((a, b) => a.name.localeCompare(b.name));
    for (const entry of entries) {
      if (++examined > 20000) { truncated = true; return; }
      if (excluded.has(entry.name) || entry.isSymbolicLink()) continue;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) { try { await walk(full, depth + 1); } catch {} }
      else if (entry.isFile()) found.push(path.relative(root, full));
    }
  }
  await walk(root);
  return { files: found.sort(), truncated };
}

function preview(result) {
  if (!result.ok || !result.change_id || !result.changes?.every(c => Array.isArray(c.before) && Array.isArray(c.after))) return result;
  return { ...result, changes: result.changes.map(({ before, after, edits, ...change }) => {
    const diff = createTwoFilesPatch(change.path || change.buffer, change.path || change.buffer, before.join('\n') + '\n', after.join('\n') + '\n');
    return { ...change, hunks: edits.map(({ first, last, ...edit }) => edit), diff: diff.slice(0, 128000), diff_truncated: diff.length > 128000 };
  }) };
}

function reference(value, outputs) {
  if (Array.isArray(value)) return value.map(v => reference(v, outputs));
  if (value && typeof value === 'object') {
    if (Object.keys(value).length === 1 && typeof value.$ref === 'string') {
      const [id, pointer = ''] = value.$ref.split('#');
      if (!Object.hasOwn(outputs, id)) throw new Error(`unknown_workflow_reference: ${id}`);
      let result = outputs[id];
      if (pointer && !pointer.startsWith('/')) throw new Error('invalid_json_pointer');
      for (const token of pointer.split('/').slice(1)) {
        const key = token.replace(/~1/g, '/').replace(/~0/g, '~');
        if (!result || !Object.hasOwn(result, key)) throw new Error(`missing_workflow_reference: ${value.$ref}`);
        result = result[key];
      }
      return structuredClone(result);
    }
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, reference(v, outputs)]));
  }
  return value;
}

export class Service {
  constructor(rpc) { this.rpc = rpc; }
  async execute(name, args, { signal } = {}) {
    validate(name, args);
    const call = async (method, input) => {
      if (signal?.aborted) return { ok: false, code: 'cancelled' };
      const id = randomUUID();
      const abort = () => { void this.rpc.call('cancel_request', { request_id: id }); };
      signal?.addEventListener('abort', abort, { once: true });
      try { return await this.rpc.call(method, input, id); }
      finally { signal?.removeEventListener('abort', abort); }
    };
    if (name === 'combine_targets') return { ok: true, targets: combineTargets(args) };
    if (name === 'run_workflow') {
      if (!!args.steps === !!args.name) throw new Error('provide_steps_or_name');
      let steps = args.steps;
      if (args.name) {
        if (!args.session) throw new Error('session_required');
        const saved = await call('get_workflow', { session: args.session, name: args.name });
        if (!saved.ok) return saved;
        steps = saved.steps;
        validate('run_workflow', { steps });
      }
      const ids = new Set();
      for (const step of steps) {
        if (ids.has(step.id) || step.tool === 'run_workflow' || !tools.some(t => t.name === step.tool)) throw new Error('duplicate_recursive_or_unknown_workflow_step');
        ids.add(step.id);
      }
      const outputs = Object.create(null);
      for (const step of steps) {
        if (signal?.aborted) return { ok: false, code: 'cancelled', steps: outputs };
        let result;
        try {
          const input = reference(step.arguments, outputs);
          if (args.session && input.session === undefined && !tools.find(t => t.name === step.tool).local) input.session = args.session;
          result = await this.execute(step.tool, input, { signal });
        } catch (error) { result = { ok: false, code: 'invalid_step', message: error.message }; }
        outputs[step.id] = result;
        if (!result.ok) return { ok: false, code: 'workflow_stopped', failed_step: step.id, steps: outputs };
      }
      return { ok: true, steps: outputs };
    }
    if (name === 'invoke_provider') {
      const context = await call('get_context', { session: args.session });
      if (!context.ok) return context;
      const provider = context.providers.find(p => p.name === args.provider);
      if (!provider) return { ok: false, code: 'provider_unavailable' };
      validateProvider(provider.inputSchema, args.input);
    }
    if (name === 'discover_files' || name === 'project_search') {
      const context = await call('get_context', { session: args.session, limit: 100 });
      if (!context.ok) return context;
      const root = await fs.realpath(context.cwd);
      const inventory = await discover(root);
      if (name === 'discover_files') {
        const matches = inventory.files.filter(f => f.includes(args.query || ''));
        const offset = args.offset || 0, limit = args.limit || 100;
        return { ok: true, root, files: matches.slice(offset, offset + limit), next_offset: offset + limit < matches.length ? offset + limit : -1, truncated: inventory.truncated };
      }
      const buffers = [...context.buffers];
      let offset = context.next_offset;
      while (offset >= 0) {
        const page = await call('get_context', { session: args.session, offset, limit: 100 });
        if (!page.ok) return page;
        buffers.push(...page.buffers); offset = page.next_offset;
      }
      const live = new Map(buffers.filter(b => b.path).map(b => [path.resolve(b.path), b]));
      const files = new Set(inventory.files);
      for (const full of live.keys()) if (full.startsWith(root + path.sep)) files.add(path.relative(root, full));
      const findings = [], skipped = [];
      const limit = args.limit || 100;
      for (const relative of files) {
        if (signal?.aborted) return { ok: false, code: 'cancelled' };
        const full = path.join(root, relative), buffer = live.get(full);
        let text;
        if (buffer) {
          const lines = []; let first = 1, revision;
          for (;;) {
            const page = await call('read_buffer', { session: args.session, buffer: buffer.buffer, start_line: first, limit: 1000 });
            if (!page.ok) { skipped.push({ path: relative, reason: page.code }); break; }
            if (revision && revision !== page.revision) { skipped.push({ path: relative, reason: 'stale_revision' }); break; }
            revision = page.revision; lines.push(...page.lines);
            if (lines.join('\n').length > 2_000_000) { skipped.push({ path: relative, reason: 'too_large' }); break; }
            if (!page.next_line) { text = lines.join('\n'); buffer.revision = revision; break; }
            first = page.next_line;
          }
        } else {
          try {
            // Recheck symlinks after traversal and never escape the project root.
            const real = await fs.realpath(full);
            if (!real.startsWith(root + path.sep) || (await fs.stat(real)).size > 2_000_000) { skipped.push({ path: relative, reason: 'outside_project_or_too_large' }); continue; }
            text = await fs.readFile(real, 'utf8');
          } catch { skipped.push({ path: relative, reason: 'unreadable' }); continue; }
        }
        if (text === undefined) continue;
        if (text.includes('\0')) { skipped.push({ path: relative, reason: 'binary' }); continue; }
        const lines = text.split('\n');
        for (let i = 0; i < lines.length; i++) {
          let start = 0, at;
          while ((at = lines[i].indexOf(args.query, start)) !== -1) {
            const begin = { line: i + 1, byte: Buffer.byteLength(lines[i].slice(0, at)) };
            const end = { line: i + 1, byte: begin.byte + Buffer.byteLength(args.query) };
            findings.push({ message: lines[i].slice(0, 500), source: 'project-search', ...(buffer ? { location: { buffer: buffer.buffer, revision: buffer.revision, start: begin, end } } : { disk_location: { path: relative, start: begin, end }, requires_open: true }) });
            if (findings.length >= limit) return { ok: true, findings, skipped: skipped.slice(0, 100), truncated: true };
            start = at + args.query.length;
          }
        }
      }
      return { ok: true, findings, skipped: skipped.slice(0, 100), truncated: inventory.truncated };
    }
    return preview(await call(name, args));
  }
}
