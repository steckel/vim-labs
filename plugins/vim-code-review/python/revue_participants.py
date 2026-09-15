"""Scoped participants in the local backend's existing review database.

This is a backend extension, independent of its Vim and MCP transports. A trusted
owner creates an assignment; a participant connection binds to that assignment.
"""
import copy
import datetime
import json
import uuid


def encode(value):
    return json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(',', ':'))


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds')


def text(value, name, maximum=200):
    if not isinstance(value, str) or not value.strip() or len(value) > maximum:
        raise ValueError('Invalid ' + name)
    return value


class LocalParticipants:
    def __init__(self, backend):
        self.backend = backend
        self.db = backend.db
        self.db.execute('''CREATE TABLE IF NOT EXISTS assignments (
            id TEXT PRIMARY KEY, review TEXT NOT NULL REFERENCES reviews(id),
            data TEXT NOT NULL)''')
        self.db.commit()

    def assignment(self, assignment):
        row = self.db.execute('SELECT data FROM assignments WHERE id=?', (assignment,)).fetchone()
        if not row:
            raise ValueError('Assignment unavailable')
        return json.loads(row[0])

    def reference(self, data, reference):
        if not isinstance(reference, dict):
            raise ValueError('An exact comparison reference is required')
        source = data['revisions'].get(reference.get('snapshot'), {}).get('snapshot', {})
        keys = ('snapshot', 'base', 'head', 'base_tip')
        if not source or set(reference) != set(keys) or any(reference[k] != source[k] for k in keys):
            raise ValueError('Comparison does not belong to this review')
        return dict(reference)

    def selected(self, data, target):
        if not isinstance(target, dict) or set(target) != {'thread', 'message', 'message_kind', 'expected_version'}:
            raise ValueError('Select an exact versioned message in an anchored discussion')
        thread = next((t for t in data['snapshot']['threads'] if t['id'] == target['thread']), None)
        if not thread:
            raise ValueError('Assignment requires an existing anchored discussion')
        message = next((m for m in thread['comments'] if m['id'] == target['message'] and m.get('kind', 'comment') == target['message_kind']), None)
        if not message or message['version'] != target['expected_version']:
            raise ValueError('Selected message changed; inspect it before assigning')
        return thread, message

    def record(self, assignment, kind, details):
        self.db.execute('INSERT INTO events(review,id,kind,data) VALUES (?,?,?,?)',
                        (assignment['review'], uuid.uuid4().hex, kind, encode(dict(details, assignment=assignment['id']))))

    def owner(self, request):
        op = request['op']
        review = text(request.get('review'), 'review')
        with self.db:
            self.db.execute('BEGIN IMMEDIATE')
            data = self.backend.load(review)
            if op == 'assignments':
                return {'backend': 'local', 'connection': self.backend.connection, 'review': review,
                        'items': [json.loads(r[0]) for r in self.db.execute('SELECT data FROM assignments WHERE review=? ORDER BY rowid', (review,))]}
            if op == 'assign':
                operation = text(request.get('id'), 'operation ID')
                participant = request.get('participant', {})
                if not isinstance(participant, dict) or set(participant) != {'id', 'label'}:
                    raise ValueError('A participant needs a stable ID and label')
                text(participant['id'], 'participant ID')
                text(participant['label'], 'participant label', 100)
                fields = {k: request.get(k) for k in ('id', 'review', 'participant', 'reference', 'targets')}
                if request.get('require_current'):
                    fields['require_current'] = True
                payload = encode(fields)
                prior = self.db.execute('SELECT payload,receipt FROM receipts WHERE review=? AND operation=?', (review, operation)).fetchone()
                if prior:
                    if prior[0] != payload:
                        raise ValueError('Operation ID was used for another assignment')
                    return dict(json.loads(prior[1]), recovered=True)
                if request.get('reconcile'):
                    raise ValueError('No assignment receipt found; reconciliation did not create an assignment')
                reference = self.reference(data, request.get('reference'))
                if request.get('require_current') and any(reference[k] != data['snapshot'][k] for k in reference):
                    raise ValueError('Comparison changed; inspect a new assignment preview')
                targets = request.get('targets')
                if not isinstance(targets, list) or not 1 <= len(targets) <= 50:
                    raise ValueError('Select between 1 and 50 messages')
                selected, ids = [], set()
                for target in targets:
                    thread, message = self.selected(data, target)
                    if message['id'] in ids:
                        raise ValueError('Select each message once')
                    ids.add(message['id'])
                    selected.append(dict(target, original_body=message['body'], author=message['author']))
                assignment = {'id': uuid.uuid4().hex, 'backend': 'local', 'review': review, 'connection': self.backend.connection,
                              'participant': dict(participant), 'reference': reference, 'targets': selected,
                              'version': uuid.uuid4().hex, 'created': now(), 'cancelled': False,
                              'outcomes': {t['message']: {'state': 'assigned'} for t in targets}}
                self.db.execute('INSERT INTO assignments VALUES (?,?,?)', (assignment['id'], review, encode(assignment)))
                self.db.execute('INSERT INTO receipts VALUES (?,?,?,?)', (review, operation, payload, encode(assignment)))
                self.record(assignment, 'assignment.created', {'targets': targets})
                return assignment
            assignment = self.assignment(text(request.get('assignment'), 'assignment'))
            if assignment['review'] != review:
                raise ValueError('Assignment belongs to another review')
            if op == 'assignment':
                return assignment
            if op != 'cancel_assignment':
                raise ValueError('Unsupported assignment action')
            operation = request.get('id')
            if operation is not None:
                text(operation, 'operation ID')
                payload = encode({k: request.get(k) for k in ('op', 'id', 'review', 'assignment', 'expected_version')})
                prior = self.db.execute('SELECT payload,receipt FROM receipts WHERE review=? AND operation=?', (review, operation)).fetchone()
                if prior:
                    if prior[0] != payload:
                        raise ValueError('Operation ID was used for another cancellation')
                    return dict(json.loads(prior[1]), recovered=True)
            if request.get('reconcile'):
                raise ValueError('No cancellation receipt found; reconciliation did not cancel the assignment')
            if request.get('expected_version') != assignment['version']:
                raise ValueError('Assignment changed; reload before cancelling')
            if not assignment['cancelled']:
                assignment.update(cancelled=True, version=uuid.uuid4().hex)
                self.db.execute('UPDATE assignments SET data=? WHERE id=?', (encode(assignment), assignment['id']))
                self.record(assignment, 'assignment.cancelled', {})
            if operation is not None:
                receipt = {'id': operation, 'assignment': assignment['id'],
                           'expected_version': request['expected_version'], 'version': assignment['version'],
                           'cancelled': True, 'url': ''}
                self.db.execute('INSERT INTO receipts VALUES (?,?,?,?)', (review, operation, payload, encode(receipt)))
                return receipt
            return assignment

    def scoped_thread(self, assignment, data, thread_id):
        if thread_id not in {t['thread'] for t in assignment['targets']}:
            raise ValueError('Thread is outside this assignment')
        thread = next((t for t in data['snapshot']['threads'] if t['id'] == thread_id), None)
        if thread is None:
            raise ValueError('Assigned thread is no longer available')
        return thread

    def source(self, data, thread):
        source_id = thread.get('anchor', {}).get('snapshot')
        revision = data['revisions'].get(source_id)
        if not revision:
            raise ValueError('Original source is unavailable')
        file = next((f for f in revision['snapshot']['files'] if f['path'] == thread['path']), None)
        if not file:
            raise ValueError('Original file is unavailable')
        return revision, file

    def call(self, assignment_id, action, args):
        if not isinstance(args, dict):
            raise ValueError('Tool arguments must be an object')
        allowed = {
            'get_assignment': set(), 'get_thread': {'thread'},
            'get_source': {'thread', 'side', 'start', 'count'}, 'get_changes': {'cursor'},
            'reply_to_comment': {'operation_id', 'thread', 'message', 'expected_version', 'body'},
            'set_outcome': {'operation_id', 'message', 'expected_version', 'state', 'summary', 'run_id', 'result_reference'}}
        if action not in allowed or set(args) - allowed[action]:
            raise ValueError('Unsupported participant action or arguments')
        # Reads share a coherent SQLite transaction. Writes also serialize with
        # human feedback, so selection checks, message, receipt and event agree.
        with self.db:
            self.db.execute('BEGIN IMMEDIATE' if action in ('reply_to_comment', 'set_outcome') else 'BEGIN')
            assignment = self.assignment(assignment_id)
            if assignment['cancelled']:
                raise ValueError('Assignment cancelled; this connection no longer has access')
            data = self.backend.load(assignment['review'])
            if action == 'get_assignment':
                return assignment
            if action in ('get_thread', 'get_source'):
                thread = self.scoped_thread(assignment, data, text(args.get('thread'), 'thread'))
                if action == 'get_thread':
                    # Do not expose owner-only mutation capabilities to the agent.
                    result = copy.deepcopy(thread)
                    result.pop('capabilities', None)
                    for message in result['comments']:
                        message.pop('capabilities', None)
                    try:
                        revision, _ = self.source(data, thread)
                        reference = {k: revision['snapshot'][k] for k in ('snapshot', 'base', 'head', 'base_tip')}
                        unavailable = ''
                    except ValueError as error:
                        reference, unavailable = {}, str(error)
                    return {'thread': result, 'original_comparison': reference, 'assigned_comparison': assignment['reference'], 'source_unavailable': unavailable}
                revision, file = self.source(data, thread)
                reference = {k: revision['snapshot'][k] for k in ('snapshot', 'base', 'head', 'base_tip')}
                side, start, count = args.get('side'), args.get('start', 1), args.get('count', 100)
                if side not in ('base', 'head') or type(start) is not int or start < 1 or type(count) is not int or not 1 <= count <= 200:
                    raise ValueError('Choose a source side, positive start and count from 1 to 200')
                source = revision['contents'][file['id']][side]
                lines = source.get('lines', [])
                return {'reference': reference, 'path': file['path'], 'side': side, 'kind': source['kind'],
                        'start': start, 'lines': lines[start-1:start-1+count], 'total': len(lines),
                        'next_start': start+count if start-1+count < len(lines) else None,
                        'message': source.get('message', '')}
            if action == 'get_changes':
                cursor = args.get('cursor', 0)
                if type(cursor) is not int or not 0 <= cursor <= 9223372036854775807:
                    raise ValueError('Invalid changes cursor')
                threads = {t['thread'] for t in assignment['targets']}
                ids = {m['id'] for t in data['snapshot']['threads'] if t['id'] in threads for m in t['comments']}
                rows = self.db.execute('SELECT cursor,kind,data FROM events WHERE review=? AND cursor>? ORDER BY cursor LIMIT 101', (assignment['review'], cursor)).fetchall()
                events = []
                for position, kind, encoded in rows[:100]:
                    event = json.loads(encoded)
                    message = event.get('after', event.get('before', event)).get('id')
                    if event.get('assignment') == assignment_id or message in ids or event.get('receipt', {}).get('thread') in threads:
                        events.append({'cursor': position, 'kind': kind, 'message': message})
                return {'items': events, 'cursor': rows[min(99, len(rows)-1)][0] if rows else cursor, 'has_more': len(rows) > 100}
            operation = text(args.get('operation_id'), 'operation ID')
            operation = 'participant:' + assignment_id + ':' + operation
            payload = encode({'assignment': assignment_id, 'action': action, 'arguments': args})
            row = self.db.execute('SELECT payload,receipt FROM receipts WHERE review=? AND operation=?', (assignment['review'], operation)).fetchone()
            if row:
                if row[0] != payload:
                    raise ValueError('Operation ID was used for different participant feedback')
                return dict(json.loads(row[1]), recovered=True)
            if action == 'reply_to_comment':
                thread = self.scoped_thread(assignment, data, text(args.get('thread'), 'thread'))
                message = next((m for m in thread['comments'] if m['id'] == args.get('message')), None)
                if not message or message['version'] != args.get('expected_version'):
                    raise ValueError('Reply target changed; read the thread again')
                body = text(args.get('body'), 'reply body', 100000)
                comment = {'id': uuid.uuid4().hex, 'kind': 'reply', 'body': body, 'created': now(),
                           'author': assignment['participant']['label'], 'author_role': 'Agent',
                           'actor': 'participant:' + assignment['participant']['id'],
                           'assignment': assignment_id, 'in_reply_to': message['id'], 'publication': 'local',
                           'version': uuid.uuid4().hex}
                thread['comments'].append(comment)
                receipt = {'id': comment['id'], 'assignment': assignment_id, 'thread': thread['id'],
                           'in_reply_to': message['id'], 'actor': comment['actor'], 'url': ''}
                self.db.execute('UPDATE reviews SET data=? WHERE id=?', (encode(data), data['id']))
                self.record(assignment, 'comment.created', receipt)
            else:
                message = text(args.get('message'), 'message')
                if message not in assignment['outcomes'] or args.get('expected_version') != assignment['version']:
                    raise ValueError('Assignment target or version changed')
                if args.get('state') not in ('working', 'needs_input', 'addressed', 'failed'):
                    raise ValueError('Unsupported outcome state')
                outcome = {'state': args['state'], 'summary': text(args.get('summary'), 'outcome summary', 10000)}
                if 'run_id' in args:
                    outcome['run_id'] = text(args['run_id'], 'run ID')
                if 'result_reference' in args:
                    outcome['result_reference'] = self.reference(data, args['result_reference'])
                assignment['outcomes'][message] = outcome
                assignment['version'] = uuid.uuid4().hex
                self.db.execute('UPDATE assignments SET data=? WHERE id=?', (encode(assignment), assignment_id))
                receipt = {'id': operation, 'assignment': assignment_id, 'version': assignment['version'], 'message': message, 'outcome': outcome}
                self.record(assignment, 'assignment.outcome', receipt)
            self.db.execute('INSERT INTO receipts VALUES (?,?,?,?)', (assignment['review'], operation, payload, encode(receipt)))
            return receipt
