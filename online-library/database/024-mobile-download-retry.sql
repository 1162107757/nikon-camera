-- Preserve historical usage and caps; share the existing lock during rollout.
BEGIN;
CREATE OR REPLACE FUNCTION public.nikon_mobile_release_download_budget(p_key text,p_sha256 text,p_bytes integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE
 v_now timestamptz:=clock_timestamp();v_keys text[];v_caps bigint[]:=ARRAY[20,1000];
 v_bytecaps bigint[]:=ARRAY[536870912,5368709120];v_expiry timestamptz[];
 v_lease_key text;v_cost bigint:=p_bytes;v_row nikon_mobile_release_budgets;
 v_lease nikon_mobile_release_budgets;v_retry integer;i integer;
BEGIN
 IF p_key IS NULL OR p_key !~ '^[a-f0-9]{64}$' OR p_sha256 IS NULL OR p_sha256 !~ '^[a-f0-9]{64}$'
  OR p_bytes IS NULL OR p_bytes NOT BETWEEN 0 AND 134217728 THEN
  RETURN jsonb_build_object('error','INVALID');
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('nikon-mobile-public-budget',0));
 v_keys:=ARRAY['file:ip:'||p_key||':'||to_char(v_now,'YYYYMMDDHH24'),
               'file:global:'||to_char(v_now AT TIME ZONE 'UTC','YYYYMMDD')];
 v_expiry:=ARRAY[v_now+interval '2 hours',v_now+interval '2 days'];
 v_lease_key:='file:lease:'||p_key||':'||p_sha256;
 SELECT * INTO v_lease FROM nikon_mobile_release_budgets WHERE budget_key=v_lease_key;
 IF FOUND AND v_lease.expires_at>v_now AND v_lease.bytes=p_bytes THEN v_cost:=0;END IF;
 FOR i IN 1..2 LOOP
  SELECT * INTO v_row FROM nikon_mobile_release_budgets WHERE budget_key=v_keys[i];
  IF FOUND AND(v_row.requests>=v_caps[i] OR v_cost>0 AND v_row.bytes+v_cost>v_bytecaps[i]) THEN
   v_retry:=greatest(1,ceil(extract(epoch FROM
    CASE WHEN i=1 THEN date_trunc('hour',v_now)+interval '1 hour'
    ELSE (date_trunc('day',v_now AT TIME ZONE 'UTC')+interval '1 day') AT TIME ZONE 'UTC' END-v_now))::integer);
   RETURN jsonb_build_object('error','BUDGET','scope',CASE WHEN i=1 THEN 'ip' ELSE 'global' END,'retryAfterSeconds',v_retry);
  END IF;
 END LOOP;
 FOR i IN 1..2 LOOP
  INSERT INTO nikon_mobile_release_budgets VALUES(v_keys[i],1,v_cost,v_expiry[i])
  ON CONFLICT(budget_key) DO UPDATE SET requests=nikon_mobile_release_budgets.requests+1,bytes=nikon_mobile_release_budgets.bytes+v_cost;
 END LOOP;
 -- Fixed ten-minute window: retries still count as requests and cannot extend it.
 IF p_bytes>0 AND v_cost>0 THEN
  INSERT INTO nikon_mobile_release_budgets VALUES(v_lease_key,1,p_bytes,v_now+interval '10 minutes')
  ON CONFLICT(budget_key) DO UPDATE SET requests=1,bytes=p_bytes,expires_at=excluded.expires_at;
 END IF;
 DELETE FROM nikon_mobile_release_budgets WHERE expires_at<v_now;
 RETURN jsonb_build_object('allowed',true,'chargedBytes',v_cost);
END; $$;
REVOKE ALL ON FUNCTION public.nikon_mobile_release_download_budget(text,text,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.nikon_mobile_release_download_budget(text,text,integer) TO service_role;
COMMIT;
