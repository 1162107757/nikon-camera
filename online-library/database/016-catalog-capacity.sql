-- Expand only the publication limits. Preserve publication locking, revisions,
-- asset authorization and every other deployed function unchanged.
BEGIN;
DO $catalog_capacity$
DECLARE source text; previous_fragment text; next_fragment text;
BEGIN
  source := pg_get_functiondef('public.nikon_publish_preset(uuid,integer,boolean)'::regprocedure);
  previous_fragment := $previous$    IF jsonb_array_length(manifest->'presets') > 256 THEN RAISE EXCEPTION 'CATALOG_FULL'; END IF;
    IF octet_length(convert_to(manifest::text,'UTF8')) > 524288 THEN RAISE EXCEPTION 'CATALOG_TOO_LARGE'; END IF;$previous$;
  next_fragment := $next$    IF jsonb_array_length(manifest->'presets') > 1024 THEN RAISE EXCEPTION 'CATALOG_FULL'; END IF;
    IF octet_length(convert_to(manifest::text,'UTF8')) > 2097152 THEN RAISE EXCEPTION 'CATALOG_TOO_LARGE'; END IF;$next$;
  IF strpos(source, next_fragment) = 0 THEN
    IF (length(source) - length(replace(source, previous_fragment, ''))) / length(previous_fragment) <> 1 THEN
      RAISE EXCEPTION 'CATALOG_CAPACITY_PATCH_MISMATCH';
    END IF;
    EXECUTE replace(source, previous_fragment, next_fragment);
  END IF;
END;
$catalog_capacity$;
COMMIT;
