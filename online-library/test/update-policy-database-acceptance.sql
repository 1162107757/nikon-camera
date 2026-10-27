-- Local PostgreSQL only. All policy fixture changes roll back.
BEGIN;
INSERT INTO nikon_admins(username,password_hash,disabled) VALUES
 ('policy-admin','synthetic-unused-hash',false),('policy-disabled','synthetic-unused-hash',true);
INSERT INTO nikon_app_releases(package_name,version_name,version_code,min_sdk,byte_length,sha256,signer_sha256,storage_path,channel,notes)
 VALUES('cc.huevia','policy-fixture',101,26,4,repeat('e',64),'04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31','app-releases/'||repeat('e',64)||'.apk','beta','Synthetic policy release');
SET LOCAL ROLE service_role;
DO $$
DECLARE r jsonb; v_id uuid; v_revision integer; v_count integer;
BEGIN
 IF has_function_privilege('anon','public.nikon_app_release_policy(text,uuid,integer,boolean,text)','EXECUTE')
  OR has_function_privilege('authenticated','public.nikon_app_release_policy(text,uuid,integer,boolean,text)','EXECUTE')
  OR has_table_privilege('anon','public.nikon_app_releases','UPDATE') THEN RAISE EXCEPTION 'anonymous policy mutation permitted'; END IF;
 SELECT id INTO v_id FROM nikon_app_releases WHERE version_code=101;
 IF nikon_app_release_policy('missing',v_id,1,true,'REQUIRE 101 '||repeat('e',64))->>'error'<>'FORBIDDEN'
  OR nikon_app_release_policy('policy-disabled',v_id,1,true,'REQUIRE 101 '||repeat('e',64))->>'error'<>'FORBIDDEN' THEN RAISE EXCEPTION 'invalid administrator changed policy'; END IF;
 IF nikon_app_release_policy('policy-admin',v_id,1,null,'')->>'error'<>'INVALID' THEN RAISE EXCEPTION 'null policy permitted'; END IF;
 IF nikon_app_release_policy('policy-admin',v_id,2,true,'REQUIRE 101 '||repeat('e',64))->>'error'<>'CONFLICT' THEN RAISE EXCEPTION 'stale policy write permitted'; END IF;
 IF nikon_app_release_policy('policy-admin',v_id,1,true,'REQUIRE 101 '||repeat('f',64))->>'error'<>'CONFIRMATION' THEN RAISE EXCEPTION 'foreign-artifact confirmation permitted'; END IF;
 r:=nikon_app_release_policy('policy-admin',v_id,1,true,'REQUIRE 101 '||repeat('e',64));
 IF r->>'mandatory'<>'true' OR r->>'status'<>'draft' OR (r->>'revision')::integer<>2 THEN RAISE EXCEPTION 'draft policy did not preserve lifecycle %',r; END IF;
 r:=nikon_app_release_action('policy-admin',v_id,2,'publish','','PUBLISH 101 '||repeat('e',64));
 IF r->>'status'<>'published' OR r->>'mandatory'<>'true' THEN RAISE EXCEPTION 'publish lost reviewed policy %',r; END IF;
 r:=nikon_app_release_policy('policy-admin',v_id,3,false,'OPTIONAL 101 '||repeat('e',64));
 IF r->>'mandatory'<>'false' OR (r->>'revision')::integer<>4 OR r->>'status'<>'published' THEN RAISE EXCEPTION 'published requirement could not be revoked %',r; END IF;
 SELECT count(*) INTO v_count FROM nikon_app_release_audit WHERE release_id=v_id;
 r:=nikon_app_release_policy('policy-admin',v_id,4,false,'OPTIONAL 101 '||repeat('e',64));
 IF (r->>'revision')::integer<>4 OR (SELECT count(*) FROM nikon_app_release_audit WHERE release_id=v_id)<>v_count THEN RAISE EXCEPTION 'same policy not idempotent'; END IF;
 IF nikon_app_release_policy('policy-admin',v_id,3,true,'REQUIRE 101 '||repeat('e',64))->>'error'<>'CONFLICT' THEN RAISE EXCEPTION 'stale policy re-enabled forced update'; END IF;
 IF NOT EXISTS(SELECT 1 FROM nikon_app_release_audit WHERE release_id=v_id AND actor='policy-admin' AND action='policy' AND details->>'previousMandatory'='true' AND details->>'mandatory'='false' AND details->>'revision'='4') THEN RAISE EXCEPTION 'policy audit lacks previous value/actor/revision'; END IF;
 r:=nikon_app_release_action('policy-admin',v_id,4,'withdraw','','WITHDRAW 101');
 IF r->>'status'<>'withdrawn' THEN RAISE EXCEPTION 'withdrawal failed'; END IF;
 IF nikon_app_release_policy('policy-admin',v_id,5,true,'REQUIRE 101 '||repeat('e',64))->>'error'<>'CONFLICT' THEN RAISE EXCEPTION 'withdrawn requirement changed'; END IF;
END; $$;
ROLLBACK;
