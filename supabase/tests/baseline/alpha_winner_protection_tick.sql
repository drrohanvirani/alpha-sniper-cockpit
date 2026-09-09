CREATE OR REPLACE FUNCTION public.alpha_winner_protection_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r record;
  v_tradebook_balance numeric;
  v_campaign_start date;
  v_peak numeric;
  v_peak_hist numeric;
  v_peak_obs numeric;
  v_peak_gain numeric;
  v_current_gain numeric;
  v_drawdown numeric;
  v_giveback numeric;
  v_sma10 numeric;
  v_sma20 numeric;
  v_sma50 numeric;
  v_vol_ratio numeric;
  v_ret5 numeric;
  v_baseline text;
  v_state text;
  v_priority int;
  v_queue_key text;
  v_count int := 0;
  v_watch int := 0;
  v_review int := 0;
  v_urgent int := 0;
  v_old_state text;
  v_changed boolean;
begin
  for r in
    select ticker,quantity,avg_price,current_price,portfolio_weight,snapshot_at
    from public.live_portfolio
    where quantity>0 and avg_price>0 and current_price>0
  loop
    v_count := v_count + 1;
    v_campaign_start := null;
    v_tradebook_balance := null;

    select coalesce(sum(case when upper(trade_type) in ('BUY','B') then quantity when upper(trade_type) in ('SELL','S') then -quantity else 0 end),0)
      into v_tradebook_balance
    from public.zerodha_tradebook_fills
    where upper(replace(symbol,'-BE',''))=upper(replace(r.ticker,'-BE',''));

    if abs(coalesce(v_tradebook_balance,0)-r.quantity) < 0.001 and v_tradebook_balance>0 then
      with d as (
        select trade_date,
               sum(case when upper(trade_type) in ('BUY','B') then quantity when upper(trade_type) in ('SELL','S') then -quantity else 0 end) net_qty
        from public.zerodha_tradebook_fills
        where upper(replace(symbol,'-BE',''))=upper(replace(r.ticker,'-BE',''))
        group by trade_date
      ), x as (
        select trade_date,sum(net_qty) over(order by trade_date rows unbounded preceding) bal
        from d
      ), z as (
        select max(trade_date) filter(where bal=0) last_zero from x
      )
      select min(x.trade_date) into v_campaign_start
      from x cross join z
      where x.trade_date>coalesce(z.last_zero,date '1900-01-01') and x.bal>0;
      v_baseline := case when v_campaign_start is not null then 'HIGH_TRADEBOOK_MATCH' else 'PARTIAL_PROSPECTIVE' end;
    else
      v_baseline := 'PARTIAL_PROSPECTIVE';
    end if;

    v_peak_hist := null;
    if v_campaign_start is not null then
      select max(high) into v_peak_hist
      from public.trade_audit_market_cache
      where upper(replace(ticker,'-BE',''))=upper(replace(r.ticker,'-BE',''))
        and candle_date>=v_campaign_start;
    end if;

    select max(current_price) into v_peak_obs
    from public.alpha_market_observations
    where upper(replace(ticker,'-BE',''))=upper(replace(r.ticker,'-BE',''))
      and (v_campaign_start is null or (observed_at at time zone 'Asia/Kolkata')::date>=v_campaign_start);

    v_peak := greatest(r.current_price,coalesce(v_peak_hist,r.current_price),coalesce(v_peak_obs,r.current_price));
    v_peak_gain := 100*(v_peak/r.avg_price-1);
    v_current_gain := 100*(r.current_price/r.avg_price-1);
    v_drawdown := 100*(r.current_price/v_peak-1);
    v_giveback := case when v_peak>r.avg_price and r.current_price<v_peak then 100*(v_peak-r.current_price)/(v_peak-r.avg_price) else 0 end;

    select f.sma10,f.sma20,f.sma50,f.volume_ratio_20d,f.return_5d_pct
      into v_sma10,v_sma20,v_sma50,v_vol_ratio,v_ret5
    from public.alpha_market_features f
    where upper(replace(f.symbol,'-BE',''))=upper(replace(r.ticker,'-BE',''))
    order by f.trade_date desc limit 1;

    v_state := 'NORMAL';
    v_priority := 0;
    if v_peak_gain>=20 and (v_giveback>=60 or v_drawdown<=-12) then
      v_state := 'URGENT_PROFIT_PROTECTION_REVIEW'; v_priority:=100; v_urgent:=v_urgent+1;
    elsif v_peak_gain>=15 and (v_giveback>=40 or v_drawdown<=-8) then
      v_state := 'PROFIT_PROTECTION_REVIEW'; v_priority:=96; v_review:=v_review+1;
    elsif v_peak_gain>=10 and (v_giveback>=25 or v_drawdown<=-5) then
      v_state := 'WATCH_GIVEBACK'; v_priority:=84; v_watch:=v_watch+1;
    end if;

    v_queue_key := 'WINNER_PROTECTION:'||upper(replace(r.ticker,'-BE',''));
    select evidence->>'state' into v_old_state from public.alpha_autonomy_queue where queue_key=v_queue_key limit 1;
    v_changed := coalesce(v_old_state,'NORMAL') is distinct from v_state;

    update public.portfolio_campaign_targets pct
    set execution_plan = coalesce(pct.execution_plan,'{}'::jsonb) || jsonb_build_object(
          'profit_retention', jsonb_build_object(
            'state',v_state,
            'checked_at',now(),
            'campaign_peak',v_peak,
            'peak_gain_pct',round(v_peak_gain,2),
            'current_gain_pct',round(v_current_gain,2),
            'profit_giveback_pct',round(v_giveback,2),
            'drawdown_from_peak_pct',round(v_drawdown,2),
            'sma10',v_sma10,'sma20',v_sma20,'sma50',v_sma50,
            'requires_preopen_map',v_peak_gain>=10,
            'required_map_fields',jsonb_build_array('sell_into_strength','sell_into_weakness','hard_fail_safe','post_trim_residual_policy','reentry_criteria'),
            'intraday_rule',case when v_state='URGENT_PROFIT_PROTECTION_REVIEW' then 'IMMEDIATE_ACTION_REVIEW_NO_SILENT_QUEUE' when v_state='PROFIT_PROTECTION_REVIEW' then 'SAME_SESSION_ACTION_REVIEW' when v_state='WATCH_GIVEBACK' then 'ACTIVE_WATCH' else 'NORMAL' end
          )
        ),
        updated_at=now()
    where upper(replace(pct.ticker,'-BE',''))=upper(replace(r.ticker,'-BE',''));

    if v_state='NORMAL' then
      update public.alpha_autonomy_queue
         set status='RESOLVED',resolved_at=now(),updated_at=now(),
             answer_evidence=jsonb_build_array(jsonb_build_object('checked_at',now(),'current_price',r.current_price,'peak_reference',v_peak,'peak_gain_pct',round(v_peak_gain,2),'current_gain_pct',round(v_current_gain,2),'drawdown_from_peak_pct',round(v_drawdown,2),'profit_giveback_pct',round(v_giveback,2),'baseline_quality',v_baseline)),
             answer_conclusion='Winner-protection state returned to NORMAL',
             decision_impact='No protection action required at this check',
             answered_at=now(),
             evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object('last_state','NORMAL','checked_at',now(),'current_price',r.current_price,'peak_reference',v_peak,'peak_gain_pct',round(v_peak_gain,2),'current_gain_pct',round(v_current_gain,2),'drawdown_from_peak_pct',round(v_drawdown,2),'profit_giveback_pct',round(v_giveback,2),'baseline_quality',v_baseline)
       where queue_key=v_queue_key and status='OPEN';
    else
      insert into public.alpha_autonomy_queue(queue_key,queue_type,ticker,priority,objective,recommended_next_step,evidence,status,updated_at,origin,generated_by_agent,human_approval_required,user_prompted,delivery_required,delivery_status,delivery_sla_minutes,detected_at)
      values(
        v_queue_key,'WINNER_PROTECTION',upper(replace(r.ticker,'-BE','')),v_priority,
        'Protect an earned winner without mechanically killing the right tail',
        case
          when v_state='WATCH_GIVEBACK' then 'ACTIVE WATCH: pre-open map must already contain sell-into-strength and sell-into-weakness paths. Do not let this become a passive HOLD.'
          when v_state='PROFIT_PROTECTION_REVIEW' then 'SAME-SESSION ACTION REVIEW: compare HOLD FULL vs staged trim using frozen evidence. If the only remaining condition is price, issue/refresh the broker GTT or alert level; do not leave this as an unanswered research item.'
          else 'URGENT ACTION REVIEW: profit retention has breached the urgent band. Use fresh broker truth and the prewritten fail-safe now. If residual is already near the minimum working weight, choose HOLD FULL or EXIT/ROTATE/CASH; do not create a decorative sub-6% tail.'
        end,
        jsonb_build_object(
          'state',v_state,'checked_at',now(),'snapshot_at',r.snapshot_at,'baseline_quality',v_baseline,'campaign_start',v_campaign_start,
          'avg_price',r.avg_price,'current_price',r.current_price,'peak_reference',v_peak,
          'peak_gain_pct',round(v_peak_gain,2),'current_gain_pct',round(v_current_gain,2),'drawdown_from_peak_pct',round(v_drawdown,2),'profit_giveback_pct',round(v_giveback,2),
          'sma10',v_sma10,'sma20',v_sma20,'sma50',v_sma50,'volume_ratio_20d',v_vol_ratio,'return_5d_pct',v_ret5,
          'below_sma10',case when v_sma10 is null then null else r.current_price<v_sma10 end,
          'below_sma20',case when v_sma20 is null then null else r.current_price<v_sma20 end,
          'principle','Peak/giveback escalates action review; no automatic sell from drawdown alone.',
          'state_changed',v_changed,
          'must_not_remain_unanswered',v_state in ('PROFIT_PROTECTION_REVIEW','URGENT_PROFIT_PROTECTION_REVIEW')
        ),'OPEN',now(),'SYSTEM','AUTONOMOUS_WORKER',true,false,true,'PENDING',case when v_state='URGENT_PROFIT_PROTECTION_REVIEW' then 15 else 30 end,now()
      )
      on conflict(queue_key) do update set
        ticker=excluded.ticker,priority=excluded.priority,objective=excluded.objective,recommended_next_step=excluded.recommended_next_step,
        evidence=excluded.evidence,status='OPEN',updated_at=now(),resolved_at=null,human_approval_required=true,
        delivery_required=true,delivery_status=case when public.alpha_autonomy_queue.delivery_status='DELIVERED' and not v_changed then public.alpha_autonomy_queue.delivery_status else 'PENDING' end,
        delivery_sla_minutes=excluded.delivery_sla_minutes,detected_at=case when v_changed then now() else coalesce(public.alpha_autonomy_queue.detected_at,now()) end,
        answered_at=case when v_changed then null else public.alpha_autonomy_queue.answered_at end,
        answer_conclusion=case when v_changed then null else public.alpha_autonomy_queue.answer_conclusion end,
        decision_impact=case when v_changed then null else public.alpha_autonomy_queue.decision_impact end;

      if v_state in ('PROFIT_PROTECTION_REVIEW','URGENT_PROFIT_PROTECTION_REVIEW') then
        insert into public.brain_events(event_type,entity_type,entity_key,payload)
        values('PROFIT_RETENTION_ACTION_REQUIRED','TICKER',upper(replace(r.ticker,'-BE','')),
          jsonb_build_object('state',v_state,'priority',v_priority,'current_price',r.current_price,'peak',v_peak,'peak_gain_pct',round(v_peak_gain,2),'current_gain_pct',round(v_current_gain,2),'profit_giveback_pct',round(v_giveback,2),'detected_at',now(),'delivery_sla_minutes',case when v_state='URGENT_PROFIT_PROTECTION_REVIEW' then 15 else 30 end));
      end if;
    end if;
  end loop;

  return jsonb_build_object('ok',true,'holdings_checked',v_count,'watch',v_watch,'review',v_review,'urgent',v_urgent,'run_at',now());
end;
$function$
