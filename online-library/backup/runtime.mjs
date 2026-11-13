import COS from '../server/vendor/cos-sdk.cjs';
import {createHash,timingSafeEqual} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PREFIX,safePath,runBackup,pruneOldBackups} from './core.mjs';

const ENVIRONMENT='nikon-d8girdjsr252fd90e';
const REGION='ap-shanghai',BUCKET='huevia-updates-1252602548';
const ORIGIN=`https://${ENVIRONMENT}.api.tcloudbasegateway.com`;
const unavailable=code=>Object.assign(new Error(code),{code});
export function invocationAction(event,token){
  if(event?.Type!=='Timer'||event?.TriggerName!=='huevia-daily-backup'||typeof token!=='string'||!/^[a-f0-9]{64}$/.test(token)
    ||typeof event.Message!=='string'||event.Message.length>512)throw unavailable('BACKUP_INVOCATION_DENIED');
  let message;try{message=JSON.parse(event.Message);}catch{throw unavailable('BACKUP_INVOCATION_DENIED');}
  if(typeof message.token!=='string'||message.token.length>128||!['backup','status','diagnose'].includes(message.action)
    ||!timingSafeEqual(createHash('sha256').update(token).digest(),createHash('sha256').update(message.token).digest()))throw unavailable('BACKUP_INVOCATION_DENIED');
  return message.action;
}
export function credentialsForInvocation(context){
  // CloudBase serializes the refreshed context environment in newer Node runtimes.
  // See TencentCloudBase/node-sdk CloudBase.parseContext; never fall back to
  // cold-start process.env credentials when the instance is reused tomorrow.
  let environment={};
  if(typeof context?.environment==='string'){
    try{environment=JSON.parse(context.environment);}catch{throw unavailable('INVALID_BACKUP_CONTEXT');}
  }else if(typeof context?.environ==='string'){
    for(const item of context.environ.split(';')){const i=item.indexOf('=');if(i>0)environment[item.slice(0,i)]=item.slice(i+1);}
  }
  if(!environment||typeof environment!=='object'||Array.isArray(environment))throw unavailable('INVALID_BACKUP_CONTEXT');
  const refreshed={...context,...environment};
  const values=['TENCENTCLOUD_SECRETID','TENCENTCLOUD_SECRETKEY','TENCENTCLOUD_SESSIONTOKEN'].map(key=>refreshed[key]);
  if(!values.every(x=>typeof x==='string'&&x.length>0&&x.length<4096))throw unavailable('BACKUP_ROLE_CREDENTIALS_REQUIRED');
  return {SecretId:values[0],SecretKey:values[1],SecurityToken:values[2]};
}
export async function readBounded(response,maximum){
  if(!response.ok)throw unavailable('SOURCE_REQUEST_FAILED');
  const declared=response.headers.get('content-length');let count=0;const chunks=[];
  if(declared!==null&&(!/^\d+$/.test(declared)||Number(declared)>maximum))throw unavailable('SOURCE_TOO_LARGE');
  try{for await(const part of response.body){count+=part.length;if(count>maximum)throw unavailable('SOURCE_TOO_LARGE');chunks.push(part);}}
  finally{try{if(!response.body?.locked)await response.body?.cancel();}catch{}}
  if(declared!==null&&!response.headers.get('content-encoding')&&Number(declared)!==count)throw unavailable('SOURCE_TRUNCATED');
  return Buffer.concat(chunks,count);
}
export function cloudbaseReader(serviceKey,fetchImpl=fetch){
  if(typeof serviceKey!=='string'||serviceKey.length<20)throw unavailable('BACKUP_DATABASE_CREDENTIAL_REQUIRED');
  async function request(path,{method='GET',body,maximum=64*1024*1024}={}){
    const response=await fetchImpl(ORIGIN+path,{method,body,headers:{Authorization:'Bearer '+serviceKey,'Content-Type':'application/json'},
      redirect:'error',signal:AbortSignal.timeout(60000)});
    return readBounded(response,maximum);
  }
  return {
    snapshot:()=>request('/v1/rdb/rest/rpc/nikon_backup_snapshot',{method:'POST',body:'{}'}),
    get:item=>request('/v1/storages/object/authenticated/nikon-presets/'+safePath(item.path).split('/').map(encodeURIComponent).join('/'),{maximum:item.size})
  };
}
export function cosStorage(client){
  const call=(name,params)=>new Promise((resolve,reject)=>client[name]({Bucket:BUCKET,Region:REGION,...params},(error,result)=>error?reject(unavailable('COS_'+name.toUpperCase()+'_FAILED')):resolve(result)));
  const own=key=>{if(!key.startsWith(PREFIX)||!/^huevia-backups\/daily\/\d{4}-\d{2}-\d{2}\/[a-zA-Z0-9-]+\//.test(key))throw unavailable('OUTSIDE_BACKUP_PREFIX');return key;};
  async function get(Key,maximum,source=false){
    if(source){if(!/^huevia-updates\/(?:app-releases\/[a-f0-9]{64}\.(?:apk|bin)|mobile-releases\/(?:ios|android)\/[a-f0-9]{64}\.bin)$/.test(Key))throw unavailable('INVALID_COS_SOURCE');}else own(Key);
    const result=await call('getObject',{Key,DataType:'buffer',Range:'bytes=0-'+maximum});const bytes=Buffer.isBuffer(result.Body)?result.Body:Buffer.from(result.Body);
    if(bytes.length>maximum)throw unavailable('COS_OBJECT_TOO_LARGE');return bytes;
  }
  return {
    put:(key,data,type)=>call('putObject',{Key:own(key),Body:data,ContentLength:data.length,ContentType:type,CacheControl:'no-store',
      ContentMD5:createHash('md5').update(data).digest('base64'),Headers:{'x-cos-server-side-encryption':'AES256','x-cos-forbid-overwrite':'true'}}),
    get:(key,max)=>get(key,max),
    sourceGet:item=>get('huevia-updates/'+safePath(item.path),item.size,true),
    async list(prefix,marker){if(prefix!==PREFIX)throw unavailable('INVALID_LIST_PREFIX');const page=await call('getBucket',{Prefix:prefix,Marker:marker,MaxKeys:1000});
      const truncated=page.IsTruncated===true||page.IsTruncated==='true';if(truncated&&(!page.NextMarker||page.NextMarker===marker))throw unavailable('INVALID_LIST_CURSOR');
      return {keys:(page.Contents||[]).map(x=>x.Key),next:truncated?page.NextMarker:null};},
    remove:key=>call('deleteObject',{Key:own(key)})
  };
}
export async function main(event,context){
  // An event function has no public HTTP route. IAM invocation is still required.
  const action=invocationAction(event,process.env.BACKUP_TRIGGER_TOKEN);
  if(action==='diagnose')return {contextType:typeof context,contextKeys:Object.keys(context||{}),nestedKeys:Object.fromEntries(Object.entries(context||{}).filter(([,v])=>v&&typeof v==='object').map(([k,v])=>[k,Object.keys(v).slice(0,30)])),environmentCredentialNames:['TENCENTCLOUD_SECRETID','TENCENTCLOUD_SECRETKEY','TENCENTCLOUD_SESSIONTOKEN'].filter(k=>!!process.env[k])};
  const client=new COS({...credentialsForInvocation(context),Protocol:'https:',AutoSwitchHost:false,Timeout:60000});
  const storage=cosStorage(client);
  if(action==='status'){
    const keys=[];let cursor;do{const page=await storage.list(PREFIX,cursor);keys.push(...page.keys.filter(key=>key.endsWith('/COMPLETE.json')));cursor=page.next;}while(cursor);
    const key=keys.sort().at(-1);if(!key)return {complete:false};
    const manifest=JSON.parse((await storage.get(key,2*1024*1024)).toString('utf8'));
    if(!manifest.complete||key!==manifest.run+'COMPLETE.json')throw unavailable('INVALID_COMPLETED_MANIFEST');
    return {complete:true,manifest:key,files:manifest.files.length,databaseSha256:manifest.database.sha256,tables:Object.keys(manifest.database.tableCounts).length,completedAt:manifest.completedAt};
  }
  const cloudbase=cloudbaseReader(process.env.CLOUDBASE_SERVICE_KEY);
  const log=value=>console.log(JSON.stringify(value));
  try{
    const snapshotBytes=await cloudbase.snapshot();
    const recoveryFiles=await Promise.all(['schema-migrations.sql','RECOVERY.md'].map(async name=>({name,bytes:await readFile(new URL('./recovery/'+name,import.meta.url))})));
    const result=await runBackup({snapshotBytes,storage,recoveryFiles,source:{get:item=>item.provider==='cos'?storage.sourceGet(item):cloudbase.get(item)},log});
    const removed=await pruneOldBackups(storage,result);log({event:'backup-retention',removed});
    return {complete:true,manifest:result.run+'COMPLETE.json',tables:Object.keys(result.database.tableCounts).length,files:result.files.length};
  }catch(error){const code=/^[A-Z0-9_]{1,80}$/.test(error?.code||'')?error.code:'BACKUP_FAILED';log({event:'backup-failed',code});throw unavailable(code);}
}
