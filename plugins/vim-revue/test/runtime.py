"""Real supervisor/MCP subprocesses with a deterministic fake Codex executable.

No model, account credentials, live user session or external writes are used.
"""
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import unittest
from unittest.mock import patch

import participants as fixtures
local, ROOT = fixtures.local, fixtures.ROOT
import revue_runtime as runtime


class RuntimeTest(unittest.TestCase):
    setUp = fixtures.ParticipantsTest.setUp
    git = fixtures.ParticipantsTest.git
    draft = fixtures.ParticipantsTest.draft
    mutate = fixtures.ParticipantsTest.mutate
    snapshot_now = fixtures.ParticipantsTest.snapshot_now
    assign = fixtures.ParticipantsTest.assign

    def executable(self, mode='complete'):
        path = self.root / ('fake-codex-' + mode)
        count = self.root / 'executions'
        release = self.root / 'release'
        code = r'''
import json, os, pathlib, subprocess, sys, time
args=sys.argv[1:]
prompt=sys.stdin.read()
with open(COUNT,'a') as f:f.write(json.dumps(args)+'\n')
thread='ea43da39-2e59-44e0-9129-029e6a1b551a'
if 'resume' in args:
    thread=args[args.index('resume')+2]
print(json.dumps({'type':'thread.started','thread_id':thread}),flush=True)
if MODE=='hold':
    while not pathlib.Path(RELEASE).exists():time.sleep(.02)
    sys.exit(0)
if MODE=='bad':
    print('not JSON',flush=True)
    sys.exit(1)
config={}
for i,arg in enumerate(args):
    if arg=='-c':
        k,v=args[i+1].split('=',1);config[k]=json.loads(v)
mcp=subprocess.Popen([config['mcp_servers.revue.command']]+config['mcp_servers.revue.args'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
serial=0
def call(method,params):
    global serial
    serial+=1
    mcp.stdin.write(json.dumps({'jsonrpc':'2.0','id':serial,'method':method,'params':params})+'\n');mcp.stdin.flush()
    response=json.loads(mcp.stdout.readline())
    assert 'error' not in response,response
    return response['result']
call('initialize',{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'fake-codex','version':'1'}})
mcp.stdin.write(json.dumps({'jsonrpc':'2.0','method':'notifications/initialized'})+'\n');mcp.stdin.flush()
assignment=call('tools/call',{'name':'get_assignment','arguments':{}})['structuredContent']
target=assignment['targets'][0]
run=assignment['runtime']['run']
result=call('tools/call',{'name':'reply_to_comment','arguments':{'operation_id':'reply-'+run,'thread':target['thread'],
    'message':target['message'],'expected_version':target['expected_version'],'body':'Fixture runtime reply for this comment.'}})
assert not result['isError'],result
result=call('tools/call',{'name':'set_outcome','arguments':{'operation_id':'outcome-'+run,'message':target['message'],
    'expected_version':assignment['version'],'state':'addressed','summary':'Fixture completed through actual MCP.'}})
assert not result['isError'],result
result=call('tools/call',{'name':'set_outcome','arguments':{'operation_id':'foreign-run','message':target['message'],
    'expected_version':result['structuredContent']['version'],'state':'failed','summary':'Wrong run','run_id':'foreign'}})
assert result['isError'],result
mcp.stdin.close();mcp.wait(timeout=5);mcp.stdout.close()
print(json.dumps({'type':'item.completed','item':{'type':'agent_message','text':'Fixture run finished; no real agent was used.'}}),flush=True)
print(json.dumps({'type':'turn.completed'}),flush=True)
'''
        path.write_text('#!' + sys.executable + '\nMODE=' + repr(mode) + '\nCOUNT=' + repr(str(count)) + '\nRELEASE=' + repr(str(release)) + '\n' + code)
        path.chmod(0o700)
        return {'adapter':'codex','executable':str(path),'sandbox':'workspace-write'}

    def prepare(self, mode='complete'):
        assignment, _ = self.assign()
        self.runs = runtime.LocalRuns(self.backend)
        request = {'op':'prepare_run','id':local.identity(),'review':self.review,'assignment':assignment['id'],
                   'expected_version':assignment['version'],'runtime':self.executable(mode)}
        return self.backend.request(request), request

    def await_run(self, run_id, predicate):
        deadline=time.monotonic()+15
        last={}
        while time.monotonic()<deadline:
            last=self.runs.status(run_id)
            if predicate(last):return last
            time.sleep(.025)
        self.fail('Run did not reach expected state: '+repr(last))

    def ui_draft(self, assignment, runtime_config):
        return self.draft(kind='participant_run', body='', assignment=assignment['id'],
            expected_version=assignment['version'], participant=assignment['participant'],
            runtime=runtime_config, run_mode='start', run='', resume_run='', thread='',
            reference=assignment['reference'], count=len(assignment['targets']), workspace=str(self.repo.resolve()))

    def test_preview_binding_and_receipt_only_recovery(self):
        assignment, _ = self.assign()
        draft = self.ui_draft(assignment, self.executable())
        request = {'op':'mutate','review':self.review,'draft':draft}
        # Simulate the supervisor being unavailable after preparation commits.
        with patch.object(runtime.LocalRuns, 'dispatch', side_effect=OSError('fixture dispatch failure')):
            receipt = self.backend.request(request)
        self.assertEqual('fixture dispatch failure', receipt['dispatch_error'])
        self.assertEqual('start', receipt['run_mode'])
        self.assertEqual(draft['workspace'], receipt['intent']['workspace'])
        self.assertFalse((self.root/'executions').exists())
        self.assertTrue(self.backend.request(dict(request,reconcile=True))['recovered'])
        for key, value in [('run_mode','resume'),('workspace','/wrong'),('thread','wrong'),('count',99),('participant',{'id':'other','label':'Other'})]:
            with self.subTest(key=key), self.assertRaisesRegex(ValueError,'another run'):
                self.backend.request(dict(request,draft=dict(draft,**{key:value}),reconcile=True))
        self.assertFalse((self.root/'executions').exists())
        # A new explicit dispatch must still agree with every previewed field.
        dispatch = dict(draft,id=local.identity(),run_mode='dispatch',run=receipt['run'])
        with self.assertRaisesRegex(ValueError,'Previewed'):
            self.backend.request(dict(request,draft=dict(dispatch,workspace='/wrong')))
        self.runs=runtime.LocalRuns(self.backend)
        result=self.backend.request(dict(request,draft=dispatch))
        self.await_run(result['run'],lambda r:r['state']=='completed' and not r['process_held'])
        self.assertTrue(self.backend.request(dict(request,draft=dispatch,reconcile=True))['recovered'])
        self.assertEqual(1,len((self.root/'executions').read_text().splitlines()))

    def test_abandoned_resume_retains_executed_session(self):
        receipt, request=self.prepare()
        self.runs.dispatch(self.review,receipt['run'])
        first=self.await_run(receipt['run'],lambda r:r['state']=='completed' and not r['process_held'])
        assignment=self.runs.participants.assignment(first['assignment'])
        follow=dict(request,id=local.identity(),expected_version=assignment['version'],resume_run=first['id'])
        abandoned=self.backend.request(follow)
        self.backend.request({'op':'abandon_run','review':self.review,'run':abandoned['run']})
        with self.assertRaisesRegex(ValueError,'Resume the latest'):
            self.backend.request(dict(follow,id=local.identity(),resume_run=None))
        replacement=self.backend.request(dict(follow,id=local.identity()))
        self.assertEqual(first['thread'],self.runs.get(replacement['run'])['resume_thread'])
        self.assertEqual(1,len((self.root/'executions').read_text().splitlines()))

    def test_vim_start_recovery_and_exact_resume(self):
        assignment, _ = self.assign()
        config=self.backend.request({'op':'open','review':self.review})
        config.update(store=str(self.store),assignment=assignment['id'],participant=assignment['participant'],runtime=self.executable())
        path=self.root/'runtime-ui.json';path.write_text(json.dumps(config))
        with patch.dict(os.environ,REVUE_RUNTIME_CONFIG=str(path)):
            fixtures.run(ROOT/'test/runtime_local.vim',repeat=2)
        self.runs=runtime.LocalRuns(self.backend)
        runs=self.backend.request({'op':'runs','review':self.review})['items']
        self.assertEqual(2,len(runs))
        self.assertEqual(['completed','completed'],[r['state'] for r in runs])
        self.assertEqual(runs[0]['thread'],runs[1]['thread'])
        self.assertEqual(runs[0]['id'],runs[1]['resume_run'])
        self.assertEqual(2,len((self.root/'executions').read_text().splitlines()))
        self.assertEqual(3,len(self.snapshot_now()['threads'][0]['comments']))
        self.assertFalse(self.snapshot_now()['threads'][0]['resolved'])

    def abandon_draft(self, run_id):
        run=self.runs.get(run_id)
        assignment=self.runs.participants.assignment(run['assignment'])
        return dict(self.ui_draft(assignment,run['runtime']),run_mode='abandon',run=run_id,thread=run['resume_thread'],workspace=run['workspace'])

    def test_abandonment_binding_rollback_and_recovery(self):
        receipt, request=self.prepare()
        assignment=self.runs.participants.assignment(request['assignment'])
        target=assignment['targets'][0]
        self.runs.participants.call(assignment['id'],'set_outcome',{'operation_id':'changed',
            'message':target['message'],'expected_version':assignment['version'],'state':'working','summary':'Updated after preparation'})
        draft=self.abandon_draft(receipt['run'])
        operation={'op':'mutate','review':self.review,'draft':draft}
        self.assertNotEqual(request['expected_version'],draft['expected_version'])
        with self.assertRaisesRegex(ValueError,'changes nothing'):
            self.backend.request(dict(operation,reconcile=True))
        with self.assertRaisesRegex(ValueError,'Previewed'):
            self.backend.request(dict(operation,draft=dict(draft,workspace='/foreign')))
        handle=self.runs.lock(self.runs.get(receipt['run']))
        try:
            with self.assertRaisesRegex(ValueError,'owned by a process'):
                self.backend.request(operation)
        finally:handle.close()
        with patch.object(runtime.LocalParticipants,'record',side_effect=RuntimeError('event storage failed')):
            with self.assertRaisesRegex(RuntimeError,'event storage failed'):
                self.backend.request(operation)
        self.assertEqual('prepared',self.runs.get(receipt['run'])['state'])
        self.assertIsNone(self.backend.db.execute('SELECT receipt FROM receipts WHERE operation=?',(draft['id'],)).fetchone())
        Path(request['runtime']['executable']).unlink()
        result=self.backend.request(operation)
        self.assertTrue(result['abandoned'])
        self.backend.close();self.backend=local.LocalBackend(self.store);self.addCleanup(self.backend.close)
        self.runs=runtime.LocalRuns(self.backend)
        self.assertTrue(self.backend.request(dict(operation,reconcile=True))['recovered'])
        self.assertTrue(self.backend.request(operation)['recovered'])
        for change in [{'run':'foreign'},{'expected_version':'old'},{'runtime':{}},{'count':99}]:
            with self.subTest(change=change),self.assertRaisesRegex(ValueError,'another abandonment'):
                self.backend.request(dict(operation,draft=dict(draft,**change),reconcile=True))
        self.assertEqual(1,self.backend.db.execute("SELECT COUNT(*) FROM events WHERE kind='run.abandoned'").fetchone()[0])
        self.assertEqual('abandoned',self.runs.get(receipt['run'])['state'])
        self.assertFalse((self.root/'executions').exists())
        self.assertFalse(self.runs.participants.assignment(request['assignment'])['cancelled'])
        self.assertEqual(1,len(self.snapshot_now()['threads'][0]['comments']))

    def test_abandonment_races_with_dispatch(self):
        receipt, request=self.prepare('hold')
        operation={'op':'mutate','review':self.review,'draft':self.abandon_draft(receipt['run'])}
        def act(abandon):
            backend=local.LocalBackend(self.store)
            try:
                try:return backend.request(operation if abandon else {'op':'dispatch_run','review':self.review,'run':receipt['run']})
                except ValueError as error:return {'error':str(error)}
            finally:backend.close()
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                results=list(pool.map(act,[False,True]))
            if results[1].get('abandoned'):
                self.assertEqual('abandoned',self.runs.status(receipt['run'])['state'])
            else:
                self.await_run(receipt['run'],lambda r:r['execution_started'] and r['process_held'])
                with self.assertRaisesRegex(ValueError,'unstarted|owned'):
                    self.backend.request(operation)
        finally:
            (self.root/'release').write_text('release')
            for worker in list(runtime._workers):worker.wait(timeout=5)
            self.await_run(receipt['run'],lambda r:not r['process_held'] and r['state'] not in runtime.ACTIVE)
        result=self.runs.status(receipt['run'])
        executions=(self.root/'executions').read_text().splitlines() if (self.root/'executions').exists() else []
        self.assertEqual(0 if result['state']=='abandoned' else 1,len(executions))

    def test_abandonment_refuses_running_process_and_allows_cancelled_preparation(self):
        receipt, request=self.prepare('hold')
        draft=self.abandon_draft(receipt['run'])
        self.runs.dispatch(self.review,receipt['run'])
        try:
            self.await_run(receipt['run'],lambda r:r['execution_started'] and r['process_held'])
            with self.assertRaisesRegex(ValueError,'unstarted'):
                self.backend.request({'op':'mutate','review':self.review,'draft':draft})
            self.assertTrue(self.runs.status(receipt['run'])['process_held'])
        finally:
            (self.root/'release').write_text('release')
            for worker in list(runtime._workers):worker.wait(timeout=5)
        second, request=self.prepare()
        assignment=self.runs.participants.assignment(request['assignment'])
        self.backend.request({'op':'cancel_assignment','review':self.review,'assignment':assignment['id'],'expected_version':assignment['version']})
        result=self.backend.request({'op':'mutate','review':self.review,'draft':self.abandon_draft(second['run'])})
        self.assertTrue(result['abandoned'])
        self.assertTrue(self.runs.participants.assignment(assignment['id'])['cancelled'])

    def test_vim_abandonment_recovery(self):
        receipt, request=self.prepare()
        assignment=self.runs.participants.assignment(request['assignment'])
        self.runs.participants.call(assignment['id'],'set_outcome',{'operation_id':'ui-changed',
            'message':assignment['targets'][0]['message'],'expected_version':assignment['version'],'state':'working','summary':'Prepared scope is now outdated'})
        config=self.backend.request({'op':'open','review':self.review})
        config.update(store=str(self.store),assignment=assignment['id'],participant=assignment['participant'],runtime=request['runtime'])
        path=self.root/'abandon-ui.json';path.write_text(json.dumps(config))
        with patch.dict(os.environ,REVUE_RUNTIME_CONFIG=str(path)):
            fixtures.run(ROOT/'test/runtime_abandon.vim',repeat=2)
        self.assertEqual('abandoned',self.runs.get(receipt['run'])['state'])
        self.assertFalse(self.runs.participants.assignment(assignment['id'])['cancelled'])
        self.assertEqual(1,self.backend.db.execute("SELECT COUNT(*) FROM events WHERE kind='run.abandoned'").fetchone()[0])
        self.assertFalse((self.root/'executions').exists())

    def test_preparation_idempotence_and_abandonment(self):
        receipt, request=self.prepare()
        self.assertFalse((self.root/'executions').exists())
        self.assertTrue(self.backend.request(dict(request,reconcile=True))['recovered'])
        with self.assertRaisesRegex(ValueError,'another run'):
            self.backend.request(dict(request,runtime=dict(request['runtime'],sandbox='read-only')))
        with self.assertRaisesRegex(ValueError,'starts nothing'):
            self.backend.request(dict(request,id=local.identity(),reconcile=True))
        with self.assertRaisesRegex(ValueError,'existing prepared'):
            self.backend.request(dict(request,id=local.identity()))
        self.backend.request({'op':'dispatch_run','review':self.review,'run':receipt['run'],'reconcile':True})
        self.assertFalse((self.root/'executions').exists())
        self.backend.request({'op':'abandon_run','review':self.review,'run':receipt['run']})
        replacement=self.backend.request(dict(request,id=local.identity()))
        self.assertNotEqual(receipt['run'],replacement['run'])

    def test_dispatch_races_and_exact_session_resume(self):
        receipt, request=self.prepare()
        def dispatch(_):
            backend=local.LocalBackend(self.store)
            try:return backend.request({'op':'dispatch_run','review':self.review,'run':receipt['run']})
            finally:backend.close()
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(dispatch,range(4)))
        first=self.await_run(receipt['run'],lambda r:r['state']=='completed' and not r['process_held'])
        self.assertEqual(1,len((self.root/'executions').read_text().splitlines()))
        assignment=self.participants.assignment(request['assignment'])
        self.assertEqual(receipt['run'],assignment['outcomes'][assignment['targets'][0]['message']]['run_id'])
        self.assertEqual(2,len(self.snapshot_now()['threads'][0]['comments']))
        self.assertFalse(self.snapshot_now()['threads'][0]['resolved'])
        self.backend.close();self.backend=local.LocalBackend(self.store);self.addCleanup(self.backend.close)
        self.runs=runtime.LocalRuns(self.backend)
        with self.assertRaisesRegex(ValueError,'Resume the latest'):
            self.backend.request(dict(request,id=local.identity(),expected_version=assignment['version']))
        second=self.backend.request(dict(request,id=local.identity(),expected_version=assignment['version'],resume_run=first['id']))
        self.backend.request({'op':'dispatch_run','review':self.review,'run':second['run']})
        resumed=self.await_run(second['run'],lambda r:r['state']=='completed' and not r['process_held'])
        self.assertEqual(first['thread'],resumed['thread'])
        commands=[json.loads(line) for line in (self.root/'executions').read_text().splitlines()]
        self.assertEqual(2,len(commands))
        self.assertEqual(['resume','--',first['thread'],'-'],commands[1][-4:])
        self.assertEqual(3,len(self.snapshot_now()['threads'][0]['comments']))

    def test_cancelled_and_changed_assignments_do_not_launch(self):
        receipt, request=self.prepare()
        self.participants.call(request['assignment'],'set_outcome',{'operation_id':'changed','message':self.participants.assignment(request['assignment'])['targets'][0]['message'],
            'expected_version':request['expected_version'],'state':'working','summary':'Changed after preparation'})
        self.backend.request({'op':'dispatch_run','review':self.review,'run':receipt['run']})
        self.await_run(receipt['run'],lambda r:r['state']=='failed' and not r['process_held'])
        self.assertFalse((self.root/'executions').exists())
        current=self.participants.assignment(request['assignment'])
        self.backend.request({'op':'cancel_assignment','review':self.review,'assignment':current['id'],'expected_version':current['version']})
        with self.assertRaisesRegex(ValueError,'cancelled'):
            self.backend.request({'op':'dispatch_run','review':self.review,'run':receipt['run']})

    def test_supervisor_loss_keeps_child_ownership_and_unknown_state(self):
        receipt, request=self.prepare('hold')
        self.backend.request({'op':'dispatch_run','review':self.review,'run':receipt['run']})
        try:
            state=self.await_run(receipt['run'],lambda r:r['state']=='running' and bool(r['thread']))
            worker=runtime._workers[-1]
            worker.kill();worker.wait(timeout=5)
            held=self.runs.status(receipt['run'])
            self.assertTrue(held['process_held'])
            with self.assertRaisesRegex(ValueError,'active run'):
                self.backend.request(dict(request,id=local.identity(),resume_run=receipt['run']))
        finally:
            (self.root/'release').touch()
            self.await_run(receipt['run'],lambda r:not r['process_held'])
        state=self.runs.status(receipt['run'])
        self.assertEqual('unknown',state['state'])
        self.assertEqual(1,len((self.root/'executions').read_text().splitlines()))

    def test_bad_stream_retains_session_without_automatic_retry(self):
        receipt, _=self.prepare('bad')
        self.backend.request({'op':'dispatch_run','review':self.review,'run':receipt['run']})
        state=self.await_run(receipt['run'],lambda r:r['state']=='unknown' and not r['process_held'])
        self.assertTrue(state['thread'])
        self.backend.request({'op':'dispatch_run','review':self.review,'run':receipt['run']})
        self.assertEqual(1,len((self.root/'executions').read_text().splitlines()))

    def test_argv_and_scope_are_owner_bound(self):
        receipt, _=self.prepare()
        run=self.runs.get(receipt['run'])
        argv=runtime.codex_argv(run,self.store)
        self.assertIn('--json',argv)
        self.assertNotIn('--dangerously-bypass-approvals-and-sandbox',argv)
        self.assertEqual(str(self.repo.resolve()),argv[argv.index('--cd')+1])
        with self.assertRaisesRegex(ValueError,'another review'):
            self.runs.dispatch('foreign',run['id'])
        with self.assertRaisesRegex(ValueError,'not active'):
            runtime.RunParticipant(self.backend,run['assignment'],run['id']).call(run['assignment'],'get_assignment',{})
        with self.assertRaises(ValueError):runtime.descriptor({'adapter':'codex','executable':sys.executable,'sandbox':'danger-full-access'})


if __name__=='__main__':
    unittest.main()
