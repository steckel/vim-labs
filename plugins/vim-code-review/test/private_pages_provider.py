"""Actual adapter projection behind a read-only test transport; never GitHub I/O."""
import copy
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('private_fixture', ROOT.parent / 'vim-code-review-github/test/test_feedback_pages.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)

def profile():
    case = fixture.FeedbackTest()
    case.setUp()
    case.configure_open(pending=True)
    case.api.action_rules = lambda _: ({}, [{'id': 'COMMENT', 'label': 'Comment'}], 'alex')
    case.pr['reviews'] = {'nodes': [case.private_node(4)], 'totalCount': 1}
    case.pr['reviewThreads'] = fixture.connection([case.private_thread()], 'later', 2)
    case.pr['comments'] = fixture.connection([])
    raw = [{'id': i, 'body': 'Body ' + str(i), 'user': {'login': 'alex'}, 'path': 'code.py', 'side': 'RIGHT',
            'line': 1, 'pull_request_review_id': 7,
            **({'in_reply_to_id': i-1} if i % 2 == 0 else {})} for i in (101, 102, 201, 202)]
    case.api.load_pending = lambda *args: (copy.deepcopy(case.open_review), copy.deepcopy(raw))
    first = case.api.open(42, incremental=True)
    case.pr['reviewThreads'] = fixture.connection([case.private_thread(201)], total=2)
    page = case.api.feedback_page({'number': 42, 'reference': case.ref, 'cursor': first['feedback']['cursor']})
    header = first['pending_reviews']['items'][0]
    verified = case.api.verify_pending({'number': 42, 'reference': case.ref,
        'target': {'review': '7', 'actor': header['actor'], 'read_version': header['read_version']}})
    return {'first': first, 'page': page, 'verified': verified,
            'content': json.loads((ROOT / 'test/fixtures/comment-ui.json').read_text())['content']}

if __name__ == '__main__':
    data = profile()
    if '--fixture' in sys.argv:
        print(json.dumps(data)); sys.exit(0)
    request = json.load(sys.stdin)
    if request['op'] == 'open':
        result = data['first']
    elif request['op'] == 'feedback_page':
        assert request['cursor'] == data['first']['feedback']['cursor']
        result = data['page']
    elif request['op'] == 'file':
        result = data['content']
    elif request['op'] == 'verify_pending':
        assert request['target'] == data['verified']['target']
        result = data['verified']
    else:
        raise RuntimeError('Private paging fixture permits reads only')
    json.dump({'ok': True, 'data': result}, sys.stdout)
