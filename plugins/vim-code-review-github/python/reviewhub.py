#!/usr/bin/env python3
"""GitHub adapter. One JSON request on stdin, one JSON result on stdout.

Only the adapter knows GitHub endpoints. Credentials stay in the gh credential
store/environment; they are never returned to Vim or persisted with a draft.
"""
from __future__ import annotations

import concurrent.futures
from datetime import datetime, timezone
import hashlib
from html.parser import HTMLParser
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

REACTIONS = {'+1': 'Thumbs up', '-1': 'Thumbs down', 'laugh': 'Laugh', 'hooray': 'Hooray',
             'confused': 'Confused', 'heart': 'Heart', 'rocket': 'Rocket', 'eyes': 'Eyes'}


def readiness_check(node):
    """A reported check is not a complete inventory of repository requirements."""
    if not isinstance(node, dict) or not isinstance(node.get('id'), str) or not node['id']:
        raise Failure('A readiness check has no identity.', 'incomplete')
    kind = node.get('__typename')
    required = node.get('isRequired')
    if required is not None and type(required) is not bool:
        raise Failure('Invalid check requirement state.', 'incomplete')
    if kind == 'CheckRun':
        name, native = node.get('name'), node.get('status')
        conclusion = node.get('conclusion')
        state = 'pending' if native in ('QUEUED', 'IN_PROGRESS', 'WAITING', 'PENDING', 'REQUESTED') else 'unknown'
        if native == 'COMPLETED':
            state = {'SUCCESS': 'passed', 'FAILURE': 'failed', 'TIMED_OUT': 'failed',
                     'ACTION_REQUIRED': 'failed', 'STARTUP_FAILURE': 'failed',
                     'CANCELLED': 'cancelled', 'SKIPPED': 'skipped', 'NEUTRAL': 'neutral',
                     'STALE': 'unknown'}.get(conclusion, 'unknown')
        detail = native + (' / ' + conclusion if isinstance(conclusion, str) else '') if isinstance(native, str) else ''
        url = node.get('detailsUrl') or node.get('permalink') or ''
    elif kind == 'StatusContext':
        name, native = node.get('context'), node.get('state')
        state = {'SUCCESS': 'passed', 'FAILURE': 'failed', 'ERROR': 'failed',
                 'PENDING': 'pending', 'EXPECTED': 'pending'}.get(native, 'unknown')
        detail = node.get('description') or native
        url = node.get('targetUrl') or ''
    else:
        raise Failure('Unsupported readiness check type.', 'incomplete')
    if not all(isinstance(x, str) for x in (name, native, detail, url)) or not name:
        raise Failure('Incomplete readiness check fields.', 'incomplete')
    return {'id': node['id'], 'name': name, 'state': state, 'required': required,
            'detail': detail, 'url': url}

TIMELINE_FIELDS = {
    'IssueComment': 'author { login } createdAt body url databaseId',
    'PullRequestReview': 'author { login } createdAt submittedAt body state url databaseId commit { oid }',
    'PullRequestCommit': 'url commit { oid messageHeadline committedDate author { name user { login } } }',
    'PullRequestReviewThread': 'path comments(first:1) { nodes { databaseId body createdAt url author { login } } }',
    'MergedEvent': 'actor { login } createdAt url commit { oid }',
    'ReferencedEvent': 'actor { login } createdAt commit { oid }',
    'ReviewDismissedEvent': 'actor { login } createdAt url dismissalMessage previousReviewState review { url }',
    'HeadRefForcePushedEvent': 'actor { login } createdAt beforeCommit { oid } afterCommit { oid }',
    'LabeledEvent': 'actor { login } createdAt label { name }',
    'UnlabeledEvent': 'actor { login } createdAt label { name }',
    'RenamedTitleEvent': 'actor { login } createdAt previousTitle currentTitle',
    'CrossReferencedEvent': 'actor { login } createdAt source { ... on Issue { title url } ... on PullRequest { title url } }',
    'ReviewRequestedEvent': 'actor { login } createdAt requestedReviewer { ... on User { login } ... on Team { name } }',
    'ReviewRequestRemovedEvent': 'actor { login } createdAt requestedReviewer { ... on User { login } ... on Team { name } }',
}
for _event in ('ClosedEvent', 'ReopenedEvent', 'ReadyForReviewEvent', 'ConvertToDraftEvent',
               'HeadRefDeletedEvent', 'HeadRefRestoredEvent', 'LockedEvent', 'UnlockedEvent',
               'MentionedEvent', 'SubscribedEvent', 'UnsubscribedEvent'):
    TIMELINE_FIELDS[_event] = 'actor { login } createdAt'


def timeline_event(node, review_url):
    if not isinstance(node, dict) or not isinstance(node.get('id'), str) or not node['id'] or not isinstance(node.get('__typename'), str):
        raise Failure('Timeline returned an event without a stable identity.', 'incomplete')
    kind = node['__typename']
    actor = node.get('actor') or node.get('author') or {}
    title = re.sub(r'(?<=[a-z])(?=[A-Z])', ' ', kind.removesuffix('Event'))
    event = {'id': node['id'], 'kind': kind, 'title': title, 'actor': actor.get('login', ''),
             'created': node.get('submittedAt') or node.get('createdAt') or '',
             'body': node.get('body') or '', 'url': node.get('url') or review_url,
             'provenance': 'GitHub timeline', 'details': []}
    if kind == 'IssueComment':
        event['title'] = 'Commented'
        if node.get('databaseId') is not None:
            event['target'] = {'kind': 'conversation', 'message': str(node['databaseId']), 'message_kind': 'comment'}
    elif kind == 'PullRequestReview':
        state = node.get('state', '')
        event['title'] = {'APPROVED': 'Approved', 'CHANGES_REQUESTED': 'Requested changes',
                          'COMMENTED': 'Reviewed', 'DISMISSED': 'Review dismissed', 'PENDING': 'Private review'}.get(state, 'Review state unavailable')
        if node.get('databaseId') is not None:
            event['target'] = {'kind': 'conversation', 'message': str(node['databaseId']), 'message_kind': state}
        if (node.get('commit') or {}).get('oid'):
            event['reviewed_head'] = node['commit']['oid']
            event['details'].append('Reviewed commit: ' + event['reviewed_head'])
            event['details'].append('Original review base is unavailable here; the event link opens GitHub.')
    elif kind == 'PullRequestCommit':
        commit = node.get('commit') or {}
        author = commit.get('author') or {}
        event.update(title='Committed', created=commit.get('committedDate', ''),
                     actor=(author.get('user') or {}).get('login') or author.get('name', ''),
                     body=commit.get('messageHeadline', ''))
        if commit.get('oid'):
            event['details'].append('Commit: ' + commit['oid'])
    elif kind == 'PullRequestReviewThread':
        comments = (node.get('comments') or {}).get('nodes') or []
        root = comments[0] if comments and isinstance(comments[0], dict) else {}
        event.update(title='Inline discussion', actor=(root.get('author') or {}).get('login', ''),
                     created=root.get('createdAt', ''), body=root.get('body') or '', url=root.get('url') or review_url)
        event['details'].append('File: ' + node.get('path', 'unavailable'))
        if root.get('databaseId') is not None:
            event['target'] = {'kind': 'thread', 'thread': str(root['databaseId']), 'message': str(root['databaseId']), 'message_kind': 'comment', 'lookup': node['id']}
    elif kind == 'HeadRefForcePushedEvent':
        event['title'] = 'Force-pushed head branch'
        event['details'].append('Before: ' + (node.get('beforeCommit') or {}).get('oid', 'unavailable'))
        event['details'].append('After: ' + (node.get('afterCommit') or {}).get('oid', 'unavailable'))
    elif kind in ('MergedEvent', 'ReferencedEvent'):
        event['details'].append('Commit: ' + (node.get('commit') or {}).get('oid', 'unavailable'))
    elif kind == 'ReviewDismissedEvent':
        event.update(title='Dismissed review', body=node.get('dismissalMessage') or '')
        event['details'].append('Previous decision: ' + node.get('previousReviewState', 'unavailable'))
    elif kind in ('LabeledEvent', 'UnlabeledEvent'):
        event['details'].append('Label: ' + (node.get('label') or {}).get('name', 'unavailable'))
    elif kind in ('ReviewRequestedEvent', 'ReviewRequestRemovedEvent'):
        reviewer = node.get('requestedReviewer') or {}
        event['details'].append('Reviewer: ' + (reviewer.get('login') or reviewer.get('name') or 'unavailable'))
    elif kind == 'RenamedTitleEvent':
        event['details'].extend(['Before: ' + node.get('previousTitle', ''), 'After: ' + node.get('currentTitle', '')])
    elif kind == 'CrossReferencedEvent':
        source = node.get('source') or {}
        event.update(body=source.get('title', ''), url=source.get('url') or review_url)
    elif kind not in TIMELINE_FIELDS:
        event['details'].append('Additional details unavailable here; open the event link.')
    return event


# Use REST-compatible identity/version fields so opening an edit after a paged
# read has the same precondition as opening it after a full REST refresh.
FEEDBACK_MESSAGE_FIELDS = """fullDatabaseId body createdAt updatedAt url authorAssociation
  author { login __typename ... on User { databaseId } ... on Bot { databaseId } }
  viewerCanUpdate viewerCanReact reactionGroups { content reactors { totalCount } }"""
FEEDBACK_THREAD_FIELDS = """id path diffSide startDiffSide line startLine originalLine originalStartLine subjectType
  isOutdated isResolved resolvedBy { login } viewerCanReply viewerCanResolve viewerCanUnresolve
  comments(first:100) { totalCount pageInfo { hasNextPage endCursor } nodes { """ + FEEDBACK_MESSAGE_FIELDS + """
    diffHunk path originalCommit { oid } replyTo { fullDatabaseId } state pullRequestReview { fullDatabaseId } } }"""


FEEDBACK_PENDING_FIELDS = """reviews(first:100,states:[PENDING]) { totalCount nodes {
  id fullDatabaseId state body updatedAt url commit { oid }
  author { login } comments { totalCount }
} }"""


def private_feedback_inventory(pr, viewer, allow_pending):
    connection = pr.get('reviews') or {}
    nodes = connection.get('nodes')
    if not isinstance(nodes, list):
        raise Failure('Cannot verify private review inventory.', 'incomplete')
    if nodes and not allow_pending:
        raise Failure('A private review is pending. Refresh to load private feedback.', 'stale')
    if nodes and connection.get('totalCount') != len(nodes):
        raise Failure('Private review inventory is incomplete.', 'incomplete')
    actor = 'github-login:' + viewer.casefold()
    items = []
    for node in nodes:
        identity = str(node.get('fullDatabaseId', ''))
        author = (node.get('author') or {}).get('login', '')
        head = (node.get('commit') or {}).get('oid')
        total = (node.get('comments') or {}).get('totalCount')
        if (not identity.isdigit() or node.get('state') != 'PENDING' or author.casefold() != viewer.casefold()
                or not isinstance(head, str) or not head or type(total) is not int or total < 0
                or not isinstance(node.get('body'), str) or not isinstance(node.get('updatedAt'), str)):
            raise Failure('Private review identity, ownership or coverage is unavailable.', 'incomplete')
        version = hashlib.sha256(json.dumps([identity, author.casefold(), head, node['body'], node['updatedAt'], total]).encode()).hexdigest()
        body = normalize_comment({'id': int(identity), 'body': node['body'], 'user': {'login': author}}, 'PENDING')['body']
        summary = {'id': identity, 'kind': 'PENDING', 'body': body, 'author': author, 'created': '',
                   'publication': 'pending', 'pending_review': identity, 'actor': actor,
                   'capabilities': {'edit': {'enabled': False, 'reason': 'Verify the full private review before editing its summary.'}}}
        items.append({'id': identity, 'actor': actor, 'author': author, 'head': head, 'body': body,
                      'comments': [], 'total': total, 'complete': False, 'version': '', 'read_version': version,
                      'summary': summary, 'url': node.get('url', ''), 'state': 'pending'})
    if len({r['id'] for r in items}) != len(items):
        raise Failure('Repeated private review identity.', 'incomplete')
    return {'available': True, 'actor': actor, 'items': items, 'error': ''}


def private_feedback_targets(pending, threads):
    reviews = {r['id']: r for r in pending['items']}
    for thread in threads:
        for message in thread['comments']:
            identity = message.get('pending_review')
            if not identity:
                continue
            if identity not in reviews or message.get('actor') != pending['actor']:
                raise Failure('Private comment belongs to another review or actor.', 'stale')
            reviews[identity]['comments'].append({'message': message['id'], 'message_kind': message['kind'],
                'thread': thread['id'], 'path': thread['path'], 'side': thread['side'],
                'start': thread['start'], 'line': thread['line'], 'subject_type': thread['subject_type'],
                'body': message['body'], 'author': message['author']})
    if any(len(r['comments']) > r['total'] for r in reviews.values()):
        raise Failure('Private review coverage changed while loading.', 'stale')


def private_feedback_rules(threads, pending):
    for thread in threads:
        for message in thread['comments']:
            if message.get('publication') != 'pending':
                continue
            enabled = message.get('actor') == pending['actor'] and message['author'].casefold() == pending['actor'].split(':', 1)[1]
            native = message.pop('_private_can_edit', message.get('capabilities', {}).get('edit', {}).get('enabled', False))
            message['capabilities']['edit'] = {'enabled': enabled and native, 'reason': 'Private editing requires the verified author and current native permission.'}
            has_replies = message['id'] == thread['id'] and len(thread['comments']) > 1
            message['capabilities']['delete'] = {'enabled': enabled and native and not has_replies, 'scope': 'message',
                'reason': 'Root deletion with replies requires verified semantics.' if has_replies else 'Private deletion rechecks native permission before sending.'}
        if thread['comments'][0].get('publication') == 'pending':
            for action in ('reply', 'resolve', 'reopen'):
                thread['capabilities'][action] = {'enabled': False, 'reason': 'This thread is private. Use a private reply; resolve after publication.'}


def feedback_message(node, pending=False):
    if not isinstance(node, dict) or not str(node.get('fullDatabaseId', '')).isdigit():
        raise Failure('Feedback message has no stable database identity.', 'incomplete')
    author = node.get('author') or {}
    raw = {'id': int(node['fullDatabaseId']), 'body': node.get('body'),
           'created_at': node.get('createdAt'), 'updated_at': node.get('updatedAt'),
           'html_url': node.get('url', ''), 'author_association': node.get('authorAssociation'),
           'user': {'login': author.get('login', 'deleted')}}
    if author.get('databaseId') is not None:
        raw['user']['id'] = author['databaseId']
    if author.get('__typename') == 'Bot':
        raw['user']['type'] = 'Bot'
    groups = node.get('reactionGroups')
    if isinstance(groups, list):
        reaction_names = {'THUMBS_UP': '+1', 'THUMBS_DOWN': '-1', 'LAUGH': 'laugh', 'HOORAY': 'hooray',
                          'CONFUSED': 'confused', 'HEART': 'heart', 'ROCKET': 'rocket', 'EYES': 'eyes'}
        counts = dict.fromkeys(REACTIONS, 0)
        for group in groups:
            count = (group.get('reactors') or {}).get('totalCount')
            if group.get('content') not in reaction_names or type(count) is not int or count < 0:
                raise Failure('Incomplete feedback reaction counts.', 'incomplete')
            counts[reaction_names[group['content']]] = count
        raw['reactions'] = counts
    for field in ('body', 'created_at', 'updated_at'):
        if not isinstance(raw[field], str):
            raise Failure('Incomplete feedback message body or timestamps.', 'incomplete')
    result = normalize_comment(raw, pending=pending)
    result['_native_permissions'] = {name: node.get(field) is True for name, field in
                                     [('edit', 'viewerCanUpdate'), ('reaction', 'viewerCanReact')]}
    return result


def feedback_message_rules(messages, viewer):
    for message in messages:
        native = message.pop('_native_permissions', {name: message.get('capabilities', {}).get(name, {}).get('enabled', True) for name in ('edit', 'reaction')})
        message['capabilities'] = {'edit': {'enabled': bool(viewer) and message['author'].casefold() == viewer.casefold()
            and (message.get('publication') != 'pending' or (message.get('pending_review') and message.get('actor') == 'github-login:' + viewer.casefold())) and native.get('edit', True),
            'reason': 'Editing requires your published message and current GitHub permission. Native pending feedback uses its private workflow.'}}
        supported = message['kind'] == 'comment' and message.get('publication') != 'pending'
        message['capabilities']['reactions'] = {'enabled': supported}
        message['capabilities']['message_history'] = {'enabled': message.get('publication') != 'pending' and message.get('kind', 'comment') in ('comment', 'APPROVED', 'CHANGES_REQUESTED', 'COMMENTED', 'DISMISSED')}
        message['capabilities']['reaction'] = {'enabled': supported and bool(viewer) and native.get('reaction', True),
            'reason': 'Reactions require a published message, verified actor and current GitHub permission.'}


def published_delete_rules(threads, conversation, viewer):
    actor = 'github-login:' + viewer.casefold() if viewer else ''
    for thread, messages in [(None, conversation)] + [(t, t['comments']) for t in threads]:
        for message in messages:
            root_with_replies = bool(thread and thread['id'] == message['id'] and len(messages) > 1)
            message['capabilities']['delete_message'] = {
                'enabled': bool(actor) and message['author'].casefold() == viewer.casefold()
                    and message.get('publication') != 'pending' and message.get('kind') == 'comment' and not root_with_replies,
                'scope': 'message', 'actor': actor,
                'reason': 'Root deletion with replies needs verified GitHub scope; inspect it on GitHub.' if root_with_replies else
                    'Only your published comments are supported; current GitHub delete permission is checked before sending.'}


def feedback_connection(connection, after=None):
    if not isinstance(connection, dict) or not isinstance(connection.get('nodes'), list):
        raise Failure('Incomplete feedback connection.', 'incomplete')
    info = connection.get('pageInfo')
    if not isinstance(info, dict) or type(info.get('hasNextPage')) is not bool:
        raise Failure('Incomplete feedback page information.', 'incomplete')
    more = info['hasNextPage']
    cursor = info.get('endCursor')
    if more and (not isinstance(cursor, str) or not cursor or cursor == after or not connection['nodes']):
        raise Failure('Feedback pagination did not advance.', 'incomplete')
    return connection['nodes'], cursor if more else None


def original_source(thread):
    fields = {k: thread.get(k, '') for k in ('id', 'original_path', 'original_side', 'original_start_side',
              'original_commit_id', 'original_line', 'original_start_line', 'subject_type', 'hunk')}
    token = hashlib.sha256(json.dumps(fields, sort_keys=True).encode()).hexdigest()
    valid = bool(re.fullmatch(r'[0-9a-fA-F]{40}|[0-9a-fA-F]{64}', str(fields['original_commit_id'])))
    valid = valid and (fields['subject_type'] == 'file' or (type(fields['original_line']) is int and fields['original_line'] > 0))
    source = {'token': token, 'available': valid, 'label': 'Inspect original code context',
              'reason': '' if valid else 'GitHub did not supply an original commit and source location.'}
    if isinstance(thread.get('native_id'), str) and thread['native_id']:
        source['lookup'] = thread['native_id']
    return source


def original_hunk_rows(hunk, side):
    rows = {}
    before = after = None
    for line in hunk.splitlines():
        header = re.match(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@', line)
        if header:
            before, after = map(int, header.groups())
            continue
        if before is None or not line or line[0] not in (' ', '+', '-'):
            continue
        if side == 'base' and line[0] in (' ', '-'):
            rows[before] = line[1:]
        if side == 'head' and line[0] in (' ', '+'):
            rows[after] = line[1:]
        if line[0] != '+':
            before += 1
        if line[0] != '-':
            after += 1
    return rows


def reaction_actor(user):
    return 'github:' + str(user['id']) if user.get('id') is not None else 'github-login:' + user['login'].casefold() if user.get('login') else ''


def review_inventory(files, threads, conversation, pending, viewer, state_error, orphaned):
    """Coverage of normalized, accessible data; private access is independent."""
    public = [t for t in threads if t['comments'][0].get('publication') != 'pending']
    feedback_reason = 'Some replies have no available root discussion.' if orphaned else ''
    if viewer and not pending['available']:
        feedback_reason = (feedback_reason + ' Private feedback could not be fully loaded.').strip()
    result = {
        'files': {'state': 'complete', 'total': len(files), 'scope': 'Selected comparison'},
        'threads': {'state': 'partial' if feedback_reason else 'complete',
                    'scope': 'Public threads and accessible private comments', 'reason': feedback_reason},
        'conversation': {'state': 'complete', 'total': len(conversation),
                         'scope': 'General comments and published reviews; excludes system events'},
        'private': {'state': 'complete' if pending['available'] else 'failed' if viewer else 'unknown',
                    'scope': 'Signed-in actor only', 'reason': pending.get('error', '')},
        'thread_state': {'state': 'failed' if state_error else 'complete' if all('resolved' in t for t in public) else 'partial',
                         'total': len(public), 'scope': 'Published threads',
                         'reason': state_error or ('' if all('resolved' in t for t in public) else 'Some discussion states are unavailable.')}}
    if not feedback_reason:
        result['threads']['total'] = len(threads)
    if pending['available']:
        result['private']['total'] = len(pending['items'])
    return result


def reaction_groups(entries, actor):
    result = []
    for content, label in REACTIONS.items():
        matches = [r for r in entries if r.get('content') == content]
        people = []
        unavailable = 0
        seen = set()
        for reaction in matches:
            user = reaction.get('user') or {}
            identity = reaction_actor(user)
            login = user.get('login')
            if not identity or not isinstance(login, str) or not login:
                unavailable += 1
                continue
            if identity in seen:
                raise Failure('Reaction membership changed while loading; reload the list.', 'incomplete')
            seen.add(identity)
            people.append({'id': identity, 'label': login})
        item = {'id': content, 'label': label, 'count': len(matches),
                'members': {'items': people, 'unavailable': unavailable}}
        if actor:
            item['mine'] = any(reaction_actor(r.get('user') or {}) == actor for r in matches)
        result.append(item)
    return result


def pending_record(review, comments, actor):
    targets = []
    for comment in comments:
        normalized = normalize_comment(comment, pending=True)
        targets.append({'message': normalized['id'], 'message_kind': 'comment',
                        'thread': str(comment.get('in_reply_to_id') or comment['id']),
                        'path': comment.get('path', ''), 'side': 'base' if comment.get('side') == 'LEFT' else 'head',
                        'start': comment.get('start_line') or comment.get('line') or 0,
                        'line': comment.get('line') or 0, 'subject_type': comment.get('subject_type', 'line'),
                        'body': normalized['body'], 'author': normalized['author']})
    version = {'review': {k: review.get(k) for k in ('id', 'body', 'state', 'commit_id')},
               'comments': [{k: c.get(k) for k in ('id', 'body', 'updated_at', 'path', 'side', 'line', 'start_line', 'subject_type', 'in_reply_to_id')}
                            for c in sorted(comments, key=lambda c: c['id'])]}
    summary = normalize_comment(review, 'PENDING')
    summary.update(pending_review=str(review['id']), actor=actor, capabilities={'edit': {'enabled': True, 'body_required': False}})
    return {'summary': summary, 'id': str(review['id']), 'actor': actor, 'author': (review.get('user') or {}).get('login', ''),
            'head': review.get('commit_id', ''), 'body': normalize_comment(review, 'PENDING')['body'],
            'version': hashlib.sha256(json.dumps(version, sort_keys=True).encode()).hexdigest(),
            'comments': targets, 'url': review.get('html_url', ''), 'state': 'pending'}


class RenderedLinks(HTMLParser):
    """Read anchors from provider-rendered HTML without loading any resources."""
    def __init__(self, base):
        super().__init__(convert_charrefs=True)
        self.base, self.active, self.links = base, None, []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'a':
            href = attrs.get('href', '')
            try:
                url = urllib.parse.urljoin(self.base, href)
                parsed = urllib.parse.urlsplit(url)
            except ValueError:
                self.active = None
                return
            safe = parsed.scheme in ('http', 'https') and bool(parsed.netloc) and not re.search(r'[\s<>"`\x00-\x1f]', url)
            self.active = {'url': url, 'label': ''} if safe and href and attrs.get('aria-hidden') != 'true' else None
        elif tag == 'img' and self.active is not None:
            self.active['label'] += attrs.get('alt', '')

    def handle_data(self, text):
        if self.active is not None: self.active['label'] += text

    def handle_endtag(self, tag):
        if tag == 'a' and self.active is not None:
            item = self.active
            item['label'] = ' '.join(item['label'].split()) or item['url']
            if item not in self.links: self.links.append(item)
            self.active = None


class Failure(Exception):
    def __init__(self, message, code="error", unknown=False):
        super().__init__(message)
        self.code = code
        self.unknown = unknown


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if urllib.parse.urlparse(req.full_url).netloc != urllib.parse.urlparse(newurl).netloc:
            raise Failure("GitHub redirected to a different host; open this resource in your browser.")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def connection(value, cwd):
    value = value.strip()
    if not value:
        proc = subprocess.run(["git", "-C", cwd, "remote", "get-url", "origin"],
                              capture_output=True, text=True)
        if proc.returncode:
            raise Failure("No origin remote. Use :Reviews owner/repo or :Reviews https://HOST/owner/repo.")
        value = proc.stdout.strip()
    number = None
    if re.fullmatch(r"[\w.-]+/[\w.-]+", value):
        host, repo = "github.com", value
    else:
        match = re.fullmatch(r"(?:[^@/]+@)?([^:/]+):([^ ]+)", value)
        if match and "://" not in value:
            host, repo = match.groups()
        else:
            url = urllib.parse.urlparse(value)
            if url.scheme not in ("https", "ssh") or not url.hostname:
                raise Failure("Expected owner/repo or a GitHub repository/PR URL.")
            host, repo = url.hostname, url.path.strip("/")
        parts = repo.split("/")
        if len(parts) >= 4 and parts[2] == "pull" and parts[3].isdigit():
            number, repo = int(parts[3]), "/".join(parts[:2])
    repo = repo.removesuffix(".git")
    if not re.fullmatch(r"[A-Za-z0-9.-]+", host) or not re.fullmatch(r"[\w.-]+/[\w.-]+", repo):
        raise Failure("Invalid GitHub host or owner/repository.")
    return {"host": host, "repo": repo, "number": number}


def token_for(host):
    token = os.environ.get("GH_TOKEN", os.environ.get("GITHUB_TOKEN", "")) if host == "github.com" else ""
    if token:
        return token
    try:
        proc = subprocess.run(["gh", "auth", "token", "--hostname", host],
                              capture_output=True, text=True, timeout=10)
        return proc.stdout.strip() if proc.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


class GitHub:
    def __init__(self, conn, token=None):
        self.conn = conn
        self.repo = conn["repo"]
        host = conn["host"]
        if not re.fullmatch(r"[A-Za-z0-9.-]+", host) or not re.fullmatch(r"[\w.-]+/[\w.-]+", self.repo):
            raise Failure("Invalid connection")
        self.root = "https://api.github.com" if host == "github.com" else "https://" + host + "/api/v3"
        self.token = token_for(host) if token is None else token

    def action_rules(self, pr):
        """Known actor restrictions; the API still authorizes each actual write."""
        enabled = bool(self.token)
        reason = '' if enabled else 'Sign in to GitHub before publishing feedback.'
        viewer = ''
        if enabled:
            try:
                actor = self.api('user')
                viewer = actor.get('login', '') if isinstance(actor, dict) else ''
            except Failure:
                # Reading a public review must remain possible when actor lookup fails.
                viewer = ''
        rules = {kind: {'enabled': enabled, 'body_required': True, 'reason': reason,
                        'permission_check': 'submission'}
                 for kind in ('comment', 'file_comment', 'reply', 'conversation', 'review')}
        rules['suggestion'] = {'enabled': enabled, 'reason': reason, 'sides': ['head']}
        rules['comment']['anchors'] = {
            'scope': 'diff', 'sides': ['base', 'head'],
            'reason': 'Creating comments outside diff hunks is not verified for this GitHub API adapter. Open the review in GitHub, or use :RevueFileComment for whole-file feedback.'}
        rules['batch'] = {'enabled': enabled, 'body_required': False, 'reason': reason,
                          'mode': 'atomic', 'kinds': ['comment', 'review'], 'max_reviews': 1,
                          'review_body_optional_with_comments': True, 'default_label': 'Comment review'}
        actions = []
        author = pr.get('user', {}).get('login', '')
        for event, label in [('COMMENT', 'Comment'), ('APPROVE', 'Approve'), ('REQUEST_CHANGES', 'Request changes')]:
            available, why = enabled, reason
            if event != 'COMMENT' and enabled:
                if not viewer:
                    available, why = False, 'Cannot verify the current GitHub actor; refresh after signing in.'
                elif viewer.casefold() == author.casefold():
                    available, why = False, 'Authors cannot approve or request changes on their own pull request.'
            actions.append({'id': event, 'label': label, 'enabled': available, 'reason': why,
                            'body_required': event != 'APPROVE'})
        return rules, actions, viewer

    def api(self, path, method="GET", body=None, raw=False, graphql=False):
        if method != "GET" and not self.token:
            raise Failure("Sign in first: gh auth login --hostname " + self.conn["host"] + " --web", "auth")
        headers = {"Accept": "application/vnd.github.raw+json" if raw else "application/vnd.github+json",
                   "User-Agent": "vim-code-review-github", "X-GitHub-Api-Version": "2022-11-28"}
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        data = None if body is None else json.dumps(body).encode()
        if data is not None:
            headers["Content-Type"] = "application/json"
        url = self.root + "/" + path.lstrip("/")
        if graphql:
            url = (self.root[:-len('/api/v3')] + '/api/graphql') if self.root.endswith('/api/v3') else self.root + '/graphql'
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.build_opener(SafeRedirect()).open(req, timeout=35) as response:
                content = response.read(8 * 1024 * 1024 + 1)
                if len(content) > 8 * 1024 * 1024:
                    raise Failure("Resource exceeds the 8 MiB viewing limit.", "too_large")
                return content if raw else json.loads(content or b"null")
        except urllib.error.HTTPError as exc:
            try:
                message = json.loads(exc.read()).get("message", str(exc))
            except (ValueError, AttributeError):
                message = str(exc)
            if exc.code in (401, 403, 429):
                message += "; check gh auth login and GitHub API rate limits"
            raise Failure(message, str(exc.code), method != "GET" and exc.code >= 500) from exc
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
            raise Failure("GitHub request failed: " + str(exc), "transport", method != "GET") from exc

    def graphql(self, query, variables, write=False):
        try:
            result = self.api('', 'POST', {'query': query, 'variables': variables}, graphql=True)
        except Failure as error:
            if not write:
                error.unknown = False
            elif error.code == 'too_large':
                error.unknown = True
            raise
        if not isinstance(result, dict) or result.get('errors') or not isinstance(result.get('data'), dict) or not result['data']:
            errors = result.get('errors', []) if isinstance(result, dict) else []
            message = '; '.join(str(e.get('message', 'GraphQL error')) for e in errors if isinstance(e, dict)) if isinstance(errors, list) else ''
            raise Failure(message or 'Incomplete GitHub GraphQL response', 'graphql', write)
        return result['data']

    def thread_states(self, number):
        if not self.token:
            raise Failure('Sign in to load thread resolution and permissions.', 'auth')
        owner, repo = self.repo.split('/')
        query = '''query($owner:String!, $repo:String!, $number:Int!, $after:String) {
          repository(owner:$owner, name:$repo) { pullRequest(number:$number) {
            reviewThreads(first:100, after:$after) { pageInfo { hasNextPage endCursor }
              nodes { id isResolved isOutdated viewerCanReply viewerCanResolve viewerCanUnresolve
                resolvedBy { login } comments(first:1) { nodes { databaseId } } }
            } } } }'''
        cursor = None
        states = {}
        for _ in range(100):
            data = self.graphql(query, {'owner': owner, 'repo': repo, 'number': int(number), 'after': cursor})
            try:
                connection = data['repository']['pullRequest']['reviewThreads']
                for node in connection['nodes']:
                    if any(type(node.get(key)) is not bool for key in ('isResolved', 'isOutdated', 'viewerCanReply', 'viewerCanResolve', 'viewerCanUnresolve')) or not node.get('id'):
                        raise ValueError('Missing thread permissions')
                    comments = node['comments']['nodes']
                    if not comments or comments[0].get('databaseId') is None:
                        continue
                    states[str(comments[0]['databaseId'])] = {
                        'native_id': node['id'], 'resolved': node['isResolved'],
                        'resolved_by': (node.get('resolvedBy') or {}).get('login', ''),
                        'outdated': node['isOutdated'],
                        'capabilities': {name: {'enabled': node[key], 'reason': '' if node[key] else 'GitHub does not allow this action on the thread.'}
                                         for name, key in [('reply', 'viewerCanReply'), ('resolve', 'viewerCanResolve'), ('reopen', 'viewerCanUnresolve')]}}
                page = connection['pageInfo']
                if not page['hasNextPage']:
                    return states
                if not page.get('endCursor') or page['endCursor'] == cursor:
                    raise ValueError('Invalid thread pagination cursor')
                cursor = page['endCursor']
            except (KeyError, TypeError, ValueError) as error:
                raise Failure('Incomplete GitHub thread state: ' + str(error), 'incomplete') from error
        raise Failure('Thread inventory exceeds the supported page limit.', 'incomplete')

    def pages(self, path):
        result = []
        for page in range(1, 101):
            values = self.api(path + ("&" if "?" in path else "?") + "per_page=100&page=" + str(page))
            if not isinstance(values, list):
                raise Failure("Expected a paginated GitHub list")
            result.extend(values)
            if len(values) < 100:
                return result
        raise Failure("The result exceeds 10,000 entries. Narrow the query.", "too_large")

    def list(self, request):
        page = max(1, int(request.get("page", 1)))
        query = request.get("query", "").strip()
        if query:
            q = urllib.parse.urlencode({"q": "repo:" + self.repo + " is:pr " + query,
                                       "sort": "updated", "order": "desc", "per_page": 30, "page": page})
            data = self.api("search/issues?" + q)
            items = data["items"]
            more = page * 30 < min(data["total_count"], 1000)
        else:
            items = self.api("repos/" + self.repo + "/pulls?state=open&sort=updated&direction=desc&per_page=30&page=" + str(page))
            more = len(items) == 30
        return {"connection": self.conn, "authenticated": bool(self.token), "page": page, "more": more,
                "items": [{"id": p["number"], "title": p["title"], "author": p["user"]["login"],
                           "url": p["html_url"], "draft": p.get("draft", False), "state": p["state"]} for p in items]}

    def open(self, number, incremental=False):
        prefix = "repos/" + self.repo
        pr = self.api(prefix + "/pulls/" + str(number))
        tasks = {
            "files": prefix + "/pulls/" + str(number) + "/files",
            "comments": prefix + "/pulls/" + str(number) + "/comments",
            "conversation": prefix + "/issues/" + str(number) + "/comments",
            "reviews": prefix + "/pulls/" + str(number) + "/reviews",
        }
        paged = bool(incremental and self.token)
        initial_tasks = {k: path for k, path in tasks.items() if not paged or k in ('files', 'reviews')}
        base_tip, head = pr["base"]["sha"], pr["head"]["sha"]
        # These reads depend only on the initial PR identity. Bound concurrency,
        # then retain the source/actor checks before exposing any combined view.
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            futures = {key: pool.submit(self.pages, path) for key, path in initial_tasks.items()}
            comparison_read = pool.submit(self.api, prefix + "/compare/" + base_tip + "..." + head + "?per_page=1")
            actor_read = pool.submit(self.action_rules, pr)
            values = {key: future.result() for key, future in futures.items()}
            comparison = comparison_read.result()
            rules, actions, viewer = actor_read.result()
        page = None
        paging_error = ''
        base = comparison["merge_base_commit"]["sha"]
        fresh = self.api(prefix + "/pulls/" + str(number))
        if fresh["head"]["sha"] != head or fresh["base"]["sha"] != base_tip:
            raise Failure("PR changed while loading. Refresh to load a coherent revision.", "stale")
        if paged:
            try:
                page = self.feedback_page({'number': number, 'cursor': '', 'allow_pending': True, 'review_count': sum(r.get('state') != 'PENDING' for r in values['reviews']), 'reference':
                    {'snapshot': base + ':' + head, 'base': base, 'head': head, 'base_tip': base_tip}})
                if {str(r['id']) for r in values['reviews'] if r.get('state') == 'PENDING'} != {r['id'] for r in page['pending_reviews']['items']}:
                    raise Failure('Private review inventory changed while opening. Refresh.', 'stale')
            except Failure as error:
                # Unsupported schema/access and changed private state fall back
                # to the complete reader, never to an empty partial review.
                paging_error = str(error)
                page = None
        if page is None:
            if paging_error:
                values['reviews'] = self.pages(tasks['reviews'])
            missing = {k: path for k, path in tasks.items() if k not in values}
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                futures = {key: pool.submit(self.pages, path) for key, path in missing.items()}
                values.update({key: future.result() for key, future in futures.items()})
        else:
            values['comments'], values['conversation'] = [], []
        files = []
        for f in values["files"]:
            files.append({"id": f["filename"], "path": f["filename"], "old_path": f.get("previous_filename", f["filename"]),
                          "status": f["status"], "patch": f.get("patch", ""), "additions": f["additions"], "deletions": f["deletions"]})
        if pr.get("changed_files", len(files)) != len(files):
            raise Failure("GitHub did not return the complete changed-file list; open the PR in your browser.", "incomplete")
        if page is not None and page['viewer'] != viewer:
            raise Failure('Signed-in actor changed while loading feedback. Refresh.', 'stale')
        pending_reviews = {r['id'] for r in values['reviews'] if r.get('state') == 'PENDING'}
        actor = 'github-login:' + viewer.casefold() if viewer else ''
        pending = {'available': bool(viewer), 'actor': actor, 'items': [], 'error': '' if viewer else 'Cannot verify the signed-in actor; pending review state is unavailable.'}
        # A review-specific read discovers private comments not present in the PR list.
        comments_by_id = {c['id']: c for c in values['comments'] if c.get('pull_request_review_id') not in pending_reviews}
        for review in ([] if page is not None else values['reviews']):
            if review.get('state') != 'PENDING' or not viewer or (review.get('user') or {}).get('login', '').casefold() != viewer.casefold():
                continue
            try:
                loaded, private = self.load_pending(number, str(review['id']))
                if (loaded.get('user') or {}).get('login', '').casefold() != viewer.casefold():
                    raise Failure('Pending review ownership changed while loading.', 'stale')
                pending['items'].append(pending_record(loaded, private, actor))
                comments_by_id.update({c['id']: c for c in private})
            except Failure as error:
                pending['available'], pending['error'] = False, str(error)
        if page is not None:
            pending = page['pending_reviews']
        comments = list(comments_by_id.values())
        roots = {c["id"]: c for c in comments if not c.get("in_reply_to_id")}
        threads = []
        for root_id, c in roots.items():
            replies = [r for r in comments if r.get("in_reply_to_id") == root_id]
            file_comment = c.get('subject_type') == 'file'
            threads.append({"id": str(root_id), "path": c["path"], "subject_type": 'file' if file_comment else 'line',
                            "side": '' if file_comment else "base" if c.get("side") == "LEFT" else "head",
                            "line": 0 if file_comment else c.get("line") or 0, "start": 0 if file_comment else c.get("start_line") or c.get("line") or 0,
                            "outdated": c['path'] not in {f['path'] for f in files} if file_comment else c.get("line") is None, "original_line": c.get("original_line") or 0,
                            "original_start_line": c.get("original_start_line") or c.get("original_line") or 0,
                            "original_commit_id": c.get("original_commit_id", ""),
                            'original_path': c['path'],
                            'original_side': 'base' if c.get('side') == 'LEFT' else 'head',
                            'original_start_side': 'base' if (c.get('start_side') or c.get('side')) == 'LEFT' else 'head',
                            "hunk": c.get("diff_hunk", ""), "comments": [normalize_comment(x, pending=x.get('pull_request_review_id') in pending_reviews) for x in [c] + replies]})
        if page is not None:
            threads = page['threads']
        conversation = [normalize_comment(c) for c in values["conversation"]]
        if page is not None:
            conversation.extend(page['conversation'])
        conversation.extend(normalize_comment(c, c.get("state", "review")) for c in values["reviews"]
                            if c.get("state") != "PENDING")
        conversation.sort(key=lambda c: c["created"])
        key = self.conn["host"] + "/" + self.repo + "/" + str(number)
        state_error = ''
        try:
            states = {} if page is not None else self.thread_states(number)
            for thread in threads:
                if thread['id'] in states:
                    thread.update(states[thread['id']])
        except Failure as error:
            state_error = str(error)
        for thread in threads:
            thread['original_source'] = original_source(thread)
            enabled = bool(viewer) and pending['available'] and bool(thread.get('native_id')) and thread.get('capabilities', {}).get('pending_reply' if page is not None else 'reply', {}).get('enabled', False)
            thread.setdefault('capabilities', {})['pending_reply'] = {'enabled': enabled, 'reason': '' if enabled else 'Private replies require a verified actor and current thread reply permission.'}
            if thread['comments'] and thread['comments'][0].get('publication') == 'pending':
                thread.setdefault('capabilities', {}).update({action: {'enabled': False, 'reason': 'This thread is private pending feedback. Use a private reply; resolution is available after publication.'}
                                                              for action in ('reply', 'resolve', 'reopen')})
        rules['comparisons'] = {'enabled': True}
        rules['feedback_refresh'] = {'enabled': bool(self.token), 'scope': 'One feedback page including private threads; files and reviews load separately', 'reason': paging_error or ''}
        rules['verify_pending'] = {'enabled': bool(self.token), 'reason': 'Sign in to verify a complete private review.'}
        rules['feedback_page'] = {'enabled': page is not None, 'reason': paging_error or 'The complete feedback inventory was loaded.'}
        rules['feedback_lookup'] = {'enabled': bool(self.token), 'requires_token': True, 'current_only': True}
        rules['timeline'] = {'enabled': bool(self.token), 'reason': '' if self.token else 'Sign in to load GitHub timeline history; use the review URL to read it in a browser.'}
        rules['service_progress'] = {'enabled': bool(self.token)}
        rules['service_viewed'] = {'enabled': bool(self.token), 'body_required': False}
        rules['readiness'] = {'enabled': bool(self.token), 'reason': '' if self.token else 'Sign in to inspect GitHub checks and review requirements.'}
        rules['thread_context'] = {'enabled': True}
        rules['comparison_range'] = {'enabled': True, 'sides': ['base', 'head'],
                                     'semantics': 'Exact endpoints when the start is the merge base (ancestor); other ranges are reported unsupported.'}
        rules['thread_state'] = {'enabled': not bool(state_error), 'body_required': False, 'reason': state_error}
        rules['edit'] = {'enabled': bool(viewer), 'body_required': True, 'reason': 'A verified GitHub actor is required to edit feedback.'}
        rules['reactions'] = {'enabled': True}
        rules['rendered_links'] = {'enabled': bool(self.token), 'reason': 'Sign in to read GitHub-rendered link destinations.'}
        rules['message_history'] = {'enabled': bool(self.token), 'reason': 'Sign in to read GitHub edit history; the message link remains available.'}
        rules['reaction'] = {'enabled': bool(viewer), 'body_required': False, 'reason': 'A verified GitHub actor is required to change reactions.'}
        rules['pending_reviews'] = {'enabled': True}
        rules['start_pending'] = {'enabled': bool(viewer) and pending['available'], 'body_required': False, 'reason': pending['error']}
        rules['save_pending'] = {'enabled': bool(viewer) and pending['available'], 'kinds': ['comment', 'file_comment', 'reply'], 'reason': pending['error']}
        rules['stage_batch'] = {'enabled': bool(viewer) and pending['available'], 'mode': 'sequential', 'min_interval_ms': 1000, 'kinds': ['comment', 'file_comment', 'reply'], 'reason': pending['error']}
        rules['edit_pending'] = {'enabled': bool(viewer) and pending['available'], 'reason': pending['error']}
        rules['reanchor_draft'] = {'enabled': True, 'kinds': ['comment', 'file_comment']}
        rules['delete_message'] = {'enabled': bool(viewer), 'body_required': False, 'reason': 'Sign in to delete your published comments.'}
        rules['delete_pending_comment'] = {'enabled': bool(viewer) and pending['available'], 'body_required': False, 'reason': pending['error']}
        rules['discard_pending'] = {'enabled': bool(viewer) and pending['available'], 'body_required': False, 'reason': pending['error']}
        rules['submit_pending'] = {'enabled': bool(viewer) and pending['available'], 'body_required': False, 'reason': pending['error']}
        feedback_message_rules(conversation + [c for t in threads for c in t['comments']], viewer)
        published_delete_rules(threads, conversation, viewer)
        if page is not None:
            private_feedback_rules(threads, pending)
        private_ids = {c['message']: r['id'] for r in pending['items'] for c in r['comments']} if page is None else {}
        for message in [c for t in threads for c in t['comments']]:
            if message['id'] in private_ids:
                message.update(pending_review=private_ids[message['id']], actor=actor)
                message['capabilities']['edit'] = {'enabled': pending['available'] and bool(viewer) and message['author'].casefold() == viewer.casefold(),
                    'reason': 'Editing private feedback requires its verified author and a current pending review.'}
        for thread in threads:
            for message in thread['comments']:
                if message['id'] not in private_ids:
                    continue
                has_replies = message['id'] == thread['id'] and len(thread['comments']) > 1
                enabled = message['capabilities']['edit']['enabled'] and not has_replies
                message['capabilities']['delete'] = {'enabled': enabled, 'scope': 'message',
                    'reason': 'Root deletion with replies needs verified GitHub semantics; open GitHub to inspect it.' if has_replies else
                              'Only your own verified private comments can be deleted here.'}
        snapshot = {"version": 1, "key": key, "number": number, "display_id": "#" + str(number),
                "review_actions": actions, "capabilities": rules, "viewer": viewer,
                "pending_reviews": pending,
                'inventory': review_inventory(files, threads, conversation, pending, viewer, state_error,
                                              any(c.get('in_reply_to_id') and c['in_reply_to_id'] not in roots for c in comments)),
                "thread_state_error": state_error,
                "title": pr["title"], "body": (pr.get("body") or "").replace("\r\n", "\n"),
                "author": pr["user"]["login"], "url": pr["html_url"], "state": "merged" if pr.get("merged") else pr["state"],
                "base": base, "base_tip": base_tip, "head": head, "snapshot": base + ":" + head,
                "head_repo": (pr["head"].get("repo") or {}).get("full_name", self.repo),
                "reviewers": [r["login"] for r in pr.get("requested_reviewers", [])],
                "files": files, "threads": threads, "conversation": conversation, "authenticated": bool(self.token)}

        if page is not None:
            snapshot['feedback'] = {'cursor': page['next_cursor']}
            snapshot['inventory'].update(page['inventory'])
        if paging_error:
            snapshot['feedback_loading_note'] = 'Loaded the complete inventory after paging was unavailable: ' + paging_error
        # Successful paging already rechecks source, actor and private state
        # after all nested reads. Everything since that guard is local projection;
        # only the complete-reader fallback still needs the final REST check.
        if incremental and page is None:
            final = self.api(prefix + '/pulls/' + str(number))
            if final['head']['sha'] != head or final['base']['sha'] != base_tip:
                raise Failure('PR changed while loading. Refresh to load a coherent revision.', 'stale')
        return snapshot

    @staticmethod
    def comparison_reference(snapshot, label=''):
        return {key: snapshot[key] for key in ('snapshot', 'base', 'head', 'base_tip', 'head_repo', 'base_repo', 'range', 'context') if key in snapshot} | {'label': label}

    def feedback_thread(self, node, pending=None):
        if not isinstance(node, dict) or not isinstance(node.get('id'), str):
            raise Failure('Incomplete feedback thread identity.', 'incomplete')
        messages, after = feedback_connection(node.get('comments'))
        messages = list(messages)
        seen_cursors = set()
        while after:
            if after in seen_cursors or len(seen_cursors) >= 100:
                raise Failure('A discussion exceeds the supported reply-page limit; open GitHub.', 'incomplete')
            seen_cursors.add(after)
            query = 'query($id:ID!, $after:String!){node(id:$id){... on PullRequestReviewThread { comments(first:100,after:$after){totalCount pageInfo{hasNextPage endCursor} nodes{' + FEEDBACK_MESSAGE_FIELDS + ' diffHunk path originalCommit{oid} replyTo{fullDatabaseId} state pullRequestReview{fullDatabaseId}}}}}}'
            result = self.graphql(query, {'id': node['id'], 'after': after})
            extra, after = feedback_connection((result.get('node') or {}).get('comments'), after)
            messages.extend(extra)
        if not messages or any(not isinstance(m, dict) or m.get('state') not in (('SUBMITTED', 'PENDING') if pending is not None else ('SUBMITTED',)) for m in messages):
            raise Failure('Private or unavailable feedback changed during paging; refresh the review.', 'stale')
        ids = [str(m.get('fullDatabaseId', '')) for m in messages]
        if len(set(ids)) != len(ids) or messages[0].get('replyTo') or any(str((m.get('replyTo') or {}).get('fullDatabaseId')) != ids[0] for m in messages[1:]):
            raise Failure('Discussion replies have inconsistent root identities; refresh the review.', 'incomplete')
        total = node['comments'].get('totalCount')
        if type(total) is not int or total != len(messages):
            raise Failure('Discussion changed while loading its replies; refresh the review.', 'stale')
        for field in ('isOutdated', 'isResolved', 'viewerCanReply', 'viewerCanResolve', 'viewerCanUnresolve'):
            if type(node.get(field)) is not bool:
                raise Failure('Incomplete feedback thread state.', 'incomplete')
        if node.get('subjectType') not in ('LINE', 'FILE') or (node['subjectType'] != 'FILE' and node.get('diffSide') not in ('LEFT', 'RIGHT')):
            raise Failure('Incomplete feedback anchor.', 'incomplete')
        if not isinstance(node.get('path'), str) or not isinstance(messages[0].get('path'), str):
            raise Failure('Incomplete feedback file identity.', 'incomplete')
        for field in ('line', 'startLine', 'originalLine', 'originalStartLine'):
            if node.get(field) is not None and (type(node[field]) is not int or node[field] < 0):
                raise Failure('Invalid feedback source coordinates.', 'incomplete')
        file_comment = node['subjectType'] == 'FILE'
        root = messages[0]
        side = 'base' if node.get('diffSide') == 'LEFT' else 'head'
        thread = {'id': ids[0], 'native_id': node['id'], 'path': node['path'],
                  'subject_type': 'file' if file_comment else 'line', 'side': '' if file_comment else side,
                  'line': 0 if file_comment else node.get('line') or 0,
                  'start': 0 if file_comment else node.get('startLine') or node.get('line') or 0,
                  'outdated': node['isOutdated'], 'resolved': node['isResolved'],
                  'resolved_by': (node.get('resolvedBy') or {}).get('login', ''),
                  'original_line': node.get('originalLine') or 0,
                  'original_start_line': node.get('originalStartLine') or node.get('originalLine') or 0,
                  'original_commit_id': (root.get('originalCommit') or {}).get('oid', ''),
                  'original_path': root['path'], 'original_side': side,
                  'original_start_side': 'base' if (node.get('startDiffSide') or node.get('diffSide')) == 'LEFT' else 'head',
                  'hunk': root.get('diffHunk', ''), 'comments': [feedback_message(m, m.get('state') == 'PENDING') for m in messages],
                  'capabilities': {name: {'enabled': node[field], 'reason': '' if node[field] else 'GitHub does not allow this thread action.'}
                                   for name, field in [('reply', 'viewerCanReply'), ('resolve', 'viewerCanResolve'), ('reopen', 'viewerCanUnresolve')]}}
        for raw, message in zip(messages, thread['comments']):
            if raw.get('state') == 'PENDING':
                review_id = str((raw.get('pullRequestReview') or {}).get('fullDatabaseId', ''))
                if pending is None or review_id not in {r['id'] for r in pending['items']} or message['author'].casefold() != pending['actor'].split(':', 1)[1]:
                    raise Failure('Private comment review or author changed while paging.', 'stale')
                message.update(pending_review=review_id, actor=pending['actor'], _private_can_edit=raw.get('viewerCanUpdate') is True)
        thread['original_source'] = original_source(thread)
        thread['capabilities']['pending_reply'] = {'enabled': node['viewerCanReply'], 'reason': 'Private replies require current thread reply permission.'}
        return thread

    def feedback_lookup(self, request):
        target, reference = request.get('target', {}), request.get('reference', {})
        try:
            ref = {k: reference[k] for k in ('snapshot', 'base', 'head', 'base_tip')}
            if (target.get('kind') != 'thread' or target.get('message_kind') != 'comment'
                    or any(not isinstance(target.get(k), str) or not target[k] for k in ('thread', 'message', 'lookup'))
                    or len(target['lookup']) > 1024 or ref['snapshot'] != ref['base'] + ':' + ref['head']
                    or any(not re.fullmatch(r'[0-9a-f]{40}', ref[k]) for k in ('base', 'head', 'base_tip'))
                    or 'context' in reference or 'range' in reference):
                raise ValueError()
        except (KeyError, TypeError, AttributeError, ValueError):
            raise Failure('Discussion lookup needs a native thread and current PR comparison.', 'validation')
        query = 'query($id:ID!){viewer{login} node(id:$id){... on PullRequestReviewThread{' + FEEDBACK_THREAD_FIELDS + ' pullRequest{number repository{nameWithOwner} headRefOid baseRefOid updatedAt ' + FEEDBACK_PENDING_FIELDS + '}}}}'
        result = self.graphql(query, {'id': target['lookup']})
        node = result.get('node') if isinstance(result, dict) else None
        if not isinstance(node, dict):
            raise Failure('This discussion is unavailable in the requested review.', 'unavailable')
        pr = node.get('pullRequest') or {}
        if (not isinstance(pr, dict) or not isinstance(pr.get('repository'), dict)
                or not isinstance(pr['repository'].get('nameWithOwner'), str)
                or node.get('id') != target['lookup'] or pr.get('number') != int(request['number'])
                or (pr.get('repository') or {}).get('nameWithOwner', '').casefold() != self.repo.casefold()):
            raise Failure('This discussion is unavailable in the requested review.', 'unavailable')
        viewer = (result.get('viewer') or {}).get('login', '')
        pending = self.feedback_guard(pr, ref, viewer, None, True)
        # Public threads only. Mixed/private threads retain ordinary paging.
        try:
            thread = self.feedback_thread(node)
        except Failure as error:
            raise Failure(str(error) + ' Use ordinary feedback paging or open GitHub for this discussion.', 'incomplete') from error
        if thread['id'] != target['thread'] or not any(m['id'] == target['message'] and m.get('kind', 'comment') == target['message_kind'] for m in thread['comments']):
            raise Failure('The requested message is not in this discussion.', 'unavailable')
        guard_query = 'query($owner:String!,$repo:String!,$number:Int!){viewer{login} repository(owner:$owner,name:$repo){pullRequest(number:$number){headRefOid baseRefOid updatedAt ' + FEEDBACK_PENDING_FIELDS + '}}}'
        owner, repo = self.repo.split('/')
        guard = self.graphql(guard_query, {'owner': owner, 'repo': repo, 'number': int(request['number'])})
        self.feedback_guard((guard.get('repository') or {}).get('pullRequest') or {}, ref,
                            (guard.get('viewer') or {}).get('login', ''),
                            {'viewer': viewer, 'updated': pr['updatedAt'], 'private_versions': {r['id']: r['read_version'] for r in pending['items']}}, True)
        feedback_message_rules(thread['comments'], viewer)
        published_delete_rules([thread], [], viewer)
        return {'key': self.conn['host'] + '/' + self.repo + '/' + str(request['number']),
                'target': target, 'reference': reference, 'thread': thread}

    def feedback_page(self, request):
        reference = request.get('reference', {})
        try:
            ref = {k: reference[k] for k in ('snapshot', 'base', 'head', 'base_tip')}
            if ref['snapshot'] != ref['base'] + ':' + ref['head'] or any(not isinstance(v, str) or not v for v in ref.values()):
                raise ValueError()
        except (ValueError, KeyError, TypeError):
            raise Failure('Feedback needs an immutable current PR comparison.', 'validation')
        cursor = request.get('cursor', '')
        key = self.conn['host'] + '/' + self.repo + '/' + str(request['number'])
        saved = {'threads_after': None, 'conversation_after': None, 'threads_done': False, 'conversation_done': False,
                 'review_count': request.get('review_count', 0), 'allow_pending': request.get('allow_pending') is True}
        if not isinstance(cursor, str) or len(cursor) > 10000:
            raise Failure('Invalid feedback cursor.', 'validation')
        if cursor:
            try:
                saved = json.loads(cursor)
                if saved['review'] != key or saved['reference'] != ref:
                    raise ValueError()
                for kind in ('threads', 'conversation'):
                    after = saved[kind + '_after']
                    if type(saved[kind + '_done']) is not bool or (after is not None and (not isinstance(after, str) or not after)) or (not saved[kind + '_done'] and after is None):
                        raise ValueError()
                if not isinstance(saved['viewer'], str) or not saved['viewer'] or not isinstance(saved['updated'], str):
                    raise ValueError()
            except (ValueError, TypeError, KeyError):
                raise Failure('Feedback cursor belongs to another review or comparison. Refresh.', 'validation')
        if type(saved.get('review_count')) is not int or saved['review_count'] < 0:
            raise Failure('Invalid feedback review-summary count.', 'validation')
        query = '''query($owner:String!, $repo:String!, $number:Int!, $ta:String, $ca:String, $threads:Boolean!, $conversation:Boolean!) {
          viewer { login }
          repository(owner:$owner,name:$repo) { pullRequest(number:$number) {
            headRefOid baseRefOid updatedAt ''' + FEEDBACK_PENDING_FIELDS + '''
            reviewThreads(first:20,after:$ta) @include(if:$threads) {totalCount pageInfo{hasNextPage endCursor} nodes { ''' + FEEDBACK_THREAD_FIELDS + ''' }}
            comments(first:50,after:$ca) @include(if:$conversation) {totalCount pageInfo{hasNextPage endCursor} nodes { ''' + FEEDBACK_MESSAGE_FIELDS + ''' }}
          }}
        }'''
        owner, repo = self.repo.split('/')
        variables = {'owner': owner, 'repo': repo, 'number': int(request['number']),
                     'ta': saved['threads_after'], 'ca': saved['conversation_after'],
                     'threads': not saved['threads_done'], 'conversation': not saved['conversation_done']}
        result = self.graphql(query, variables)
        pr = (result.get('repository') or {}).get('pullRequest') or {}
        viewer = (result.get('viewer') or {}).get('login', '')
        pending = self.feedback_guard(pr, ref, viewer, saved if cursor else None, saved.get('allow_pending', False))
        threads, conversation = [], []
        next_state = dict(saved, review=key, reference=ref, viewer=viewer, updated=pr['updatedAt'],
                          private_versions={r['id']: r['read_version'] for r in pending['items']})
        for kind, field in [('threads', 'reviewThreads'), ('conversation', 'comments')]:
            if saved[kind + '_done']:
                continue
            nodes, after = feedback_connection(pr.get(field), saved[kind + '_after'])
            total = pr[field].get('totalCount')
            if type(total) is int and total >= len(nodes):
                if cursor and kind + '_total' in saved and saved[kind + '_total'] != total:
                    raise Failure('Feedback count changed while paging; refresh the review.', 'stale')
                next_state[kind + '_total'] = total
            ids = [str(n.get('id') if kind == 'threads' else n.get('fullDatabaseId')) for n in nodes if isinstance(n, dict)]
            if len(ids) != len(nodes) or len(set(ids)) != len(ids):
                raise Failure('Feedback page has repeated or missing identities.', 'incomplete')
            next_state[kind + '_after'], next_state[kind + '_done'] = after, after is None
            if kind == 'threads':
                threads = [self.feedback_thread(n, pending if saved.get("allow_pending") else None) for n in nodes]
            else:
                conversation = [feedback_message(n) for n in nodes]
        # Nested reply reads may span requests. Recheck revision/private state
        # before exposing a complete unit; this is not an atomic snapshot claim.
        guard_query = 'query($owner:String!,$repo:String!,$number:Int!){viewer{login} repository(owner:$owner,name:$repo){pullRequest(number:$number){headRefOid baseRefOid updatedAt ' + FEEDBACK_PENDING_FIELDS + '}}}'
        guard = self.graphql(guard_query, {'owner': owner, 'repo': repo, 'number': int(request['number'])})
        self.feedback_guard((guard.get('repository') or {}).get('pullRequest') or {}, ref,
                            (guard.get('viewer') or {}).get('login', ''), next_state, saved.get('allow_pending', False))
        feedback_message_rules(conversation + [m for t in threads for m in t['comments']], viewer)
        published_delete_rules(threads, conversation, viewer)
        private_feedback_rules(threads, pending)
        private_feedback_targets(pending, threads)
        counts = dict(saved.get('private_counts', {}))
        for review in pending['items']:
            previous = counts.get(review['id'], 0)
            if type(previous) is not int or previous < 0:
                raise Failure('Invalid private feedback coverage cursor.', 'validation')
            counts[review['id']] = previous + len(review['comments'])
            if counts[review['id']] > review['total'] or (next_state['threads_done'] and counts[review['id']] != review['total']):
                raise Failure('Private feedback is not fully represented by the thread connection. Refresh for the complete reader.', 'incomplete')
        next_state['private_counts'] = counts
        complete = next_state['threads_done'] and next_state['conversation_done']
        result = {'snapshot': ref['snapshot'], 'cursor': cursor, 'threads': threads, 'conversation': conversation, 'viewer': viewer, 'pending_reviews': pending,
                'complete': complete, 'next_cursor': '' if complete else json.dumps(next_state, sort_keys=True),
                'inventory': {name: {'state': 'complete' if next_state['threads_done' if name == 'thread_state' else name + '_done'] else 'partial',
                                     'scope': {'threads': 'Full replies in each loaded thread', 'conversation': 'Comments and review summaries',
                                               'thread_state': 'GitHub thread state'}[name]}
                              for name in ('threads', 'conversation', 'thread_state')}}
        if pending['items']:
            result['inventory']['private'] = {'state': 'complete', 'total': len(pending['items']), 'scope': 'Private review headers; comment coverage shown in Pending'}
        for name in ('threads', 'conversation', 'thread_state'):
            total = next_state.get(('threads' if name == 'thread_state' else name) + '_total')
            if total is not None:
                result['inventory'][name]['total'] = total + (saved['review_count'] if name == 'conversation' else 0)
        if pending['items']:
            result['inventory']['thread_state'] = {'state': 'unknown', 'reason': 'Public resolution total is not inferred from private thread counts.'}
        return result

    @staticmethod
    def feedback_guard(pr, ref, viewer, saved, allow_pending=False):
        if not viewer or not isinstance(pr.get('updatedAt'), str) or not isinstance((pr.get('reviews') or {}).get('nodes'), list):
            raise Failure('Cannot verify feedback inventory identity.', 'incomplete')
        pending = private_feedback_inventory(pr, viewer, allow_pending)
        if saved and saved.get('private_versions', {}) != {r['id']: r['read_version'] for r in pending['items']}:
            raise Failure('Private review changed while paging; refresh to inspect it.', 'stale')
        if pr.get('headRefOid') != ref['head'] or pr.get('baseRefOid') != ref['base_tip']:
            raise Failure('PR source changed while paging; refresh the review.', 'stale')
        if saved and (saved['viewer'] != viewer or saved['updated'] != pr['updatedAt']):
            raise Failure('Feedback or signed-in actor changed while paging; refresh the review.', 'stale')
        return pending

    def service_progress(self, request):
        reference, path = request.get('reference'), request.get('path')
        if (not isinstance(reference, dict) or not {'snapshot', 'base', 'head', 'base_tip'} <= set(reference) or set(reference) - {'snapshot', 'base', 'head', 'base_tip', 'head_repo', 'base_repo'} or
                any(not isinstance(reference.get(k), str) or not reference[k] for k in reference) or
                reference['snapshot'] != reference['base'] + ':' + reference['head'] or
                not isinstance(path, str) or not path or len(path) > 4096):
            raise Failure('Service progress needs a current full comparison and file path.', 'validation')
        if not self.token:
            raise Failure('Sign in to read your service Viewed state.', 'auth')
        owner, repo = self.repo.split('/')
        variables = {'owner': owner, 'repo': repo, 'number': int(request['number'])}
        fields = 'id headRefOid baseRefOid url'
        def read(after=None, files=False):
            query = ('query($owner:String!,$repo:String!,$number:Int!' + (',$after:String' if files else '') +
                     '){viewer{id login} repository(owner:$owner,name:$repo){pullRequest(number:$number){' + fields +
                     (' files(first:100,after:$after){pageInfo{hasNextPage endCursor} nodes{path viewerViewedState}}' if files else '') + '}}}')
            data = self.graphql(query, dict(variables, after=after) if files else variables)
            viewer, pr = data.get('viewer') or {}, (data.get('repository') or {}).get('pullRequest') or {}
            if not all(isinstance(viewer.get(k), str) and viewer[k] for k in ('id', 'login')) or not all(isinstance(pr.get(k), str) and pr[k] for k in ('id', 'headRefOid', 'baseRefOid', 'url')):
                raise Failure('Service progress identity is unavailable.', 'incomplete')
            if pr['headRefOid'] != reference['head'] or pr['baseRefOid'] != reference['base_tip']:
                raise Failure('PR source changed; refresh before inspecting service progress.', 'stale')
            return viewer, pr
        found, after, seen, identity = None, None, set(), None
        for _ in range(100):
            viewer, pr = read(after, True)
            current = (viewer['id'], pr['id'])
            if identity is not None and current != identity:
                raise Failure('Viewer or review changed during progress read.', 'stale')
            identity = current
            connection = pr.get('files') or {}
            nodes, info = connection.get('nodes'), connection.get('pageInfo') or {}
            if not isinstance(nodes, list) or type(info.get('hasNextPage')) is not bool:
                raise Failure('Incomplete service progress page.', 'incomplete')
            matches = [f for f in nodes if isinstance(f, dict) and f.get('path') == path]
            if len(matches) > 1:
                raise Failure('Ambiguous service progress path.', 'incomplete')
            if matches:
                found = matches[0]
                break
            if not info['hasNextPage']:
                break
            after = info.get('endCursor')
            if not isinstance(after, str) or not after or after in seen:
                raise Failure('Invalid service progress cursor.', 'incomplete')
            seen.add(after)
        if found is None:
            raise Failure('File not found within available service progress pages.', 'incomplete')
        if found.get('viewerViewedState') not in ('VIEWED', 'UNVIEWED', 'DISMISSED'):
            raise Failure('Unknown service Viewed state.', 'incomplete')
        viewer, pr = read()
        if (viewer['id'], pr['id']) != identity:
            raise Failure('Viewer or review changed during progress read.', 'stale')
        return {'reference': reference, 'path': path, 'actor': 'github-node:' + viewer['id'],
                'actor_label': viewer['login'], 'review_id': pr['id'], 'state': found['viewerViewedState'].lower(),
                'url': pr['url'] + '/files'}

    def change_service_viewed(self, request):
        draft = request['draft']
        if (not isinstance(draft.get('id'), str) or not re.fullmatch(r'[A-Za-z0-9_-]+', draft['id']) or
                type(draft.get('viewed')) is not bool or draft.get('body') != '' or
                not isinstance(draft.get('actor'), str) or not draft['actor'] or
                not isinstance(draft.get('review_id'), str) or not draft['review_id']):
            raise Failure('Invalid service Viewed intent.', 'validation')
        read_request = {'number': request['number'], 'reference': draft.get('reference'), 'path': draft.get('path')}
        before = self.service_progress(read_request)
        if before['actor'] != draft['actor'] or before['review_id'] != draft['review_id']:
            raise Failure('Service Viewed actor or review changed.', 'stale', bool(request.get('reconcile')))
        desired = 'viewed' if draft['viewed'] else 'unviewed'
        receipt = {k: draft[k] for k in ('id', 'actor', 'review_id', 'reference', 'path', 'viewed')}
        if request.get('reconcile') or before['state'] == desired:
            if before['state'] != desired:
                raise Failure('Requested service Viewed state is not observed; no write repeated.', 'unknown', True)
            return dict(receipt, observed=True, url=before['url'])
        name = 'markFileAsViewed' if draft['viewed'] else 'unmarkFileAsViewed'
        input_type = 'MarkFileAsViewedInput' if draft['viewed'] else 'UnmarkFileAsViewedInput'
        self.graphql('mutation($input:' + input_type + '!){' + name + '(input:$input){clientMutationId pullRequest{id}}}',
                     {'input': {'pullRequestId': draft['review_id'], 'path': draft['path'], 'clientMutationId': draft['id']}}, True)
        try:
            after = self.service_progress(read_request)
            if after['actor'] != draft['actor'] or after['review_id'] != draft['review_id'] or after['state'] != desired:
                raise Failure('The requested service Viewed state could not be verified.', 'unknown', True)
        except Failure as error:
            raise Failure('Service Viewed write may have occurred: ' + str(error), 'unknown', True) from error
        return dict(receipt, observed=True, url=after['url'])

    def readiness(self, request):
        reference = request.get('reference')
        cursor = request.get('cursor', '')
        if not isinstance(reference, dict) or any(not isinstance(reference.get(k), str) or not reference[k] for k in ('snapshot', 'head', 'base')):
            raise Failure('A reviewed comparison is required for readiness.', 'validation')
        if not isinstance(cursor, str) or len(cursor) > 10000:
            raise Failure('Invalid readiness cursor.', 'validation')
        key = self.conn['host'] + '/' + self.repo + '/' + str(request['number'])
        saved = None
        if cursor:
            try:
                saved = json.loads(cursor)
                if (not isinstance(saved, dict) or saved.get('review') != key or saved.get('reference') != reference or
                        any(not isinstance(saved.get(k), str) or not saved[k] for k in ('after', 'head', 'base_tip', 'pr'))):
                    raise ValueError()
            except (ValueError, TypeError):
                raise Failure('Readiness cursor belongs to another review or comparison. Reload readiness.', 'validation')
        owner, repo = self.repo.split('/')
        variables = {'owner': owner, 'repo': repo, 'number': int(request['number']), 'after': saved['after'] if saved else None}
        fields = 'id url headRefOid baseRefOid state isDraft reviewDecision mergeStateStatus mergeable'
        metadata_query = '''query($owner:String!, $repo:String!, $number:Int!) {
          repository(owner:$owner, name:$repo) { pullRequest(number:$number) { ''' + fields + ''' } } }'''
        metadata_variables = {k: v for k, v in variables.items() if k != 'after'}
        initial = (self.graphql(metadata_query, metadata_variables).get('repository') or {}).get('pullRequest')
        if not isinstance(initial, dict) or not isinstance(initial.get('id'), str) or not initial['id']:
            raise Failure('Review readiness is unavailable.', 'unavailable')
        # Use the global PR identity for required classification. A fork's
        # check repository need not share the base repository's PR numbers.
        variables['pr'] = initial['id']
        query = '''query($owner:String!, $repo:String!, $number:Int!, $after:String, $pr:ID!) {
          repository(owner:$owner, name:$repo) { pullRequest(number:$number) { ''' + fields + '''
            commits(last:1) { nodes { commit { oid statusCheckRollup {
              contexts(first:50, after:$after) { totalCount pageInfo { hasNextPage endCursor }
                nodes { __typename ... on CheckRun { id name status conclusion detailsUrl permalink isRequired(pullRequestId:$pr) }
                  ... on StatusContext { id context state description targetUrl isRequired(pullRequestId:$pr) } }
              } } } } }
          } } }'''
        pr = (self.graphql(query, variables).get('repository') or {}).get('pullRequest')
        def identity(value):
            if not isinstance(value, dict) or any(not isinstance(value.get(k), str) or not value[k] for k in ('id', 'url', 'headRefOid', 'baseRefOid', 'state', 'mergeStateStatus', 'mergeable')) or type(value.get('isDraft')) is not bool:
                raise Failure('Readiness metadata is unavailable or incomplete.', 'incomplete')
            if value.get('reviewDecision') is not None and not isinstance(value['reviewDecision'], str):
                raise Failure('Invalid review decision.', 'incomplete')
            return {k: value.get(k) for k in fields.split()}
        meta = identity(pr)
        if identity(initial) != meta:
            raise Failure('Review state changed while checks were loading. Reload readiness.', 'stale')
        if saved and (saved['pr'], saved['head'], saved['base_tip']) != (pr['id'], pr['headRefOid'], pr['baseRefOid']):
            raise Failure('Review branches changed between check pages. Reload readiness.', 'stale')
        commits = (pr.get('commits') or {}).get('nodes')
        if not isinstance(commits, list) or len(commits) != 1 or not isinstance(commits[0], dict):
            raise Failure('Current head checks are unavailable.', 'incomplete')
        commit = commits[0].get('commit')
        if not isinstance(commit, dict) or commit.get('oid') != pr['headRefOid'] or 'statusCheckRollup' not in commit:
            raise Failure('Checks do not match the current review head.', 'stale')
        rollup = commit['statusCheckRollup']
        checks, total, more, after = [], 0, False, ''
        if rollup is not None:
            connection = rollup.get('contexts') if isinstance(rollup, dict) else None
            if not isinstance(connection, dict) or not isinstance(connection.get('nodes'), list):
                raise Failure('Incomplete check inventory.', 'incomplete')
            page = connection.get('pageInfo') or {}
            total = connection.get('totalCount')
            if type(page.get('hasNextPage')) is not bool or type(total) is not int or total < len(connection['nodes']):
                raise Failure('Incomplete check pagination.', 'incomplete')
            more, after = page['hasNextPage'], page.get('endCursor')
            if more and (not isinstance(after, str) or not after or after == variables['after'] or not connection['nodes']):
                raise Failure('Check pagination did not advance.', 'incomplete')
            checks = [readiness_check(n) for n in connection['nodes']]
            if len({c['id'] for c in checks}) != len(checks):
                raise Failure('Repeated check identity.', 'incomplete')
        elif saved:
            raise Failure('Check inventory changed between pages. Reload readiness.', 'stale')
        # Recheck the live review after the page read. This is an observation,
        # never an authorization to merge, and can become stale immediately.
        latest = (self.graphql(metadata_query, metadata_variables).get('repository') or {}).get('pullRequest')
        if identity(latest) != meta:
            raise Failure('Review state changed while checks were loading. Reload readiness.', 'stale')
        review = {'APPROVED': 'Approved', 'CHANGES_REQUESTED': 'Changes requested', 'REVIEW_REQUIRED': 'Review required'}.get(pr.get('reviewDecision'), 'Unavailable')
        merge = {'BEHIND': 'Branch is behind', 'BLOCKED': 'Blocked', 'CLEAN': 'Clean', 'DIRTY': 'Conflicts', 'DRAFT': 'Draft',
                 'HAS_HOOKS': 'Pre-receive hooks apply', 'UNKNOWN': 'Unknown', 'UNSTABLE': 'Non-passing commit status'}.get(pr['mergeStateStatus'], 'Unknown')
        facts = [
            {'id': 'review', 'name': 'Code review', 'value': review, 'detail': 'GitHub review decision; full policy is not enumerated.', 'url': pr['url']},
            {'id': 'merge', 'name': 'Merge status', 'value': merge, 'detail': 'GitHub reports ' + pr['mergeStateStatus'] + '; this is not a merge action.', 'url': pr['url']},
            {'id': 'conflicts', 'name': 'Conflicts', 'value': {'MERGEABLE': 'None reported', 'CONFLICTING': 'Present', 'UNKNOWN': 'Not determined'}.get(pr['mergeable'], 'Unknown'), 'detail': 'Conflict status alone does not establish readiness.', 'url': pr['url']},
            {'id': 'state', 'name': 'Review', 'value': pr['state'] + (' / draft' if pr['isDraft'] else ''), 'detail': '', 'url': pr['url']}]
        next_cursor = json.dumps({'review': key, 'reference': reference, 'pr': pr['id'], 'head': pr['headRefOid'], 'base_tip': pr['baseRefOid'], 'after': after}, sort_keys=True) if more else ''
        return {'reference': reference, 'head': pr['headRefOid'], 'base_tip': pr['baseRefOid'],
                'observed_at': datetime.now(timezone.utc).isoformat(timespec='seconds'), 'url': pr['url'],
                'facts': facts, 'checks': checks, 'total': total, 'cursor': cursor, 'next_cursor': next_cursor, 'complete': not more,
                'scope': 'Reported checks only; missing required checks and other repository rules may not be listed. Paged results are observations, not a merge guarantee.'}

    def timeline(self, request):
        cursor = request.get('cursor', '')
        if not isinstance(cursor, str):
            raise Failure('Invalid timeline cursor.', 'validation')
        key = self.conn['host'] + '/' + self.repo + '/' + str(request['number'])
        before = None
        if cursor:
            try:
                saved = json.loads(cursor)
                if saved['review'] != key or not isinstance(saved['before'], str) or not saved['before'] or len(cursor) > 10000:
                    raise ValueError()
                before = saved['before']
            except (ValueError, TypeError, KeyError):
                raise Failure('Timeline cursor does not belong to this review. Reload history.', 'validation')
        owner, repo = self.repo.split('/')
        fragments = ' '.join('... on ' + kind + ' { ' + fields + ' }' for kind, fields in TIMELINE_FIELDS.items())
        query = '''query($owner:String!, $repo:String!, $number:Int!, $before:String) {
          repository(owner:$owner, name:$repo) { pullRequest(number:$number) { url
            timelineItems(last:50, before:$before) { totalCount pageInfo { hasPreviousPage startCursor }
              nodes { __typename ... on Node { id } ''' + fragments + ''' } }
          } } }'''
        result = self.graphql(query, {'owner': owner, 'repo': repo, 'number': int(request['number']), 'before': before})
        pr = (result.get('repository') or {}).get('pullRequest')
        if not isinstance(pr, dict) or not isinstance(pr.get('timelineItems'), dict):
            raise Failure('Review timeline is unavailable.', 'unavailable')
        connection = pr['timelineItems']
        page = connection.get('pageInfo') or {}
        nodes = connection.get('nodes')
        total = connection.get('totalCount')
        if not isinstance(nodes, list) or type(page.get('hasPreviousPage')) is not bool:
            raise Failure('Incomplete timeline page.', 'incomplete')
        more, next_before = page['hasPreviousPage'], page.get('startCursor')
        if more and (not isinstance(next_before, str) or not next_before or next_before == before or not nodes):
            raise Failure('Timeline did not advance. Reload history.', 'incomplete')
        events = [timeline_event(n, pr.get('url', '')) for n in nodes]
        if len({e['id'] for e in events}) != len(events):
            raise Failure('Timeline returned duplicate event identities.', 'incomplete')
        output = {'cursor': cursor, 'items': events, 'complete': not more,
                'next_cursor': json.dumps({'review': key, 'before': next_before}, sort_keys=True) if more else '',
                'scope': 'GitHub timeline; current message bodies and review states. Reload for newer activity.'}
        # GitHub can report fewer totalCount entries than returned nodes (for
        # example subscription events). Preserve events; do not invent a total.
        if type(total) is int and total >= len(events):
            output['total'] = total
        return output

    def context_thread(self, snapshot, target, number):
        """Find a complete thread without confusing an initial page with absence."""
        matches = [t for t in snapshot['threads'] if t['id'] == target.get('thread')]
        lookup = target.get('lookup', '')
        reference = self.comparison_reference(snapshot)
        if not matches and lookup and snapshot['capabilities'].get('feedback_lookup', {}).get('enabled'):
            try:
                result = self.feedback_lookup({'number': number, 'reference': reference,
                    'target': {'kind': 'thread', 'thread': target['thread'], 'message': target['thread'],
                               'message_kind': 'comment', 'lookup': lookup}})
                matches = [result['thread']]
            except Failure as error:
                # Private/mixed threads need the existing authenticated paging
                # path. Scope, permission and stale-reference failures must not
                # silently turn into a different lookup.
                if error.code != 'incomplete':
                    raise
        cursor = snapshot.get('feedback', {}).get('cursor', '')
        seen = set()
        complete = snapshot.get('inventory', {}).get('threads', {}).get('state') == 'complete'
        while not matches and cursor and not complete and snapshot['capabilities'].get('feedback_page', {}).get('enabled'):
            if cursor in seen or len(seen) >= 100:
                raise Failure('Original discussion lookup exceeded its page limit or did not advance. Open the discussion on GitHub.', 'incomplete')
            seen.add(cursor)
            page = self.feedback_page({'number': number, 'reference': reference, 'cursor': cursor})
            if page.get('snapshot') != snapshot['snapshot'] or page.get('cursor') != cursor:
                raise Failure('Review changed while locating original discussion context. Refresh and try again.', 'stale')
            matches = [t for t in page['threads'] if t['id'] == target['thread']]
            cursor = page['next_cursor']
            complete = page.get('inventory', {}).get('threads', {}).get('state') == 'complete'
        if len(matches) != 1:
            raise Failure('This discussion could not be located in the available review feedback. Its original diff remains in the current view.', 'unavailable')
        thread = matches[0]
        if thread['id'] != target['thread'] or (lookup and thread.get('native_id') != lookup):
            raise Failure('The original discussion identity changed. Refresh and try again.', 'stale')
        if not any(t['id'] == thread['id'] for t in snapshot['threads']):
            snapshot['threads'].append(thread)
            # Only the target is retained from additional reads. Do not advance
            # the user's general paging cursor or claim those pages are loaded.
            for name in ('threads', 'thread_state'):
                inventory = snapshot.setdefault('inventory', {}).setdefault(name, {})
                inventory.update(state='partial', scope='Initial feedback plus verified original-context target')
                if type(inventory.get('total')) is int and inventory['total'] < len(snapshot['threads']):
                    inventory.pop('total', None)
        return thread

    def thread_context(self, request):
        target = request.get('target', {})
        if (not isinstance(target, dict) or any(not isinstance(target.get(k), str) or not target[k] for k in ('thread', 'token'))
                or not isinstance(target.get('lookup', ''), str) or len(target.get('lookup', '')) > 1024):
            raise Failure('Original context requires a thread identity and anchor token.', 'validation')
        snapshot = self.open(int(request['number']), incremental=True)
        thread = self.context_thread(snapshot, target, int(request['number']))
        source = original_source(thread)
        if not source['available'] or source['token'] != target.get('token'):
            raise Failure('The original source reference changed or is unavailable. Refresh the discussion and try again.', 'stale')
        head = thread['original_commit_id']
        repo = snapshot.get('head_repo', self.repo)
        commit = self.api('repos/' + repo + '/commits/' + head + '?per_page=100')
        if commit.get('sha') != head or not isinstance(commit.get('parents'), list):
            raise Failure('The original commit could not be verified.', 'unavailable')
        parents = commit['parents']
        base = parents[0].get('sha', '') if parents else 'empty-parent:' + head
        if parents and not re.fullmatch(r'[0-9a-fA-F]{40}|[0-9a-fA-F]{64}', base):
            raise Failure('The original commit parent is unavailable.', 'unavailable')
        whole_file = thread.get('subject_type') == 'file'
        side = thread.get('original_side', thread['side'])
        start = thread.get('original_start_line') or thread.get('original_line', 0)
        end = thread.get('original_line', 0)
        if not whole_file and (type(start) is not int or type(end) is not int or start < 1 or start > end or thread.get('original_start_side', side) != side):
            raise Failure('The original range spans unsupported sides or has no valid coordinates. Read the original diff in the discussion.', 'unavailable')
        path = thread.get('original_path', thread['path'])
        candidates = [path]
        candidates.extend(f['old_path'] for f in snapshot['files'] if f['path'] == path and f['old_path'] != path)
        verified = []
        for candidate in dict.fromkeys(candidates):
            changed = next((f for f in commit.get('files', []) if f['filename'] == candidate), {})
            file = {'id': candidate, 'path': candidate, 'old_path': changed.get('previous_filename', candidate),
                    'status': changed.get('status', 'modified') if parents else 'added', 'patch': changed.get('patch', '')}
            context_snapshot = dict(snapshot, base=base, head=head, base_repo=repo, head_repo=repo)
            content = self.file({'snapshot': context_snapshot, 'file': file})
            location_side = side
            if whole_file:
                location_side = 'base' if content['head']['kind'] == 'absent' else 'head'
                valid = content[location_side]['kind'] in ('text', 'binary')
            else:
                rows = original_hunk_rows(thread.get('hunk', ''), side)
                text = content[side]
                valid = text['kind'] == 'text' and all(n in rows for n in range(start, end + 1))
                valid = valid and all(1 <= n <= len(text['lines']) and text['lines'][n - 1] == value for n, value in rows.items())
            if valid:
                verified.append((file, location_side))
                if candidate == path:
                    break
        if len(verified) != 1:
            reason = 'The original excerpt does not match the commit parent; GitHub does not provide the original review base.' if side == 'base' else 'The original source path or excerpt could not be verified at its original commit.'
            raise Failure(reason + ' The original diff remains in the discussion.', 'unavailable')
        file, side = verified[0]
        kind = 'original-head' if side == 'head' else 'commit-parent-file' if whole_file else 'matching-parent'
        note = ('Verified original head and file.' if side == 'head' else
                'File removed by the original commit; showing its parent version. Original review base is unverified.' if whole_file else
                'Commit parent matches the original excerpt; it is not a verified original review base.')
        note += ' This view shows one file at the original commit and ' + ('its first parent' if parents else 'an empty base (root commit)') + ', not the full original PR diff.'
        context = {'thread': thread['id'], 'token': source['token'], 'kind': kind, 'note': note,
                   'label': 'Verified original head' if side == 'head' else 'Deleted file in commit parent' if whole_file else 'Parent excerpt matched',
                   'basis': 'Original PR base unverified',
                   'path': file['path'], 'side': side, 'start': 1 if whole_file else start, 'line': 1 if whole_file else end}
        snapshot.update(snapshot='context:' + thread['id'] + ':' + source['token'], base=base, head=head,
                        base_repo=repo, head_repo=repo, files=[file], context=context, comparison_note=note)
        snapshot.setdefault('inventory', {})['files'] = {'state': 'complete', 'total': 1, 'scope': 'One-file original code context'}
        for item in snapshot['threads']:
            item['outdated'] = item['id'] != thread['id']
            item['line'] = item['start'] = 0
            if item['id'] == thread['id']:
                item['path'] = file['path']
                if not whole_file:
                    item.update(side=side, start=start, line=end)
        for action in ('comment', 'file_comment', 'review', 'batch'):
            snapshot['capabilities'][action] = {'enabled': False, 'reason': 'Return to Latest to create new source feedback or a review.'}
        return {'thread': thread['id'], 'token': source['token'], 'snapshot': snapshot, 'location': {k: context[k] for k in ('path', 'side', 'start', 'line')}}

    def comparison_range(self, request):
        selection = request.get('selection', {})
        if not isinstance(selection, dict) or set(selection) != {'from', 'to'}:
            raise Failure('A range requires from and to endpoints', 'validation')
        endpoints = []
        for name in ('from', 'to'):
            endpoint = selection.get(name, {})
            if not isinstance(endpoint, dict) or not isinstance(endpoint.get('reference'), dict):
                raise Failure('A range endpoint requires a comparison reference', 'validation')
            reference = endpoint.get('reference', {})
            side = endpoint.get('side')
            if side not in ('base', 'head') or 'range' in reference or 'context' in reference:
                raise Failure('Choose an original comparison and its base or head for each endpoint', 'validation')
            if any(not re.fullmatch(r'[0-9a-fA-F]{40}|[0-9a-fA-F]{64}', str(reference.get(k, ''))) for k in ('base', 'head')) or reference.get('snapshot') != reference['base'] + ':' + reference['head']:
                raise Failure('Range endpoint identity does not match immutable source refs', 'validation')
            repo = reference.get(side + '_repo', self.repo)
            if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
                raise Failure('Invalid comparison repository', 'validation')
            endpoints.append((reference[side], repo))
        base, base_repo = endpoints[0]
        head, head_repo = endpoints[1]
        # Network object lookup accepts fork commits by immutable SHA, as in
        # ordinary historical reads. No moving branch name enters the request.
        reference = {'snapshot': base + ':' + head, 'base': base, 'head': head,
                     'head_repo': head_repo, 'base_repo': base_repo}
        snapshot = self.comparison(dict(request, reference=reference))
        snapshot.update(snapshot='range:' + base + ':' + head, range=selection)
        for kind in ('comment', 'file_comment', 'review', 'batch'):
            snapshot['capabilities'][kind] = {'enabled': False, 'reason': 'Open the latest pull request comparison to create new source feedback or a review.'}
        return snapshot

    def comparisons(self, request):
        current = self.open(int(request['number']))
        base, head = current['base'], current['head']
        items = [self.comparison_reference(current, 'Current pull request comparison')]
        commits = []
        total = None
        prefix = 'repos/' + self.repo + '/compare/' + base + '...' + head
        for page in range(1, 101):
            result = self.api(prefix + '?per_page=100&page=' + str(page))
            if total is None:
                total = result.get('total_commits')
            if type(total) is not int or result.get('total_commits') != total or not isinstance(result.get('commits'), list):
                raise Failure('Incomplete comparison commit history', 'incomplete')
            commits.extend(result['commits'])
            if len(commits) >= total:
                break
            if not result['commits']:
                raise Failure('Commit history ended before its declared total', 'incomplete')
        if len(commits) != total or len({c['sha'] for c in commits}) != total:
            raise Failure('Commit history exceeds the page limit or contains duplicate entries', 'incomplete')
        omitted_roots = 0
        for commit in commits:
            parents = commit.get('parents')
            if not isinstance(parents, list):
                raise Failure('Commit history omitted parent identities', 'incomplete')
            if not parents:
                omitted_roots += 1
                continue
            before, after = parents[0]['sha'], commit['sha']
            reference = self.comparison_reference(current, 'Commit: ' + commit.get('commit', {}).get('message', '').split('\n')[0])
            reference.update(snapshot=before + ':' + after, base=before, head=after,
                             base_repo=current.get('head_repo', self.repo))
            if not any(item['snapshot'] == reference['snapshot'] for item in items):
                items.append(reference)
        return {'items': items, 'latest': current, 'complete': not omitted_roots,
                'scope': 'Current pull request and its reachable commits; each commit uses its first parent. Saved references may include earlier force-pushed history.' +
                         (' Root commits without a first parent are omitted.' if omitted_roots else '')}

    def comparison(self, request):
        reference = request.get('reference', {})
        if 'context' in reference:
            context = reference['context']
            snapshot = self.thread_context(dict(request, target={'thread': context.get('thread'), 'token': context.get('token')}))['snapshot']
            if any(reference.get(k, snapshot[k]) != snapshot[k] for k in ('snapshot', 'base', 'head', 'context')):
                raise Failure('Saved original-context identity changed; existing source is retained.', 'stale')
            return snapshot
        if 'range' in reference:
            snapshot = self.comparison_range(dict(request, selection=reference['range']))
            if any(reference.get(k, snapshot[k]) != snapshot[k] for k in ('snapshot', 'base', 'head')):
                raise Failure('Saved range identity does not match its endpoints', 'validation')
            return snapshot
        identity = str(reference.get('snapshot', ''))
        parts = identity.split(':')
        if len(parts) != 2 or any(not re.fullmatch(r'[0-9a-fA-F]{40}|[0-9a-fA-F]{64}', part) for part in parts):
            raise Failure('A historical comparison requires immutable base and head object IDs', 'validation')
        base, head = parts
        if reference.get('base', base) != base or reference.get('head', head) != head:
            raise Failure('Comparison reference identity does not match its source refs', 'validation')
        current = self.open(int(request['number']))
        if identity == current['snapshot']:
            return current
        head_repo = reference.get('head_repo', current.get('head_repo', self.repo))
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', head_repo):
            raise Failure('Invalid comparison repository', 'validation')
        qualified_head = head if head_repo == self.repo else head_repo.split('/')[0] + ':' + head
        base_repo = reference.get('base_repo', self.repo)
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', base_repo):
            raise Failure('Invalid base comparison repository', 'validation')
        qualified_base = base if base_repo == self.repo else base_repo.split('/')[0] + ':' + base
        result = self.api('repos/' + self.repo + '/compare/' + qualified_base + '...' + qualified_head + '?per_page=1')
        if result.get('merge_base_commit', {}).get('sha') != base:
            raise Failure('Requested base is not the comparison merge base; the original source identity was not substituted', 'validation')
        files = result.get('files')
        if not isinstance(files, list) or len(files) >= 300:
            raise Failure('GitHub comparison file inventory is unavailable or reaches its 300-file limit; completeness cannot be verified. Open this comparison in GitHub.', 'incomplete')
        current.update(base=base, head=head, snapshot=identity, head_repo=head_repo, base_repo=base_repo,
                       base_tip=reference.get('base_tip', current['base_tip']))
        current['files'] = [{'id': f['filename'], 'path': f['filename'],
                             'old_path': f.get('previous_filename', f['filename']), 'status': f['status'],
                             'patch': f.get('patch', ''), 'additions': f.get('additions', 0), 'deletions': f.get('deletions', 0)} for f in files]
        paths = {f['path'] for f in current['files']}
        current.setdefault('inventory', {})['files'] = {'state': 'complete', 'total': len(current['files']), 'scope': 'Selected comparison'}
        for thread in current['threads']:
            # A head-side original line is exact only on its original head commit.
            # A historical base cannot be inferred from an original head ID.
            file_thread = thread.get('subject_type') == 'file'
            exact = thread.get('original_commit_id') == head and thread['path'] in paths and (file_thread or thread['side'] == 'head' and thread.get('original_line', 0) > 0)
            thread['outdated'] = not exact
            thread['line'] = thread.get('original_line', 0) if exact and not file_thread else 0
            thread['start'] = thread.get('original_start_line', thread['line']) if exact and not file_thread else 0
        current['comparison_note'] = 'Historical source with current conversation. Only verified original-head anchors are placed inline; other threads retain their original diff context.'
        for kind in ('comment', 'file_comment', 'review', 'batch'):
            current['capabilities'][kind] = {'enabled': False, 'reason': 'Open the latest pull request comparison to publish new inline feedback or a review.'}
        return current

    def file(self, request):
        snapshot, f = request["snapshot"], request["file"]
        def read(side):
            if (side == "base" and f["status"] == "added") or (side == "head" and f["status"] == "removed"):
                return {"lines": [], "kind": "absent"}
            repo = snapshot.get('base_repo', self.repo) if side == "base" else snapshot.get("head_repo", self.repo)
            path = f["old_path"] if side == "base" else f["path"]
            endpoint = "repos/" + repo + "/contents/" + urllib.parse.quote(path, safe="/") + "?ref=" + snapshot[side]
            try:
                raw = self.api(endpoint, raw=True)
                if b"\x00" in raw:
                    return {"lines": [], "kind": "binary", "hash": hashlib.sha256(raw).hexdigest()}
                text = raw.decode("utf-8")
                lines = text.split("\n")[:-1] if text.endswith("\n") else text.split("\n")
                crlf = "\r\n" in text and "\n" not in text.replace("\r\n", "")
                return {"lines": [line.removesuffix("\r") for line in lines] if crlf else lines,
                        "kind": "text", "hash": hashlib.sha256(raw).hexdigest(), "final_newline": text.endswith("\n"), "fileformat": "dos" if crlf else "unix"}
            except UnicodeDecodeError:
                return {"lines": [], "kind": "binary", "hash": hashlib.sha256(raw).hexdigest()}
            except Failure as exc:
                return {"lines": [], "kind": "unavailable", "message": str(exc)}
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            base, head = pool.submit(read, "base"), pool.submit(read, "head")
            return {"base": base.result(), "head": head.result()}

    def mutate(self, request):
        if request['draft'].get('kind') == 'service_viewed':
            return self.change_service_viewed(request)
        if request['draft'].get('kind') == 'start_pending' or request['draft'].get('pending_mode'):
            return self.save_pending(request)
        if request['draft'].get('kind') == 'delete_message':
            return self.delete_message(request)
        if request['draft'].get('kind') == 'delete_pending_comment':
            return self.delete_pending_comment(request)
        if request['draft'].get('kind') == 'discard_pending':
            return self.discard_pending(request)
        if request['draft'].get('kind') == 'submit_pending':
            return self.submit_pending(request)
        if request['draft'].get('kind') == 'reaction':
            return self.change_reaction(request)
        if request['draft'].get('kind') == 'edit':
            return self.edit_message(request)
        if request['draft'].get('kind') == 'batch':
            return self.batch(request)
        if request['draft'].get('kind') == 'thread_state':
            return self.change_thread_state(request)
        number, draft = int(request["number"]), request["draft"]
        kind = draft["kind"]
        prefix = "repos/" + self.repo
        marker = "<!-- revue:" + draft["id"] + " -->"
        if not re.fullmatch(r"[A-Za-z0-9_-]+", draft["id"]):
            raise Failure("Invalid draft identity")
        list_path = prefix + ("/issues/" + str(number) + "/comments" if kind == "conversation" else
                              "/pulls/" + str(number) + ("/reviews" if kind == "review" else "/comments"))
        # Receipts make repeat calls recoverable; an uncertain outcome is never
        # automatically reposted. Reconciliation is a read-only operation.
        matches = [c for c in self.pages(list_path) if marker in (c.get("body") or "")]
        if matches:
            return {"id": str(matches[0]["id"]), "url": matches[0].get("html_url", ""), "recovered": True}
        if request.get("reconcile"):
            raise Failure("No receipt found yet. Keep this draft and inspect GitHub before retrying.", "unknown", True)
        validate_suggestion(draft)
        body = draft["body"].strip()
        event = draft.get('event', 'COMMENT')
        if not body and not (kind == 'review' and event == 'APPROVE'):
            raise Failure("Write a comment before sending.", "validation")
        payload = {"body": body + "\n\n" + marker}
        if not self.token:
            raise Failure('Sign in before publishing feedback.', 'auth')
        if kind in ("comment", "file_comment", "review"):
            fresh = self.api(prefix + "/pulls/" + str(number))
            if fresh["head"]["sha"] != draft["head"] or fresh["base"]["sha"] != draft["base_tip"]:
                raise Failure("PR changed since you opened it. Draft retained; refresh and review the new revision.", "stale")
            if kind == 'review':
                _, actions, _ = self.action_rules(fresh)
                action = next((a for a in actions if a['id'] == event), None)
                if action is None or not action['enabled']:
                    raise Failure(action['reason'] if action else 'Unsupported review decision', 'permission')
        if kind == "conversation":
            path = prefix + "/issues/" + str(number) + "/comments"
        elif kind == "reply":
            path = prefix + "/pulls/" + str(number) + "/comments/" + str(int(draft["thread"])) + "/replies"
        elif kind == "review":
            path = prefix + "/pulls/" + str(number) + "/reviews"
            event = draft.get("event", "COMMENT")
            if event not in ("COMMENT", "APPROVE", "REQUEST_CHANGES"):
                raise Failure("Unsupported review decision")
            payload.update({"commit_id": draft["head"], "event": event})
        elif kind == "file_comment":
            if any(k in draft for k in ('side', 'start', 'end', 'line')):
                raise Failure('File comments have no line coordinates', 'validation')
            files = self.pages(prefix + '/pulls/' + str(number) + '/files')
            file = next((f for f in files if f['filename'] == draft.get('path')), None)
            if file is None or draft.get('old_path') != file.get('previous_filename', file['filename']):
                raise Failure('File does not belong to this comparison or its rename target changed', 'validation')
            path = prefix + '/pulls/' + str(number) + '/comments'
            payload.update(commit_id=draft['head'], path=draft['path'], subject_type='file')
        elif kind == "comment":
            path = prefix + "/pulls/" + str(number) + "/comments"
            payload.update({"commit_id": draft["head"], "path": draft["path"], "line": draft["end"],
                            "side": "LEFT" if draft["side"] == "base" else "RIGHT"})
            if draft["start"] != draft["end"]:
                payload.update({"start_line": draft["start"], "start_side": payload["side"]})
        else:
            raise Failure("Unknown action: " + kind)
        result = self.api(path, "POST", payload)
        return {"id": str(result["id"]), "url": result.get("html_url", "")}

    def verify_pending(self, request):
        target = request.get('target') or {}
        review_id = target.get('review', '')
        reference = request.get('reference') or {}
        if any(not isinstance(reference.get(k), str) or not reference[k] for k in ('snapshot', 'base', 'head', 'base_tip')) or reference['snapshot'] != reference['base'] + ':' + reference['head']:
            raise Failure('Private verification needs an immutable PR comparison.', 'validation')
        if not isinstance(review_id, str) or not review_id.isdigit() or not target.get('read_version'):
            raise Failure('Select a private review with a verified inventory identity.', 'validation')
        query = 'query($owner:String!,$repo:String!,$number:Int!){viewer{login} repository(owner:$owner,name:$repo){pullRequest(number:$number){headRefOid baseRefOid updatedAt ' + FEEDBACK_PENDING_FIELDS + '}}}'
        owner, repo = self.repo.split('/')
        variables = {'owner': owner, 'repo': repo, 'number': int(request['number'])}
        def current():
            data = self.graphql(query, variables)
            return self.feedback_guard((data.get('repository') or {}).get('pullRequest') or {}, reference,
                                       (data.get('viewer') or {}).get('login', ''), None, True)
        before = current()
        matches = [r for r in before['items'] if r['id'] == review_id]
        if before['actor'] != target.get('actor') or len(matches) != 1 or matches[0]['read_version'] != target['read_version']:
            raise Failure('Private review changed. Refresh before verifying publication contents.', 'stale')
        review, comments = self.load_pending(request['number'], review_id)
        record = pending_record(review, comments, before['actor'])
        after = current()
        latest = [r for r in after['items'] if r['id'] == review_id]
        if (after['actor'] != before['actor'] or len(latest) != 1 or latest[0]['read_version'] != target['read_version']
                or len(comments) != latest[0]['total'] or len({c['id'] for c in comments}) != len(comments)
                or record['author'].casefold() != matches[0]['author'].casefold() or record['head'] != matches[0]['head']
                or record['body'] != matches[0]['body']):
            raise Failure('Private review changed while verifying complete contents. Refresh.', 'stale')
        record.update(complete=True, total=len(comments), read_version=target['read_version'])
        return {'target': target, 'snapshot': reference.get('snapshot'), 'review': record}

    def load_pending(self, number, review_id):
        if not re.fullmatch(r'[0-9]+', review_id):
            raise Failure('Invalid pending review identity.', 'validation')
        path = 'repos/' + self.repo + '/pulls/' + str(int(number)) + '/reviews/' + review_id
        review = self.api(path)
        if str(review.get('id')) != review_id or review.get('state') != 'PENDING':
            raise Failure('The review is no longer pending; refresh to inspect its state.', 'stale')
        if not isinstance(review.get('commit_id'), str) or not review['commit_id']:
            raise Failure('The pending review has no verified source revision.', 'validation')
        comments = self.pages(path + '/comments')
        if any(c.get('pull_request_review_id') != review['id'] for c in comments):
            raise Failure('Pending review comments have mismatched ownership.', 'validation')
        after = self.api(path)
        if any(after.get(k) != review.get(k) for k in ('id', 'body', 'state', 'commit_id')):
            raise Failure('Pending review changed while loading; refresh again.', 'stale')
        return review, comments

    def save_pending(self, request):
        draft = request['draft']
        operation, mode, kind = draft.get('id'), draft.get('pending_mode'), draft.get('kind')
        if not isinstance(operation, str) or not re.fullmatch(r'[A-Za-z0-9_-]+', operation) or mode not in ('create', 'add'):
            raise Failure('Invalid private-save operation.', 'validation')
        if kind not in ('start_pending', 'comment', 'file_comment', 'reply') or (kind == 'start_pending' and mode != 'create'):
            raise Failure('Unsupported private-save target.', 'validation')
        if mode == 'create' and kind in ('file_comment', 'reply'):
            raise Failure('Start a pending review before adding whole-file feedback or private replies.', 'validation')
        if kind == 'reply' and (not isinstance(draft.get('thread'), str) or not re.fullmatch(r'[0-9]+', draft['thread'])):
            raise Failure('Invalid private reply thread.', 'validation')
        review_id = draft.get('pending_review', '')
        if mode == 'add' and (not isinstance(review_id, str) or not re.fullmatch(r'[0-9]+', review_id)):
            raise Failure('Invalid pending review identity.', 'validation')
        if mode == 'create' and review_id:
            raise Failure('A new pending review cannot target an existing ID.', 'validation')
        fields = ('id', 'kind', 'pending_mode', 'pending_review', 'actor', 'pending_head', 'head', 'base_tip', 'snapshot', 'path', 'old_path', 'side', 'start', 'end', 'suggestion', 'body') + (('thread',) if kind == 'reply' else ())
        digest = hashlib.sha256(json.dumps({k: draft.get(k) for k in fields}, sort_keys=True).encode()).hexdigest()
        marker = '<!-- revue-pending:' + operation + ':' + digest + ' -->'
        path = 'repos/' + self.repo + '/pulls/' + str(int(request['number']))
        receipt = {'id': operation, 'pending_mode': mode, 'actor': draft.get('actor')}
        if kind == 'reply': receipt['thread'] = draft['thread']
        def verify_first_comment(native_id):
            if kind != 'comment' or mode != 'create': return
            try:
                comments = self.pages(path + '/reviews/' + native_id + '/comments')
                found = [c for c in comments if marker in (c.get('body') or '') and str(c.get('pull_request_review_id')) == native_id]
                if len(found) != 1:
                    raise Failure('The created review has no unique first-comment receipt.', 'unknown', True)
            except Failure as error:
                error.unknown = True
                raise

        # Recovery is identity/marker based, including after browser publication.
        listing = path + ('/reviews' if mode == 'create' else '/reviews/' + review_id + '/comments')
        objects = self.pages(listing)
        matches = [r for r in objects if marker in (r.get('body') or '')]
        if len(matches) == 1:
            obj = matches[0]
            if mode == 'add' and (str(obj.get('pull_request_review_id')) != review_id or (kind == 'reply' and str(obj.get('in_reply_to_id')) != draft['thread'])):
                raise Failure('Mismatched private comment receipt.', 'unknown', True)
            if mode == 'create': verify_first_comment(str(obj['id']))
            return dict(receipt, pending_review=str(obj['id']) if mode == 'create' else review_id, recovered=True,
                        url=obj.get('html_url', ''))
        if matches or request.get('reconcile'):
            raise Failure('No unique matching private-save receipt. Nothing was saved again.', 'unknown', True)
        if not self.token:
            raise Failure('Sign in before saving private feedback.', 'auth')
        viewer = self.api('user').get('login', '')
        if not viewer or draft.get('actor') != 'github-login:' + viewer.casefold():
            raise Failure('Private review actor changed.', 'permission')
        fresh = self.api(path)
        if kind != 'reply' and (fresh['head']['sha'] != draft.get('head') or fresh['base']['sha'] != draft.get('base_tip')):
            raise Failure('PR comparison changed. Refresh before saving private feedback.', 'stale')
        parent = None
        if mode == 'create':
            if any(r.get('state') == 'PENDING' and (r.get('user') or {}).get('login', '').casefold() == viewer.casefold() for r in objects):
                raise Failure('A pending review already exists. Refresh and explicitly select it before saving.', 'stale')
        else:
            parent, _ = self.load_pending(request['number'], review_id)
            if (parent.get('user') or {}).get('login', '').casefold() != viewer.casefold():
                raise Failure('Pending review belongs to another actor.', 'permission')
            if parent['commit_id'] != draft.get('pending_head') or (kind != 'reply' and parent['commit_id'] != draft.get('head')):
                raise Failure('Pending review concerns another source revision. Inspect it before adding feedback.', 'stale')
        if not isinstance(draft.get('body'), str) or (kind != 'start_pending' and not draft['body'].strip()):
            raise Failure('Write private feedback first.', 'validation')
        validate_suggestion(draft)
        if kind not in ('start_pending', 'reply'):
            files = self.pages(path + '/files')
            file = next((f for f in files if f['filename'] == draft.get('path')), None)
            if file is None or draft.get('old_path') != file.get('previous_filename', file['filename']):
                raise Failure('Private comment file or rename target changed.', 'stale')
            if kind == 'comment':
                if draft.get('side') not in ('base', 'head') or type(draft.get('start')) is not int or type(draft.get('end')) is not int or not 1 <= draft['start'] <= draft['end']:
                    raise Failure('Invalid private comment line range.', 'validation')
                # Require every selected line to belong to the returned diff.
                allowed, row = set(), 0
                side = draft['side']
                for line in file.get('patch', '').splitlines():
                    hunk = re.match(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@', line)
                    if hunk:
                        row = int(hunk[1 if side == 'base' else 2])
                    elif line[:1] in (' ', '-' if side == 'base' else '+'):
                        allowed.add(row)
                        row += 1
                if draft['end'] - draft['start'] + 1 > len(allowed) or any(n not in allowed for n in range(draft['start'], draft['end'] + 1)):
                    raise Failure('Private comment range is outside the returned diff.', 'validation')
            elif any(k in draft for k in ('side', 'start', 'end', 'line')):
                raise Failure('Whole-file feedback has no line coordinates.', 'validation')
        body = draft['body'] + '\n\n' + marker
        if mode == 'create':
            payload = {'commit_id': draft['head'], 'body': body if kind == 'start_pending' else marker}
            if kind == 'comment':
                side = 'LEFT' if draft['side'] == 'base' else 'RIGHT'
                comment = {'path': draft['path'], 'line': draft['end'], 'side': side, 'body': body}
                if draft['start'] != draft['end']:
                    comment.update(start_line=draft['start'], start_side=side)
                payload['comments'] = [comment]
            try:
                result = self.api(path + '/reviews', 'POST', payload)
            except Failure as error:
                if error.code == 'too_large': error.unknown = True
                raise
            if not isinstance(result, dict) or not isinstance(result.get('id'), int) or result.get('state') != 'PENDING' or marker not in (result.get('body') or ''):
                raise Failure('No matching pending review creation receipt.', 'unknown', True)
            verify_first_comment(str(result['id']))
            return dict(receipt, pending_review=str(result['id']), url=result.get('html_url', ''))
        if not isinstance(parent.get('node_id'), str) or not parent['node_id']:
            raise Failure('The pending review has no GraphQL identity.', 'validation')
        if kind == 'reply':
            thread = self.thread_states(request['number']).get(draft['thread'])
            if not thread or not thread.get('native_id') or not thread.get('capabilities', {}).get('reply', {}).get('enabled'):
                raise Failure('This thread is unavailable or does not allow replies.', 'permission')
            value = {'pullRequestReviewId': parent['node_id'], 'pullRequestReviewThreadId': thread['native_id'],
                     'body': body, 'clientMutationId': operation}
            query = """mutation($input:AddPullRequestReviewThreadReplyInput!) {
              addPullRequestReviewThreadReply(input:$input) { clientMutationId comment {
                body databaseId replyTo { databaseId } pullRequestReview { databaseId }
              } } }"""
            result = self.graphql(query, {'input': value}, write=True)
            try:
                mutation = result['addPullRequestReviewThreadReply']
                comment = mutation['comment']
                if mutation['clientMutationId'] != operation or marker not in comment['body'] or str(comment['pullRequestReview']['databaseId']) != review_id or str(comment['replyTo']['databaseId']) != draft['thread']:
                    raise ValueError('Mismatched private reply')
            except (KeyError, TypeError, ValueError):
                raise Failure('No matching private reply receipt.', 'unknown', True)
            return dict(receipt, pending_review=review_id)
        value = {'pullRequestReviewId': parent['node_id'], 'path': draft['path'], 'body': body, 'clientMutationId': operation,
                 'subjectType': 'FILE' if kind == 'file_comment' else 'LINE'}
        if kind == 'comment':
            value.update(line=draft['end'], side='LEFT' if draft['side'] == 'base' else 'RIGHT')
            if draft['start'] != draft['end']:
                value.update(startLine=draft['start'], startSide=value['side'])
        query = '''mutation($input:AddPullRequestReviewThreadInput!) {
          addPullRequestReviewThread(input:$input) { clientMutationId thread {
            comments(first:1) { nodes { body databaseId pullRequestReview { databaseId } } }
          } } }'''
        result = self.graphql(query, {'input': value}, write=True)
        try:
            mutation = result['addPullRequestReviewThread']
            nodes = mutation['thread']['comments']['nodes']
            if mutation['clientMutationId'] != operation or len(nodes) != 1 or marker not in nodes[0]['body'] or str(nodes[0]['pullRequestReview']['databaseId']) != review_id:
                raise ValueError('Mismatched private save')
        except (KeyError, TypeError, ValueError):
            raise Failure('No matching private comment receipt.', 'unknown', True)
        return dict(receipt, pending_review=review_id)

    def delete_message(self, request):
        draft = request['draft']
        if (not isinstance(draft.get('id'), str) or not re.fullmatch(r'[A-Za-z0-9_-]+', draft['id'])
                or not isinstance(draft.get('message'), str) or not re.fullmatch(r'[0-9]+', draft['message'])
                or not isinstance(draft.get('thread'), str) or (draft['thread'] and not re.fullmatch(r'[0-9]+', draft['thread']))
                or draft.get('message_kind') != 'comment' or draft.get('delete_scope') != 'message'
                or draft.get('body') != '' or draft.get('pending_review')
                or not isinstance(draft.get('original_body'), str) or not isinstance(draft.get('expected_version'), str)
                or not draft['expected_version']):
            raise Failure('Invalid published comment deletion target.', 'validation')
        if not self.token:
            raise Failure('Sign in to verify the deleting actor.', 'auth')
        viewer = self.api('user').get('login', '')
        actor = 'github-login:' + viewer.casefold() if viewer else ''
        if not actor or actor != draft.get('actor'):
            raise Failure('Published deletion actor changed.', 'permission')
        number = str(int(request['number']))
        prefix = 'repos/' + self.repo
        pr_path = prefix + '/pulls/' + number
        pr = self.api(pr_path)
        if not isinstance(pr, dict) or str(pr.get('number')) != number:
            raise Failure('Cannot verify access to the selected pull request.', 'incomplete')
        inline = bool(draft['thread'])
        collection = pr_path + '/comments' if inline else prefix + '/issues/' + number + '/comments'
        membership_key = 'pull_request_url' if inline else 'issue_url'
        membership_path = '/' + (pr_path if inline else prefix + '/issues/' + number)
        comments = self.pages(collection)
        ids = set()
        for comment in comments:
            identifier = str(comment.get('id', ''))
            if (not identifier.isdigit() or identifier in ids
                    or urllib.parse.urlparse(comment.get(membership_key, '')).path.casefold() != membership_path.casefold()):
                raise Failure('Cannot verify the complete review comment inventory.', 'incomplete')
            ids.add(identifier)
        matches = [c for c in comments if str(c['id']) == draft['message']]
        receipt = {key: draft[key] for key in ('id', 'message', 'message_kind', 'thread', 'actor', 'delete_scope', 'expected_version')}
        receipt.update(deleted=True, url='')
        if request.get('reconcile'):
            # Successful review-specific inventory + same actor establishes
            # observable absence. It does not attribute absence to this request.
            if not matches:
                return dict(receipt, observed=True)
            raise Failure('The message still exists. Recovery did not delete it again.', 'unknown', True)
        if len(matches) != 1:
            raise Failure('The selected message is no longer available. Refresh.', 'stale')
        current = matches[0]
        def verify(comment):
            if (str(comment.get('id')) != draft['message']
                    or urllib.parse.urlparse(comment.get(membership_key, '')).path.casefold() != membership_path.casefold()
                    or (comment.get('user') or {}).get('login', '').casefold() != viewer.casefold()
                    or (inline and str(comment.get('in_reply_to_id') or comment['id']) != draft['thread'])):
                raise Failure('The comment owner, review or thread changed.', 'permission')
            normalized = normalize_comment(comment)
            if normalized['version'] != draft['expected_version'] or normalized['body'] != draft['original_body']:
                raise Failure('Comment changed. Cancel this operation and inspect its current text.', 'stale')
        verify(current)
        if inline and draft['message'] == draft['thread'] and any(str(c.get('in_reply_to_id')) == draft['message'] for c in comments):
            raise Failure('Root deletion with replies is unavailable until GitHub scope is verified.', 'permission')
        node_id = current.get('node_id')
        if not isinstance(node_id, str) or not node_id:
            raise Failure('Comment permission identity is unavailable.', 'incomplete')
        native_type = 'PullRequestReviewComment' if inline else 'IssueComment'
        parent = ' pullRequestReview { state }' if inline else ''
        node = self.graphql('query($id:ID!) { node(id:$id) { ... on ' + native_type +
                            ' { id body viewerCanDelete' + parent + ' } } }', {'id': node_id}).get('node')
        if (not isinstance(node, dict) or node.get('id') != node_id or node.get('viewerCanDelete') is not True
                or node.get('body') != current.get('body')
                or (inline and (node.get('pullRequestReview') or {}).get('state') not in ('COMMENTED', 'APPROVED', 'CHANGES_REQUESTED', 'DISMISSED'))):
            raise Failure('This published comment is no longer deletable.', 'permission')
        path = prefix + ('/pulls/comments/' if inline else '/issues/comments/') + draft['message']
        verify(self.api(path))
        # No documented conditional DELETE: a concurrent edit/reply can still
        # occur after preflight. Do not advertise atomic conflict protection.
        try:
            result = self.api(path, 'DELETE')
        except Failure as error:
            if error.code == 'too_large': error.unknown = True
            raise
        if result is not None:
            raise Failure('Unexpected deletion response. Check the outcome.', 'unknown', True)
        return receipt

    def delete_pending_comment(self, request):
        draft = request['draft']
        for key in ('pending_review', 'message', 'thread'):
            if not isinstance(draft.get(key), str) or not re.fullmatch(r'[0-9]+', draft[key]):
                raise Failure('Invalid private comment target.', 'validation')
        if (not isinstance(draft.get('id'), str) or not re.fullmatch(r'[A-Za-z0-9_-]+', draft['id'])
                or draft.get('message_kind') != 'comment' or draft.get('body') != ''
                or draft.get('delete_scope') != 'message'):
            raise Failure('Invalid private comment deletion.', 'validation')
        if not self.token:
            raise Failure('Sign in to verify private comment ownership.', 'auth')
        viewer = self.api('user').get('login', '')
        actor = 'github-login:' + viewer.casefold() if viewer else ''
        if not actor or actor != draft.get('actor'):
            raise Failure('Private comment actor changed.', 'permission')
        prefix = 'repos/' + self.repo
        review_path = prefix + '/pulls/' + str(int(request['number'])) + '/reviews/' + draft['pending_review']
        parent = self.api(review_path)
        if (not isinstance(parent, dict) or str(parent.get('id')) != draft['pending_review']
                or (parent.get('user') or {}).get('login', '').casefold() != viewer.casefold()):
            raise Failure('Cannot verify the selected review and owner.', 'permission')
        comments = self.pages(review_path + '/comments')
        if any(str(c.get('pull_request_review_id')) != draft['pending_review'] for c in comments):
            raise Failure('Private comment inventory has mismatched ownership.', 'incomplete')
        matches = [c for c in comments if str(c.get('id')) == draft['message']]
        receipt = {key: draft[key] for key in ('id', 'message', 'message_kind', 'thread', 'pending_review', 'actor', 'delete_scope')}
        receipt['deleted'] = True
        if request.get('reconcile'):
            # A missing global ID or 404 does not prove deletion. A successful
            # review-specific list for its verified owner establishes absence.
            if not matches:
                return dict(receipt, observed=True)
            raise Failure('The comment still exists. Recovery did not delete it again.', 'unknown', True)
        if len(matches) != 1 or parent.get('state') != 'PENDING' or parent.get('commit_id') != draft.get('pending_head'):
            raise Failure('Private comment or review state changed. Refresh before deleting.', 'stale')
        current = matches[0]
        if (str(current.get('in_reply_to_id') or current['id']) != draft['thread']
                or (current.get('user') or {}).get('login', '').casefold() != viewer.casefold()):
            raise Failure('The selected comment does not match its thread or owner.', 'permission')
        normalized = normalize_comment(current)
        if normalized['version'] != draft.get('expected_version') or normalized['body'] != draft.get('original_body'):
            raise Failure('Comment changed. Cancel this operation and inspect its current contents.', 'stale')
        if draft['message'] == draft['thread']:
            all_comments = self.pages(prefix + '/pulls/' + str(int(request['number'])) + '/comments') + comments
            if any(str(c.get('in_reply_to_id')) == draft['message'] for c in all_comments):
                raise Failure('Root deletion with replies is not supported until its scope is verified.', 'permission')
        # Verify current service permission instead of inferring it from authorship.
        node_id = current.get('node_id')
        if not isinstance(node_id, str) or not node_id:
            raise Failure('Comment permission identity is unavailable.', 'incomplete')
        node = self.graphql("""query($id:ID!) { node(id:$id) { ... on PullRequestReviewComment {
          id viewerCanDelete pullRequestReview { databaseId state }
        } } }""", {'id': node_id}).get('node')
        if (not isinstance(node, dict) or node.get('id') != node_id
                or node.get('viewerCanDelete') is not True
                or str((node.get('pullRequestReview') or {}).get('databaseId')) != draft['pending_review']
                or (node.get('pullRequestReview') or {}).get('state') != 'PENDING'):
            raise Failure('This private comment is no longer deletable.', 'permission')
        # GitHub has no documented conditional-delete version field. Preflight
        # cannot prevent another client editing/publishing after these reads.
        try:
            result = self.api(prefix + '/pulls/comments/' + draft['message'], 'DELETE')
        except Failure as error:
            if error.code == 'too_large': error.unknown = True
            raise
        if result is not None:
            raise Failure('Unexpected delete response. Check the comment outcome.', 'unknown', True)
        return receipt

    def discard_pending(self, request):
        draft = request['draft']
        review_id, operation = draft.get('pending_review'), draft.get('id')
        if not isinstance(review_id, str) or not re.fullmatch(r'[0-9]+', review_id) or not isinstance(operation, str) or not re.fullmatch(r'[A-Za-z0-9_-]+', operation):
            raise Failure('Invalid pending review operation.', 'validation')
        if not self.token:
            raise Failure('Sign in to verify the owner of the pending review.', 'auth')
        viewer = self.api('user').get('login', '')
        actor = 'github-login:' + viewer.casefold() if viewer else ''
        if not actor or actor != draft.get('actor'):
            raise Failure('Pending review actor changed.', 'permission')
        path = 'repos/' + self.repo + '/pulls/' + str(int(request['number']))
        receipt = {'id': operation, 'pending_review': review_id, 'actor': actor, 'discarded': True}
        if request.get('reconcile'):
            # A 404 can mean lost access. Require a successful complete review list
            # for the same verified actor; absence is observation, not attribution.
            reviews = self.pages(path + '/reviews')
            if not any(str(r.get('id')) == review_id for r in reviews):
                return dict(receipt, observed=True)
            raise Failure('The review still exists. Nothing was deleted again.', 'unknown', True)
        review, comments = self.load_pending(request['number'], review_id)
        if (review.get('user') or {}).get('login', '').casefold() != viewer.casefold():
            raise Failure('The pending review belongs to another actor.', 'permission')
        current = pending_record(review, comments, actor)
        if any(current[key] != draft.get(field) for key, field in (
                ('version', 'expected_version'), ('head', 'pending_head'),
                ('comments', 'pending_comments'), ('body', 'pending_body'))):
            raise Failure('Pending review changed. Cancel this local operation and inspect the refreshed review before discarding.', 'stale')
        try:
            result = self.api(path + '/reviews/' + review_id, 'DELETE')
        except Failure as exc:
            if exc.code == 'too_large':
                raise Failure(str(exc), exc.code, True) from exc
            raise
        if not isinstance(result, dict) or str(result.get('id')) != review_id:
            raise Failure('No matching pending-review discard receipt. Check server state.', 'unknown', True)
        return receipt

    def submit_pending(self, request):
        draft = request['draft']
        review_id, operation = draft.get('pending_review'), draft.get('id')
        if not isinstance(review_id, str) or not re.fullmatch(r'[0-9]+', review_id) or not isinstance(operation, str) or not re.fullmatch(r'[A-Za-z0-9_-]+', operation):
            raise Failure('Invalid pending review operation.', 'validation')
        states = {'COMMENT': 'COMMENTED', 'APPROVE': 'APPROVED', 'REQUEST_CHANGES': 'CHANGES_REQUESTED'}
        if draft.get('event') not in states:
            raise Failure('Unsupported review decision.', 'validation')
        path = 'repos/' + self.repo + '/pulls/' + str(int(request['number']))
        review_path = path + '/reviews/' + review_id
        digest = hashlib.sha256(json.dumps({k: draft.get(k) for k in ('id', 'pending_review', 'actor', 'expected_version', 'pending_head', 'pending_comments', 'head', 'base_tip', 'snapshot', 'event', 'body')}, sort_keys=True).encode()).hexdigest()
        marker = '<!-- revue-publish:' + operation + ':' + digest + ' -->'
        review = self.api(review_path)
        if str(review.get('id')) != review_id:
            raise Failure('GitHub returned a different review.', 'validation')
        receipt = {'id': operation, 'pending_review': review_id, 'actor': draft.get('actor'), 'event': draft['event'], 'url': review.get('html_url', '')}
        if review.get('state') != 'PENDING' and marker in (review.get('body') or ''):
            return dict(receipt, recovered=True)
        if request.get('reconcile'):
            raise Failure('No matching publication receipt. Nothing was submitted again.', 'unknown', True)
        if not self.token:
            raise Failure('Sign in before publishing the pending review.', 'auth')
        viewer = self.api('user').get('login', '')
        actor = 'github-login:' + viewer.casefold() if viewer else ''
        if not actor or actor != draft.get('actor') or (review.get('user') or {}).get('login', '').casefold() != viewer.casefold():
            raise Failure('Pending review actor or ownership changed.', 'permission')
        review, comments = self.load_pending(request['number'], review_id)
        current = pending_record(review, comments, actor)
        if current['version'] != draft.get('expected_version') or current['head'] != draft.get('pending_head') or current['comments'] != draft.get('pending_comments'):
            raise Failure('Pending review changed. Refresh and inspect its comments before preparing publication again.', 'stale')
        fresh = self.api(path)
        if fresh['head']['sha'] != draft.get('head') or fresh['base']['sha'] != draft.get('base_tip'):
            raise Failure('PR changed while preparing publication; refresh and inspect the new comparison.', 'stale')
        _, actions, _ = self.action_rules(fresh)
        action = next((a for a in actions if a['id'] == draft['event']), {})
        if not action.get('enabled'):
            raise Failure(action.get('reason', 'Review decision unavailable.'), 'permission')
        if not isinstance(draft.get('body'), str) or (not draft['body'].strip() and not comments and draft['event'] != 'APPROVE'):
            raise Failure('Write a review summary first.', 'validation')
        markers = re.findall(r'<!-- revue(?:-batch|-edit|-publish|-pending)?:[A-Za-z0-9_:-]+ -->', review.get('body') or '')
        body = draft['body'] + ''.join('\n\n' + item for item in markers + [marker])
        try:
            result = self.api(review_path + '/events', 'POST', {'event': draft['event'], 'body': body})
        except Failure as error:
            if error.code == 'too_large':
                error.unknown = True
            raise
        if not isinstance(result, dict) or str(result.get('id')) != review_id or result.get('state') != states[draft['event']] or marker not in (result.get('body') or ''):
            raise Failure('No matching published review receipt; inspect or reconcile before acting again.', 'unknown', True)
        return dict(receipt, url=result.get('html_url', receipt['url']))

    def reaction_context(self, request, target):
        message, thread = target.get('message'), target.get('thread', '')
        if target.get('message_kind') != 'comment' or not isinstance(message, str) or not re.fullmatch(r'[0-9]+', message) or not isinstance(thread, str) or (thread and not re.fullmatch(r'[0-9]+', thread)):
            raise Failure('Reactions support exact inline or conversation comment identities.', 'validation')
        prefix, number = 'repos/' + self.repo, str(int(request['number']))
        listing = prefix + ('/pulls/' if thread else '/issues/') + number + '/comments'
        matches = [c for c in self.pages(listing) if str(c['id']) == message]
        if len(matches) != 1:
            raise Failure('The message is unavailable in this review.', 'missing')
        comment = matches[0]
        if thread and str(comment.get('in_reply_to_id') or comment['id']) != thread:
            raise Failure('The reaction target belongs to a different thread.', 'validation')
        if thread and comment.get('pull_request_review_id'):
            reviews = self.pages(prefix + '/pulls/' + number + '/reviews')
            review = next((r for r in reviews if r['id'] == comment['pull_request_review_id']), None)
            if review is None or review.get('state') == 'PENDING':
                raise Failure('Cannot verify that this reaction target is published.', 'permission')
        return prefix + ('/pulls/comments/' if thread else '/issues/comments/') + message + '/reactions'

    def rendered_links(self, request):
        target = request.get('target', {})
        kind, thread, message = target.get('message_kind'), target.get('thread', ''), target.get('message')
        if not isinstance(message, str) or not re.fullmatch(r'[0-9]+', message) or not isinstance(thread, str):
            raise Failure('Invalid link message identity.', 'validation')
        prefix = 'repos/' + self.repo
        path = prefix + '/pulls/' + str(int(request['number']))
        pending = target.get('pending_review', '')
        if pending and (not isinstance(pending, str) or not re.fullmatch(r'[0-9]+', pending)):
            raise Failure('Invalid private link target.', 'validation')
        if thread:
            if kind != 'comment' or not re.fullmatch(r'[0-9]+', thread):
                raise Failure('Invalid link thread.', 'validation')
            listing = path + ('/reviews/' + pending if pending else '') + '/comments'
        elif kind == 'comment' and not pending:
            listing = prefix + '/issues/' + str(int(request['number'])) + '/comments'
        elif kind in ('APPROVED', 'CHANGES_REQUESTED', 'COMMENTED', 'DISMISSED') and not pending:
            listing = path + '/reviews'
        else:
            raise Failure('Rendered links are unavailable for this message kind.', 'validation')
        matches = [c for c in self.pages(listing) if str(c.get('id')) == message]
        if len(matches) != 1:
            raise Failure('The selected message is no longer available.', 'missing')
        current = matches[0]
        if (thread and str(current.get('in_reply_to_id') or current['id']) != thread
                or pending and str(current.get('pull_request_review_id')) != pending):
            raise Failure('Link message no longer belongs to the selected thread/review.', 'stale')
        normalized = normalize_comment(current, kind)
        if normalized['version'] != target.get('expected_version') or normalized['body'] != target.get('body'):
            raise Failure('Message changed. Refresh before loading its links.', 'stale')
        node_id = current.get('node_id')
        if not isinstance(node_id, str) or not node_id:
            raise Failure('Rendered message identity is unavailable.', 'incomplete')
        node = self.graphql("""query($id:ID!) { node(id:$id) {
          ... on PullRequestReviewComment { id body bodyHTML }
          ... on IssueComment { id body bodyHTML }
          ... on PullRequestReview { id body bodyHTML }
        } }""", {'id': node_id}).get('node')
        if (not isinstance(node, dict) or node.get('id') != node_id or node.get('body') != (current.get('body') or '')
                or not isinstance(node.get('bodyHTML'), str)):
            raise Failure('The rendered message changed or is unavailable. Refresh before reading its links.', 'stale')
        parser = RenderedLinks(normalized['url'])
        parser.feed(node['bodyHTML'])
        return {'message': message, 'message_kind': kind, 'thread': thread,
                'version': normalized['version'], 'links': parser.links}

    def message_history(self, request):
        if not self.token:
            raise Failure('Sign in to read edit history; open the message on GitHub instead.', 'auth')
        target = request.get('target', {})
        message, kind, thread = target.get('message'), target.get('message_kind'), target.get('thread', '')
        if not isinstance(message, str) or not re.fullmatch(r'[0-9]+', message) or not isinstance(thread, str) or (thread and not re.fullmatch(r'[0-9]+', thread)):
            raise Failure('Invalid edit-history message identity.', 'validation')
        prefix = 'repos/' + self.repo
        number = str(int(request['number']))
        if kind == 'comment':
            path = prefix + ('/pulls/comments/' if thread else '/issues/comments/') + message
            typename = 'PullRequestReviewComment' if thread else 'IssueComment'
        elif kind in ('APPROVED', 'CHANGES_REQUESTED', 'COMMENTED', 'DISMISSED') and not thread:
            path = prefix + '/pulls/' + number + '/reviews/' + message
            typename = 'PullRequestReview'
        else:
            raise Failure('Edit history is unavailable for this message kind.', 'validation')
        raw = self.api(path)
        if not isinstance(raw, dict) or str(raw.get('id')) != message:
            raise Failure('The selected message is unavailable.', 'missing')
        if kind == 'comment':
            link = raw.get('pull_request_url' if thread else 'issue_url', '')
            expected = '/' + prefix + ('/pulls/' if thread else '/issues/') + number
            if not isinstance(link, str) or not urllib.parse.urlsplit(link).path.lower().endswith(expected.lower()):
                raise Failure('Edit history belongs to a different review.', 'validation')
            if thread and str(raw.get('in_reply_to_id') or raw['id']) != thread:
                raise Failure('Edit history belongs to a different thread.', 'validation')
            if thread:
                review_id = raw.get('pull_request_review_id')
                if not isinstance(review_id, int):
                    raise Failure('Published review membership is unavailable.', 'incomplete')
                review = self.api(prefix + '/pulls/' + number + '/reviews/' + str(review_id))
                if str(review.get('id')) != str(review_id) or review.get('state') not in ('APPROVED', 'CHANGES_REQUESTED', 'COMMENTED', 'DISMISSED'):
                    raise Failure('Private or unavailable comment history must be viewed on GitHub.', 'permission')
        elif raw.get('state') != kind:
            raise Failure('Review state changed; refresh before reading its history.', 'stale')
        current = normalize_comment(raw, kind)
        if current['version'] != target.get('expected_version') or current['body'] != target.get('body'):
            raise Failure('Message changed; refresh before reading edit history.', 'stale')
        node_id = raw.get('node_id')
        if not isinstance(node_id, str) or not node_id:
            raise Failure('Native message identity is unavailable.', 'incomplete')
        cursor = request.get('cursor', '')
        if not isinstance(cursor, str):
            raise Failure('Invalid edit-history cursor.', 'validation')
        binding = {'host': self.conn['host'], 'repo': self.repo, 'number': number, 'node': node_id, 'version': current['version']}
        after, total, loaded = None, None, 0
        if cursor:
            try:
                saved = json.loads(cursor)
                if len(cursor) > 10000 or any(saved.get(k) != v for k, v in binding.items()) or not isinstance(saved.get('after'), str) or not saved['after'] or type(saved.get('total')) is not int or saved['total'] < 0 or type(saved.get('loaded')) is not int or not 0 < saved['loaded'] < saved['total']:
                    raise ValueError()
                after, total, loaded = saved['after'], saved['total'], saved['loaded']
            except (ValueError, TypeError, AttributeError):
                raise Failure('Edit-history cursor changed; reload history.', 'stale')
        query = '''query($id:ID!, $after:String){node(id:$id){... on ''' + typename + ''' {
          id body userContentEdits(first:50,after:$after){totalCount pageInfo{hasNextPage endCursor}
            nodes{id editedAt editor{login} deletedAt deletedBy{login} diff}}
        }}}'''
        node = self.graphql(query, {'id': node_id, 'after': after}).get('node')
        if not isinstance(node, dict) or node.get('id') != node_id or node.get('body') != (raw.get('body') or ''):
            raise Failure('Message changed or edit history is unavailable.', 'stale')
        connection = node.get('userContentEdits')
        if not isinstance(connection, dict):
            raise Failure('GitHub did not expose edit history; use the message link.', 'incomplete')
        nodes, next_cursor = feedback_connection(connection, after)
        count = connection.get('totalCount')
        if type(count) is not int or count < loaded + len(nodes) or len(nodes) > 50 or total is not None and total != count or not next_cursor and count != loaded + len(nodes):
            raise Failure('Edit history changed; reload history.', 'stale')
        items, seen = [], set()
        for edit in nodes:
            if not isinstance(edit, dict) or not isinstance(edit.get('id'), str) or not edit['id'] or edit['id'] in seen or not isinstance(edit.get('editedAt'), str):
                raise Failure('GitHub returned incomplete edit metadata.', 'incomplete')
            seen.add(edit['id'])
            removed = edit.get('deletedAt') is not None
            content = edit.get('diff')
            state = 'redacted' if removed else 'available' if isinstance(content, str) else 'unavailable'
            actor = (edit.get('editor') or {}).get('login', '')
            details = ['GitHub-provided edit content; not a reconstructed patch']
            if removed:
                details = ['Redacted at ' + str(edit['deletedAt']) + ' by ' + ((edit.get('deletedBy') or {}).get('login') or 'unavailable actor')]
            items.append({'id': edit['id'], 'kind': 'Edit', 'title': 'Recorded edit', 'actor': actor,
                          'created': edit['editedAt'], 'body': content.replace('\r\n', '\n') if state == 'available' else '',
                          'url': current['url'], 'details': details, 'provenance': 'GitHub edit history', 'content_state': state})
        fresh = normalize_comment(self.api(path), kind)
        if fresh['version'] != current['version']:
            raise Failure('Message changed during history retrieval; refresh and reload.', 'stale')
        return {'target': target, 'cursor': cursor, 'items': list(reversed(items)), 'complete': not next_cursor,
                'next_cursor': json.dumps(dict(binding, after=next_cursor, total=count, loaded=loaded + len(nodes)), sort_keys=True) if next_cursor else '',
                'total': count, 'scope': 'GitHub-provided edit content; may include initial creation. Redacted content is not reconstructed.'}

    def reactions(self, request):
        path = self.reaction_context(request, request['target'])
        user = {}
        if self.token:
            try:
                user = self.api('user')
            except Failure:
                pass
        actor = reaction_actor(user)
        return {'items': reaction_groups(self.pages(path), actor), 'actor': actor,
                'actor_label': user.get('login', 'unavailable'), 'complete': True}

    def change_reaction(self, request):
        draft = request['draft']
        if not isinstance(draft.get('id'), str) or not re.fullmatch(r'[A-Za-z0-9_-]+', draft['id']) or draft.get('reaction') not in REACTIONS or type(draft.get('present')) is not bool or draft.get('body') != '':
            raise Failure('Invalid reaction operation.', 'validation')
        if not self.token:
            raise Failure('Sign in to verify your reaction state.', 'auth', bool(request.get('reconcile')))
        actor = reaction_actor(self.api('user'))
        if not actor or actor != draft.get('actor'):
            raise Failure('Reaction actor changed; use the original account to recover this operation.', 'permission', bool(request.get('reconcile')))
        path = self.reaction_context(request, draft)
        def own():
            return [r for r in self.pages(path) if r.get('content') == draft['reaction'] and reaction_actor(r.get('user') or {}) == actor]
        current = own()
        receipt = {key: draft[key] for key in ('id', 'message', 'message_kind', 'thread', 'actor', 'reaction', 'present')}
        receipt.update(url='', observed=True)
        if bool(current) == draft['present']:
            return dict(receipt, recovered=bool(request.get('reconcile')))
        if request.get('reconcile'):
            raise Failure('Requested reaction state is not observed. Recovery did not repeat the mutation.', 'unknown', True)
        try:
            if draft['present']:
                self.api(path, 'POST', {'content': draft['reaction']})
            else:
                if len(current) != 1 or type(current[0].get('id')) is not int:
                    raise Failure('The current actor reaction identity is ambiguous.', 'validation')
                self.api(path + '/' + str(current[0]['id']), 'DELETE')
        except Failure as error:
            if error.code == 'too_large':
                error.unknown = True
            raise
        try:
            observed = bool(own()) == draft['present']
        except Failure as error:
            error.unknown = True
            raise
        if not observed:
            raise Failure('Reaction update outcome is not confirmed; retain the operation and check again.', 'unknown', True)
        return receipt

    def edit_message(self, request):
        draft, number = request['draft'], int(request['number'])
        if not re.fullmatch(r'[A-Za-z0-9_-]+', str(draft.get('id', ''))):
            raise Failure('Invalid edit operation identity', 'validation')
        if not isinstance(draft.get('message'), str) or not re.fullmatch(r'[0-9]+', draft['message']):
            raise Failure('Invalid message identity', 'validation')
        kind, thread = draft.get('message_kind'), draft.get('thread', '')
        if not isinstance(thread, str):
            raise Failure('Invalid thread identity', 'validation')
        prefix = 'repos/' + self.repo
        pending_id = draft.get('pending_review', '')
        if pending_id and (not isinstance(pending_id, str) or not re.fullmatch(r'[0-9]+', pending_id)):
            raise Failure('Invalid pending review identity', 'validation')
        if thread:
            if kind != 'comment' or not re.fullmatch(r'[0-9]+', thread):
                raise Failure('Invalid inline message target', 'validation')
            listing = prefix + '/pulls/' + str(number) + ('/reviews/' + pending_id + '/comments' if pending_id else '/comments')
            path = prefix + '/pulls/comments/' + draft['message']
            method = 'PATCH'
        elif kind == 'comment':
            listing = prefix + '/issues/' + str(number) + '/comments'
            path = prefix + '/issues/comments/' + draft['message']
            method = 'PATCH'
        elif kind in ('APPROVED', 'CHANGES_REQUESTED', 'COMMENTED', 'DISMISSED') or (kind == 'PENDING' and pending_id == draft['message']):
            listing = prefix + '/pulls/' + str(number) + '/reviews'
            path = listing + '/' + draft['message']
            method = 'PUT'
        else:
            raise Failure('This message kind is not editable', 'validation')
        if pending_id and not (thread or kind == 'PENDING'):
            raise Failure('Invalid private edit target', 'validation')
        # Listing proves review membership; a bare global comment ID does not.
        matches = [c for c in self.pages(listing) if str(c['id']) == draft['message']]
        if len(matches) != 1:
            raise Failure('The message is no longer available in this review', 'missing', bool(request.get('reconcile')))
        current = matches[0]
        if thread and str(current.get('in_reply_to_id') or current['id']) != thread:
            raise Failure('Message does not belong to the selected thread', 'validation')
        fields = ('id', 'message', 'message_kind', 'thread', 'expected_version', 'original_body', 'body') + (('pending_review', 'actor') if pending_id else ())
        digest = hashlib.sha256(json.dumps({k: draft.get(k) for k in fields}, sort_keys=True, ensure_ascii=True).encode()).hexdigest()
        marker = '<!-- revue-edit:' + draft['id'] + ':' + digest + ' -->'
        receipt = {'id': draft['id'], 'message': draft['message'], 'message_kind': kind, 'thread': thread, 'url': current.get('html_url', '')}
        if pending_id:
            receipt.update(pending_review=pending_id, actor=draft.get('actor'))
        if marker in (current.get('body') or ''):
            return dict(receipt, recovered=True)
        if request.get('reconcile'):
            raise Failure('No matching edit receipt found. Keep this edit; recovery never updates the message again.', 'unknown', True)
        if '<!-- revue-edit:' + draft['id'] + ':' in (current.get('body') or ''):
            raise Failure('Edit operation ID was already used for a different replacement', 'validation')
        if not self.token:
            raise Failure('Sign in before editing feedback.', 'auth')
        viewer = self.api('user').get('login', '')
        current = self.api(path)
        if not isinstance(current, dict) or str(current.get('id', '')) != draft['message']:
            raise Failure('The current message could not be verified', 'validation')
        if not viewer or viewer.casefold() != (current.get('user') or {}).get('login', '').casefold():
            raise Failure('Only your own feedback can be edited here.', 'permission')
        if current.get('state') == 'PENDING' and not pending_id:
            raise Failure('Native pending reviews must be edited through their own workflow.', 'permission')
        if not thread and kind != 'comment' and current.get('state') != kind:
            raise Failure('The review state changed; refresh before editing its summary.', 'stale')
        if pending_id:
            if draft.get('actor') != 'github-login:' + viewer.casefold():
                raise Failure('Pending review actor changed.', 'permission')
            parent = self.api(prefix + '/pulls/' + str(number) + '/reviews/' + pending_id)
            if str(parent.get('id')) != pending_id or parent.get('state') != 'PENDING':
                raise Failure('The review is no longer pending. This private edit will not be applied to published feedback.', 'stale')
            if (parent.get('user') or {}).get('login', '').casefold() != viewer.casefold():
                raise Failure('Pending review belongs to another actor.', 'permission')
            if thread and str(current.get('pull_request_review_id')) != pending_id:
                raise Failure('Private message no longer belongs to this pending review.', 'stale')
        elif thread and current.get('pull_request_review_id'):
            reviews = self.pages(prefix + '/pulls/' + str(number) + '/reviews')
            review = next((r for r in reviews if r['id'] == current['pull_request_review_id']), None)
            if review is None or review.get('state') == 'PENDING':
                raise Failure('Cannot verify that this inline message is published; refresh or use the native review workflow.', 'permission')
        normalized = normalize_comment(current, kind)
        if normalized['version'] != draft.get('expected_version') or normalized['body'] != draft.get('original_body'):
            raise Failure('Message changed. Refresh and compare original, current and proposed text before accepting a new edit base.', 'stale')
        if not isinstance(draft.get('body'), str) or (not draft['body'].strip() and not (pending_id and kind == 'PENDING')):
            raise Failure('Write a replacement message first.', 'validation')
        # Preserve earlier creation/batch/edit receipts, including after later edits.
        markers = re.findall(r'<!-- revue(?:-batch|-edit|-publish|-pending)?:[A-Za-z0-9_:-]+ -->', current.get('body') or '')
        payload = {'body': draft['body'] + ''.join('\n\n' + item for item in markers + [marker])}
        # GitHub's documented update API has no compare-and-swap version field.
        # The preflight detects observed changes, not a concurrent write after it.
        try:
            result = self.api(path, method, payload)
        except Failure as error:
            if error.code == 'too_large':
                error.unknown = True
            raise
        if not isinstance(result, dict) or str(result.get('id', '')) != draft['message'] or marker not in (result.get('body') or ''):
            raise Failure('GitHub did not return the matching edit receipt; inspect or reconcile before acting again.', 'unknown', True)
        return dict(receipt, url=result.get('html_url', receipt['url']))

    def change_thread_state(self, request):
        draft = request['draft']
        operation = draft.get('id', '')
        desired = draft.get('resolved')
        expected = draft.get('expected_resolved')
        if not re.fullmatch(r'[A-Za-z0-9_-]+', operation) or type(desired) is not bool or type(expected) is not bool:
            raise Failure('Invalid thread-state operation', 'validation')
        states = self.thread_states(request['number'])
        thread = states.get(str(draft.get('thread', '')))
        if thread is None:
            raise Failure('Thread is not available in this review.', 'missing', bool(request.get('reconcile')))
        receipt = {'id': operation, 'thread': draft['thread'], 'resolved': desired, 'url': ''}
        if thread['resolved'] == desired:
            # Confirms the requested outcome, not which actor changed it.
            return dict(receipt, observed=True, recovered=bool(request.get('reconcile')))
        if request.get('reconcile'):
            raise Failure('The requested thread state is not observed. No mutation was repeated.', 'unknown', True)
        if thread['resolved'] != expected:
            raise Failure('Thread state changed; refresh before acting.', 'stale')
        action = 'resolve' if desired else 'reopen'
        if not thread['capabilities'][action]['enabled']:
            raise Failure(thread['capabilities'][action]['reason'], 'permission')
        mutation = 'resolveReviewThread' if desired else 'unresolveReviewThread'
        input_type = 'ResolveReviewThreadInput' if desired else 'UnresolveReviewThreadInput'
        query = 'mutation($input:' + input_type + '!) { ' + mutation + '(input:$input) { clientMutationId thread { id isResolved } } }'
        data = self.graphql(query, {'input': {'threadId': thread['native_id'], 'clientMutationId': operation}}, write=True)
        payload = data.get(mutation)
        result = payload.get('thread') if isinstance(payload, dict) else None
        result = result if isinstance(result, dict) else {}
        if result.get('id') != thread['native_id'] or result.get('isResolved') is not desired:
            raise Failure('Thread mutation returned no matching state; refresh to verify.', 'unknown', True)
        return receipt

    def batch(self, request):
        batch = dict(request['draft'])
        batch.pop('state', None)
        batch.pop('error', None)
        items = [dict(item) for item in batch.get('items', [])]
        if any(item.get('pending_mode') for item in items):
            raise Failure('Private-save drafts cannot be published in a batch.', 'validation')
        for item in items:
            item.pop('state', None)
        batch['items'] = items
        operation = batch.get('id', '')
        ids = [item.get('id', '') for item in items]
        if not re.fullmatch(r'[A-Za-z0-9_-]+', operation) or not items or any(not re.fullmatch(r'[A-Za-z0-9_-]+', i) for i in ids) or len(set(ids)) != len(ids) or operation in ids:
            raise Failure('A batch requires distinct operation and item IDs', 'validation')
        if any(item.get('kind') not in ('comment', 'review') for item in items):
            raise Failure('GitHub review batches accept inline comments and one review decision; send replies/conversation separately.', 'validation')
        reviews = [item for item in items if item['kind'] == 'review']
        if len(reviews) > 1 or any(any(item.get(k) != batch.get(k) for k in ('head', 'base_tip', 'snapshot')) for item in items):
            raise Failure('Select one comparison and at most one review decision', 'validation')
        fingerprint = hashlib.sha256(json.dumps(batch, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        marker = '<!-- revue:' + operation + ' -->'
        content_marker = '<!-- revue-batch:' + operation + ':' + fingerprint + ' -->'
        path = 'repos/' + self.repo + '/pulls/' + str(int(request['number']))

        def receipt(review, recovered=False):
            result = {'id': str(review['id']), 'url': review.get('html_url', ''), 'recovered': recovered}
            result['items'] = [dict(draft=item['id'], id=result['id'], url=result['url']) for item in items]
            return result

        for review in self.pages(path + '/reviews'):
            if marker in (review.get('body') or ''):
                if content_marker not in review['body']:
                    raise Failure('Batch ID already exists with different feedback', 'validation')
                return receipt(review, True)
        if request.get('reconcile'):
            raise Failure('No batch receipt found yet. Keep the frozen batch; nothing was reposted.', 'unknown', True)
        fresh = self.api(path)
        if fresh['head']['sha'] != batch['head'] or fresh['base']['sha'] != batch['base_tip']:
            raise Failure('PR changed. The batch remains anchored to its original comparison.', 'stale')
        rules, actions, _ = self.action_rules(fresh)
        event = reviews[0].get('event', 'COMMENT') if reviews else 'COMMENT'
        action = next((a for a in actions if a['id'] == event), None)
        if not rules['batch']['enabled'] or action is None or not action['enabled']:
            raise Failure((action or {}).get('reason') or 'This review action is unavailable', 'permission')
        comments = []
        for item in items:
            validate_suggestion(item)
            if item['kind'] != 'comment':
                continue
            if not item.get('body', '').strip() or item.get('side') not in ('base', 'head') or type(item.get('start')) is not int or type(item.get('end')) is not int or not 1 <= item['start'] <= item['end']:
                raise Failure('Invalid inline comment in batch', 'validation')
            side = 'LEFT' if item['side'] == 'base' else 'RIGHT'
            comment = {'path': item['path'], 'line': item['end'], 'side': side,
                       'body': item['body'] + '\n\n<!-- revue:' + item['id'] + ' -->'}
            if item['start'] != item['end']:
                comment.update(start_line=item['start'], start_side=side)
            comments.append(comment)
        body = reviews[0].get('body', '') if reviews else ''
        if not comments and action['body_required'] and not body.strip():
            raise Failure('This review decision requires a message', 'validation')
        # Receipt metadata is hidden; never invent human summary prose.
        payload = {'commit_id': batch['head'], 'event': event,
                   'body': body + '\n\n' + marker + '\n' + content_marker, 'comments': comments}
        return receipt(self.api(path + '/reviews', 'POST', payload))


def validate_suggestion(draft):
    if not draft.get('suggestion'):
        return
    if draft['suggestion'] is not True or draft.get('kind') != 'comment' or draft.get('side') != 'head':
        raise Failure('Suggestions require a head-side inline comment', 'validation')
    lines = draft.get('body', '').split('\n')
    index = found = 0
    while index < len(lines):
        fence = re.match(r'^ {0,3}(`{3,}|~{3,})\s*(.*)$', lines[index])
        if not fence:
            index += 1
            continue
        suggestion = fence[2].strip() == 'suggestion'
        closing = re.compile(r'^ {0,3}' + re.escape(fence[1][0]) + '{' + str(len(fence[1])) + r',}\s*$')
        index += 1
        while index < len(lines) and not closing.match(lines[index]):
            index += 1
        if suggestion:
            if index == len(lines):
                raise Failure('Close the suggestion fence before submitting', 'validation')
            found += 1
        index += 1
    if found != 1:
        raise Failure('Keep exactly one suggestion block for the selected range', 'validation')


def normalize_comment(c, kind="comment", pending=False):
    user = c.get('user') or {}
    result = {"id": str(c["id"]), "author": user.get("login", "deleted"),
            "body": re.sub(r"\n{0,2}<!-- revue(?:-batch|-edit|-publish|-pending)?:[A-Za-z0-9_:-]+ -->", "", (c.get("body") or "").replace("\r\n", "\n")),
            "created": c.get("submitted_at") or c.get("created_at") or "", "kind": kind,
            "url": c.get("html_url", "")}
    version_fields = {k: c.get(k) for k in ('id', 'body', 'updated_at', 'state')}
    version_fields['author'] = user.get('id', user.get('login', ''))
    result['version'] = hashlib.sha256(json.dumps(version_fields, sort_keys=True, ensure_ascii=True).encode()).hexdigest()
    if re.search(r'<!-- revue-edit:[A-Za-z0-9_-]+:[a-f0-9]{64} -->', c.get('body') or ''):
        result['edited'] = True
    roles = {'OWNER': 'Owner', 'MEMBER': 'Member', 'COLLABORATOR': 'Collaborator',
             'CONTRIBUTOR': 'Contributor', 'FIRST_TIME_CONTRIBUTOR': 'First-time contributor',
             'FIRST_TIMER': 'First-time participant', 'MANNEQUIN': 'Imported identity'}
    if c.get('author_association') in roles:
        result['author_role'] = roles[c['author_association']]
    if user.get('type') == 'Bot':
        result['author_type'] = 'bot'
    if c.get('updated_at'):
        # A generic update timestamp does not establish a body edit.
        result['updated'] = c['updated_at']
    summary = c.get('reactions')
    if isinstance(summary, dict):
        items = [{'id': key, 'label': label, 'count': summary[key]} for key, label in REACTIONS.items() if type(summary.get(key)) is int and summary[key] >= 0]
        result['reactions'] = {'items': items, 'complete': len(items) == len(REACTIONS)}
    decisions = {'APPROVED': 'Approved', 'CHANGES_REQUESTED': 'Changes requested',
                 'COMMENTED': 'Reviewed', 'DISMISSED': 'Review dismissed'}
    if kind in decisions:
        result['decision'] = decisions[kind]
        if c.get('commit_id'):
            result['reviewed_head'] = c['commit_id']
    if pending or c.get('state') == 'PENDING':
        result['publication'] = 'pending'
    return result


def dispatch(request):
    conn = request.get("connection") or connection(request.get("repo", ""), request.get("cwd", os.getcwd()))
    api = GitHub(conn)
    op = request["op"]
    if op == "list":
        return api.list(request)
    if op == "open":
        return api.open(int(request.get("number") or conn.get("number") or 0), incremental=request.get("incremental", True))
    if op == "comparisons":
        return api.comparisons(request)
    if op == "comparison":
        return api.comparison(request)
    if op == 'comparison_range':
        return api.comparison_range(request)
    if op == 'thread_context':
        return api.thread_context(request)
    if op == 'timeline':
        return api.timeline(request)
    if op == 'service_progress':
        return api.service_progress(request)
    if op == 'readiness':
        return api.readiness(request)
    if op == 'message_history':
        return api.message_history(request)
    if op == 'feedback_page':
        return api.feedback_page(request)
    if op == 'feedback_lookup':
        return api.feedback_lookup(request)
    if op == 'verify_pending':
        return api.verify_pending(request)
    if op == "file":
        return api.file(request)
    if op == "mutate":
        return api.mutate(request)
    if op == 'rendered_links':
        return api.rendered_links(request)
    if op == 'reactions':
        return api.reactions(request)
    raise Failure("Unknown provider operation: " + op)


def main():
    try:
        request = json.load(sys.stdin)
        result = {"ok": True, "data": dispatch(request)}
    except Failure as exc:
        result = {"ok": False, "error": str(exc), "code": exc.code, "unknown": exc.unknown}
    except Exception as exc:
        result = {"ok": False, "error": type(exc).__name__ + ": " + str(exc), "code": "internal"}
    print(json.dumps(result, ensure_ascii=True))


if __name__ == "__main__":
    main()
