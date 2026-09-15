import Ajv from 'ajv';

const str = { type: 'string', maxLength: 1_000_000, pattern: '^[^\\u0000]*$' };
const short = { type: 'string', minLength: 1, maxLength: 1024 };
const integer = { type: 'integer', minimum: 0 };
const bool = { type: 'boolean' };
const enumOf = (...values) => ({ type: 'string', enum: values });
const array = (items, maxItems = 1000) => ({ type: 'array', items, maxItems });
export const object = (properties, required = Object.keys(properties)) => ({ type: 'object', properties, required, additionalProperties: false });
export const position = object({ line: { type: 'integer', minimum: 1 }, byte: integer });
export const location = object({ buffer: short, revision: short, start: position, end: position });
const edit = object({ start: position, end: position, text: str, expected: str }, ['start', 'end', 'text']);
const change = object({ buffer: short, revision: short, edits: { ...array(edit), minItems: 1 } });
const finding = object({ location, message: str, source: short, severity: enumOf('error', 'warning', 'info', 'hint') }, ['location', 'message']);
const anyObject = { type: 'object', additionalProperties: true };
const definitions = [];
function tool(name, description, properties = {}, required = [], mutation = false, local = false) {
  definitions.push({ name, description, inputSchema: object(local ? properties : { session: short, ...properties }, local ? required : ['session', ...required]), mutation, local });
}
tool('list_sessions', 'Discover live Vim sessions and supported capabilities.', {}, [], false, true);
tool('get_context', 'Read compact live context, available providers, and captured selection.', { offset: integer, limit: { type: 'integer', minimum: 1, maximum: 100 } });
tool('read_buffer', 'Read bounded live text with a revision. Coordinates use 1-based lines and 0-based UTF-8 bytes.', { buffer: short, start_line: { type: 'integer', minimum: 1 }, limit: { type: 'integer', minimum: 1, maximum: 1000 } }, ['buffer']);
tool('search', 'Find literal or Vim-regex matches in revisioned target ranges. Returns reusable findings.', { targets: array(location), query: short, regex: bool, limit: { type: 'integer', minimum: 1, maximum: 500 } }, ['targets', 'query']);
tool('prepare_changes', 'Validate edits against live revisions and return a stored change set plus a diff. Does not edit buffers.', { changes: { ...array(change, 20), minItems: 1 }, title: short }, ['changes']);
tool('apply_changes', 'Apply all or selected hunks from a prepared change set. One undo block per buffer; per-buffer results, no cross-buffer atomicity.', { change_id: short, hunks: array(short) }, ['change_id'], true);
tool('undo_change', 'Undo an applied change only if its resulting revision and undo sequence are still current.', { change_id: short, buffer: short }, ['change_id', 'buffer'], true);
tool('review_changes', 'Open before/after diff scratch buffers for a prepared change set.', { change_id: short, buffer: short }, ['change_id'], true);
tool('save_buffer', 'Explicitly save a named live buffer after revision and external disk conflict checks.', { buffer: short, revision: short }, ['buffer', 'revision'], true);
tool('navigate', 'Visit a revisioned location, or return to the previous view.', { location, back: bool }, [], true);
tool('publish_findings', 'Create an owned quickfix/location list without replacing existing lists.', { findings: array(finding, 500), title: short, kind: enumOf('quickfix', 'location') }, ['findings', 'title'], true);
tool('get_events', 'Poll bounded buffer/lifecycle invalidation events after a cursor. A gap means reread snapshots.', { after: integer });
tool('get_history', 'Read recent operation results; use request_status for ambiguous requests.', {});
tool('request_status', 'Inspect a request by request_id after a timeout; never replay a mutation blindly.', { request_id: short }, ['request_id'], false, true);
tool('cancel_request', 'Cancel an undispatched request. Dispatched operations may already have executed.', { request_id: short }, ['request_id'], true, true);
tool('combine_targets', 'Union, intersect, subtract, or filter revision-compatible target ranges.', { operation: enumOf('union', 'intersection', 'difference', 'filter'), left: array(location), right: array(location), buffers: array(short) }, ['operation', 'left'], false, true);
tool('discover_files', 'List project files under the session cwd, excluding VCS, dependency, and symlink directories.', { query: str, offset: integer, limit: { type: 'integer', minimum: 1, maximum: 500 } });
tool('project_search', 'Literal project search. Loaded unsaved buffers override disk; disk findings require open_buffer before edits.', { query: short, limit: { type: 'integer', minimum: 1, maximum: 500 } }, ['query']);
tool('open_buffer', 'Explicitly load a project-relative file or create an unnamed buffer; returns live identity and revision.', { path: str, unnamed: bool }, [], true);
tool('transform', 'Prepare a change set from target text: literal/Vim-regex substitution, uppercase, lowercase, trim, or sort_lines. Expression replacements are disabled.', { targets: array(location), operation: enumOf('substitute', 'uppercase', 'lowercase', 'trim', 'sort_lines'), query: str, replacement: str, regex: bool }, ['targets', 'operation']);
tool('inspect_editor', 'Discover marks, jumps, folds, tags, mappings, commands, registers, or selected options.', { kind: enumOf('marks', 'jumps', 'folds', 'tags', 'mappings', 'commands', 'registers', 'options'), query: str }, ['kind']);
tool('help', 'Return excerpts from installed Vim/plugin help without opening a window.', { topic: short }, ['topic']);
tool('invoke_provider', 'Invoke an explicitly registered typed Vim9 provider. Results use standard snapshots, findings, or changes where applicable.', { provider: short, input: anyObject }, ['provider', 'input'], true);
tool('start_job', 'Start an explicitly configured named build/test/lint job; no arbitrary shell command. Output is bounded.', { name: short }, ['name'], true);
tool('get_job', 'Read job status/output and errorformat findings.', { job_id: short }, ['job_id']);
tool('stop_job', 'Request termination of a running named job.', { job_id: short }, ['job_id'], true);
tool('record_macro', 'Store literal macro keystrokes in a named register; does not execute.', { register: { type: 'string', pattern: '^[a-z]$' }, keys: str }, ['register', 'keys'], true);
tool('execute_macro', 'Execute a named macro once. Requires advanced automation opt-in; no preview or rollback guarantee.', { register: { type: 'string', pattern: '^[a-z]$' } }, ['register'], true);
tool('execute_ex', 'Execute an Ex command and return actual output/errors. Requires advanced automation opt-in; may have external effects.', { command: short }, ['command'], true);
tool('workspace', 'Explicitly split, create a tab, close a window/tab, or unload an unmodified buffer. Never forces discarding changes.', { action: enumOf('split', 'vsplit', 'tabnew', 'close', 'tabclose', 'unload'), buffer: short }, ['action'], true);
tool('get_workflow', 'Read an explicitly configured named workflow from g:vim9_mcp_workflows.', { name: short }, ['name']);
tool('run_workflow', 'Run inline steps or a named Vim workflow. References use {"$ref":"step-id#/field"}. Stops on failure; never rolls back or retries implicitly.', { steps: array(object({ id: short, tool: short, arguments: anyObject }), 12), name: short, session: short }, [], true, true);

export const tools = definitions;
const ajv = new Ajv({ allErrors: true, strict: false });
const validators = new Map(definitions.map(t => [t.name, ajv.compile(t.inputSchema)]));
export function validate(name, args) {
  const check = validators.get(name);
  if (!check) throw new Error(`unknown_tool: ${name}`);
  if (!check(args)) throw new Error(`invalid_arguments: ${ajv.errorsText(check.errors)}`);
  return definitions.find(t => t.name === name);
}
export function validateProvider(schema, value) {
  const check = ajv.compile(schema);
  if (!check(value)) throw new Error(`invalid_provider_input: ${ajv.errorsText(check.errors)}`);
}
