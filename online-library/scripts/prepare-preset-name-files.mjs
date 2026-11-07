// Read-only source acquisition for the name migration; all bytes stay outside the APK.
import { readFile, writeFile, readdir, mkdir, unlink } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { createHash } from 'node:crypto';
import { validatePresetFile } from '../server/validation.mjs';
const directory=resolve(process.argv[2]||'');
const backup=JSON.parse(await readFile(join(directory,'before.json'),'utf8'));
const hash=b=>createHash('sha256').update(b).digest('hex');
const cached=new Map();
async function walk(p){for(const e of await readdir(p,{withFileTypes:true})){const f=join(p,e.name);if(e.isDirectory())await walk(f);else if(/\.(ncp|np3)$/i.test(e.name)){const b=await readFile(f);cached.set(hash(b),b);}}}
await walk(resolve('online-library/.local'));
await mkdir(join(directory,'files'),{recursive:true});
let index=0,downloaded=0;const summary=[];
async function worker(){while(index<backup.rows.length){const row=backup.rows[index++],file=row.published.file;
 let bytes=cached.get(file.sha256);
 if(!bytes){const url=new URL(file.url);if(url.origin!=='https://nikon-d8girdjsr252fd90e-1252602548.ap-shanghai.app.tcloudbase.com'||!url.pathname.startsWith('/preset-library/files/'))throw Error('Unexpected source');const r=await fetch(url,{signal:AbortSignal.timeout(45000)});if(!r.ok)throw Error('Source download failed');bytes=Buffer.from(await r.arrayBuffer());downloaded++;}
 if(bytes.length!==file.byteLength||hash(bytes)!==file.sha256)throw Error('Source identity mismatch');
 const format=validatePresetFile(bytes);const extension=format.extension;
 await writeFile(join(directory,'files',file.sha256+'.'+extension),bytes);
 // An earlier acquisition pass inferred an NP3 suffix from the shared NCP magic.
 // Remove only this run's identical, wrongly suffixed cache alias.
 if(extension==='np3'){const alias=join(directory,'files',file.sha256+'.ncp');try{if(hash(await readFile(alias))===file.sha256)await unlink(alias);}catch(e){if(e.code!=='ENOENT')throw e;}}
 if(extension==='ncp'&&bytes.length===638){const samples=Array.from({length:257},(_,i)=>bytes.readUInt16BE(120+i*2)/32767);summary.push({name:row.published.name,sha256:file.sha256,format,base:bytes.readUInt16BE(36),sharpening:bytes[40]-128,saturation:bytes[43]-128,hue:bytes[44]-128,filter:bytes[45],toning:bytes[46],gamma:bytes[62]+bytes[63]/100,shadows:samples[64],middle:samples[128],highlights:samples[192],contrast:(samples[192]-samples[64])/.5});}
}}
await Promise.all(Array.from({length:4},worker));
await writeFile(join(directory,'parameters.json'),JSON.stringify(summary.sort((a,b)=>a.name.localeCompare(b.name)),null,2));
console.log(JSON.stringify({checked:backup.rows.length,downloaded,legacyParameters:summary.length}));
