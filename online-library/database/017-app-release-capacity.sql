-- Apply after 014 (normally after 016). APK-only capacity upgrade; no release,
-- publication, update policy, preset/image limit or existing budget is changed.
-- 32 MiB APKs use at most 64 existing 512 KiB upload chunks.
-- Deployment must separately provide a large-file transport: SCF Web Function
-- responses are limited to 6 MB. Raising this validation cap alone is insufficient.
BEGIN;
-- The same private bucket stores the completed APK. Its old 4 MiB object cap
-- would otherwise reject the final write after all chunks passed validation.
-- Application routes retain their separate preset, image and avatar limits.
DO $$ BEGIN
 IF to_regclass('storage.buckets') IS NOT NULL THEN
  UPDATE storage.buckets SET file_size_limit=33554432 WHERE id='nikon-presets' AND public=false;
 END IF;
END; $$;
ALTER TABLE public.nikon_app_releases DROP CONSTRAINT IF EXISTS nikon_app_releases_byte_length_check;
ALTER TABLE public.nikon_app_releases ADD CONSTRAINT nikon_app_releases_byte_length_check CHECK(byte_length BETWEEN 1 AND 33554432);
-- Preserve legacy immutable .apk keys, while new uploads use opaque .bin keys.
-- The object bytes, checksum, Android manifest and signatures remain APK data.
-- 006's cross-column inline CHECK received PostgreSQL's table-level name.
ALTER TABLE public.nikon_app_releases DROP CONSTRAINT IF EXISTS nikon_app_releases_check;
ALTER TABLE public.nikon_app_releases DROP CONSTRAINT IF EXISTS nikon_app_releases_storage_path_check;
ALTER TABLE public.nikon_app_releases ADD CONSTRAINT nikon_app_releases_storage_path_check
 CHECK(storage_path IN ('app-releases/'||sha256||'.apk','app-releases/'||sha256||'.bin'));
ALTER TABLE public.nikon_app_uploads DROP CONSTRAINT IF EXISTS nikon_app_uploads_byte_length_check;
ALTER TABLE public.nikon_app_uploads ADD CONSTRAINT nikon_app_uploads_byte_length_check CHECK(byte_length BETWEEN 1 AND 33554432);
ALTER TABLE public.nikon_app_upload_chunks DROP CONSTRAINT IF EXISTS nikon_app_upload_chunks_chunk_index_check;
ALTER TABLE public.nikon_app_upload_chunks ADD CONSTRAINT nikon_app_upload_chunks_chunk_index_check CHECK(chunk_index BETWEEN 0 AND 63);

-- Both chunk and final-APK writes consume actual bytes, including retries.
-- Preserve 256 mutation requests/15 minutes and 64 MiB actual writes/day.
CREATE OR REPLACE FUNCTION public.nikon_app_upload_budget(p_actor text,p_bytes integer DEFAULT 0,p_count_request boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE v_now timestamptz:=clock_timestamp(); v_request_key text; v_day_key text; v_requests bigint; v_bytes bigint;
BEGIN
 IF NOT nikon_app_admin_allowed(p_actor) THEN RETURN jsonb_build_object('error','FORBIDDEN'); END IF;
 IF p_bytes IS NULL OR p_bytes NOT BETWEEN 0 AND 33554432 OR p_count_request IS NULL THEN RETURN jsonb_build_object('error','INVALID'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('nikon-app-upload-actual-budget',0));
 v_request_key:='upload:requests:'||floor(extract(epoch FROM v_now)/900)::bigint::text;
 v_day_key:='upload:bytes:'||to_char(v_now AT TIME ZONE 'UTC','YYYYMMDD');
 SELECT requests INTO v_requests FROM nikon_app_release_budgets WHERE budget_key=v_request_key;
 SELECT bytes INTO v_bytes FROM nikon_app_release_budgets WHERE budget_key=v_day_key;
 IF (p_count_request AND coalesce(v_requests,0)>=256) OR coalesce(v_bytes,0)+p_bytes>67108864 THEN RETURN jsonb_build_object('error','BUDGET'); END IF;
 IF p_count_request THEN
  INSERT INTO nikon_app_release_budgets(budget_key,requests,bytes,expires_at) VALUES(v_request_key,1,0,v_now+interval '30 minutes')
  ON CONFLICT(budget_key) DO UPDATE SET requests=nikon_app_release_budgets.requests+1;
 END IF;
 IF p_bytes>0 THEN
  INSERT INTO nikon_app_release_budgets(budget_key,requests,bytes,expires_at) VALUES(v_day_key,0,p_bytes,v_now+interval '2 days')
  ON CONFLICT(budget_key) DO UPDATE SET bytes=nikon_app_release_budgets.bytes+p_bytes;
 END IF;
 DELETE FROM nikon_app_release_budgets WHERE expires_at<v_now;
 RETURN jsonb_build_object('allowed',true);
END; $$;

-- Preserve 20 downloads/80 MiB per source/hour and 1000 downloads/2 GiB/day.
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
  v_caps:=ARRAY[20,1000]; v_bytecaps:=ARRAY[83886080,2147483648]; v_expiry:=ARRAY[v_now+interval '2 hours',v_now+interval '2 days'];
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

CREATE OR REPLACE FUNCTION public.nikon_app_upload_begin(p_actor text,p_size integer,p_channel text,p_notes text)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE v_row nikon_app_uploads;
BEGIN
 IF NOT nikon_app_admin_allowed(p_actor) THEN RETURN jsonb_build_object('error','FORBIDDEN'); END IF;
 IF p_size NOT BETWEEN 1 AND 33554432 OR p_channel NOT IN ('stable','beta') OR p_notes IS NULL OR length(p_notes) NOT BETWEEN 1 AND 6000 THEN RETURN jsonb_build_object('error','INVALID'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('nikon-app-upload',0));
 IF (SELECT count(*) FROM nikon_app_uploads WHERE status='uploading' AND expires_at>now())>=4
 OR (SELECT coalesce(sum(byte_length),0) FROM nikon_app_uploads WHERE created_at>=date_trunc('day',now()))+p_size>67108864 THEN RETURN jsonb_build_object('error','BUDGET'); END IF;
 INSERT INTO nikon_app_uploads(actor,byte_length,channel,notes) VALUES(p_actor,p_size,p_channel,p_notes) RETURNING * INTO v_row;
 RETURN jsonb_build_object('uploadId',v_row.id,'expiresAt',v_row.expires_at);
END; $$;

CREATE OR REPLACE FUNCTION public.nikon_app_upload_check(p_actor text,p_id uuid,p_index integer,p_size integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE v_row nikon_app_uploads;
BEGIN
 IF NOT nikon_app_admin_allowed(p_actor) THEN RETURN jsonb_build_object('error','FORBIDDEN'); END IF;
 SELECT * INTO v_row FROM nikon_app_uploads WHERE id=p_id AND actor=p_actor FOR UPDATE;
 IF NOT FOUND OR v_row.status<>'uploading' OR v_row.expires_at<=now() THEN RETURN jsonb_build_object('error','UPLOAD_EXPIRED'); END IF;
 IF p_index<0 OR p_index>63 OR p_index*524288>=v_row.byte_length OR p_size<>least(524288,v_row.byte_length-p_index*524288) THEN RETURN jsonb_build_object('error','INVALID'); END IF;
 RETURN jsonb_build_object('allowed',true);
END; $$;

COMMIT;
