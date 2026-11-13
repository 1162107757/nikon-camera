import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
let PGlite;
try { ({PGlite}=await import('../../.community-pg-test/node_modules/@electric-sql/pglite/dist/index.js')); } catch(error) { if(error.code!=='ERR_MODULE_NOT_FOUND')throw error; }

test('100 MiB migration is idempotent, preserves releases/usage/grants and supports all 200 chunks', {skip:!PGlite}, async()=>{
 const db=new PGlite();
 try {
  await db.exec('CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role BYPASSRLS;');
  for(const file of ['001-library.sql','002-users.sql','003-password-accounts.sql','004-preset-categories.sql','005-community.sql','006-app-releases.sql','012-huevia-package.sql','014-app-update-policy.sql','017-app-release-capacity.sql','018-app-download-budget.sql','019-app-release-ip-budget.sql','020-admin-apk-upload-budget.sql'])await db.exec(await readFile(new URL('../database/'+file,import.meta.url),'utf8'));
  await db.exec("CREATE SCHEMA storage;CREATE TABLE storage.buckets(id text PRIMARY KEY,public boolean,file_size_limit bigint);INSERT INTO storage.buckets VALUES('nikon-presets',false,33554432),('unrelated',true,4194304);INSERT INTO nikon_admins(username,password_hash,disabled) VALUES('capacity-admin','unused',false);");
  await db.exec("INSERT INTO nikon_app_release_budgets VALUES('retained-fixture',7,123456,now()+interval '1 day');INSERT INTO nikon_app_releases(package_name,version_name,version_code,min_sdk,byte_length,sha256,signer_sha256,storage_path,channel,notes,status,mandatory,revision) VALUES('cc.huevia','history',900,26,4,repeat('a',64),'04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31','app-releases/'||repeat('a',64)||'.bin','beta','history','published',true,7);");
  const prior=(await db.query('SELECT * FROM nikon_app_releases')).rows,usage=(await db.query('SELECT * FROM nikon_app_release_budgets')).rows;
  const migration=await readFile(new URL('../database/023-app-release-100mib.sql',import.meta.url),'utf8');await db.exec(migration);await db.exec(migration);
  assert.deepEqual((await db.query('SELECT * FROM nikon_app_releases')).rows,prior);assert.deepEqual((await db.query('SELECT * FROM nikon_app_release_budgets')).rows,usage);
  assert.deepEqual((await db.query('SELECT id,public,file_size_limit::integer FROM storage.buckets ORDER BY id')).rows,[{id:'nikon-presets',public:false,file_size_limit:104857600},{id:'unrelated',public:true,file_size_limit:4194304}]);
  const begin=async(size,actor='capacity-admin')=>(await db.query("SELECT nikon_app_upload_begin($1,$2,'beta','capacity test') AS v",[actor,size])).rows[0].v;
  assert.equal((await begin(104857601)).error,'INVALID');assert.equal((await begin(104857600,'missing')).error,'FORBIDDEN');
  const upload=await begin(104857600);assert.ok(upload.uploadId);
  const check=async(index)=>(await db.query('SELECT nikon_app_upload_check($1,$2,$3,524288) AS v',['capacity-admin',upload.uploadId,index])).rows[0].v;
  for(const index of [0,63,64,100,199])assert.equal((await check(index)).allowed,true);
  for(const index of [-1,200])assert.equal((await check(index)).error,'INVALID');
  const budget=async(size)=>(await db.query('SELECT nikon_app_upload_budget($1,$2,false) AS v',['capacity-admin',size])).rows[0].v;
  for(let i=0;i<8;i++)assert.equal((await budget(104857600)).allowed,true);assert.equal((await budget(1)).error,'BUDGET');assert.equal((await budget(104857601)).error,'INVALID');
  const download=async(size,key='b'.repeat(64))=>(await db.query('SELECT nikon_release_download_budget($1,$2,$3) AS v',[key,'c'.repeat(64),size])).rows[0].v;
  assert.equal((await download(104857601)).error,'INVALID');assert.equal((await download(104857600)).allowed,true);
  assert.equal((await download(104857600)).chargedBytes,0,'same-file retry still avoids a second byte charge');
  const grants=(await db.query("SELECT has_function_privilege('anon','public.nikon_app_upload_begin(text,integer,text,text)','execute') AS anon,has_function_privilege('service_role','public.nikon_app_upload_begin(text,integer,text,text)','execute') AS service")).rows[0];assert.deepEqual(grants,{anon:false,service:true});
 } finally { await db.close(); }
});
