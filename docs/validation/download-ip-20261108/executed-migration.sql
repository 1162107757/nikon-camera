DO $migration$ BEGIN PERFORM pg_advisory_xact_lock(hashtextextended('nikon-app-release-budget',0));
EXECUTE $ddl0$CREATE OR REPLACE FUNCTION public.nikon_release_budget_atomic(p_key text,p_kind text,p_bytes integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE v_now timestamptz:=clock_timestamp(); v_key text; v_cap bigint; v_bytecap bigint; v_expiry timestamptz; v_row nikon_app_release_budgets;
BEGIN
 IF p_key IS NULL OR p_key !~ '^[a-f0-9]{64}$' OR p_kind IS NULL OR p_kind NOT IN ('metadata','download') OR p_bytes IS NULL OR p_bytes<0 OR p_bytes>33554432 THEN RETURN jsonb_build_object('error','INVALID'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('nikon-app-release-budget',0));
 IF p_kind='metadata' THEN
  v_key:='meta:ip:'||p_key||':'||to_char(v_now,'YYYYMMDDHH24MI'); v_cap:=120; v_bytecap:=0; v_expiry:=v_now+interval '2 minutes';
 ELSE
  -- Compatibility for an older function instance during deployment.
  v_key:='file:ip:'||p_key||':'||to_char(v_now,'YYYYMMDDHH24'); v_cap:=60; v_bytecap:=268435456; v_expiry:=v_now+interval '2 hours';
 END IF;
 SELECT * INTO v_row FROM nikon_app_release_budgets WHERE budget_key=v_key;
 IF FOUND AND (v_row.requests>=v_cap OR (v_bytecap>0 AND p_bytes>0 AND v_row.bytes+p_bytes>v_bytecap)) THEN RETURN jsonb_build_object('error','BUDGET'); END IF;
 INSERT INTO nikon_app_release_budgets(budget_key,requests,bytes,expires_at) VALUES(v_key,1,p_bytes,v_expiry)
 ON CONFLICT(budget_key) DO UPDATE SET requests=nikon_app_release_budgets.requests+1,bytes=nikon_app_release_budgets.bytes+p_bytes;
 DELETE FROM nikon_app_release_budgets WHERE expires_at<v_now;
 RETURN jsonb_build_object('allowed',true);
END; $$;$ddl0$; EXECUTE 'REVOKE ALL ON FUNCTION public.nikon_release_budget_atomic(text,text,integer) FROM PUBLIC,anon,authenticated'; EXECUTE 'GRANT EXECUTE ON FUNCTION public.nikon_release_budget_atomic(text,text,integer) TO service_role';
EXECUTE $ddl1$CREATE OR REPLACE FUNCTION public.nikon_release_download_budget(p_key text,p_sha256 text,p_bytes integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE v_now timestamptz:=clock_timestamp(); v_key text; v_lease_key text; v_cost bigint:=p_bytes; v_row nikon_app_release_budgets; v_lease nikon_app_release_budgets; v_retry integer;
BEGIN
 IF p_key IS NULL OR p_key !~ '^[a-f0-9]{64}$' OR p_sha256 IS NULL OR p_sha256 !~ '^[a-f0-9]{64}$' OR p_bytes IS NULL OR p_bytes<0 OR p_bytes>33554432 THEN RETURN jsonb_build_object('error','INVALID'); END IF;
 -- Same lock as the compatibility RPC, so old/new instances cannot race quota updates.
 PERFORM pg_advisory_xact_lock(hashtextextended('nikon-app-release-budget',0));
 v_key:='file:ip:'||p_key||':'||to_char(v_now,'YYYYMMDDHH24');
 v_lease_key:='file:lease:'||p_key||':'||p_sha256;
 SELECT * INTO v_lease FROM nikon_app_release_budgets WHERE budget_key=v_lease_key;
 IF FOUND AND v_lease.expires_at>v_now AND v_lease.bytes=p_bytes THEN v_cost:=0; END IF;
 SELECT * INTO v_row FROM nikon_app_release_budgets WHERE budget_key=v_key;
 v_retry:=greatest(1,ceil(extract(epoch FROM date_trunc('hour',v_now)+interval '1 hour'-v_now))::integer);
 IF FOUND AND (v_row.requests>=60 OR (v_cost>0 AND v_row.bytes+v_cost>268435456)) THEN
  RETURN jsonb_build_object('error','IP_BUDGET','scope','ip','retryAfterSeconds',v_retry);
 END IF;
 INSERT INTO nikon_app_release_budgets(budget_key,requests,bytes,expires_at) VALUES(v_key,1,v_cost,v_now+interval '2 hours')
 ON CONFLICT(budget_key) DO UPDATE SET requests=nikon_app_release_budgets.requests+1,bytes=nikon_app_release_budgets.bytes+v_cost;
 -- A fixed ten-minute retry window, not extended by retries. Every request still counts.
 IF p_bytes>0 AND v_cost>0 THEN
  INSERT INTO nikon_app_release_budgets(budget_key,requests,bytes,expires_at) VALUES(v_lease_key,1,p_bytes,v_now+interval '10 minutes')
  ON CONFLICT(budget_key) DO UPDATE SET requests=1,bytes=p_bytes,expires_at=excluded.expires_at;
 END IF;
 DELETE FROM nikon_app_release_budgets WHERE expires_at<v_now;
 RETURN jsonb_build_object('allowed',true,'scope','ip','chargedBytes',v_cost);
END; $$;$ddl1$; EXECUTE 'REVOKE ALL ON FUNCTION public.nikon_release_download_budget(text,text,integer) FROM PUBLIC,anon,authenticated'; EXECUTE 'GRANT EXECUTE ON FUNCTION public.nikon_release_download_budget(text,text,integer) TO service_role';
END; $migration$;