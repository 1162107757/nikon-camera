import {createHash,randomUUID} from 'node:crypto';
import {gzipSync,gunzipSync} from 'node:zlib';

export const PREFIX='huevia-backups/daily/';
export const digest=b=>createHash('sha256').update(b).digest('hex');
const failure=code=>Object.assign(new Error(code),{code});
const shanghaiDay=date=>new Date(+date+8*3600000).toISOString().slice(0,10);
export function safePath(value){
  if(typeof value!=='string'||!value.length||value.length>1024||value.startsWith('/')||value.includes('\\')
    ||value.split('/').some(s=>!s||s==='.'||s==='..')||/[\x00-\x1f\x7f]/.test(value))throw failure('INVALID_SOURCE_PATH');
  return value;
}
export function inspectSnapshot(bytes){
  if(!Buffer.isBuffer(bytes)||bytes.length<10||bytes.length>64*1024*1024)throw failure('INVALID_SNAPSHOT_SIZE');
  const s=JSON.parse(bytes.toString('utf8'));
  if(s.format!=='huevia-data-backup-v1'||!s.tables||!Array.isArray(s.columns)||!Array.isArray(s.functions)
    ||!Number.isFinite(Date.parse(s.capturedAt)))throw failure('INVALID_SNAPSHOT');
  for(const [name,rows] of Object.entries(s.tables))if(!/^(?:public\.nikon_[a-z0-9_]+|storage\.(?:buckets|objects))$/.test(name)||!Array.isArray(rows))throw failure('INVALID_SNAPSHOT_TABLE');
  for(const name of ['public.nikon_presets','public.nikon_users','public.nikon_app_releases','storage.objects','storage.buckets'])if(!s.tables[name])throw failure('INCOMPLETE_SNAPSHOT');
  const bucket=s.tables['storage.buckets'].find(b=>b.id==='nikon-presets');
  if(!bucket||bucket.public!==false)throw failure('SOURCE_BUCKET_NOT_PRIVATE');
  const sources=[];
  for(const object of s.tables['storage.objects']){
    if(object.bucket_id!=='nikon-presets')throw failure('UNEXPECTED_SOURCE_BUCKET');
    const size=Number(object.metadata?.size);
    if(!Number.isSafeInteger(size)||size<1||size>96*1024*1024)throw failure('INVALID_SOURCE_SIZE');
    sources.push({provider:'cloudbase',path:safePath(object.name),size});
  }
  for(const release of s.tables['public.nikon_app_releases']){
    const path=safePath(release.storage_path),size=Number(release.byte_length);
    if(!/^[a-f0-9]{64}$/.test(release.sha256)||!new RegExp('^app-releases/'+release.sha256+'\\.(apk|bin)$').test(path)
      ||!Number.isSafeInteger(size)||size<1||size>32*1024*1024)throw failure('INVALID_RELEASE');
    sources.push({provider:'cos',path,size,sha256:release.sha256});
  }
  for(const release of s.tables['public.nikon_mobile_releases']||[]){
    const path=safePath(release.storage_path),size=Number(release.byte_length);
    if(!['ios','android'].includes(release.platform)||!/^[a-f0-9]{64}$/.test(release.sha256)
      ||path!==`mobile-releases/${release.platform}/${release.sha256}.bin`
      ||!Number.isSafeInteger(size)||size<1024||size>128*1024*1024)throw failure('INVALID_MOBILE_RELEASE');
    sources.push({provider:'cos',path,size,sha256:release.sha256});
  }
  // Unfinished upload chunks are temporary transport data, not recoverable releases.
  // Their DB state remains in the dump, but is explicitly excluded from the durable-file contract.
  const seen=new Map();for(const source of sources){const key=source.provider+':'+source.path;const prior=seen.get(key);if(prior&&JSON.stringify(prior)!==JSON.stringify(source))throw failure('CONFLICTING_SOURCE');seen.set(key,source);}
  return {snapshot:s,sources:[...seen.values()],tableCounts:Object.fromEntries(Object.entries(s.tables).map(([name,rows])=>[name,rows.length]))};
}
export async function mapBounded(items,concurrency,operation){
  let next=0,error;const results=new Array(items.length);
  await Promise.all(Array.from({length:Math.min(concurrency,items.length)},async()=>{while(!error){const i=next++;if(i>=items.length)return;try{results[i]=await operation(items[i],i);}catch(e){error=e;}}}));
  if(error)throw error;return results;
}
export async function runBackup({snapshotBytes,storage,source,recoveryFiles=[],now=new Date(),id=randomUUID(),log=()=>{}}){
  if(!/^[a-f0-9-]{36}$/.test(id)||!Number.isFinite(+now))throw failure('INVALID_RUN');
  const {snapshot,sources,tableCounts}=inspectSnapshot(snapshotBytes);
  const run=PREFIX+shanghaiDay(now)+'/'+now.toISOString().replace(/[:.]/g,'-')+'-'+id+'/';
  const packed=gzipSync(snapshotBytes,{level:9});
  const dbKey=run+'database.json.gz';await storage.put(dbKey,packed,'application/gzip');
  const back=await storage.get(dbKey,packed.length);if(!back.equals(packed)||!gunzipSync(back).equals(snapshotBytes))throw failure('DATABASE_READBACK_MISMATCH');
  const recovery=[];
  for(const file of recoveryFiles){
    if(!/^[a-zA-Z0-9-]+\.(?:sql|md)$/.test(file.name)||!Buffer.isBuffer(file.bytes)||file.bytes.length>4*1024*1024)throw failure('INVALID_RECOVERY_FILE');
    const key=run+'recovery/'+file.name;await storage.put(key,file.bytes,'application/octet-stream');
    if(!(await storage.get(key,file.bytes.length)).equals(file.bytes))throw failure('RECOVERY_READBACK_MISMATCH');
    recovery.push({key,bytes:file.bytes.length,sha256:digest(file.bytes)});
  }
  let reserved=0;const waiters=[];const budget=128*1024*1024;
  async function reserve(size){const weight=Math.min(budget,Math.max(1,size*3));while(reserved+weight>budget)await new Promise(resolve=>waiters.push(resolve));reserved+=weight;return ()=>{reserved-=weight;for(const done of waiters.splice(0))done();};}
  const files=await mapBounded(sources,3,async(item,index)=>{
    const release=await reserve(item.size);try{
    const bytes=await source.get(item);if(bytes.length!==item.size)throw failure('SOURCE_LENGTH_MISMATCH');
    const hash=digest(bytes);if(item.sha256&&hash!==item.sha256)throw failure('SOURCE_HASH_MISMATCH');
    const key=run+'files/'+item.provider+'/'+digest(Buffer.from(item.path));
    await storage.put(key,bytes,'application/octet-stream');
    const copy=await storage.get(key,item.size);if(copy.length!==item.size||digest(copy)!==hash)throw failure('FILE_READBACK_MISMATCH');
    if(index%50===0)log({event:'backup-progress',completed:index+1,total:sources.length});
    return {...item,key,sha256:hash};
    }finally{release();}
  });
  const manifest={format:'huevia-backup-manifest-v1',complete:true,run,capturedAt:snapshot.capturedAt,completedAt:new Date().toISOString(),
    database:{key:dbKey,bytes:packed.length,sha256:digest(packed),uncompressedSha256:digest(snapshotBytes),tableCounts},files,recovery,
    excluded:['COS in-progress app-upload and mobile-upload chunks','CloudBase platform auth/storage migrations and multipart internals','Cloud service keys and cloud provider account configuration'],
    retentionDays:30};
  const manifestBytes=Buffer.from(JSON.stringify(manifest));const key=run+'COMPLETE.json';await storage.put(key,manifestBytes,'application/json');
  if(!(await storage.get(key,manifestBytes.length)).equals(manifestBytes))throw failure('MANIFEST_READBACK_MISMATCH');
  log({event:'backup-complete',run,tables:Object.keys(tableCounts).length,files:files.length,bytes:packed.length+files.reduce((n,f)=>n+f.size,0)});
  return manifest;
}

export async function pruneOldBackups(storage,complete,now=new Date()){
  if(!complete?.complete||!complete.run.startsWith(PREFIX)||!Number.isFinite(+now))throw failure('NO_COMPLETED_BACKUP');
  // Only our date-prefixed backup keys; never APKs, source data, or another prefix.
  const cutoff=shanghaiDay(new Date(+now-30*86400000));let marker;let removed=0;
  do{const page=await storage.list(PREFIX,marker);for(const key of page.keys){
    const match=/^huevia-backups\/daily\/(\d{4}-\d{2}-\d{2})\//.exec(key);
    if(!match)throw failure('UNSAFE_RETENTION_KEY');
    if(match[1]<cutoff&&!key.startsWith(complete.run)){await storage.remove(key);removed++;}
  }marker=page.next;}while(marker);
  return removed;
}
