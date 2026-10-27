import {createServer} from 'node:http';
import {readFile,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {resolve,relative,extname,isAbsolute} from 'node:path';
const root=fileURLToPath(new URL('./',import.meta.url));
const types={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8','.png':'image/png','.json':'application/json; charset=utf-8','.md':'text/plain; charset=utf-8'};
const server=createServer(async(req,res)=>{
 try{
  const path=new URL(req.url,'http://127.0.0.1').pathname;
  const file=resolve(root,'.'+decodeURIComponent(path==='/'?'/prototype.html':path));
  const rel=relative(root,file);if(rel.startsWith('..')||isAbsolute(rel)){res.writeHead(403);res.end();return;}
  const data=await readFile(file);res.writeHead(200,{'Content-Type':types[extname(file)]||'application/octet-stream','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(req.method==='HEAD'?undefined:data);
 }catch{res.writeHead(404);res.end('Not found');}
});
await new Promise(done=>server.listen(Number(process.env.HUEVIA_PREVIEW_PORT||0),'127.0.0.1',done));
const url=`http://127.0.0.1:${server.address().port}/prototype.html`;
await writeFile(new URL('./PREVIEW-SERVER.json',import.meta.url),JSON.stringify({scope:'Task-owned loopback design preview only',pid:process.pid,url,started:new Date().toISOString()},null,2));
console.log(url);
