-- Legacy Android release channel: 100 MiB, 200 x 512 KiB chunks.
-- Retain four full-size declarations/day and count chunks + final object as writes.
-- No usage reset, publication/policy changes, admin/grant changes, or mobile-channel changes.
BEGIN;
SELECT pg_advisory_xact_lock(hashtextextended('nikon-app-upload-actual-budget',0));
SELECT pg_advisory_xact_lock(hashtextextended('nikon-app-upload',0));
DO $$ BEGIN
 IF to_regclass('storage.buckets') IS NOT NULL THEN
  UPDATE storage.buckets SET file_size_limit=greatest(coalesce(file_size_limit,0),104857600)
   WHERE id='nikon-presets' AND public=false AND file_size_limit IS NOT NULL;
 END IF;
END; $$;
ALTER TABLE public.nikon_app_releases DROP CONSTRAINT IF EXISTS nikon_app_releases_byte_length_check;
ALTER TABLE public.nikon_app_releases ADD CONSTRAINT nikon_app_releases_byte_length_check CHECK(byte_length BETWEEN 1 AND 104857600);
ALTER TABLE public.nikon_app_uploads DROP CONSTRAINT IF EXISTS nikon_app_uploads_byte_length_check;
ALTER TABLE public.nikon_app_uploads ADD CONSTRAINT nikon_app_uploads_byte_length_check CHECK(byte_length BETWEEN 1 AND 104857600);
ALTER TABLE public.nikon_app_upload_chunks DROP CONSTRAINT IF EXISTS nikon_app_upload_chunks_chunk_index_check;
ALTER TABLE public.nikon_app_upload_chunks ADD CONSTRAINT nikon_app_upload_chunks_chunk_index_check CHECK(chunk_index BETWEEN 0 AND 199);

DO $migration$
DECLARE v_signature text; v_definition text;
BEGIN
 FOREACH v_signature IN ARRAY ARRAY[
  'public.nikon_app_upload_budget(text,integer,boolean)',
  'public.nikon_app_upload_begin(text,integer,text,text)',
  'public.nikon_release_budget_atomic(text,text,integer)',
  'public.nikon_release_download_budget(text,text,integer)'
 ] LOOP
  v_definition:=pg_get_functiondef(v_signature::regprocedure);
  IF position('33554432' IN v_definition)>0 THEN v_definition:=replace(v_definition,'33554432','104857600');
  ELSIF position('104857600' IN v_definition)=0 THEN RAISE EXCEPTION 'Unexpected package capacity in %',v_signature;
  END IF;
  IF v_signature LIKE '%nikon_app_upload_budget(%' THEN
   IF position('268435456' IN v_definition)>0 THEN v_definition:=replace(v_definition,'268435456','838860800');
   ELSIF position('838860800' IN v_definition)=0 THEN RAISE EXCEPTION 'Unexpected actual-write allowance'; END IF;
  ELSIF v_signature LIKE '%nikon_app_upload_begin(%' THEN
   IF position('134217728' IN v_definition)>0 THEN v_definition:=replace(v_definition,'134217728','419430400');
   ELSIF position('419430400' IN v_definition)=0 THEN RAISE EXCEPTION 'Unexpected declared-size allowance'; END IF;
  END IF;
  EXECUTE v_definition;
 END LOOP;
 v_definition:=pg_get_functiondef('public.nikon_app_upload_check(text,uuid,integer,integer)'::regprocedure);
 IF position('p_index>63' IN v_definition)>0 THEN EXECUTE replace(v_definition,'p_index>63','p_index>199');
 ELSIF position('p_index>199' IN v_definition)=0 THEN RAISE EXCEPTION 'Unexpected chunk index limit'; END IF;
END; $migration$;
NOTIFY pgrst,'reload schema';
COMMIT;
