// Editorial names only. No app build, recipe conversion, category or schema changes.
import { readFile, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { executeSql, sqlRows, quoteSql, ENV_ID, PUBLIC_ORIGIN } from './cloud-tools.mjs';
import { validatePresetFile } from '../server/validation.mjs';

export const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value==='object'
  ? Object.fromEntries(Object.keys(value).sort().map(k=>[k,canonical(value[k])])) : value;
const stable=value=>JSON.stringify(canonical(value));
const hash=value=>createHash('sha256').update(value).digest('hex');
const mappingFile=fileURLToPath(new URL('../data/preset-names.zh-CN.tsv',import.meta.url));
const brandRules=[[/^canon\b/i,'佳能'],[/^nikon[_\s]/i,'尼康'],[/^nik1v1/i,'尼康'],[/^fuji[\s-]/i,'富士'],
  [/^kodak/i,'柯达'],[/^konica\b/i,'柯尼卡'],[/^agfa\b/i,'爱克发'],[/^pentax\b/i,'宾得'],[/^leica/i,'徕卡'],[/^arri\b/i,'阿莱']];

export function parseNames(text){
  const result=new Map(),used=new Set();
  for(const [index,line] of text.replace(/^\uFEFF/,'').split(/\r?\n/).entries()){
    if(!line||line.startsWith('#'))continue;
    const pair=line.split('\t');
    if(pair.length!==2||pair.some(v=>v!==v.trim()||!v)||result.has(pair[0])||used.has(pair[1]))throw Error('Invalid or duplicate name at line '+(index+1));
    const [from,to]=pair;
    if(to.length>160||/[\x00-\x1f\x7f-\x9f]/.test(to)||!/[\u3400-\u9fff]/.test(to))throw Error('Chinese display name required');
    for(const [pattern,brand] of brandRules)if(pattern.test(from)&&!to.startsWith(brand+' '))throw Error('Brand must be retained in Chinese: '+from);
    result.set(from,to);used.add(to);
  }
  return result;
}

export function makePlan(backup,names){
  if(backup.environment!==ENV_ID||!Array.isArray(backup.rows)||backup.rows.length!==names.size)throw Error('Snapshot/name inventory mismatch');
  const ids=new Set(),originals=new Set();
  const assignments=backup.rows.map(row=>{
    const p=row.published;
    if(!/^[a-f0-9-]{36}$/.test(row.id)||ids.has(row.id)||!p||row.status!=='published'||stable(row.draft)!==stable(p)
      ||Number(row.revision)!==Number(row.published_revision)||!Number.isSafeInteger(Number(row.revision))||!names.has(p.name)
      ||originals.has(p.name)||!/^[a-f0-9]{64}$/.test(p.file?.sha256||''))throw Error('Snapshot has an unreviewed or unpublished change');
    ids.add(row.id);originals.add(p.name);
    return {id:row.id,oldName:p.name,name:names.get(p.name),revision:Number(row.revision),sha256:p.file.sha256,category:p.category||'',publishedAt:row.published_at};
  });
  return {version:1,environment:ENV_ID,total:assignments.length,assignments};
}

export function nameMigrationSql(plan,{rollback=false,dryRun=false}={}){
  if(plan.environment!==ENV_ID||plan.total!==plan.assignments?.length||!plan.total)throw Error('Unexpected migration plan');
  const targets=plan.assignments.map(x=>{
    if(!/^[a-f0-9-]{36}$/.test(x.id)||!Number.isSafeInteger(x.revision)||x.revision<1||!/^[a-f0-9]{64}$/.test(x.sha256)
      ||typeof x.oldName!=='string'||typeof x.name!=='string'||!x.name.length||x.name.length>160)throw Error('Invalid migration target');
    return {id:x.id,from:rollback?x.name:x.oldName,to:rollback?x.oldName:x.name,revision:x.revision+(rollback?1:0),sha256:x.sha256,publishedAt:x.publishedAt};
  });
  return `DO $preset_names$
DECLARE entry jsonb; current_row nikon_presets%ROWTYPE; renamed jsonb; saved jsonb; manifest jsonb;
BEGIN
  BEGIN
    PERFORM pg_advisory_xact_lock(1852403310,1);
    IF (SELECT count(*) FROM nikon_presets)<>${plan.total} THEN RAISE EXCEPTION 'NAME_INVENTORY_CONFLICT'; END IF;
    FOR entry IN SELECT value FROM jsonb_array_elements(${quoteSql(JSON.stringify(targets))}::jsonb) ORDER BY value->>'id' LOOP
      SELECT * INTO current_row FROM nikon_presets WHERE id=(entry->>'id')::uuid FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'NAME_TARGET_MISSING'; END IF;
      IF current_row.status<>'published' OR current_row.draft IS DISTINCT FROM current_row.published
        OR current_row.published_revision IS DISTINCT FROM current_row.revision
        OR current_row.published->'file'->>'sha256' IS DISTINCT FROM entry->>'sha256'
        OR current_row.published_at IS DISTINCT FROM (entry->>'publishedAt')::timestamptz
        THEN RAISE EXCEPTION 'NAME_METADATA_CONFLICT'; END IF;
      IF current_row.revision=(entry->>'revision')::integer+1 AND current_row.draft->>'name'=entry->>'to' THEN CONTINUE; END IF;
      IF current_row.revision<>(entry->>'revision')::integer OR current_row.draft->>'name' IS DISTINCT FROM entry->>'from'
        THEN RAISE EXCEPTION 'NAME_REVISION_CONFLICT'; END IF;
      renamed:=jsonb_set(current_row.draft,'{name}',entry->'to',false);
      saved:=nikon_save_preset(current_row.id,current_row.revision,renamed);
      PERFORM nikon_publish_preset(current_row.id,(saved->>'revision')::integer,true);
      UPDATE nikon_presets SET published_at=current_row.published_at WHERE id=current_row.id;
    END LOOP;
    SELECT nikon_catalog_manifest() INTO manifest;
    IF jsonb_array_length(manifest->'presets')<>${plan.total} OR octet_length(convert_to(manifest::text,'UTF8'))>2097152
      THEN RAISE EXCEPTION 'NAME_CATALOG_LIMIT'; END IF;
    ${dryRun?"RAISE SQLSTATE 'PZ001' USING MESSAGE='NAME_DRY_RUN_COMPLETE';":''}
  ${dryRun?"EXCEPTION WHEN SQLSTATE 'PZ001' THEN NULL;":'END;'}
  ${dryRun?'END;':''}
END $preset_names$;`;
}

function loadJson(text){return JSON.parse(text.replace(/^\uFEFF/,''));}
async function snapshotRows(){
  const rows=sqlRows(executeSql('SELECT id::text,revision,draft,published,published_revision,status,created_at::text,updated_at::text,published_at::text FROM nikon_presets ORDER BY id'));
  for(const row of rows)for(const key of ['draft','published'])if(typeof row[key]==='string')row[key]=JSON.parse(row[key]);
  return rows;
}
async function snapshotVersions(){
  const rows=sqlRows(executeSql('SELECT preset_id::text,revision,snapshot,created_at::text FROM nikon_preset_versions ORDER BY preset_id,revision'));
  for(const row of rows)if(typeof row.snapshot==='string')row.snapshot=JSON.parse(row.snapshot);
  return rows;
}
export function verifyAfter(backup,plan,rows,versions,catalog){
  if(rows.length!==backup.rows.length||catalog.presets.length!==rows.length||versions.length!==backup.versions.length+plan.total)throw Error('Unexpected inventory/version count');
  const expected=new Map(plan.assignments.map(x=>[x.id,x]));
  for(const before of backup.rows){
    const now=rows.find(x=>x.id===before.id),target=expected.get(before.id),data={...before.draft,name:target.name};
    if(!now||stable(now.draft)!==stable(data)||stable(now.published)!==stable(data)||Number(now.revision)!==target.revision+1||Number(now.published_revision)!==target.revision+1
      ||['id','status','created_at','published_at'].some(k=>now[k]!==before[k]))throw Error('Non-name metadata changed: '+target.oldName);
    const version=versions.find(x=>x.preset_id===before.id&&Number(x.revision)===target.revision+1);
    if(!version||stable(version.snapshot)!==stable(data))throw Error('New history snapshot missing');
  }
  const history=new Map(versions.map(x=>[x.preset_id+':'+x.revision,x]));
  for(const v of backup.versions)if(stable(history.get(v.preset_id+':'+v.revision))!==stable(v))throw Error('Historical snapshot modified');
}

async function main(){
  const [mode,arg]=process.argv.slice(2);if(!['--plan','--dry-run','--apply','--verify','--rollback-sql'].includes(mode)||!arg)throw Error('Usage: rename-preset-names.mjs --plan|--dry-run|--apply|--verify|--rollback-sql <snapshot-directory>');
  const dir=resolve(arg),backupBytes=await readFile(join(dir,'before.json')),backup=loadJson(backupBytes.toString()),mappingBytes=await readFile(mappingFile);
  for(const row of backup.rows){const f=row.published.file,extension=f.extension||new URL(f.url).pathname.split('.').pop();
    if(!['ncp','np3'].includes(extension))throw Error('Unknown source format');
    const bytes=await readFile(join(dir,'files',f.sha256+'.'+extension));
    if(hash(bytes)!==f.sha256||bytes.length!==f.byteLength||validatePresetFile(bytes).extension!==extension)throw Error('Source recipe identity changed');
  }
  const computed=makePlan(backup,parseNames(mappingBytes.toString()));
  const plan={...computed,snapshotSha256:hash(backupBytes),mappingSha256:hash(mappingBytes)};
  if(mode==='--plan'){
    await writeFile(join(dir,'name-plan.json'),JSON.stringify(plan,null,2),{flag:'wx'});
    const lines=['# 在线预设中文名称对照','',`共 ${plan.total} 款；仅更新显示名称。配方、ID、SHA、分类、排序与旧版本不变。`,'','| 原名 | 中文名称 | 分类 |','|---|---|---|',...plan.assignments.map(x=>`| ${x.oldName.replaceAll('|','\\|')} | ${x.name} | ${x.category} |`)];
    await writeFile(join(dir,'name-preview.md'),lines.join('\n'));
    await writeFile(join(dir,'apply-names.sql'),nameMigrationSql(plan));
    await writeFile(join(dir,'rollback-names.sql'),nameMigrationSql(plan,{rollback:true}));
    console.log(JSON.stringify({planned:plan.total,snapshotSha256:plan.snapshotSha256,mappingSha256:plan.mappingSha256}));return;
  }
  if(stable(loadJson(await readFile(join(dir,'name-plan.json'),'utf8')))!==stable(plan))throw Error('Plan, mapping or original snapshot changed');
  if(mode==='--rollback-sql'){await writeFile(join(dir,'rollback-names.sql'),nameMigrationSql(plan,{rollback:true}));return;}
  if(mode==='--dry-run'){
    executeSql(nameMigrationSql(plan,{dryRun:true}));
    if(stable(await snapshotRows())!==stable(backup.rows)||stable(await snapshotVersions())!==stable(backup.versions))throw Error('Dry run failed to roll back exactly');
    await writeFile(join(dir,'dry-run.json'),JSON.stringify({pass:true,targets:plan.total,rowsAndHistoryUnchanged:true,checkedAt:new Date().toISOString()},null,2));
    console.log(JSON.stringify({dryRun:'pass',targets:plan.total,rowsAndHistoryUnchanged:true}));return;
  }
  if(mode==='--apply')executeSql(nameMigrationSql(plan));
  const rows=await snapshotRows(),versions=await snapshotVersions();
  const response=await fetch(PUBLIC_ORIGIN+'/preset-library/catalog.json',{signal:AbortSignal.timeout(45000)});if(!response.ok)throw Error('Public catalog unavailable');
  const catalog=await response.json();verifyAfter(backup,plan,rows,versions,catalog);
  const beforeCatalog=loadJson(await readFile(join(dir,'catalog-before.json'),'utf8'));
  const expectedCatalog={...beforeCatalog,presets:beforeCatalog.presets.map(x=>({...x,name:plan.assignments.find(y=>y.id===x.id).name}))};
  if(stable(catalog)!==stable(expectedCatalog))throw Error('Public catalog changed beyond names or ordering changed');
  await writeFile(join(dir,'after.json'),JSON.stringify({rows,versions},null,2));await writeFile(join(dir,'catalog-after.json'),JSON.stringify(catalog,null,2));
  const result={pass:true,renamed:plan.total,total:rows.length,oldVersionsPreserved:backup.versions.length,newVersions:plan.total,onlyNamesChanged:true,publicCatalogVerified:true,recipeHashesUnchanged:plan.total,sourceFilesChecked:plan.total,checkedAt:new Date().toISOString(),mappingSha256:plan.mappingSha256};
  await writeFile(join(dir,'name-verification.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(e=>{console.error(e.message);process.exitCode=1;});
