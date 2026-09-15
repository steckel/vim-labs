"""Read-only subprocess fixture for the ReviewHub continuation bridge."""
import copy
import json
import os
from pathlib import Path
import sys

fixture = json.loads((Path(__file__).parent / 'fixtures/comment-ui.json').read_text())
request = json.load(sys.stdin)
with (Path(os.environ['REVUE_CAP_STORE']) / 'github-requests.jsonl').open('a') as log:
    log.write(json.dumps(request) + '\n')
snapshot = fixture['snapshot']
snapshot.update(number=42, key='fixture.test/team/project/42', capabilities={'feedback_page': {'enabled': True}, 'feedback_refresh': {'enabled': True}},
                feedback={'cursor': 'remaining'}, inventory={'threads': {'state': 'partial', 'total': 2}})
more = copy.deepcopy(snapshot['threads'][0])
more['id'] = 'later-thread'
more['comments'][0].update(id='later-root', body='Second page from the ReviewHub transport')
for index, message in enumerate(more['comments'][1:]):
    message['id'] = 'later-reply-' + str(index)
if request['op'] == 'open':
    if request.get('incremental') is False:
        snapshot['threads'].append(more)
        snapshot['feedback']['cursor'] = ''
        snapshot['inventory']['threads']['state'] = 'complete'
    result = {'ok': True, 'data': snapshot}
elif request['op'] == 'file':
    result = {'ok': True, 'data': fixture['content']}
elif request['op'] == 'feedback_page':
    assert request['number'] == 42 and request['connection'] == {'host': 'fixture.test', 'repo': 'team/project'}
    assert request['cursor'] == 'remaining' and request['reference']['snapshot'] == snapshot['snapshot']
    result = {'ok': True, 'data': {'snapshot': snapshot['snapshot'], 'cursor': 'remaining', 'next_cursor': '',
                                  'complete': True, 'threads': [more], 'conversation': []}}
else:
    raise RuntimeError('Read-only fixture received an unsupported operation')
json.dump(result, sys.stdout)
