-- Isolated local PostgreSQL only. All synthetic capacity rows roll back.
BEGIN;
INSERT INTO nikon_admins(username,password_hash,disabled) VALUES('capacity-admin','synthetic-unused-hash',false);
SET LOCAL ROLE service_role;
DO $$
DECLARE u jsonb; c jsonb; r jsonb; upload_id uuid; metadata jsonb; i integer;
BEGIN
 IF has_function_privilege('anon','public.nikon_app_upload_begin(text,integer,text,text)','EXECUTE')
  OR has_function_privilege('authenticated','public.nikon_app_upload_check(text,uuid,integer,integer)','EXECUTE') THEN RAISE EXCEPTION 'capacity upgrade exposed upload RPCs'; END IF;
 IF nikon_app_upload_begin('capacity-admin',33554433,'beta','Synthetic overflow')->>'error'<>'INVALID'
  OR nikon_app_upload_budget('capacity-admin',33554433,false)->>'error'<>'INVALID'
  OR nikon_release_budget_atomic(repeat('a',64),'download',33554433)->>'error'<>'INVALID' THEN RAISE EXCEPTION '32 MiB overflow accepted'; END IF;
 IF nikon_app_upload_begin('missing',33554432,'beta','Synthetic untrusted')->>'error'<>'FORBIDDEN' THEN RAISE EXCEPTION 'capacity bypassed administrator check'; END IF;
 u:=nikon_app_upload_begin('capacity-admin',33554432,'beta','Synthetic maximum APK');upload_id:=(u->>'uploadId')::uuid;
 IF upload_id IS NULL THEN RAISE EXCEPTION '32 MiB upload rejected %',u; END IF;
 IF nikon_app_upload_check('capacity-admin',upload_id,63,524288)?'error'
  OR nikon_app_upload_check('capacity-admin',upload_id,64,524288)->>'error'<>'INVALID'
  OR nikon_app_upload_check('capacity-admin',upload_id,63,524287)->>'error'<>'INVALID' THEN RAISE EXCEPTION 'maximum chunk boundary incorrect'; END IF;
 FOR i IN 0..63 LOOP
  c:=nikon_app_upload_reserve('capacity-admin',upload_id,i,524288,repeat('a',64),'app-upload/'||upload_id::text||'/'||i::text||'-'||repeat('a',64)||'.part');
  IF c?'error' THEN RAISE EXCEPTION 'capacity reservation failed at % %',i,c; END IF;
  c:=nikon_app_upload_chunk('capacity-admin',upload_id,i,524288,repeat('a',64),'app-upload/'||upload_id::text||'/'||i::text||'-'||repeat('a',64)||'.part');
  IF c?'error' THEN RAISE EXCEPTION 'capacity chunk failed at % %',i,c; END IF;
 END LOOP;
 c:=nikon_app_upload_claim('capacity-admin',upload_id);
 IF (c->>'byteLength')::integer<>33554432 OR jsonb_array_length(c->'chunks')<>64 THEN RAISE EXCEPTION 'maximum APK assembled incorrectly %',c; END IF;
 metadata:=jsonb_build_object('packageName','cc.huevia','versionName','capacity-fixture','versionCode',999999,'minSdk',26,'byteLength',33554432,'sha256',repeat('a',64),'signerSha256','04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31','signatureSchemes',jsonb_build_array(2,3));
 r:=nikon_app_release_create('capacity-admin',upload_id,metadata,'app-releases/'||repeat('a',64)||'.bin');
 IF r?'error' OR (r->>'byte_length')::integer<>33554432 OR r->>'storage_path'<>'app-releases/'||repeat('a',64)||'.bin' OR r->>'status'<>'draft' OR (r->>'mandatory')::boolean THEN RAISE EXCEPTION 'capacity draft metadata or default policy changed %',r; END IF;
 IF nikon_app_upload_budget('capacity-admin',33554432,false)?'error'
  OR nikon_app_upload_budget('capacity-admin',33554432,false)?'error'
  OR nikon_app_upload_budget('capacity-admin',1,false)->>'error'<>'BUDGET' THEN RAISE EXCEPTION 'actual write budget changed or cannot accept a maximum APK'; END IF;
 IF nikon_release_budget_atomic(repeat('b',64),'download',33554432)?'error'
  OR nikon_release_budget_atomic(repeat('b',64),'download',33554432)?'error'
  OR nikon_release_budget_atomic(repeat('b',64),'download',33554432)->>'error'<>'BUDGET' THEN RAISE EXCEPTION 'per-source download byte budget changed'; END IF;
END; $$;
ROLLBACK;
