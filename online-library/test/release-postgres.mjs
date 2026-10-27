// Optional isolated local PostgreSQL engine. Never reads cloud credentials or contacts the live DB.
// Reuses the temporary test runtime installed for community-postgres.mjs.
import { readFile } from 'node:fs/promises';
import { PGlite } from '../../.community-pg-test/node_modules/@electric-sql/pglite/dist/index.js';
const db=new PGlite();
try{
  await db.exec('CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role BYPASSRLS;');
  for(const file of ['001-library.sql','002-users.sql','003-password-accounts.sql','004-preset-categories.sql','005-community.sql','006-app-releases.sql'])await db.exec(await readFile(new URL(`../database/${file}`,import.meta.url),'utf8'));
  // Recreate the old deployed constraints/schema, then upgrade twice to prove that
  // a rerun replaces the rootmain policy and adds readiness without a fresh DB.
  await db.exec("ALTER TABLE nikon_app_release_audit DROP CONSTRAINT nikon_app_release_audit_actor_check; ALTER TABLE nikon_app_release_audit ADD CONSTRAINT nikon_app_release_audit_actor_check CHECK(actor='rootmain'); ALTER TABLE nikon_app_uploads DROP CONSTRAINT nikon_app_uploads_actor_check; ALTER TABLE nikon_app_uploads ADD CONSTRAINT nikon_app_uploads_actor_check CHECK(actor='rootmain'); ALTER TABLE nikon_app_upload_chunks DROP COLUMN ready;");
  const releaseMigration=await readFile(new URL('../database/006-app-releases.sql',import.meta.url),'utf8');
  await db.exec(releaseMigration);await db.exec(releaseMigration);
  await db.exec(await readFile(new URL('./release-database-acceptance.sql',import.meta.url),'utf8'));
  // Upgrade a historical published row without silently forcing its clients.
  await db.exec(`INSERT INTO nikon_app_releases(package_name,version_name,version_code,min_sdk,byte_length,sha256,signer_sha256,storage_path,channel,notes,status)
    VALUES('cc.huevia','pre-policy-fixture',100,26,4,repeat('d',64),'04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31','app-releases/'||repeat('d',64)||'.apk','beta','Synthetic historical release','published');`);
  const policyMigration=await readFile(new URL('../database/014-app-update-policy.sql',import.meta.url),'utf8');
  await db.exec(policyMigration);await db.exec(policyMigration);
  const historical=await db.query('SELECT mandatory FROM nikon_app_releases WHERE version_code=100');
  if(historical.rows[0]?.mandatory!==false)throw new Error('Historical releases became mandatory');
  await db.exec("DELETE FROM nikon_app_releases WHERE version_code=100;");
  await db.exec(await readFile(new URL('./update-policy-database-acceptance.sql',import.meta.url),'utf8'));
  // Capacity upgrades must preserve an existing published mandatory policy.
  await db.exec(`INSERT INTO nikon_app_releases(package_name,version_name,version_code,min_sdk,byte_length,sha256,signer_sha256,storage_path,channel,notes,status,mandatory,revision)
    VALUES('cc.huevia','capacity-history-fixture',102,26,4,repeat('d',64),'04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31','app-releases/'||repeat('d',64)||'.apk','beta','Synthetic capacity history','published',true,7);`);
  // PG Storage is a provider-owned schema in production; model only the bucket
  // columns changed by this migration in the isolated local engine.
  await db.exec("CREATE SCHEMA storage; CREATE TABLE storage.buckets(id text PRIMARY KEY,public boolean,file_size_limit bigint); INSERT INTO storage.buckets VALUES('nikon-presets',false,4194304),('unrelated-fixture',true,4194304);");
  const capacityMigration=await readFile(new URL('../database/017-app-release-capacity.sql',import.meta.url),'utf8');
  await db.exec(capacityMigration);await db.exec(capacityMigration);
  const capacityBuckets=await db.query('SELECT id,public,file_size_limit::integer FROM storage.buckets ORDER BY id');
  if(JSON.stringify(capacityBuckets.rows)!==JSON.stringify([{id:'nikon-presets',public:false,file_size_limit:33554432},{id:'unrelated-fixture',public:true,file_size_limit:4194304}]))throw new Error('Capacity migration changed bucket visibility or unrelated storage limits');
  const capacityHistory=await db.query('SELECT status,mandatory,revision,byte_length FROM nikon_app_releases WHERE version_code=102');
  if(JSON.stringify(capacityHistory.rows[0])!==JSON.stringify({status:'published',mandatory:true,revision:7,byte_length:4}))throw new Error('Capacity migration changed historical publication or policy');
  await db.exec('DELETE FROM nikon_app_releases WHERE version_code=102');
  await db.exec(await readFile(new URL('./release-capacity-database-acceptance.sql',import.meta.url),'utf8'));
  const {rows}=await db.query('SELECT (SELECT count(*) FROM nikon_app_releases)::integer AS releases,(SELECT count(*) FROM nikon_app_uploads)::integer AS uploads,(SELECT count(*) FROM nikon_app_release_audit)::integer AS audit');
  if(Object.values(rows[0]).some(value=>value!==0))throw new Error('Release acceptance did not roll back');
  console.log('Release PostgreSQL migrations, immutable lifecycle, update-policy permissions/revocation, 32 MiB capacity/chunk 63, preserved budgets and rollback passed.');
}finally{await db.close();}
