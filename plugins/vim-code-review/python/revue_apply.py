"""Single-suggestion workspace application with a durable pre-write intent.

No Git commit, index change, thread resolution or publication. Recovery only
observes hashes; it never repeats an uncertain filesystem write.
"""
import hashlib
import fcntl
import json
import os
from pathlib import Path
import re
import stat
import sys
from contextlib import contextmanager

from revue_local import MAX_CONTENT, encode, identity, message_target


class ApplicationUnknown(ValueError):
    unknown = True


def replacement(body):
    lines, blocks, i = body.split('\n'), [], 0
    while i < len(lines):
        fence = re.match(r'^ {0,3}(`{3,}|~{3,})\s*(.*)$', lines[i])
        if not fence:
            i += 1
            continue
        suggestion = fence[2].strip() == 'suggestion'
        closing = re.compile(r'^ {0,3}' + re.escape(fence[1][0]) + '{' + str(len(fence[1])) + r',}\s*$')
        i += 1
        start = i
        while i < len(lines) and not closing.match(lines[i]):
            i += 1
        if suggestion:
            if i == len(lines):
                raise ValueError('Close the suggestion fence before applying it')
            blocks.append(lines[start:i])
        i += 1
    if len(blocks) != 1:
        raise ValueError('Select a message with exactly one unquoted suggestion block')
    if any('\r' in line or '\0' in line for line in blocks[0]):
        raise ValueError('Suggestion contains unsupported control bytes')
    return blocks[0]


@contextmanager
def parent(workspace, path):
    root = Path(workspace)
    parts = path.split('/')
    if not root.is_absolute() or root.resolve() != root or any(p in ('', '.', '..') for p in parts):
        raise ValueError('Suggestion destination is not a verified workspace path')
    handles = []
    try:
        handles.append(os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW))
        for part in parts[:-1]:
            handles.append(os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=handles[-1]))
        yield handles[-1], parts[-1]
    finally:
        for handle in reversed(handles):
            os.close(handle)


def read_file(directory, name):
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_mode & 0o6000 or getattr(info, 'st_flags', 0) or info.st_uid != os.geteuid():
            raise ValueError('Suggestion destination must be an ordinary, singly linked regular file')
        if info.st_size > MAX_CONTENT:
            raise ValueError('Suggestion destination exceeds the capture limit')
        with os.fdopen(fd, 'rb', closefd=False) as stream:
            raw = stream.read(MAX_CONTENT + 1)
        if len(raw) > MAX_CONTENT or fingerprint(info) != fingerprint(os.fstat(fd)):
            raise ValueError('Suggestion destination changed during the read')
        return raw, info
    finally:
        os.close(fd)


def fingerprint(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def copy_metadata(source, destination, info):
    os.fchown(destination, -1, info.st_gid)
    os.fchmod(destination, stat.S_IMODE(info.st_mode))
    if sys.platform == 'darwin':
        # Apple's descriptor API preserves ACLs and xattrs without following
        # paths or copying old timestamps/file flags onto the edited content.
        import ctypes
        libc = ctypes.CDLL(None, use_errno=True)
        copy = libc.fcopyfile
        copy.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
        copy.restype = ctypes.c_int
        if copy(source, destination, None, (1 << 0) | (1 << 2)):
            error = ctypes.get_errno()
            raise OSError(error, os.strerror(error))
    elif hasattr(os, 'listxattr'):
        for name in os.listxattr(source):
            os.setxattr(destination, name, os.getxattr(source, name))
    else:
        raise ValueError('Preserving file metadata is unsupported on this platform')


def replace_lines(raw, start, end, lines):
    chunks = raw.split(b'\n')
    segments = [part + b'\n' for part in chunks[:-1]] + ([chunks[-1]] if chunks[-1] else [])
    if not 1 <= start <= end <= len(segments):
        raise ValueError('Suggestion range is outside the verified file')
    # Preserve all bytes outside the selected range and the final-newline state.
    sample = next((part for part in segments[start - 1:end] if part.endswith(b'\n')), b'')
    if not sample:
        sample = next((part for part in segments if part.endswith(b'\n')), b'\n')
    eol = b'\r\n' if sample.endswith(b'\r\n') else b'\n'
    new = eol.join(line.encode('utf-8') for line in lines)
    if lines and (end < len(segments) or raw.endswith(b'\n')):
        new += eol
    result = b''.join(segments[:start - 1]) + new + b''.join(segments[end:])
    if len(result) > MAX_CONTENT:
        raise ValueError('Suggested result exceeds the capture limit')
    return result, 'CRLF' if eol == b'\r\n' else 'LF'


class LocalApplications:
    def __init__(self, backend):
        self.backend, self.db = backend, backend.db

    def plan(self, request):
        data = self.backend.load(request['review'])
        snapshot = self.backend.view(data, request['reference'])
        if snapshot['snapshot'] != data['snapshot']['snapshot'] or snapshot.get('range') or snapshot.get('context'):
            raise ValueError('Open the latest comparison before applying a suggestion')
        target = request['target']
        message = message_target(snapshot, target)
        if message.get('version') != target.get('expected_version'):
            raise ValueError('Suggestion message changed; select it again')
        thread = next((t for t in snapshot['threads'] if t['id'] == target.get('thread')), {})
        if not thread or thread.get('outdated') or thread.get('side') != 'head' or thread.get('subject_type') == 'file':
            raise ValueError('Apply requires a current head-side line discussion')
        file = next((f for f in snapshot['files'] if f['path'] == thread['path']), None)
        if not file:
            raise ValueError('The suggestion file is not in this comparison')
        source = data['revisions'][snapshot['snapshot']]['contents'][file['id']]['head']
        if source.get('kind') != 'text':
            raise ValueError('The suggestion source is not captured text')
        lines = replacement(message['body'])
        with parent(data['workspace'], file['path']) as (directory, name):
            raw, info = read_file(directory, name)
        if hashlib.sha256(raw).hexdigest() != source['hash']:
            raise ValueError('Workspace file differs from the reviewed capture; capture and review it first')
        after, eol = replace_lines(raw, thread['start'], thread['line'], lines)
        if after == raw:
            raise ValueError('Suggestion already matches the reviewed file')
        return {'kind': 'apply_suggestion', 'body': '', 'destination': 'workspace',
                **{k: snapshot[k] for k in ('snapshot', 'head', 'base_tip')},
                'reference': {k: snapshot[k] for k in ('snapshot', 'head', 'base_tip', 'base')},
                **{k: target[k] for k in ('thread', 'message', 'message_kind', 'expected_version')},
                'original_body': message['body'], 'workspace': data['workspace'], 'path': file['path'],
                'side': 'head', 'start': thread['start'], 'end': thread['line'],
                'before_hash': source['hash'], 'after_hash': hashlib.sha256(after).hexdigest(),
                'before_lines': source['lines'][thread['start'] - 1:thread['line']], 'replacement': lines,
                'file_mode': stat.S_IMODE(info.st_mode), 'line_ending': eol,
                'untracked': data.get('capture_options', {}).get('untracked', False)}

    def submit(self, request):
        database = self.db.execute('PRAGMA database_list').fetchone()[2]
        lock = Path(database).parent / '.suggestion-application.lock'
        fd = os.open(lock, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        try:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise ApplicationUnknown('Another suggestion application is in progress; check this operation after it finishes') from error
            return self._submit(request)
        finally:
            os.close(fd)

    def _submit(self, request):
        self.db.execute('CREATE TABLE IF NOT EXISTS suggestion_applications '
                        '(review TEXT NOT NULL, operation TEXT NOT NULL, payload TEXT NOT NULL, '
                        'plan TEXT NOT NULL, PRIMARY KEY(review, operation))')
        draft = dict(request['draft'])
        draft.pop('state', None)
        operation, review = draft.get('id'), request['review']
        if not isinstance(operation, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,240}', operation):
            raise ValueError('A stable suggestion operation ID is required')
        payload = encode(draft)
        existing = False
        with self.db:
            self.db.execute('BEGIN IMMEDIATE')
            receipt = self.db.execute('SELECT payload, receipt FROM receipts WHERE review=? AND operation=?', (review, operation)).fetchone()
            if receipt:
                if receipt[0] != payload:
                    raise ValueError('Suggestion operation was reused with a different preview')
                return dict(json.loads(receipt[1]), recovered=True)
            row = self.db.execute('SELECT payload, plan FROM suggestion_applications WHERE review=? AND operation=?', (review, operation)).fetchone()
            if row:
                if row[0] != payload:
                    raise ValueError('Suggestion operation was reused with a different preview')
                plan, existing = json.loads(row[1]), True
            else:
                if request.get('reconcile'):
                    result = {'id': operation, 'intent': draft, 'applied': False, 'observed': True,
                              'url': '', 'result_snapshot': '', 'capture_error': ''}
                    self.db.execute('INSERT INTO receipts VALUES (?, ?, ?, ?)', (review, operation, payload, encode(result)))
                    return result
                plan = self.plan({'review': review, 'reference': draft.get('reference', {}), 'target': draft})
                if any(encode(draft.get(k)) != encode(v) for k, v in plan.items()):
                    raise ValueError('Suggestion preview changed; inspect a fresh preview')
                self.db.execute('INSERT INTO suggestion_applications VALUES (?, ?, ?, ?)', (review, operation, payload, encode(plan)))
        # The pre-write intent is committed before any filesystem mutation.
        try:
            with self.db:
                self.db.execute('BEGIN IMMEDIATE')
                receipt = self.db.execute('SELECT receipt FROM receipts WHERE review=? AND operation=?', (review, operation)).fetchone()
                if receipt:
                    return dict(json.loads(receipt[0]), recovered=True)
                with parent(plan['workspace'], plan['path']) as (directory, name):
                    raw, info = read_file(directory, name)
                    current = hashlib.sha256(raw).hexdigest()
                    if existing:
                        if current not in (plan['before_hash'], plan['after_hash']):
                            raise ApplicationUnknown('Workspace differs from both preview and result; inspect the file and retained operation')
                        applied = current == plan['after_hash']
                    else:
                        # Revalidate discussion, comparison and filesystem after staging.
                        latest = self.plan({'review': review, 'reference': plan['reference'], 'target': plan})
                        if latest != plan or current != plan['before_hash']:
                            raise ValueError('Source changed before application; no replacement was made')
                        with parent(plan['workspace'], plan['path']) as (verified, _):
                            here, there = os.fstat(directory), os.fstat(verified)
                            if (here.st_dev, here.st_ino) != (there.st_dev, there.st_ino):
                                raise ValueError('Suggestion directory changed before application')
                        after, _ = replace_lines(raw, plan['start'], plan['end'], plan['replacement'])
                        self.install(directory, name, raw, after, info)
                        applied = True
                result = {'id': operation, 'intent': draft, 'applied': applied, 'observed': existing,
                          'url': '', 'result_snapshot': '', 'capture_error': ''}
                if applied:
                    data = self.backend.load(review)
                    snapshot = data['snapshot']
                    # Capture is a retained read of saved files, not a Git commit.
                    capture = {'id': operation + '-result', 'kind': 'capture', 'body': '', 'untracked': plan['untracked'],
                               **{k: snapshot[k] for k in ('snapshot', 'head', 'base_tip')}}
                    self.db.execute('SAVEPOINT application_capture')
                    try:
                        result['result_snapshot'] = self.backend._mutate({'review': review, 'draft': capture})['snapshot']
                    except Exception as error:
                        self.db.execute('ROLLBACK TO application_capture')
                        result['capture_error'] = str(error)
                    finally:
                        self.db.execute('RELEASE application_capture')
                    current_review = self.backend.load(review)
                    try:
                        message = message_target(current_review['snapshot'], plan)
                    except ValueError:
                        message = {}
                    if message.get('version') == plan['expected_version']:
                        message['suggestion_application'] = {
                            'state': 'observed' if existing else 'applied',
                            'label': 'Result observed in workspace' if existing else 'Applied to workspace',
                            'message_version': plan['expected_version'], 'operation': operation,
                            'result_snapshot': result['result_snapshot']}
                        self.db.execute('UPDATE reviews SET data=? WHERE id=?', (encode(current_review), review))
                self.db.execute('INSERT INTO receipts VALUES (?, ?, ?, ?)', (review, operation, payload, encode(result)))
                self.db.execute('INSERT INTO events(review, id, kind, data) VALUES (?, ?, ?, ?)',
                                (review, identity(), 'suggestion.applied' if applied else 'suggestion.not_applied', encode(result)))
                return result
        except Exception as error:
            raise ApplicationUnknown(str(error)) from error

    @staticmethod
    def install(directory, name, before, after, info):
        temporary = '.revue-suggestion-' + identity()
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=directory)
        try:
            with os.fdopen(fd, 'wb', closefd=False) as stream:
                stream.write(after)
                stream.flush()
                original = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory)
                try:
                    if fingerprint(info) != fingerprint(os.fstat(original)):
                        raise ValueError('File metadata changed before application')
                    copy_metadata(original, fd, info)
                finally:
                    os.close(original)
                os.fsync(fd)
            current, current_info = read_file(directory, name)
            if current != before or fingerprint(info) != fingerprint(current_info):
                raise ValueError('File changed immediately before application; no replacement was made')
            os.replace(temporary, name, src_dir_fd=directory, dst_dir_fd=directory)
            os.fsync(directory)
        finally:
            os.close(fd)
            try:
                os.unlink(temporary, dir_fd=directory)
            except FileNotFoundError:
                pass
