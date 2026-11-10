import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {createHash} from 'node:crypto';
import {createHandler} from '../server/app.mjs';
import {renderReleaseDownloadError} from '../server/release-download-error.mjs';
import {ReleaseMemoryStore} from './release-memory-store.mjs';

test('browser download errors render HTML without changing API errors or successful signed downloads',async t=>{
  const store=new ReleaseMemoryStore(),data=Buffer.from('synthetic signed-download payload'),id='12345678-1234-4234-8234-123456789abc';
  const sha=createHash('sha256').update(data).digest('hex');
  const row={id,status:'published',sha256:sha,byte_length:data.length,storage_path:`app-releases/${sha}.bin`,version_code:156,channel:'beta'};store.releaseRows.push(row);
  const handler=createHandler({store,storage:{preferSignedDownloads:true,get:async()=>data,signDownload:async()=>`https://download.huevia.cc/fixture.apk?synthetic=1`},publicBaseUrl:'http://127.0.0.1',environmentId:'fixture',secureCookies:false});
  const server=createServer(handler);await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));t.after(()=>{server.closeAllConnections();server.close();});
  const url=`http://127.0.0.1:${server.address().port}/preset-library/releases/${id}/file`;
  store.releaseBudgetDenied=true;
  let response=await fetch(url,{headers:{Accept:'text/html,application/xhtml+xml'}});
  assert.equal(response.status,429);assert.match(response.headers.get('content-type'),/^text\/html/);assert.equal(response.headers.get('content-disposition'),null);
  let body=await response.text();assert.match(body,/返回下载页/);assert.match(body,/当前未下载安装包/);assert.match(body,/href="\/preset-library\/download\/\?channel=beta"/);
  response=await fetch(url,{headers:{Accept:'application/json'}});assert.equal(response.status,429);assert.match(response.headers.get('content-type'),/application\/json/);assert.equal((await response.json()).error.code,'RELEASE_BUDGET');
  response=await fetch(url,{headers:{Accept:'*/*'}});assert.match(response.headers.get('content-type'),/application\/json/);
  row.status='withdrawn';response=await fetch(url,{headers:{Accept:'text/html'}});assert.equal(response.status,404);assert.match(response.headers.get('content-type'),/text\/html/);
  row.status='published';store.releaseBudgetDenied=false;response=await fetch(url,{redirect:'manual',headers:{Accept:'text/html'}});assert.equal(response.status,307);assert.equal(response.headers.get('location'),'https://download.huevia.cc/fixture.apk?synthetic=1');
});

test('download error page escapes text and does not render for metadata, POST or HTML-excluding clients',()=>{
  let page='',headers;const res={writeHead(status,value){headers=value;},end(value){page=value;}};
  const req={method:'GET',url:'/preset-library/releases/12345678-1234-4234-8234-123456789abc/file',headers:{accept:'text/html'}};
  assert.equal(renderReleaseDownloadError(req,res,{status:503,message:'<script>alert("x")</script>'}),true);assert.ok(!page.includes('<script>'));assert.match(page,/&lt;script&gt;/);assert.equal(headers['Cache-Control'],'no-store');
  assert.equal(renderReleaseDownloadError({...req,url:'/preset-library/releases/latest'},res,{status:429,message:'no'}),false);
  assert.equal(renderReleaseDownloadError({...req,method:'POST'},res,{status:429,message:'no'}),false);
  assert.equal(renderReleaseDownloadError({...req,headers:{accept:'application/json,text/html;q=0'}},res,{status:429,message:'no'}),false);
});
