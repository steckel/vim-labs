import test from 'node:test';
import assert from 'node:assert/strict';
import { combineTargets } from '../src/targets.js';
import { validate } from '../src/schema.js';
const range = (start, end, revision = 'r1') => ({ buffer: 'b1', revision, start: { line: 1, byte: start }, end: { line: 1, byte: end } });
test('target algebra composes overlapping ranges without changing input', () => {
  const left = [range(0, 5), range(10, 20)], right = [range(3, 12)];
  assert.deepEqual(combineTargets({ operation: 'union', left, right }), [range(0, 20)]);
  assert.deepEqual(combineTargets({ operation: 'intersection', left, right }), [range(3, 5), range(10, 12)]);
  assert.deepEqual(combineTargets({ operation: 'difference', left, right }), [range(0, 3), range(12, 20)]);
  assert.equal(left[0].end.byte, 5);
  assert.throws(() => combineTargets({ operation: 'union', left, right: [range(0, 1, 'r2')] }), /stale_revision/);
});
test('tool schemas reject unbounded reads, malformed positions and unknown arguments', () => {
  assert.throws(() => validate('read_buffer', { session: 's', buffer: 'b', limit: 100000 }), /invalid_arguments/);
  assert.throws(() => validate('prepare_changes', { session: 's', changes: [{ buffer: 'b', revision: 'r', edits: [{ start: { line: 0, byte: 0 }, end: { line: 1, byte: 0 }, text: '' }] }] }), /invalid_arguments/);
  assert.throws(() => validate('execute_ex', { session: 's', command: 'pwd', force: true }), /invalid_arguments/);
});
