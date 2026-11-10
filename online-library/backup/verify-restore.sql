-- Read-only production export; only session-local temporary tables are created.
DO $verify$
DECLARE snapshot jsonb; item record; columns text; copied jsonb; checked integer := 0;
BEGIN
  snapshot := public.nikon_backup_snapshot();
  FOR item IN SELECT key,value FROM jsonb_each(snapshot->'tables') WHERE key LIKE 'public.nikon\_%' ESCAPE '\'
  LOOP
    EXECUTE format('CREATE TEMP TABLE %I (LIKE public.%I INCLUDING ALL) ON COMMIT DROP',
      'restore_verify_'||split_part(item.key,'.',2),split_part(item.key,'.',2));
    SELECT string_agg(format('%I',a.attname),',' ORDER BY a.attnum) INTO columns
      FROM pg_attribute a WHERE a.attrelid=item.key::regclass AND a.attnum>0 AND NOT a.attisdropped AND a.attgenerated='';
    EXECUTE format('INSERT INTO pg_temp.%I (%s) OVERRIDING SYSTEM VALUE SELECT %s FROM jsonb_populate_recordset(NULL::%s,$1)',
      'restore_verify_'||split_part(item.key,'.',2),columns,columns,item.key) USING item.value;
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM pg_temp.%I t',
      'restore_verify_'||split_part(item.key,'.',2)) INTO copied;
    IF copied IS DISTINCT FROM (SELECT coalesce(jsonb_agg(v ORDER BY v::text),'[]'::jsonb) FROM jsonb_array_elements(item.value) v)
      THEN RAISE EXCEPTION 'BACKUP_TYPED_RESTORE_MISMATCH'; END IF;
    checked := checked+1;
  END LOOP;
  IF checked<33 THEN RAISE EXCEPTION 'BACKUP_TYPED_RESTORE_INCOMPLETE'; END IF;
END;
$verify$;
SELECT 'PASS: all application tables restored into temporary typed tables with exact JSON values' AS result;
