"""Participant backend and MCP process tests; all reviews are disposable fixtures."""
import concurrent.futures
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import unittest
from vim_pty import run

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'python'))
import revue_local as local
from revue_participants import LocalParticipants
from revue_mcp import Server
import local_backend as fixtures


class ParticipantsTest(unittest.TestCase):
    setUp = fixtures.LocalBackendTest.setUp
    git = fixtures.LocalBackendTest.git
    draft = fixtures.LocalBackendTest.draft
    mutate = fixtures.LocalBackendTest.mutate
    snapshot_now = fixtures.LocalBackendTest.snapshot_now

    def test_cancellation_rolls_back_when_event_storage_fails(self):
        assignment, _ = self.assign()
        draft = self.draft(kind='cancel_assignment', body='', assignment=assignment['id'], expected_version=assignment['version'])
        request = {'op':'mutate','review':self.review,'draft':draft}
        original = LocalParticipants.record
        def fail(*args):
            raise RuntimeError('fixture event failure')
        LocalParticipants.record = fail
        try:
            with self.assertRaisesRegex(RuntimeError, 'event failure'):
                self.backend.request(request)
        finally:
            LocalParticipants.record = original
        self.assertFalse(self.participants.assignment(assignment['id'])['cancelled'])
        self.assertIsNone(self.backend.db.execute('SELECT receipt FROM receipts WHERE operation=?',(draft['id'],)).fetchone())
        with self.assertRaisesRegex(ValueError, 'did not cancel'):
            self.backend.request(dict(request,reconcile=True))
        self.assertTrue(self.backend.request(request)['cancelled'])

    def test_cancellation_receipts_and_stale_version(self):
        assignment, _ = self.assign()
        draft = self.draft(kind='cancel_assignment', body='', assignment=assignment['id'], expected_version=assignment['version'])
        request = {'op':'mutate', 'review':self.review, 'draft':draft}
        with self.assertRaisesRegex(ValueError, 'did not cancel'):
            self.backend.request(dict(request, reconcile=True))
        self.assertFalse(self.participants.assignment(assignment['id'])['cancelled'])
        outcome = self.participants.call(assignment['id'], 'set_outcome', {'operation_id':'working',
            'message':assignment['targets'][0]['message'], 'expected_version':assignment['version'], 'state':'working', 'summary':'Inspecting'})
        with self.assertRaisesRegex(ValueError, 'changed'):
            self.backend.request(request)
        draft['expected_version'] = outcome['version']
        receipt = self.backend.request(request)
        self.assertTrue(receipt['cancelled'])
        self.backend.close()
        self.backend = local.LocalBackend(self.store)
        self.addCleanup(self.backend.close)
        recovered = self.backend.request(dict(request, reconcile=True))
        self.assertTrue(recovered['recovered'])
        self.assertEqual(receipt['version'], recovered['version'])
        with self.assertRaisesRegex(ValueError, 'another cancellation'):
            self.backend.request(dict(request, draft=dict(draft, expected_version='different'), reconcile=True))
        self.assertEqual(1,self.backend.db.execute("SELECT COUNT(*) FROM events WHERE kind='assignment.cancelled'").fetchone()[0])
        with self.assertRaisesRegex(ValueError, 'cancelled'):
            LocalParticipants(self.backend).call(assignment['id'], 'get_assignment', {})

    def test_assignment_outcomes_navigation_and_cancel_vim_restart(self):
        assignment, _ = self.assign()
        reply = self.participants.call(assignment['id'], 'reply_to_comment', self.reply(assignment))
        (self.repo/'code.py').write_text('follow-up capture\n')
        self.mutate(self.draft(kind='capture', body='', untracked=False))
        result_ref = {k:self.snapshot_now()[k] for k in ('snapshot','base','head','base_tip')}
        self.participants.call(assignment['id'], 'set_outcome', {'operation_id':'outcome-ui',
            'message':assignment['targets'][0]['message'], 'expected_version':assignment['version'],
            'state':'addressed','summary':'Inspect the follow-up capture.','run_id':'fixture-run','result_reference':result_ref})
        config = self.backend.request({'op':'open','review':self.review})
        config.update(store=str(self.store), assignment=assignment['id'], message=assignment['targets'][0]['message'],
                      reply=reply['id'], original_reference=assignment['reference'])
        path=self.root/'assignment-outcomes-config.json'; path.write_text(json.dumps(config))
        previous=os.environ.get('REVUE_ASSIGNMENT_CONFIG')
        os.environ['REVUE_ASSIGNMENT_CONFIG']=str(path)
        try:
            run(ROOT/'test/assignment_outcomes.vim', repeat=2)
        finally:
            if previous is None:os.environ.pop('REVUE_ASSIGNMENT_CONFIG',None)
            else:os.environ['REVUE_ASSIGNMENT_CONFIG']=previous
        current=self.backend.request({'op':'assignment','review':self.review,'assignment':assignment['id']})
        self.assertTrue(current['cancelled'])
        self.assertEqual('addressed',current['outcomes'][config['message']]['state'])
        self.assertFalse(self.snapshot_now()['threads'][0]['resolved'])
        self.assertEqual(2,len(self.snapshot_now()['threads'][0]['comments']))
        self.assertEqual(1,self.backend.db.execute("SELECT COUNT(*) FROM events WHERE kind='assignment.cancelled'").fetchone()[0])

    def test_assignment_mutation_receipt_only_recovery(self):
        _, owner = self.assign()
        draft = self.draft(kind='assignment', body='', participant=owner['participant'],
                           reference=owner['reference'], targets=owner['targets'])
        request = {'op': 'mutate', 'review': self.review, 'draft': draft}
        before = len(self.backend.request({'op': 'assignments', 'review': self.review})['items'])
        with self.assertRaisesRegex(ValueError, 'did not create'):
            self.backend.request(dict(request, reconcile=True))
        self.assertEqual(before, len(self.backend.request({'op': 'assignments', 'review': self.review})['items']))
        receipt = self.backend.request(request)
        self.assertEqual(draft['id'], receipt['id'])
        self.assertEqual(owner['targets'], receipt['targets'])
        self.assertNotEqual(receipt['id'], receipt['assignment'])
        (self.repo/'code.py').write_text('newer comparison\n')
        self.mutate(self.draft(kind='capture', body='', untracked=False))
        self.backend.close()
        self.backend = local.LocalBackend(self.store)
        self.addCleanup(self.backend.close)
        recovered = self.backend.request(dict(request, reconcile=True))
        self.assertTrue(recovered['recovered'])
        self.assertEqual(receipt['assignment'], recovered['assignment'])
        with self.assertRaisesRegex(ValueError, 'Comparison changed'):
            self.backend.request(dict(request, draft=dict(draft, id=local.identity())))
        with self.assertRaisesRegex(ValueError, 'another assignment'):
            self.backend.request(dict(request, draft=dict(draft, participant={'id':'other','label':'Other'}), reconcile=True))

    def test_assignment_vim_creation_and_accepted_response_loss_restart(self):
        root = self.mutate(self.draft(body='Explain this change'))['id']
        self.mutate(self.draft(kind='reply', thread=root, body='Also cover the empty-input case'))
        config = self.backend.request({'op':'open', 'review':self.review})
        config['store'] = str(self.store)
        path = self.root/'assignment-config.json'
        path.write_text(json.dumps(config))
        previous = os.environ.get('REVUE_ASSIGNMENT_CONFIG')
        os.environ['REVUE_ASSIGNMENT_CONFIG'] = str(path)
        try:
            run(ROOT/'test/assignment_local.vim', repeat=2)
        finally:
            if previous is None: os.environ.pop('REVUE_ASSIGNMENT_CONFIG', None)
            else: os.environ['REVUE_ASSIGNMENT_CONFIG'] = previous
        items = self.backend.request({'op':'assignments','review':self.review})['items']
        self.assertEqual(1,len(items))
        self.assertEqual(2,len(items[0]['targets']))
        self.assertEqual('local-agent',items[0]['participant']['id'])
        self.assertFalse(self.snapshot_now()['threads'][0]['resolved'])
        self.assertEqual(2,len(self.snapshot_now()['threads'][0]['comments']))

    def assign(self, label='Test agent'):
        root = self.mutate(self.draft())['id']
        message = self.snapshot_now()['threads'][-1]['comments'][0]
        request = {'op': 'assign', 'review': self.review, 'id': local.identity(),
                   'participant': {'id': 'agent-1', 'label': label},
                   'reference': {k:self.snapshot[k] for k in ('snapshot','base','head','base_tip')},
                   'targets':[{'thread':root,'message':root,'message_kind':'comment','expected_version':message['version']}]}
        assignment = self.backend.request(request)
        self.participants = LocalParticipants(self.backend)
        return assignment, request

    def reply(self, assignment, **changes):
        target = assignment['targets'][0]
        args = {'operation_id':local.identity(), 'thread':target['thread'], 'message':target['message'],
                'expected_version':target['expected_version'], 'body':'> Explain this change\n\nThe new value preserves the intended behavior.'}
        args.update(changes)
        return args

    def test_reply_identity_permissions_scope_and_receipts(self):
        assignment, request = self.assign(label=self.snapshot['author'])
        self.assertTrue(self.backend.request(request)['recovered'])
        args = self.reply(assignment)
        result = self.participants.call(assignment['id'], 'reply_to_comment', args)
        self.assertTrue(self.participants.call(assignment['id'], 'reply_to_comment', args)['recovered'])
        thread = self.snapshot_now()['threads'][0]
        self.assertEqual(2,len(thread['comments']))
        message = thread['comments'][-1]
        self.assertEqual(result['id'],message['id'])
        self.assertEqual('participant:agent-1',message['actor'])
        self.assertFalse(message['is_author'])
        self.assertFalse(message['capabilities']['edit']['enabled'])
        self.assertFalse(message['capabilities']['delete_message']['enabled'])
        self.assertFalse(thread['resolved'])
        self.assertEqual(self.snapshot['head'],self.snapshot_now()['head'])
        with self.assertRaises(ValueError):
            self.participants.call(assignment['id'],'reply_to_comment',dict(args,body='different'))
        for changes in ({'actor':'local:owner'}, {'thread':'foreign'}, {'expected_version':'old'}):
            with self.assertRaises(ValueError):
                self.participants.call(assignment['id'],'reply_to_comment',dict(args,operation_id=local.identity(),**changes))
        foreign = self.mutate(self.draft(body='Unassigned private context'))['id']
        with self.assertRaises(ValueError):
            self.participants.call(assignment['id'],'get_thread',{'thread':foreign})
        with self.assertRaises(ValueError):
            self.participants.call(assignment['id'],'get_assignment',{'review':'other'})

    def test_stale_selection_outcome_result_and_cancellation(self):
        assignment, request = self.assign()
        bad = dict(request,id=local.identity(),reference=dict(request['reference'],head='foreign'))
        with self.assertRaises(ValueError):self.backend.request(bad)
        bad = dict(request,id=local.identity(),targets=[dict(request['targets'][0],expected_version='old')])
        with self.assertRaises(ValueError):self.backend.request(bad)
        args = {'operation_id':'outcome','message':assignment['targets'][0]['message'], 'expected_version':assignment['version'],
                'state':'addressed','summary':'Changed locally; ready for a human review.','run_id':'fixture-run', 'result_reference':assignment['reference']}
        result = self.participants.call(assignment['id'],'set_outcome',args)
        self.assertTrue(self.participants.call(assignment['id'],'set_outcome',args)['recovered'])
        with self.assertRaises(ValueError):self.participants.call(assignment['id'],'set_outcome',dict(args,operation_id='stale'))
        current=self.participants.call(assignment['id'],'get_assignment',{})
        self.assertEqual('addressed',current['outcomes'][args['message']]['state'])
        self.assertFalse(self.snapshot_now()['threads'][0]['resolved'])
        self.backend.request({'op':'cancel_assignment','review':self.review,'assignment':assignment['id'],'expected_version':result['version']})
        for action,arguments in [('get_assignment',{}),('reply_to_comment',self.reply(assignment)),('set_outcome',args)]:
            with self.assertRaisesRegex(ValueError,'cancelled'):self.participants.call(assignment['id'],action,arguments)

    def test_restart_human_followup_source_and_changes(self):
        assignment,_=self.assign()
        first=self.participants.call(assignment['id'],'reply_to_comment',self.reply(assignment))
        human=self.mutate(self.draft(kind='reply',thread=assignment['targets'][0]['thread'],body='Please also cover the edge case.'))['id']
        (self.repo/'code.py').write_text('a new capture\n')
        self.mutate(self.draft(kind='capture',body='',untracked=False))
        self.backend.close()
        self.backend=local.LocalBackend(self.store)
        self.addCleanup(self.backend.close)
        self.participants=LocalParticipants(self.backend)
        thread=self.participants.call(assignment['id'],'get_thread',{'thread':assignment['targets'][0]['thread']})
        self.assertEqual([assignment['targets'][0]['message'],first['id'],human],[m['id'] for m in thread['thread']['comments']])
        self.assertEqual(assignment['reference'],thread['original_comparison'])
        source=self.participants.call(assignment['id'],'get_source',{'thread':assignment['targets'][0]['thread'],'side':'head','start':2,'count':1})
        self.assertEqual(['new'],source['lines'])
        self.assertEqual(3,source['next_start'])
        changes=self.participants.call(assignment['id'],'get_changes',{'cursor':0})
        self.assertIn(human,[e['message'] for e in changes['items']])
        self.assertEqual([],self.participants.call(assignment['id'],'get_changes',{'cursor':changes['cursor']})['items'])
        latest={k:self.snapshot_now()[k] for k in ('snapshot','base','head','base_tip')}
        outcome=self.participants.call(assignment['id'],'set_outcome',{'operation_id':'done','message':assignment['targets'][0]['message'],
            'expected_version':assignment['version'],'state':'addressed','summary':'Inspect the new capture.','result_reference':latest})
        self.assertEqual(latest,outcome['outcome']['result_reference'])

    def test_parallel_reply_recovery_and_atomic_rollback(self):
        assignment,_=self.assign();args=self.reply(assignment,operation_id='same')
        def send(_):
            backend=local.LocalBackend(self.store)
            try:return LocalParticipants(backend).call(assignment['id'],'reply_to_comment',args)
            finally:backend.close()
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(send,range(2)))
        self.assertEqual(results[0]['id'],results[1]['id'])
        self.assertEqual(2,len(self.snapshot_now()['threads'][0]['comments']))

        self.backend.db.execute("CREATE TRIGGER fail_event BEFORE INSERT ON events BEGIN SELECT RAISE(ABORT, 'fixture failure'); END")
        self.backend.db.commit()
        with self.assertRaises(Exception):self.participants.call(assignment['id'],'reply_to_comment',self.reply(assignment))
        self.assertEqual(2,len(self.snapshot_now()['threads'][0]['comments']))

    def test_changes_skip_unassigned_pages_and_retain_deletion_events(self):
        assignment,_=self.assign()
        initial=self.participants.call(assignment['id'],'get_changes',{'cursor':0})
        with self.backend.db:
            self.backend.db.executemany('INSERT INTO events(review,id,kind,data) VALUES (?,?,?,?)',
                [(self.review,local.identity(),'comment.created',json.dumps({'id':'unassigned-'+str(i)})) for i in range(101)])
        target=assignment['targets'][0]['thread']
        human=self.mutate(self.draft(kind='reply',thread=target,body='A later human reply'))['id']
        page=self.participants.call(assignment['id'],'get_changes',{'cursor':initial['cursor']})
        self.assertTrue(page['has_more']);self.assertEqual([],page['items'])
        later=self.participants.call(assignment['id'],'get_changes',{'cursor':page['cursor']})
        self.assertEqual([human],[e['message'] for e in later['items']])
        message=self.snapshot_now()['threads'][0]['comments'][-1]
        self.mutate(self.draft(kind='delete_message',body='',message=human,message_kind='reply',thread=target,
            actor='local:'+self.snapshot['author'],delete_scope='message',expected_version=message['version'],original_body=message['body']))
        removed=self.participants.call(assignment['id'],'get_changes',{'cursor':later['cursor']})
        self.assertEqual([('comment.deleted',human)],[(e['kind'],e['message']) for e in removed['items']])

    def test_mcp_protocol_boundaries(self):
        assignment,_=self.assign();server=Server(self.participants,assignment['id'])
        def call(i,method,params={}):return server.handle({'jsonrpc':'2.0','id':i,'method':method,'params':params})
        self.assertEqual(-32002,call(1,'tools/list')['error']['code'])
        self.assertEqual('2025-11-25',call(2,'initialize',{'protocolVersion':'future','capabilities':{},'clientInfo':{'name':'fixture','version':'1'}})['result']['protocolVersion'])
        self.assertIsNone(server.handle({'jsonrpc':'2.0','method':'notifications/initialized'}))
        self.assertEqual(6,len(call(3,'tools/list')['result']['tools']))
        self.assertEqual(-32600,call(3,'tools/list')['error']['code'])
        self.assertEqual(-32602,call(4,'tools/call',{'name':'reply_to_comment','arguments':{}})['error']['code'])
        self.assertEqual(-32602,call(5,'tools/call',{'name':'get_assignment','arguments':{'assignment':'other'}})['error']['code'])
        self.assertEqual(-32602,call(6,'tools/call',{'name':'get_changes','arguments':{'cursor':True}})['error']['code'])
        self.assertEqual(-32601,call(7,'resources/list')['error']['code'])
        self.assertIsNone(server.handle({'jsonrpc':'2.0','method':'tools/call','params':{'name':'reply_to_comment','arguments':self.reply(assignment)}}))
        self.assertEqual(1,len(self.snapshot_now()['threads'][0]['comments']))

    def test_real_stdio_reply_and_vim_restart(self):
        assignment,_=self.assign(label=self.snapshot['author']);args=self.reply(assignment,operation_id='stdio-reply')
        requests=[{'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'fixture','version':'1'}}},
                  {'jsonrpc':'2.0','method':'notifications/initialized'},
                  {'jsonrpc':'2.0','id':2,'method':'tools/call','params':{'name':'reply_to_comment','arguments':args}}]
        def run():
            proc=subprocess.run([sys.executable,str(ROOT/'python/revue_mcp.py'),'--store',str(self.store),'--assignment',assignment['id']],
                input='\n'.join(json.dumps(r) for r in requests)+'\n',text=True,capture_output=True,timeout=15)
            self.assertEqual(0,proc.returncode,proc.stderr)
            output=[json.loads(line) for line in proc.stdout.splitlines()]
            self.assertEqual(2,len(output));self.assertFalse(output[-1]['result']['isError'])
            return output[-1]['result']['structuredContent']
        result=run();self.assertTrue(run()['recovered'])
        config=self.backend.request({'op':'open','review':self.review})
        config.update(agent_message=result['id'],thread=assignment['targets'][0]['thread'])
        path=self.root/'participant-config.json';path.write_text(json.dumps(config))
        for _ in range(2):
            errors=self.root/'vim-errors'
            proc=subprocess.run(['vim','-Nu','NONE','-i','NONE','-n','-es','-S',str(ROOT/'test/participants.vim')],env=dict(os.environ,
                REVUE_LOCAL_STORE=str(self.store),REVUE_PARTICIPANT_CONFIG=str(path),REVUE_PARTICIPANT_ERRORS=str(errors),REVUE_PARTICIPANT_DRAFTS=str(self.root/'drafts')),
                capture_output=True,timeout=20)
            self.assertEqual(0,proc.returncode,errors.read_text() if errors.exists() else proc.stderr.decode())


if __name__=='__main__':
    unittest.main()
