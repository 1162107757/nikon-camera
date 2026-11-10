import test from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
let PGlite;
try { ({PGlite} = await import('../../.community-pg-test/node_modules/@electric-sql/pglite/dist/index.js')); }
catch(error) { if(error.code !== 'ERR_MODULE_NOT_FOUND') throw error; }

test('larger package budget preserves usage, request caps, global cap and input bounds',{skip:!PGlite && 'Optional isolated .community-pg-test runtime is not installed'},async()=>{
 const db=new PGlite();try{
  await db.exec('CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;CREATE TABLE nikon_app_release_budgets(budget_key text PRIMARY KEY,requests bigint NOT NULL DEFAULT 0,bytes bigint NOT NULL DEFAULT 0,expires_at timestamptz NOT NULL);');
  const prior=await readFile(new URL('../database/017-app-release-capacity.sql',import.meta.url),'utf8');const start=prior.indexOf('CREATE OR REPLACE FUNCTION public.nikon_release_budget_atomic');await db.exec(prior.slice(start,prior.indexOf('END; $$;',start)+8));
  const key='a'.repeat(64),size=31292511;
  const budget=async(bytes=size)=>(await db.query('SELECT nikon_release_budget_atomic($1,$2,$3) AS value',[key,'download',bytes])).rows[0].value;
  assert.equal((await budget()).allowed,true);assert.equal((await budget()).allowed,true);assert.equal((await budget()).error,'BUDGET');
  const before=(await db.query('SELECT * FROM nikon_app_release_budgets ORDER BY budget_key')).rows;
  const migration=await readFile(new URL('../database/018-app-download-budget.sql',import.meta.url),'utf8');await db.exec(migration);await db.exec(migration);
  assert.deepEqual((await db.query('SELECT * FROM nikon_app_release_budgets ORDER BY budget_key')).rows,before,'migration must not reset existing usage');
  for(let i=0;i<6;i++)assert.equal((await budget()).allowed,true,'eight complete modern packages fit');
  assert.equal((await budget()).error,'BUDGET','ninth package exceeds source byte cap');
  await db.exec("UPDATE nikon_app_release_budgets SET requests=20,bytes=0 WHERE budget_key LIKE 'file:ip:%'");assert.equal((await budget()).error,'BUDGET','20 requests/hour remains enforced');
  await db.exec("UPDATE nikon_app_release_budgets SET requests=0,bytes=0;UPDATE nikon_app_release_budgets SET bytes=2147483648 WHERE budget_key LIKE 'file:global:%'");assert.equal((await budget()).error,'BUDGET','global daily cap remains enforced');
  assert.equal((await budget(33554433)).error,'INVALID','32MiB package bound remains enforced');
 }finally{await db.close();}
});
