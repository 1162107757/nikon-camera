-- Four modern 32 MiB APK uploads/day: chunks + final object count as actual writes.
-- Retain all counters, permissions, request ceilings and concurrent-task bounds.
DO $migration$
DECLARE v_definition text;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('nikon-app-upload-actual-budget',0));
 PERFORM pg_advisory_xact_lock(hashtextextended('nikon-app-upload',0));
 v_definition:=pg_get_functiondef('public.nikon_app_upload_budget(text,integer,boolean)'::regprocedure);
 IF position('67108864' IN v_definition)>0 THEN
  EXECUTE replace(v_definition,'67108864','268435456');
 ELSIF position('268435456' IN v_definition)=0 THEN
  RAISE EXCEPTION 'Unexpected APK actual-write budget definition';
 END IF;
 v_definition:=pg_get_functiondef('public.nikon_app_upload_begin(text,integer,text,text)'::regprocedure);
 IF position('67108864' IN v_definition)>0 THEN
  EXECUTE replace(v_definition,'67108864','134217728');
 ELSIF position('134217728' IN v_definition)=0 THEN
  RAISE EXCEPTION 'Unexpected APK declared-size budget definition';
 END IF;
END; $migration$;
