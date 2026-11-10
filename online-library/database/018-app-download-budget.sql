-- Larger signed APKs: retain request/global caps and historical usage.
BEGIN;
CREATE OR REPLACE FUNCTION public.nikon_release_budget_atomic(p_key text,p_kind text,p_bytes integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE v_now timestamptz:=clock_timestamp(); v_keys text[]; v_caps bigint[]; v_bytecaps bigint[]; v_expiry timestamptz[]; v_row nikon_app_release_budgets; i integer;
BEGIN
 IF p_key !~ '^[a-f0-9]{64}$' OR p_kind NOT IN ('metadata','download') OR p_bytes<0 OR p_bytes>33554432 THEN RETURN jsonb_build_object('error','INVALID'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('nikon-app-release-budget',0));
 IF p_kind='metadata' THEN
  v_keys:=ARRAY['meta:ip:'||p_key||':'||to_char(v_now,'YYYYMMDDHH24MI'),'meta:global:'||to_char(v_now,'YYYYMMDDHH24MI')];
  v_caps:=ARRAY[120,1200]; v_bytecaps:=ARRAY[0,0]; v_expiry:=ARRAY[v_now+interval '2 minutes',v_now+interval '2 minutes'];
 ELSE
  v_keys:=ARRAY['file:ip:'||p_key||':'||to_char(v_now,'YYYYMMDDHH24'),'file:global:'||to_char(v_now,'YYYYMMDD')];
  v_caps:=ARRAY[20,1000]; v_bytecaps:=ARRAY[268435456,2147483648]; v_expiry:=ARRAY[v_now+interval '2 hours',v_now+interval '2 days'];
 END IF;
 FOR i IN 1..2 LOOP
  SELECT * INTO v_row FROM nikon_app_release_budgets WHERE budget_key=v_keys[i];
  IF FOUND AND (v_row.requests>=v_caps[i] OR (v_bytecaps[i]>0 AND v_row.bytes+p_bytes>v_bytecaps[i])) THEN RETURN jsonb_build_object('error','BUDGET'); END IF;
 END LOOP;
 FOR i IN 1..2 LOOP
  INSERT INTO nikon_app_release_budgets(budget_key,requests,bytes,expires_at) VALUES(v_keys[i],1,p_bytes,v_expiry[i])
  ON CONFLICT(budget_key) DO UPDATE SET requests=nikon_app_release_budgets.requests+1,bytes=nikon_app_release_budgets.bytes+p_bytes;
 END LOOP;
 DELETE FROM nikon_app_release_budgets WHERE expires_at<v_now;
 RETURN jsonb_build_object('allowed',true);
END; $$;
REVOKE ALL ON FUNCTION public.nikon_release_budget_atomic(text,text,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.nikon_release_budget_atomic(text,text,integer) TO service_role;
COMMIT;
