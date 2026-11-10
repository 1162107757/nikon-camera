import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {mkdirSync,writeFileSync} from 'node:fs';
const privateDir=new URL('../.local/data-backup/',import.meta.url);
export function backupCloudApi(service,action,body){
  const run=spawnSync(process.execPath,[fileURLToPath(new URL('./tcb-api.mjs',import.meta.url)),service,action],
    {input:JSON.stringify(body),encoding:'utf8',windowsHide:true,maxBuffer:16*1024*1024,timeout:150000});
  const raw=String(run.stdout||'').replace(/\x1b\[[0-9;]*m/g,'');let parsed;
  try{parsed=JSON.parse(raw.slice(raw.indexOf('{')));}catch{}
  mkdirSync(privateDir,{recursive:true});
  writeFileSync(new URL('api-'+action+'-'+Date.now()+'.private.json',privateDir),JSON.stringify(parsed||{unparsed:true}));
  const data=parsed?.data||parsed?.Response||parsed;
  const failure=parsed?.error||data?.Error;
  if(run.status!==0||!data||failure){
    const providerCode=failure?.code||failure?.Code||'CLOUD_API_FAILED';
    const code=/^[A-Za-z0-9_.-]{1,160}$/.test(providerCode)?providerCode:'CLOUD_API_FAILED';
    throw Object.assign(new Error(action+' failed: '+code),{code});
  }
  return data;
}
