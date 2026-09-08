// Run only in a fresh in-memory PGlite instance. Accepts NO database URL.
// Node >=20; @electric-sql/pglite 0.5.8, installed outside the application.
// Optional PGLITE_MODULE is an absolute path to that package's dist/index.js.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(process.env.PGLITE_MODULE
  ? pathToFileURL(process.env.PGLITE_MODULE).href : '@electric-sql/pglite');
const read=p=>fs.readFile(new URL(p,import.meta.url),'utf8');
const fixture=await read('fixture.sql');
const baseline=await read('baseline.sql');
const migration=await read('../../migrations/20260908125005_session_capital_lock_immutability.sql');
const targetNames=['alpha_lock_session_capital','alpha_sync_session_lock_from_brain'];
const forwardNames=['alpha_evaluate_campaign_route','alpha_reconcile_route_execution_from_broker',
  'alpha_expire_session_routes','alpha_route_monitor_tick'];
assert.deepEqual([...migration.matchAll(/(?:create or replace function)\s+public\.(\w+)/gi)].map(m=>m[1]),targetNames);
assert.doesNotMatch(migration,/\b(?:grant|revoke|alter|drop|create table|create trigger)\b/i);
assert.doesNotMatch(migration,/on conflict\(trade_date\)|update public\.alpha_session_capital_lock/i);
assert.equal((migration.match(/pg_catalog\.pg_advisory_xact_lock\(1095520332,/g)||[]).length,2);
assert.equal((migration.match(/for update;/g)||[]).length,2);
// First-create route/queue code is exactly the supplied baseline tail.
assert.equal(migration.slice(migration.indexOf("  v_routes:=v_item->'routes';")),
  baseline.slice(baseline.indexOf("  v_routes:=v_item->'routes';")));

const day='2026-09-08', expiry='2026-09-08T10:00:00Z';
const defaultRequest=[day,'TEST','PLAN:TEST',1000,400,5000,expiry,'PREOPEN_BRIDGE'];
const basePlan={status:'LOCKED',locked_at:'2026-09-08T02:00:00Z',expires_at:expiry,
  total_nav:5000,capital_owner:'TEST',lock_id:'PLAN',items:[{ticker:'TEST',rupee_amount:400,
    routes:[{route_key:'PRIMARY',entry_low:100,entry_high:101,model_entry:100,
      structural_stop:95,target_price:120}]}]};
const tables=['alpha_session_capital_lock','alpha_campaign_routes','alpha_autonomy_queue','test_events'];
const results=[];
let version;
async function run(candidate,label) {
  const db=new PGlite();
  const q=async(sql,args)=>(await db.query(sql,args)).rows;
  const scalar=async(sql,args)=>(await q(sql,args))[0].v;
  const helper=(args=defaultRequest)=>scalar('SELECT public.alpha_lock_session_capital($1::date,$2::text,$3::text,$4::numeric,$5::numeric,$6::numeric,$7::timestamptz,$8::text) AS v',args);
  const bridge=()=>scalar('SELECT public.alpha_sync_session_lock_from_brain() AS v');
  const row=()=>scalar('SELECT to_jsonb(s) AS v FROM public.alpha_session_capital_lock s');
  const snapshot=async()=>Object.fromEntries(await Promise.all(tables.map(async t=>[t,await q(`SELECT to_jsonb(t) AS data FROM public.${t} t ORDER BY to_jsonb(t)::text`)])));
  const plan=async(p=structuredClone(basePlan))=>db.query("INSERT INTO public.brain_state VALUES('ALPHA-OS-CANONICAL',$1::jsonb) ON CONFLICT(state_key) DO UPDATE SET current_truth=excluded.current_truth",[JSON.stringify({capital_plan:p})]);
  const reset=async()=>{
    await db.exec(`TRUNCATE public.alpha_session_capital_lock, public.alpha_campaign_routes,
      public.alpha_autonomy_queue,public.test_events,public.brain_state,
      public.zerodha_sync_log_internal,public.live_portfolio,public.portfolio_campaign_targets;
      SET test.clock='2026-09-08 02:30:00+00';
      INSERT INTO public.zerodha_sync_log_internal VALUES('SUCCESS',1000,now());`);
    await plan();
  };
  const advance=()=>db.exec("SET test.clock='2026-09-08 02:35:00+00'");
  const protect=async(status)=>{
    await db.exec("INSERT INTO public.alpha_campaign_routes(id,args) VALUES('11111111-1111-1111-1111-111111111111','{}') ON CONFLICT DO NOTHING");
    await db.query(`UPDATE public.alpha_session_capital_lock SET status=$1,
      fresh_campaigns_executed=1,executed_route_id='11111111-1111-1111-1111-111111111111',
      executed_decision_id='22222222-2222-2222-2222-222222222222',
      session_invalidation_reason='PRESERVE_REASON',cash_remaining=123,
      updated_at='2026-09-08 02:31:00+00'`,[status]);
  };
  const checks={};
  const test=async(name,fn)=>{try{await reset();await fn();checks[name]='PASS';}
    catch(e){checks[name]='FAIL: '+e.message;}};
  try {
    await db.exec(fixture+baseline);
    await db.exec(`REVOKE ALL ON FUNCTION public.alpha_lock_session_capital(date,text,text,numeric,numeric,numeric,timestamptz,text),
      public.alpha_sync_session_lock_from_brain() FROM PUBLIC,anon,authenticated;
      GRANT EXECUTE ON FUNCTION public.alpha_lock_session_capital(date,text,text,numeric,numeric,numeric,timestamptz,text),
      public.alpha_sync_session_lock_from_brain() TO service_role;`);
    version=await scalar('SELECT version() AS v');
    assert.equal(await scalar("SELECT now()=timestamptz '2026-09-08 02:30:00+00' AS v"),true);
    const procSQL=`SELECT p.proname, p.oid, pg_get_functiondef(p.oid) AS definition,
      p.proacl::text AS acl,p.proowner,p.prosecdef,p.proconfig
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' ORDER BY p.oid`;
    const schemaSQL=`SELECT c.relname,c.relrowsecurity,c.relacl::text,
      (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0) AS columns,
      (SELECT jsonb_agg(pg_get_constraintdef(k.oid) ORDER BY k.oid) FROM pg_constraint k WHERE k.conrelid=c.oid) AS constraints,
      (SELECT jsonb_agg(pg_get_triggerdef(t.oid) ORDER BY t.oid) FROM pg_trigger t WHERE t.tgrelid=c.oid) AS triggers
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND c.relkind='r' ORDER BY c.relname`;
    const procsBefore=await q(procSQL),schemaBefore=await q(schemaSQL),dataBefore=await snapshot();
    await db.exec(candidate);
    const procsAfter=await q(procSQL);
    assert.deepEqual(procsAfter.filter(p=>!targetNames.includes(p.proname)),procsBefore.filter(p=>!targetNames.includes(p.proname)));
    for(const name of forwardNames)assert.equal(procsAfter.filter(p=>p.proname===name).length,1);
    for(const p of procsBefore.filter(p=>targetNames.includes(p.proname))){
      const after=procsAfter.find(a=>a.oid===p.oid);
      assert.deepEqual({...after,definition:null},{...p,definition:null});
    }
    assert.deepEqual(await q(schemaSQL),schemaBefore);
    assert.deepEqual(await snapshot(),dataBefore);
    checks['O metadata: non-target definitions/ACLs, target ACLs, schema unchanged']='PASS (isolated metadata sentinels)';
    await test('A FIRST LOCK',async()=>{
      const r=await helper();
      assert.equal(r.status,'LOCKED');assert.equal(r.capital_owner_ticker,'TEST');
      assert.equal(r.capital_owner_campaign_id,'PLAN:TEST');assert.equal(r.cash_remaining,600);
      assert.equal(r.cash_reserved,400);assert.equal(r.total_nav,5000);
      assert.equal(r.max_fresh_campaigns,1);assert.equal(r.fresh_campaigns_executed,0);
      assert.equal(r.reroute_allowed,false);assert.equal(r.intraday_new_destination_allowed,false);
      assert.equal(r.executed_route_id,null);assert.equal(r.session_invalidation_reason,null);
      assert.ok(r.lock_id&&r.locked_at&&r.created_at&&r.updated_at);
      const events=await q('SELECT * FROM public.test_events');
      assert.equal(events.length,1);assert.equal(events[0].event_type,'SESSION_CAPITAL_LOCKED');
      assert.equal(events[0].payload.capital_authority,false);assert.deepEqual(r,await row());
    });
    await test('B IDENTICAL RETRY',async()=>{await helper();const before=await snapshot();const r=await row();
      await advance();assert.deepEqual(await helper(),r);assert.deepEqual(await snapshot(),before);});
    await test('C CASH/NAV REFRESH + normalized owner',async()=>{await helper();const before=await snapshot();const r=await row();
      await advance();assert.deepEqual(await helper([day,'test','PLAN:TEST',2000,900,7000,'2026-09-08T11:00:00Z','RETRY']),r);
      assert.deepEqual(await snapshot(),before);});
    for(const [letter,name,index,value] of [['D','OWNER MUTATION',1,'OTHER'],['E','CAMPAIGN MUTATION',2,'OTHER']]){
      await test(`${letter} ${name}`,async()=>{await helper();const before=await snapshot();const args=[...defaultRequest];args[index]=value;
        await assert.rejects(helper(args),e=>e.code==='P0001'&&e.message==='SESSION_CAPITAL_LOCK_CONFLICT');
        assert.deepEqual(await snapshot(),before);});
    }
    for(const [letter,status] of [['F','TRIGGERED'],['G','EXECUTED'],['H','KEEP_CASH'],['I','DATA_BLOCKED'],['J','CANCELLED'],['K','EXPIRED'],['extra','DRAFT']]){
      await test(`${letter} ${status} PRESERVATION`,async()=>{await helper();await protect(status);const before=await snapshot(),r=await row();
        await advance();assert.deepEqual(await helper(),r);assert.deepEqual(await snapshot(),before);});
    }
    await test('L BRIDGE RETRY all statuses + route/event/queue suppression',async()=>{
      for(const status of ['LOCKED','DRAFT','TRIGGERED','EXECUTED','KEEP_CASH','DATA_BLOCKED','CANCELLED','EXPIRED']){
        await reset();await bridge();await protect(status);const before=await snapshot(),r=await row();
        await advance();const reply=await bridge();assert.equal(reply.ok,true);assert.equal(reply.status,status);
        assert.equal(reply.idempotent_retry,true);assert.deepEqual(reply.session,r);assert.deepEqual(await snapshot(),before);
      }
      await reset();const p=structuredClone(basePlan);p.items[0].routes=[];await plan(p);
      await bridge();assert.equal((await q('SELECT * FROM public.alpha_autonomy_queue')).length,1);
      const before=await snapshot();await advance();await bridge();assert.deepEqual(await snapshot(),before);
    });
    await test('M BRIDGE current owner/campaign conflict',async()=>{
      for(const change of ['owner','campaign','cash']){
        await reset();await bridge();await protect('EXECUTED');const p=structuredClone(basePlan);
        if(change==='owner'){p.capital_owner='OTHER';p.items[0].ticker='OTHER';}
        if(change==='campaign')p.lock_id='OTHER';if(change==='cash')p.capital_owner='CASH';
        await plan(p);const before=await snapshot(),r=await row();const reply=await bridge();
        assert.equal(reply.ok,false);assert.equal(reply.status,'SESSION_CAPITAL_LOCK_CONFLICT');
        assert.equal(reply.existing_status,'EXECUTED');assert.deepEqual(reply.session,r);assert.deepEqual(await snapshot(),before);
      }
    });
    await test('N BRIDGE invalid current input preserves existing',async()=>{
      const variants=[null,{status:'DRAFT'},{...basePlan,locked_at:'2026-09-07T02:00:00Z'},
        {...basePlan,expires_at:'2026-09-08T02:00:00Z'},{...basePlan,locked_at:'bad-date'},
        {...basePlan,total_nav:'bad-number'},{...basePlan,items:null},{...basePlan,items:{}},
        {...basePlan,items:[{ticker:'OTHER'}]},
        {...basePlan,items:[{ticker:'TEST',rupee_amount:0}]},
        {...basePlan,items:[{ticker:'TEST',rupee_amount:'bad-number'}]}];
      for(const p of variants){
        await reset();await bridge();await protect('EXECUTED');await plan(p);
        const before=await snapshot(),r=await row(),reply=await bridge();
        assert.equal(reply.ok,false);assert.equal(reply.status,'SESSION_LOCK_PRESERVED_CURRENT_INPUT_INVALID');
        assert.equal(reply.existing_status,'EXECUTED');assert.ok(reply.reason);
        assert.deepEqual(reply.session,r);assert.deepEqual(await snapshot(),before);
      }
      await reset();await bridge();await db.exec('TRUNCATE public.zerodha_sync_log_internal');
      const before=await snapshot();assert.equal((await bridge()).status,'SESSION_LOCK_PRESERVED_CURRENT_INPUT_INVALID');
      assert.deepEqual(await snapshot(),before);
    });
    await test('O forward updates remain possible (table contract only)',async()=>{
      await helper();
      for(const status of ['TRIGGERED','EXECUTED','KEEP_CASH','EXPIRED']){
        await db.query('UPDATE public.alpha_session_capital_lock SET status=$1',[status]);
        assert.equal((await row()).status,status);
      }
    });
    await test('extra bridge financial refresh + KEEP_CASH retry',async()=>{
      await bridge();const before=await snapshot(),r=await row();
      await db.exec('UPDATE public.zerodha_sync_log_internal SET cash_available=3000');
      const p=structuredClone(basePlan);p.total_nav=8000;p.items[0].rupee_amount=900;p.expires_at='2026-09-08T11:00:00Z';
      await plan(p);assert.deepEqual((await bridge()).session,r);assert.deepEqual(await snapshot(),before);
      await reset();await plan({...basePlan,capital_owner:'CASH'});assert.equal((await bridge()).status,'KEEP_CASH');
      const cashBefore=await snapshot();assert.equal((await bridge()).idempotent_retry,true);assert.deepEqual(await snapshot(),cashBefore);
    });
    await test('extra first-create bridge paths retained',async()=>{
      const scenarios=[['LOCKED',structuredClone(basePlan)],['KEEP_CASH',{...basePlan,capital_owner:'CASH'}],
        ['KEEP_CASH',{...basePlan,items:[]}],['DATA_BLOCKED',{...basePlan,locked_at:'2026-09-07T02:00:00Z'}],
        ['DATA_BLOCKED',{...basePlan,items:[{ticker:'TEST',rupee_amount:0}]}]];
      for(const [status,p] of scenarios){await reset();await plan(p);await bridge();assert.equal((await row()).status,status);
        const snap=await snapshot();assert.equal(snap.test_events.length,['LOCKED','KEEP_CASH'].includes(status)?1:0);
        assert.equal(snap.alpha_campaign_routes.length,status==='LOCKED'?1:0);
      }
      await reset();await plan(null);assert.equal((await bridge()).status,'NO_LOCKED_CAPITAL_PLAN');assert.equal((await snapshot()).alpha_session_capital_lock.length,0);
      await reset();await plan({...basePlan,items:[{ticker:'OTHER'}]});assert.equal((await bridge()).status,'OWNER_ITEM_MISSING');
      assert.equal((await snapshot()).alpha_session_capital_lock.length,0);
    });
    await test('extra weekday/cutoff unchanged',async()=>{
      await db.exec("SET test.clock='2026-09-12 02:30:00+00'");assert.equal((await bridge()).status,'WEEKEND');
      await db.exec("SET test.clock='2026-09-08 03:45:00+00'");assert.equal((await bridge()).status,'TOO_LATE_FOR_PREOPEN_SESSION_SYNC');
      assert.equal((await snapshot()).alpha_session_capital_lock.length,0);
    });
    await test('extra helper validation + null campaign identity',async()=>{
      const variants=[[0,null,'trade_date required'],[1,' ','capital owner required'],[3,-1,'cash invalid'],
        [4,1001,'cash_reserved invalid'],[4,null,'cash_reserved invalid'],[5,0,'total_nav invalid']];
      for(const [i,v,message] of variants){const args=[...defaultRequest];args[i]=v;await assert.rejects(helper(args),e=>e.message===message);}
      assert.equal((await snapshot()).alpha_session_capital_lock.length,0);
      const args=[...defaultRequest];args[2]=null;await helper(args);const before=await snapshot();
      await helper(args);assert.deepEqual(await snapshot(),before);args[2]='PLAN:TEST';
      await assert.rejects(helper(args),e=>e.message==='SESSION_CAPITAL_LOCK_CONFLICT');assert.deepEqual(await snapshot(),before);
    });
    results.push({label,checks});
    return checks;
  } finally {await db.close();}
}
const fixed=await run(migration,'candidate migration');
const old=await run('','negative control: original functions');
console.log(JSON.stringify({version,results,concurrency:'NOT PROVEN: PGlite is single-session; native two-connection tests remain required'},null,2));
assert.ok(Object.values(fixed).every(r=>r.startsWith('PASS')),'candidate failed regressions');
for(const prefix of ['B ','C ','D ','E ','F ','G ','H ','I ','J ','K ','L ','M ','N ']){
  assert.ok(Object.entries(old).some(([name,result])=>name.startsWith(prefix)&&result.startsWith('FAIL')),
    `negative control did not expose original defect: ${prefix}`);
}
console.log('PASS: candidate regressions; original implementation rejected by B-N negative controls.');
