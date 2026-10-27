-- Apply after 008. Add format filtering before feed totals/pagination without
-- replacing other community branches or changing publication/release policy.
BEGIN;
DO $patch$
DECLARE source text; old_fragment text; new_fragment text;
BEGIN
 source:=pg_get_functiondef('public.nikon_community(text,uuid,uuid,jsonb)'::regprocedure);
 old_fragment:=$old$ IF p_action='feed' THEN
  SELECT count(*) INTO n FROM nikon_community_public_rows() r WHERE coalesce(p_body->>'category','')='' OR coalesce(r.item->>'category','')=CASE WHEN p_body->>'category'='__uncategorized__' THEN '' ELSE p_body->>'category' END;
  SELECT coalesce(jsonb_agg(t.item ORDER BY t.published_at DESC,t.id),'[]'::jsonb) INTO items FROM (
   SELECT * FROM nikon_community_public_rows() r WHERE coalesce(p_body->>'category','')='' OR coalesce(r.item->>'category','')=CASE WHEN p_body->>'category'='__uncategorized__' THEN '' ELSE p_body->>'category' END
   ORDER BY published_at DESC,id LIMIT page_size OFFSET (page_num::bigint-1)*page_size) t;
  RETURN jsonb_build_object('items',items,'total',n,'page',page_num,'pageSize',page_size,'hasMore',page_num::bigint*page_size<n,
   'categories',(SELECT coalesce(jsonb_agg(category ORDER BY category),'[]'::jsonb) FROM (SELECT DISTINCT coalesce(item->>'category','') category FROM nikon_community_public_rows() ORDER BY category LIMIT 100) cats));
$old$;
 new_fragment:=$new$ IF p_action='feed' THEN
  IF p_body ? 'fileFormat' AND (jsonb_typeof(p_body->'fileFormat') IS DISTINCT FROM 'string' OR p_body->>'fileFormat' NOT IN('','NCP','NP3')) THEN RAISE EXCEPTION 'INVALID_PRESET_FORMAT_FILTER'; END IF;
  SELECT count(*) INTO n FROM nikon_community_public_rows() r
   WHERE (coalesce(p_body->>'category','')='' OR coalesce(r.item->>'category','')=CASE WHEN p_body->>'category'='__uncategorized__' THEN '' ELSE p_body->>'category' END)
    AND (coalesce(p_body->>'fileFormat','')='' OR coalesce(r.item->>'fileFormat','NCP')=p_body->>'fileFormat');
  SELECT coalesce(jsonb_agg(t.item ORDER BY t.published_at DESC,t.id),'[]'::jsonb) INTO items FROM (
   SELECT * FROM nikon_community_public_rows() r
    WHERE (coalesce(p_body->>'category','')='' OR coalesce(r.item->>'category','')=CASE WHEN p_body->>'category'='__uncategorized__' THEN '' ELSE p_body->>'category' END)
     AND (coalesce(p_body->>'fileFormat','')='' OR coalesce(r.item->>'fileFormat','NCP')=p_body->>'fileFormat')
   ORDER BY published_at DESC,id LIMIT page_size OFFSET (page_num::bigint-1)*page_size) t;
  RETURN jsonb_build_object('items',items,'total',n,'page',page_num,'pageSize',page_size,'hasMore',page_num::bigint*page_size<n,
   'fileFormat',coalesce(p_body->>'fileFormat',''),
   'categories',(SELECT coalesce(jsonb_agg(category ORDER BY category),'[]'::jsonb) FROM (SELECT DISTINCT coalesce(item->>'category','') category FROM nikon_community_public_rows() ORDER BY category LIMIT 100) cats));
$new$;
 IF strpos(source,new_fragment)=0 THEN
  IF (length(source)-length(replace(source,old_fragment,'')))/length(old_fragment)<>1 THEN RAISE EXCEPTION 'PRESET_FORMAT_FILTER_PATCH_MISMATCH'; END IF;
  EXECUTE replace(source,old_fragment,new_fragment);
 END IF;
END;
$patch$;
NOTIFY pgrst,'reload schema';
COMMIT;
