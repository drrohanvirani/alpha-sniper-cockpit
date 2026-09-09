"""Native PG17 regression for the scheduler wrapper; not a full Alpha rehearsal.
Runs only against disposable localhost:55439 database alpha_serialization_test.
cron.alter_job is a test double: Windows distribution has no pg_cron extension.
"""
import itertools, json, os, queue, subprocess, threading, time, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PSQL = Path(os.environ['ALPHA_TEST_PSQL']).resolve()
BASE = [str(PSQL), '-X', '-qAt', '-v', 'ON_ERROR_STOP=1',
        '-h', '127.0.0.1', '-p', '55439', '-U', 'alpha_test']
DB = 'alpha_serialization_test'
JOBS = {
 'heartbeat': ('alpha-autonomy-heartbeat-30m','alpha_autonomy_heartbeat','10,40 3-11 * * 1-5'),
 'worker': ('alpha-autonomous-worker-15m','alpha_autonomous_worker_tick_v7','3,18,33,48 * * * *'),
 'liveness': ('alpha-ground-truth-liveness-5m','alpha_liveness_guard_tick','*/5 3-10 * * 1-5'),
 'daily_sop': ('alpha-master-daily-sop','alpha_master_daily_sop_tick','*/5 * * * *')}
EVIDENCE = []

def run(sql, db=DB, check=True):
    r = subprocess.run(BASE+['-d',db],input=sql,text=True,capture_output=True,timeout=20)
    if check and r.returncode: raise RuntimeError(r.stderr)
    return r

class Session:
    def __init__(self, name):
        env = dict(os.environ, PGAPPNAME=name)
        self.p = subprocess.Popen(BASE+['-d',DB],stdin=subprocess.PIPE,
             stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1,env=env)
        self.q = queue.Queue()
        def read():
            for line in self.p.stdout: self.q.put(line.strip())
        self.thread = threading.Thread(target=read,daemon=True)
        self.thread.start()
    def send(self, sql):
        self.p.stdin.write(sql+'\n'); self.p.stdin.flush()
    def until(self, marker):
        rows=[]; deadline=time.monotonic()+8
        while time.monotonic()<deadline:
            line=self.q.get(timeout=max(.01,deadline-time.monotonic()))
            if line==marker: return rows
            if line: rows.append(line)
        raise AssertionError('session marker timeout')
    def close(self):
        if self.p.poll() is None:
            self.p.stdin.close()
            try: self.p.wait(timeout=3)
            except subprocess.TimeoutExpired: self.p.kill();self.p.wait()
        self.p.stdout.close(); self.p.stderr.close()

class NativeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        version=run("SELECT current_setting('server_version_num');",db='postgres').stdout.strip()
        assert 170000<=int(version)<180000, version
        run('DROP DATABASE IF EXISTS '+DB+' WITH (FORCE);',db='postgres')
        run('CREATE DATABASE '+DB+';',db='postgres')
        run("""DO $$ BEGIN
          IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='postgres') THEN CREATE ROLE postgres; END IF;
          IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role; END IF;
          IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF;
          IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF;
        END $$;
        CREATE SCHEMA cron;
        CREATE TABLE cron.job(jobid bigint primary key,jobname text unique, schedule text,
           command text,database text,username text,active boolean);
        CREATE FUNCTION cron.alter_job(job_id bigint,schedule text DEFAULT NULL,command text DEFAULT NULL,
          database text DEFAULT NULL,username text DEFAULT NULL,active boolean DEFAULT NULL)
        RETURNS void LANGUAGE sql AS $$ UPDATE cron.job SET command=$3 WHERE jobid=$1 $$;
        """)
        for i,(key,(name,fn,schedule)) in enumerate(JOBS.items(),1):
            run(f"INSERT INTO cron.job VALUES({i},'{name}','{schedule}','select public.{fn}();','postgres','postgres',true);")
            run((ROOT/'supabase/tests/baseline'/f'{fn}.sql').read_text())
        run((ROOT/'supabase/tests/baseline/alpha_winner_protection_tick.sql').read_text())
        cls.hash_query = "SELECT jsonb_object_agg(proname,md5(pg_get_functiondef(oid))) FROM pg_proc WHERE pronamespace='public'::regnamespace;"
        before=json.loads(run(cls.hash_query).stdout)
        cls.metadata=run("SELECT jsonb_agg(jsonb_build_array(jobid,jobname,schedule,database,username,active) ORDER BY jobid) FROM cron.job;").stdout
        cls.migration=(ROOT/'supabase/migrations/20260909075906_serialize_portfolio_maintenance.sql').read_text()
        run('BEGIN;'+cls.migration+'COMMIT;')
        after=json.loads(run(cls.hash_query).stdout)
        for fn in ('alpha_autonomy_heartbeat','alpha_liveness_guard_tick','alpha_master_daily_sop_tick'):
            assert after[fn]==before[fn], fn+' changed unexpectedly'
        assert after['alpha_autonomous_worker_tick_v7']!=before['alpha_autonomous_worker_tick_v7']
        assert after['alpha_winner_protection_tick']!=before['alpha_winner_protection_tick']
        winner_def=run("SELECT pg_get_functiondef('public.alpha_winner_protection_tick()'::regprocedure);").stdout
        worker_def=run("SELECT pg_get_functiondef('public.alpha_autonomous_worker_tick_v7()'::regprocedure);").stdout
        assert "pg_advisory_xact_lock(1095520328,1)" in winner_def
        assert "order by upper(replace(ticker,'-BE','')),ticker" in winner_def
        assert 'FAILED_DEADLOCK_RETRIES_EXHAUSTED' in worker_def
        assert 'ALPHA_WINNER_PROTECTION_DEADLOCK_RETRY' in worker_def
        EVIDENCE.append({'case':'scoped_function_changes','status':'PASS',
          'unchanged':['alpha_autonomy_heartbeat','alpha_liveness_guard_tick','alpha_master_daily_sop_tick'],
          'changed':['alpha_winner_protection_tick','alpha_autonomous_worker_tick_v7'],
          'deterministic_ticker_order':True,'direct_advisory_gate':True,
          'worker_bounded_retry_and_fail_soft':True})

        run("""CREATE TABLE blast_radius_calls(stage text);
        CREATE SEQUENCE test_deadlock_seq;
        CREATE OR REPLACE FUNCTION public.alpha_autonomous_worker_tick_v4() RETURNS jsonb
          LANGUAGE sql AS $$ SELECT '{"phase":"MARKET_HOURS"}'::jsonb $$;
        CREATE OR REPLACE FUNCTION public.alpha_winner_protection_tick() RETURNS jsonb
          LANGUAGE plpgsql AS $$ BEGIN
            PERFORM nextval('test_deadlock_seq');
            RAISE EXCEPTION 'FORCED_DEADLOCK' USING ERRCODE='40P01';
          END $$;
        CREATE OR REPLACE FUNCTION public.alpha_delivery_gate_tick() RETURNS jsonb
          LANGUAGE plpgsql AS $$ BEGIN INSERT INTO blast_radius_calls VALUES('delivery');
            RETURN '{"delivery":"continued"}'::jsonb; END $$;
        CREATE OR REPLACE FUNCTION public.alpha_evolution_governor_tick() RETURNS jsonb
          LANGUAGE plpgsql AS $$ BEGIN INSERT INTO blast_radius_calls VALUES('evolution');
            RETURN '{"evolution":"continued"}'::jsonb; END $$;
        """)
        blast=json.loads(run("SELECT public.alpha_autonomous_worker_tick_v7();").stdout)
        assert blast['winner_protection']['status']=='FAILED_DEADLOCK_RETRIES_EXHAUSTED'
        assert blast['winner_protection']['attempts']==3
        assert blast['delivery_gate']=={'delivery':'continued'}
        assert blast['evolution_governor']=={'evolution':'continued'}
        assert run("SELECT count(*) FROM blast_radius_calls;").stdout.strip()=='2'
        EVIDENCE.append({'case':'worker_deadlock_blast_radius','status':'PASS',
          'winner_attempts':3,'delivery_continued':True,'evolution_continued':True})

        run("""CREATE SEQUENCE test_wrapper_retry_seq;
        CREATE OR REPLACE FUNCTION public.alpha_autonomy_heartbeat() RETURNS jsonb
          LANGUAGE plpgsql AS $$ BEGIN
            IF nextval('test_wrapper_retry_seq')=1 THEN
              RAISE EXCEPTION 'FORCED_DEADLOCK' USING ERRCODE='40P01';
            END IF;
            RETURN '{"status":"RETRIED_OK"}'::jsonb;
          END $$;""")
        retry=json.loads(run("SELECT public.alpha_run_portfolio_maintenance_serialized('heartbeat');").stdout)
        assert retry=={'status':'RETRIED_OK'}
        assert run("SELECT last_value FROM test_wrapper_retry_seq;").stdout.strip()=='2'
        EVIDENCE.append({'case':'bounded_deadlock_retry','status':'PASS','attempts':2})

        run("""CREATE TABLE test_queue(id int primary key, n int); INSERT INTO test_queue VALUES(1,0);
        CREATE TABLE test_targets(id int primary key,n int); INSERT INTO test_targets VALUES(1,0);
        CREATE TABLE test_calls(job text);
        GRANT ALL ON test_queue,test_targets,test_calls TO service_role,postgres;""")
        for i,(key,(_,fn,_)) in enumerate(JOBS.items()):
            first,second=('test_queue','test_targets') if i%2 else ('test_targets','test_queue')
            run(f"""CREATE OR REPLACE FUNCTION public.{fn}() RETURNS jsonb LANGUAGE plpgsql AS $$
            BEGIN
              UPDATE {first} SET n=n+1 WHERE id=1;
              IF current_setting('alpha.test_fail',true)='yes' THEN RAISE EXCEPTION 'TEST_ERROR'; END IF;
              UPDATE {second} SET n=n+1 WHERE id=1;
              INSERT INTO test_calls VALUES('{key}');
              RETURN jsonb_build_object('job','{key}','status','ORIGINAL_RESULT');
            END $$;""")
        EVIDENCE.append({'server_version_num':version,'production_touched':False,
                         'scope':'native wrapper concurrency, existing bodies hash preservation; downstream functions stubbed'})

    def setUp(self):
        run("TRUNCATE test_calls; UPDATE test_queue SET n=0; UPDATE test_targets SET n=0;")

    def test_16_independent_connection_pairs(self):
        for a_job,b_job in itertools.product(JOBS, repeat=2):
            with self.subTest(a=a_job,b=b_job):
                run("TRUNCATE test_calls; UPDATE test_queue SET n=0; UPDATE test_targets SET n=0;")
                self.pair(a_job,b_job,False)

    def pair(self,a_job,b_job,rollback):
        a,b=Session('alpha_test_A'),Session('alpha_test_B')
        try:
            a.send(f"BEGIN; SELECT public.alpha_run_portfolio_maintenance_serialized('{a_job}'); SELECT 'READY_A';")
            a_result=json.loads(a.until('READY_A')[0])
            self.assertEqual(a_result,{'job':a_job,'status':'ORIGINAL_RESULT'})
            b.send(f"BEGIN; SELECT public.alpha_run_portfolio_maintenance_serialized('{b_job}'); SELECT 'READY_B';")
            evidence=None
            for _ in range(30):
                row=run("""SELECT jsonb_build_object('pid',a.pid,'wait_event_type',a.wait_event_type,
                  'wait_event',a.wait_event,'blocking_pids',pg_blocking_pids(a.pid),
                  'ungranted_advisory_lock',EXISTS(SELECT 1 FROM pg_locks l
                      WHERE l.pid=a.pid AND l.locktype='advisory' AND NOT l.granted))
                  FROM pg_stat_activity a WHERE application_name='alpha_test_B' AND a.wait_event_type='Lock';""").stdout.strip()
                if row:
                    evidence=json.loads(row);break
                time.sleep(.025)
            self.assertIsNotNone(evidence, 'B did not actually wait')
            self.assertTrue(evidence['ungranted_advisory_lock'])
            self.assertTrue(evidence['blocking_pids'])
            a.send(('ROLLBACK' if rollback else 'COMMIT')+"; SELECT 'RELEASED';")
            a.until('RELEASED')
            b_result=json.loads(b.until('READY_B')[0])
            self.assertEqual(b_result,{'job':b_job,'status':'ORIGINAL_RESULT'})
            b.send("COMMIT; SELECT 'DONE';");b.until('DONE')
            counts=json.loads(run("SELECT jsonb_build_array((SELECT n FROM test_queue),(SELECT n FROM test_targets),(SELECT count(*) FROM test_calls));").stdout)
            self.assertEqual(counts,[1,1,1] if rollback else [2,2,2])
            EVIDENCE.append({'case':a_job+'/'+b_job,'rollback':rollback,'status':'PASS','wait':evidence,'counts':counts})
        finally:
            a.close();b.close()


    def test_unguarded_cycle_reproduces_deadlock(self):
        a,b=Session('alpha_negative_A'),Session('alpha_negative_B')
        try:
            a.send("BEGIN; SET LOCAL deadlock_timeout='100ms'; UPDATE test_queue SET n=n+1; SELECT 'A_LOCKED';")
            a.until('A_LOCKED')
            b.send("BEGIN; SET LOCAL deadlock_timeout='100ms'; UPDATE test_targets SET n=n+1; SELECT 'B_LOCKED';")
            b.until('B_LOCKED')
            a.send("UPDATE test_targets SET n=n+1; SELECT 'A_SECOND';")
            waiting=None
            for _ in range(30):
                row=run("SELECT jsonb_build_object('pid',pid,'wait_event_type',wait_event_type,'wait_event',wait_event,'blocking_pids',pg_blocking_pids(pid)) FROM pg_stat_activity WHERE application_name='alpha_negative_A' AND wait_event_type='Lock';").stdout.strip()
                if row: waiting=json.loads(row);break
                time.sleep(.025)
            self.assertIsNotNone(waiting)
            b.send("UPDATE test_queue SET n=n+1; SELECT 'B_SECOND';")
            for _ in range(100):
                if a.p.poll() is not None or b.p.poll() is not None: break
                time.sleep(.025)
            victim,survivor,marker=(a,b,'B_SECOND') if a.p.poll() is not None else (b,a,'A_SECOND')
            self.assertIsNotNone(victim.p.poll())
            self.assertNotEqual(victim.p.returncode,0)
            self.assertIn('deadlock detected',victim.p.stderr.read())
            survivor.until(marker)
            survivor.send("COMMIT; SELECT 'SURVIVOR_COMMITTED';")
            survivor.until('SURVIVOR_COMMITTED')
            EVIDENCE.append({'case':'negative_control_without_gate','status':'PASS',
                             'expected_deadlock_reproduced':True,'wait':waiting})
        finally:
            a.close();b.close()

    def test_rollback_releases_gate(self):
        self.pair('worker','daily_sop',True)

    def test_acl_and_invalid_selector(self):
        for role in ['anon','authenticated']:
            r=run(f"SET ROLE {role}; SELECT public.alpha_run_portfolio_maintenance_serialized('worker');",check=False)
            self.assertNotEqual(r.returncode,0)
            self.assertIn('permission denied',r.stderr)
        public_acl=run("""SELECT count(*) FROM pg_proc p,LATERAL aclexplode(p.proacl) a
           WHERE p.oid='public.alpha_run_portfolio_maintenance_serialized(text)'::regprocedure
           AND a.grantee=0 AND a.privilege_type='EXECUTE';""").stdout.strip()
        self.assertEqual(public_acl,'0')
        for role in ['service_role','postgres']:
            self.assertEqual(json.loads(run(f"SET ROLE {role}; SELECT public.alpha_run_portfolio_maintenance_serialized('worker');").stdout)['job'],'worker')
        for value in ["NULL","'other'"]:
            r=run(f"SELECT public.alpha_run_portfolio_maintenance_serialized({value});",check=False)
            self.assertNotEqual(r.returncode,0)
            self.assertIn('UNKNOWN_PORTFOLIO_MAINTENANCE_JOB',r.stderr)

    def test_error_is_not_reported_as_success(self):
        r=run("SET alpha.test_fail='yes'; SELECT public.alpha_run_portfolio_maintenance_serialized('worker');",check=False)
        self.assertNotEqual(r.returncode,0);self.assertIn('TEST_ERROR',r.stderr)
        self.assertEqual(run("SELECT n FROM test_queue;").stdout.strip(),'0')
        self.assertEqual(json.loads(run("SELECT public.alpha_run_portfolio_maintenance_serialized('worker');").stdout)['job'],'worker')

    def test_metadata_and_command_mapping(self):
        self.assertEqual(self.metadata,run("SELECT jsonb_agg(jsonb_build_array(jobid,jobname,schedule,database,username,active) ORDER BY jobid) FROM cron.job;").stdout)
        commands=json.loads(run("SELECT jsonb_object_agg(jobname,command) FROM cron.job;").stdout)
        for key,(name,_,_) in JOBS.items():
            self.assertEqual(commands[name],f"select public.alpha_run_portfolio_maintenance_serialized('{key}');")

    def test_repeat_migration_fails_closed(self):
        r=run('BEGIN;'+self.migration+'COMMIT;',check=False)
        self.assertNotEqual(r.returncode,0)
        self.assertIn('SERIALIZED_WRAPPER_ALREADY_EXISTS',r.stderr)

if __name__=='__main__':
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(NativeTests))
    Path(__file__).with_name('native-results.json').write_text(json.dumps({
        'passed':result.wasSuccessful(),'tests':result.testsRun,'evidence':EVIDENCE},indent=2))
    raise SystemExit(0 if result.wasSuccessful() else 1)

