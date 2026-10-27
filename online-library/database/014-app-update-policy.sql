-- Apply after 006 (normally after 013). Existing releases remain optional.
-- This changes policy only: it does not publish an APK or enable forced updates.
BEGIN;
ALTER TABLE public.nikon_app_releases ADD COLUMN IF NOT EXISTS mandatory boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.nikon_app_release_policy(p_actor text,p_id uuid,p_revision integer,p_mandatory boolean,p_confirmation text)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE v_row nikon_app_releases; v_previous boolean; v_confirmation text;
BEGIN
 IF NOT nikon_app_admin_allowed(p_actor) THEN RETURN jsonb_build_object('error','FORBIDDEN'); END IF;
 IF p_mandatory IS NULL THEN RETURN jsonb_build_object('error','INVALID'); END IF;
 -- Share the lifecycle lock with publish/withdraw, then compare the row revision.
 PERFORM pg_advisory_xact_lock(hashtextextended('nikon-app-release-publish',0));
 SELECT * INTO v_row FROM nikon_app_releases WHERE id=p_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('error','NOT_FOUND'); END IF;
 IF p_revision IS DISTINCT FROM v_row.revision THEN RETURN jsonb_build_object('error','CONFLICT'); END IF;
 IF v_row.status NOT IN ('draft','published') THEN RETURN jsonb_build_object('error','CONFLICT'); END IF;
 v_confirmation:=(CASE WHEN p_mandatory THEN 'REQUIRE ' ELSE 'OPTIONAL ' END)||v_row.version_code::text||' '||v_row.sha256;
 IF p_confirmation IS DISTINCT FROM v_confirmation THEN RETURN jsonb_build_object('error','CONFIRMATION'); END IF;
 IF v_row.mandatory=p_mandatory THEN RETURN to_jsonb(v_row); END IF;
 v_previous:=v_row.mandatory;
 UPDATE nikon_app_releases SET mandatory=p_mandatory,revision=revision+1 WHERE id=p_id RETURNING * INTO v_row;
 INSERT INTO nikon_app_release_audit(release_id,actor,action,details)
 VALUES(p_id,p_actor,'policy',jsonb_build_object('versionCode',v_row.version_code,'sha256',v_row.sha256,
   'channel',v_row.channel,'revision',v_row.revision,'previousMandatory',v_previous,'mandatory',v_row.mandatory));
 RETURN to_jsonb(v_row);
END; $$;
REVOKE ALL ON FUNCTION public.nikon_app_release_policy(text,uuid,integer,boolean,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.nikon_app_release_policy(text,uuid,integer,boolean,text) TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
