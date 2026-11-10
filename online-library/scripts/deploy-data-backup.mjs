// No long-lived Tencent CAM key is created. Run only after the dedicated role's
// narrow policies and existing service-credential reuse have been authorized.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash,randomBytes} from 'node:crypto';
import {executeSql,sqlRows,ENV_ID,FUNCTION_NAME} from './cloud-tools.mjs';
import {backupCloudApi as cloudApi} from './data-backup-cloud.mjs';

const name='huevia-data-backup',trigger='huevia-daily-backup';
const root=new URL('../',import.meta.url),local=new URL('.local/data-backup/',root);
const flags=new Set(process.argv.slice(2));
const one=[...flags].filter(x=>['--deploy','--configure','--run-once','--status','--diagnose','--enable-timer'].includes(x));
if(one.length!==1)throw Error('Choose exactly one backup deployment action');
await mkdir(local,{recursive:true});
const params={Namespace:ENV_ID,FunctionName:name};
if(flags.has('--deploy')){
  if(!flags.has('--allow-existing-service-credential'))throw Error('Existing service credential reuse must first be authorized');
  const existing=cloudApi('scf','ListFunctions',{Namespace:ENV_ID,Limit:100,SearchKey:name});
  if(existing.Functions?.some(x=>x.FunctionName===name))throw Error('Backup function already exists; inspect it before any update');
  const original=cloudApi('scf','GetFunction',{Namespace:ENV_ID,FunctionName:FUNCTION_NAME,ShowCode:'FALSE'});
  if(original.Status!=='Active'||original.Role!=='HueviaUpdatePackageRole')throw Error('Existing application state changed');
  const key=original.Environment?.Variables?.find(x=>x.Key==='CLOUDBASE_SERVICE_KEY')?.Value;
  if(!key)throw Error('Existing private service credential missing');
  const archive=await readFile(new URL('build/data-backup/worker.zip',root));
  const manifest=JSON.parse(await readFile(new URL('build/data-backup/manifest.json',root),'utf8'));
  if(createHash('sha256').update(archive).digest('hex')!==manifest.sha256)throw Error('Reviewed backup worker package changed');
  await writeFile(new URL('original-function.private.json',local),JSON.stringify(original));
  const dispatchToken=randomBytes(32).toString('hex');
  // CloudBase supplies its own namespace stamp; direct SCF CreateFunction is rejected.
  // Stage without the database credential, then bind/verify the dedicated role.
  const result=cloudApi('tcb','CreateFunction',{EnvId:ENV_ID,FunctionName:name,Code:{ZipFile:archive.toString('base64')},
    Type:'Event',Handler:'index.main_handler',Runtime:'Nodejs20.19',MemorySize:512,Timeout:900,InitTimeout:30,
    Role:'HueviaDataBackupRole',Description:'Huevia private daily database and file backups, thirty day retention',
    ClsLogsetId:original.ClsLogsetId,ClsTopicId:original.ClsTopicId,AutoCreateClsTopic:'FALSE',
    Environment:{Variables:[{Key:'BACKUP_TRIGGER_TOKEN',Value:dispatchToken},{Key:'TZ',Value:'Asia/Shanghai'}]}});
  await writeFile(new URL('created.json',local),JSON.stringify({requestId:result.RequestId,packageSha256:manifest.sha256,createdAt:new Date().toISOString()}));
  console.log('Dedicated worker staged without database credential; no timer enabled. Configure the verified role next.');
}else{
  const worker=cloudApi('scf','GetFunction',{...params,ShowCode:'FALSE'});
  if(worker.Status!=='Active')throw Error('Dedicated worker not ready');
  if(flags.has('--configure')){
    if(!flags.has('--allow-existing-service-credential'))throw Error('Existing credential reuse must first be authorized');
    const original=cloudApi('scf','GetFunction',{Namespace:ENV_ID,FunctionName:FUNCTION_NAME,ShowCode:'FALSE'});
    const key=original.Environment?.Variables?.find(x=>x.Key==='CLOUDBASE_SERVICE_KEY')?.Value;
    const dispatchToken=worker.Environment?.Variables?.find(x=>x.Key==='BACKUP_TRIGGER_TOKEN')?.Value;
    if(!key||!/^[a-f0-9]{64}$/.test(dispatchToken||''))throw Error('Reviewed private configuration missing');
    cloudApi('scf','UpdateFunctionConfiguration',{...params,Role:'HueviaDataBackupRole',MemorySize:512,Timeout:900,
      ClsLogsetId:original.ClsLogsetId,ClsTopicId:original.ClsTopicId,
      Environment:{Variables:[{Key:'CLOUDBASE_SERVICE_KEY',Value:key},{Key:'BACKUP_TRIGGER_TOKEN',Value:dispatchToken},{Key:'TZ',Value:'Asia/Shanghai'}]}});
    console.log('Dedicated backup role and private configuration applied; timer remains disabled.');
    process.exit(0);
  }
  if(worker.Role!=='HueviaDataBackupRole')throw Error('Dedicated backup role not verified');
  const dispatchToken=worker.Environment?.Variables?.find(x=>x.Key==='BACKUP_TRIGGER_TOKEN')?.Value;
  if(!/^[a-f0-9]{64}$/.test(dispatchToken||''))throw Error('Private backup dispatch token missing');
  const event=action=>JSON.stringify({Type:'Timer',TriggerName:trigger,Message:JSON.stringify({action,token:dispatchToken})});
  if(flags.has('--run-once')){
    // The migration only exposes a read-only, service_role-only snapshot function.
    const sql=await readFile(new URL('database/021-data-backup.sql',root),'utf8');executeSql('BEGIN;\n'+sql+"\nNOTIFY pgrst, 'reload schema';\nCOMMIT;");
    const access=sqlRows(executeSql("SELECT has_function_privilege('anon','public.nikon_backup_snapshot()','execute') AS anon,has_function_privilege('authenticated','public.nikon_backup_snapshot()','execute') AS authenticated,has_function_privilege('service_role','public.nikon_backup_snapshot()','execute') AS service"));
    if(access[0]?.anon!==false||access[0]?.authenticated!==false||access[0]?.service!==true)throw Error('Snapshot RPC grants are not the reviewed service-only grants');
    const result=cloudApi('scf','Invoke',{...params,InvocationType:'Event',ClientContext:event('backup')});
    console.log(JSON.stringify({accepted:true,requestId:result.RequestId}));
  }else if(flags.has('--status')||flags.has('--diagnose')){
    const result=cloudApi('scf','Invoke',{...params,InvocationType:'RequestResponse',ClientContext:event(flags.has('--diagnose')?'diagnose':'status')});
    const status=JSON.parse(result.Result?.RetMsg||'null');if(!status||status.errorCode||result.Result?.FunctionError)throw Error('Backup status probe failed');
    if(flags.has('--diagnose')){console.log(JSON.stringify(status));process.exit(0);}
    await writeFile(new URL('last-status.json',local),JSON.stringify(status,null,2));console.log(JSON.stringify(status));
  }else{
    const proof=JSON.parse(await readFile(new URL('last-status.json',local),'utf8'));
    if(!proof.complete||!proof.manifest?.startsWith('huevia-backups/daily/'))throw Error('No verified completed backup; timer remains disabled');
    const result=cloudApi('scf','CreateTrigger',{...params,TriggerName:trigger,Type:'timer',TriggerDesc:'0 0 3 * * * *',
      Qualifier:'$LATEST',Enable:'OPEN',CustomArgument:JSON.stringify({action:'backup',token:dispatchToken}),Description:'Daily Huevia backup, Beijing03:00, thirty day private retention'});
    console.log(JSON.stringify({enabled:true,trigger:result.TriggerInfo?.TriggerName,description:result.TriggerInfo?.TriggerDesc}));
  }
}
