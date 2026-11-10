-- One STABLE invocation sees one PostgreSQL statement snapshot across all tables.
-- No public/anonymous access. This exports application data, including credential
-- hashes; call only from the private backup worker and never log the result.
CREATE OR REPLACE FUNCTION public.nikon_backup_snapshot() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE item record; rows jsonb; tables jsonb := '{}'::jsonb;
BEGIN
  FOR item IN
    SELECT n.nspname AS ns,c.relname AS name
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE c.relkind IN ('r','p') AND ((n.nspname='public' AND c.relname LIKE 'nikon\_%' ESCAPE '\')
      OR (n.nspname='storage' AND c.relname IN ('objects','buckets')))
    ORDER BY n.nspname,c.relname
  LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) FROM %I.%I t',item.ns,item.name) INTO rows;
    tables := tables || jsonb_build_object(item.ns||'.'||item.name,rows);
  END LOOP;
  RETURN jsonb_build_object(
    'format','huevia-data-backup-v1','capturedAt',statement_timestamp(),'database',current_database(),
    'tables',tables,
    'columns',(SELECT coalesce(jsonb_agg(to_jsonb(v)),'[]'::jsonb) FROM (
      SELECT n.nspname AS schema,c.relname AS table_name,a.attname AS name,a.attnum AS ordinal,
        format_type(a.atttypid,a.atttypmod) AS type,a.attnotnull AS not_null,
        pg_get_expr(d.adbin,d.adrelid) AS default_expr,a.attidentity AS identity_kind,a.attgenerated AS generated_kind
      FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      LEFT JOIN pg_attrdef d ON d.adrelid=c.oid AND d.adnum=a.attnum
      WHERE a.attnum>0 AND NOT a.attisdropped AND c.relkind IN ('r','p') AND n.nspname='public'
        AND c.relname LIKE 'nikon\_%' ESCAPE '\' ORDER BY c.relname,a.attnum) v),
    'constraints',(SELECT coalesce(jsonb_agg(to_jsonb(v)),'[]'::jsonb) FROM (
      SELECT n.nspname AS schema,c.relname AS table_name,k.conname AS name,k.contype AS kind,pg_get_constraintdef(k.oid,true) AS definition
      FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND c.relname LIKE 'nikon\_%' ESCAPE '\' ORDER BY c.relname,k.conname) v),
    'indexes',(SELECT coalesce(jsonb_agg(to_jsonb(v)),'[]'::jsonb) FROM (
      SELECT schemaname,tablename,indexname,indexdef FROM pg_indexes
      WHERE schemaname='public' AND tablename LIKE 'nikon\_%' ESCAPE '\' ORDER BY tablename,indexname) v),
    'functions',(SELECT coalesce(jsonb_agg(to_jsonb(v)),'[]'::jsonb) FROM (
      SELECT p.proname AS name,pg_get_function_identity_arguments(p.oid) AS arguments,pg_get_functiondef(p.oid) AS definition,p.proacl::text AS acl
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname LIKE 'nikon\_%' ESCAPE '\' AND p.prokind='f' ORDER BY p.proname,p.oid) v),
    'triggers',(SELECT coalesce(jsonb_agg(to_jsonb(v)),'[]'::jsonb) FROM (
      SELECT c.relname AS table_name,t.tgname AS name,pg_get_triggerdef(t.oid,true) AS definition
      FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE NOT t.tgisinternal AND n.nspname='public' AND c.relname LIKE 'nikon\_%' ESCAPE '\' ORDER BY c.relname,t.tgname) v),
    'tableSecurity',(SELECT coalesce(jsonb_agg(to_jsonb(v)),'[]'::jsonb) FROM (
      SELECT c.relname AS name,c.relrowsecurity AS row_security,c.relforcerowsecurity AS force_row_security,c.relacl::text AS acl
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE c.relkind IN ('r','p') AND n.nspname='public' AND c.relname LIKE 'nikon\_%' ESCAPE '\' ORDER BY c.relname) v),
    'policies',(SELECT coalesce(jsonb_agg(to_jsonb(v)),'[]'::jsonb) FROM (
      SELECT * FROM pg_policies WHERE schemaname='public' AND tablename LIKE 'nikon\_%' ESCAPE '\' ORDER BY tablename,policyname) v)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.nikon_backup_snapshot() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.nikon_backup_snapshot() TO service_role;
