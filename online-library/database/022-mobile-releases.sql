-- Apply after 021. Independent unsigned-iOS / cc.huevia.next distribution.
-- Does not change legacy Android release tables, size limits, signers or publication history.
BEGIN;
CREATE TABLE IF NOT EXISTS public.nikon_mobile_releases (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 platform text NOT NULL CHECK(platform IN ('ios','android')),
 package_name text NOT NULL CHECK(package_name='cc.huevia.next'),
 version_code integer NOT NULL CHECK(version_code BETWEEN 1 AND 999999999),
 sha256 text NOT NULL CHECK(sha256 ~ '^[a-f0-9]{64}$'),
 byte_length integer NOT NULL CHECK(byte_length BETWEEN 1024 AND 134217728),
 metadata jsonb NOT NULL CHECK(jsonb_typeof(metadata)='object'),
 storage_path text NOT NULL,
 channel text NOT NULL CHECK(channel IN ('stable','beta')),
 notes text NOT NULL CHECK(length(notes) BETWEEN 1 AND 6000),
 status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','published','withdrawn')),
 revision integer NOT NULL DEFAULT 1 CHECK(revision>0),
 created_at timestamptz NOT NULL DEFAULT now(), published_at timestamptz, withdrawn_at timestamptz,
 UNIQUE(platform,package_name,version_code), UNIQUE(platform,sha256),
 CHECK(storage_path='mobile-releases/'||platform||'/'||sha256||'.bin'),
 CHECK((metadata->>'sha256'=sha256 AND (metadata->>'byteLength')::integer=byte_length AND (metadata->>'versionCode')::integer=version_code) IS TRUE),
 CHECK(((platform='ios' AND metadata->>'bundleId'=package_name AND metadata->>'distribution'='unsigned-ipa' AND metadata->>'platform'='ios')
  OR (platform='android' AND metadata->>'packageName'=package_name AND metadata->>'signerSha256'='76398947a8b493df81ebf2e90ad7b62e3eefee5fcf6cf865feaaa9bef8127b75' AND jsonb_typeof(metadata->'abis')='array' AND jsonb_array_length(metadata->'abis')>0)) IS TRUE)
);
CREATE INDEX IF NOT EXISTS nikon_mobile_release_latest ON public.nikon_mobile_releases(platform,package_name,channel,version_code DESC) WHERE status IN ('published','withdrawn');
CREATE TABLE IF NOT EXISTS public.nikon_mobile_uploads (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),actor text NOT NULL CHECK(length(actor) BETWEEN 1 AND 64),
 platform text NOT NULL CHECK(platform IN ('ios','android')),byte_length integer NOT NULL CHECK(byte_length BETWEEN 1024 AND 134217728),
 channel text NOT NULL CHECK(channel IN ('stable','beta')),notes text NOT NULL CHECK(length(notes) BETWEEN 1 AND 6000),
 status text NOT NULL DEFAULT 'uploading' CHECK(status IN ('uploading','processing','complete','failed')),
 created_at timestamptz NOT NULL DEFAULT now(),expires_at timestamptz NOT NULL DEFAULT now()+interval '1 hour'
);
CREATE TABLE IF NOT EXISTS public.nikon_mobile_upload_chunks (
 upload_id uuid NOT NULL REFERENCES public.nikon_mobile_uploads(id),chunk_index integer NOT NULL CHECK(chunk_index BETWEEN 0 AND 255),
 byte_length integer NOT NULL CHECK(byte_length BETWEEN 1 AND 524288),sha256 text NOT NULL CHECK(sha256 ~ '^[a-f0-9]{64}$'),
 storage_path text NOT NULL,ready boolean NOT NULL DEFAULT false,PRIMARY KEY(upload_id,chunk_index),
 CHECK(storage_path='mobile-upload/'||upload_id::text||'/'||chunk_index::text||'-'||sha256||'.part')
);
CREATE TABLE IF NOT EXISTS public.nikon_mobile_release_audit (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,release_id uuid NOT NULL REFERENCES public.nikon_mobile_releases(id),
 actor text NOT NULL CHECK(length(actor) BETWEEN 1 AND 64),action text NOT NULL CHECK(action IN ('upload_verified','publish','withdraw')),
 details jsonb NOT NULL DEFAULT '{}',created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.nikon_mobile_release_budgets (
 budget_key text PRIMARY KEY,requests bigint NOT NULL DEFAULT 0,bytes bigint NOT NULL DEFAULT 0,expires_at timestamptz NOT NULL
);
ALTER TABLE public.nikon_mobile_releases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nikon_mobile_uploads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nikon_mobile_upload_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nikon_mobile_release_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nikon_mobile_release_budgets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.nikon_mobile_releases,public.nikon_mobile_uploads,public.nikon_mobile_upload_chunks,public.nikon_mobile_release_audit,public.nikon_mobile_release_budgets FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE ON public.nikon_mobile_releases,public.nikon_mobile_uploads,public.nikon_mobile_upload_chunks TO service_role;
GRANT SELECT,INSERT ON public.nikon_mobile_release_audit TO service_role;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.nikon_mobile_release_budgets TO service_role;
GRANT USAGE,SELECT ON SEQUENCE public.nikon_mobile_release_audit_id_seq TO service_role;

CREATE OR REPLACE FUNCTION public.nikon_mobile_release_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF (NEW.id,NEW.platform,NEW.package_name,NEW.version_code,NEW.sha256,NEW.byte_length,NEW.metadata,NEW.storage_path,NEW.channel,NEW.notes,NEW.created_at)
 IS DISTINCT FROM (OLD.id,OLD.platform,OLD.package_name,OLD.version_code,OLD.sha256,OLD.byte_length,OLD.metadata,OLD.storage_path,OLD.channel,OLD.notes,OLD.created_at)
 OR OLD.status='withdrawn' AND NEW.status<>'withdrawn' OR OLD.status='published' AND NEW.status NOT IN ('published','withdrawn')
 THEN RAISE EXCEPTION 'MOBILE_RELEASE_IMMUTABLE'; END IF;
 RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS nikon_mobile_release_immutable ON public.nikon_mobile_releases;
CREATE TRIGGER nikon_mobile_release_immutable BEFORE UPDATE ON public.nikon_mobile_releases FOR EACH ROW EXECUTE FUNCTION public.nikon_mobile_release_immutable();

CREATE OR REPLACE FUNCTION public.nikon_mobile_release_manage(p_actor text,p_action text,p_body jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE task nikon_mobile_uploads;item nikon_mobile_releases;chunk nikon_mobile_upload_chunks;
 n integer;idx integer;amount integer;expected integer;key_request text;key_bytes text;v_now timestamptz:=clock_timestamp();platform_name text;
BEGIN
 IF NOT nikon_app_admin_allowed(p_actor) THEN RETURN jsonb_build_object('error','FORBIDDEN'); END IF;
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' THEN RETURN jsonb_build_object('error','INVALID'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('nikon-mobile-release',0));
 IF p_action='budget' THEN
  amount:=(p_body->>'bytes')::integer;
  IF amount IS NULL OR amount NOT BETWEEN 0 AND 134217728 OR jsonb_typeof(p_body->'countRequest')<>'boolean' THEN RETURN jsonb_build_object('error','INVALID'); END IF;
  key_request:='upload:requests:'||floor(extract(epoch FROM v_now)/900)::bigint::text;
  key_bytes:='upload:bytes:'||to_char(v_now AT TIME ZONE 'UTC','YYYYMMDD');
  IF ((p_body->>'countRequest')::boolean AND coalesce((SELECT requests FROM nikon_mobile_release_budgets WHERE budget_key=key_request),0)>=1024)
   OR coalesce((SELECT bytes FROM nikon_mobile_release_budgets WHERE budget_key=key_bytes),0)+amount>1073741824 THEN RETURN jsonb_build_object('error','BUDGET'); END IF;
  IF (p_body->>'countRequest')::boolean THEN INSERT INTO nikon_mobile_release_budgets VALUES(key_request,1,0,v_now+interval '30 minutes') ON CONFLICT(budget_key) DO UPDATE SET requests=nikon_mobile_release_budgets.requests+1; END IF;
  IF amount>0 THEN INSERT INTO nikon_mobile_release_budgets VALUES(key_bytes,0,amount,v_now+interval '2 days') ON CONFLICT(budget_key) DO UPDATE SET bytes=nikon_mobile_release_budgets.bytes+amount; END IF;
  DELETE FROM nikon_mobile_release_budgets WHERE expires_at<v_now;
  RETURN jsonb_build_object('allowed',true);
 END IF;
 platform_name:=p_body->>'platform';IF platform_name NOT IN ('ios','android') OR platform_name IS NULL THEN RETURN jsonb_build_object('error','INVALID'); END IF;
 IF p_action='begin' THEN
  amount:=(p_body->>'byteLength')::integer;
  IF amount IS NULL OR amount NOT BETWEEN 1024 AND 134217728 OR p_body->>'channel' NOT IN ('stable','beta') OR p_body->>'notes' IS NULL OR length(p_body->>'notes') NOT BETWEEN 1 AND 6000 THEN RETURN jsonb_build_object('error','INVALID'); END IF;
  IF (SELECT count(*) FROM nikon_mobile_uploads WHERE status IN ('uploading','processing') AND expires_at>v_now)>=4
   OR (SELECT count(*) FROM nikon_mobile_uploads WHERE actor=p_actor AND status IN ('uploading','processing') AND expires_at>v_now)>=2
   OR (SELECT coalesce(sum(byte_length),0) FROM nikon_mobile_uploads WHERE created_at>=date_trunc('day',v_now))+amount>1073741824 THEN RETURN jsonb_build_object('error','BUDGET'); END IF;
  INSERT INTO nikon_mobile_uploads(actor,platform,byte_length,channel,notes) VALUES(p_actor,platform_name,amount,p_body->>'channel',p_body->>'notes') RETURNING * INTO task;
  RETURN jsonb_build_object('uploadId',task.id,'expiresAt',task.expires_at);
 END IF;
 IF p_action IN ('reserve','chunk','claim','create','fail') THEN
  SELECT * INTO task FROM nikon_mobile_uploads WHERE id=(p_body->>'id')::uuid FOR UPDATE;
  IF NOT FOUND OR task.actor<>p_actor OR task.platform<>platform_name THEN RETURN jsonb_build_object('error','NOT_FOUND'); END IF;
  IF p_action='fail' THEN IF task.status='processing' THEN UPDATE nikon_mobile_uploads SET status='failed' WHERE id=task.id; END IF;RETURN jsonb_build_object('failed',true);END IF;
  IF task.expires_at<=v_now OR task.status NOT IN ('uploading','processing') THEN RETURN jsonb_build_object('error','EXPIRED'); END IF;
  IF p_action IN ('reserve','chunk') THEN
   idx:=(p_body->>'index')::integer;amount:=(p_body->>'bytes')::integer;expected:=least(524288,task.byte_length-idx*524288);
   IF task.status<>'uploading' OR idx IS NULL OR idx NOT BETWEEN 0 AND 255 OR expected<1 OR amount IS NULL OR amount<>expected OR p_body->>'sha256' !~ '^[a-f0-9]{64}$' OR p_body->>'path'<>'mobile-upload/'||task.id::text||'/'||idx::text||'-'||(p_body->>'sha256')||'.part' THEN RETURN jsonb_build_object('error','INVALID'); END IF;
   SELECT * INTO chunk FROM nikon_mobile_upload_chunks WHERE upload_id=task.id AND chunk_index=idx FOR UPDATE;
   IF FOUND AND (chunk.byte_length<>amount OR chunk.sha256<>p_body->>'sha256' OR chunk.storage_path<>p_body->>'path') THEN RETURN jsonb_build_object('error','CONFLICT'); END IF;
   INSERT INTO nikon_mobile_upload_chunks(upload_id,chunk_index,byte_length,sha256,storage_path,ready) VALUES(task.id,idx,amount,p_body->>'sha256',p_body->>'path',p_action='chunk')
    ON CONFLICT(upload_id,chunk_index) DO UPDATE SET ready=nikon_mobile_upload_chunks.ready OR EXCLUDED.ready;
   RETURN jsonb_build_object('accepted',true);
  END IF;
  IF p_action='claim' THEN
   IF task.status<>'uploading' THEN RETURN jsonb_build_object('error','CONFLICT'); END IF;
   IF EXISTS(SELECT 1 FROM nikon_mobile_uploads WHERE status='processing' AND expires_at>v_now) THEN RETURN jsonb_build_object('error','BUDGET'); END IF;
   n:=(task.byte_length+524287)/524288;
   IF (SELECT count(*) FROM nikon_mobile_upload_chunks WHERE upload_id=task.id AND ready)<>n OR (SELECT coalesce(sum(byte_length),0) FROM nikon_mobile_upload_chunks WHERE upload_id=task.id AND ready)<>task.byte_length THEN RETURN jsonb_build_object('error','INCOMPLETE'); END IF;
   UPDATE nikon_mobile_uploads SET status='processing' WHERE id=task.id;
   RETURN jsonb_build_object('byteLength',task.byte_length,'chunks',(SELECT jsonb_agg(jsonb_build_object('path',storage_path,'size',byte_length,'sha256',sha256) ORDER BY chunk_index) FROM nikon_mobile_upload_chunks WHERE upload_id=task.id));
  END IF;
  IF p_action='create' THEN
   IF task.status<>'processing' OR jsonb_typeof(p_body->'metadata')<>'object' OR (p_body->'metadata'->>'byteLength')::integer<>task.byte_length THEN RETURN jsonb_build_object('error','INVALID'); END IF;
   INSERT INTO nikon_mobile_releases(platform,package_name,version_code,sha256,byte_length,metadata,storage_path,channel,notes)
    VALUES(platform_name,'cc.huevia.next',(p_body->'metadata'->>'versionCode')::integer,p_body->'metadata'->>'sha256',task.byte_length,p_body->'metadata',p_body->>'path',task.channel,task.notes) RETURNING * INTO item;
   UPDATE nikon_mobile_uploads SET status='complete' WHERE id=task.id;
   INSERT INTO nikon_mobile_release_audit(release_id,actor,action,details) VALUES(item.id,p_actor,'upload_verified',jsonb_build_object('sha256',item.sha256,'byteLength',item.byte_length));
   RETURN to_jsonb(item);
  END IF;
 END IF;
 IF p_action IN ('publish','withdraw') THEN
  SELECT * INTO item FROM nikon_mobile_releases WHERE id=(p_body->>'id')::uuid FOR UPDATE;
  IF NOT FOUND OR item.platform<>platform_name THEN RETURN jsonb_build_object('error','NOT_FOUND'); END IF;
  IF (p_body->>'expectedRevision')::integer IS DISTINCT FROM item.revision THEN RETURN jsonb_build_object('error','CONFLICT'); END IF;
  IF p_action='publish' THEN
   IF item.status<>'draft' THEN RETURN jsonb_build_object('error','CONFLICT'); END IF;
   IF p_body->>'confirmation' IS DISTINCT FROM 'PUBLISH '||item.version_code::text||' '||item.sha256 THEN RETURN jsonb_build_object('error','CONFIRMATION'); END IF;
   IF EXISTS(SELECT 1 FROM nikon_mobile_releases WHERE platform=item.platform AND package_name=item.package_name AND channel=item.channel AND status IN ('published','withdrawn') AND version_code>item.version_code) THEN RETURN jsonb_build_object('error','DOWNGRADE'); END IF;
   UPDATE nikon_mobile_releases SET status='published',published_at=v_now,revision=revision+1 WHERE id=item.id RETURNING * INTO item;
  ELSE
   IF item.status<>'published' THEN RETURN jsonb_build_object('error','CONFLICT'); END IF;
   IF p_body->>'confirmation' IS DISTINCT FROM 'WITHDRAW '||item.version_code::text||' '||item.sha256 THEN RETURN jsonb_build_object('error','CONFIRMATION'); END IF;
   UPDATE nikon_mobile_releases SET status='withdrawn',withdrawn_at=v_now,revision=revision+1 WHERE id=item.id RETURNING * INTO item;
  END IF;
  INSERT INTO nikon_mobile_release_audit(release_id,actor,action,details) VALUES(item.id,p_actor,p_action,jsonb_build_object('sha256',item.sha256,'versionCode',item.version_code));
  RETURN to_jsonb(item);
 END IF;
 RETURN jsonb_build_object('error','INVALID');
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('error','DUPLICATE');
 WHEN invalid_text_representation OR check_violation OR not_null_violation OR numeric_value_out_of_range THEN RETURN jsonb_build_object('error','INVALID');
END; $$;

CREATE OR REPLACE FUNCTION public.nikon_mobile_release_budget(p_key text,p_kind text,p_bytes integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE v_now timestamptz:=clock_timestamp();keys text[];request_caps bigint[];byte_caps bigint[];expiry timestamptz[];row nikon_mobile_release_budgets;i integer;
BEGIN
 IF p_key IS NULL OR p_key !~ '^[a-f0-9]{64}$' OR p_kind IS NULL OR p_kind NOT IN ('metadata','download') OR p_bytes IS NULL OR p_bytes NOT BETWEEN 0 AND 134217728 THEN RETURN jsonb_build_object('error','INVALID'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('nikon-mobile-public-budget',0));
 IF p_kind='metadata' THEN
  keys:=ARRAY['meta:ip:'||p_key||':'||to_char(v_now,'YYYYMMDDHH24MI'),'meta:global:'||to_char(v_now,'YYYYMMDDHH24MI')];request_caps:=ARRAY[120,1200];byte_caps:=ARRAY[0,0];expiry:=ARRAY[v_now+interval '2 minutes',v_now+interval '2 minutes'];
 ELSE
  keys:=ARRAY['file:ip:'||p_key||':'||to_char(v_now,'YYYYMMDDHH24'),'file:global:'||to_char(v_now AT TIME ZONE 'UTC','YYYYMMDD')];request_caps:=ARRAY[20,1000];byte_caps:=ARRAY[536870912,5368709120];expiry:=ARRAY[v_now+interval '2 hours',v_now+interval '2 days'];
 END IF;
 FOR i IN 1..2 LOOP SELECT * INTO row FROM nikon_mobile_release_budgets WHERE budget_key=keys[i];IF FOUND AND(row.requests>=request_caps[i] OR byte_caps[i]>0 AND row.bytes+p_bytes>byte_caps[i]) THEN RETURN jsonb_build_object('error','BUDGET');END IF;END LOOP;
 FOR i IN 1..2 LOOP INSERT INTO nikon_mobile_release_budgets VALUES(keys[i],1,p_bytes,expiry[i]) ON CONFLICT(budget_key) DO UPDATE SET requests=nikon_mobile_release_budgets.requests+1,bytes=nikon_mobile_release_budgets.bytes+p_bytes;END LOOP;
 DELETE FROM nikon_mobile_release_budgets WHERE expires_at<v_now;
 RETURN jsonb_build_object('allowed',true);
END; $$;
REVOKE ALL ON FUNCTION public.nikon_mobile_release_manage(text,text,jsonb),public.nikon_mobile_release_budget(text,text,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.nikon_mobile_release_manage(text,text,jsonb),public.nikon_mobile_release_budget(text,text,integer) TO service_role;
COMMIT;
