import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const base=path.dirname(fileURLToPath(import.meta.url));
const types={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8','.jpg':'image/jpeg','.png':'image/png','.json':'application/json; charset=utf-8','.md':'text/plain; charset=utf-8'};
const port=Number(process.env.HUEVIA_WAVE_PORT||8794);
http.createServer(async(req,res)=>{
 try{
  const route=decodeURIComponent(new URL(req.url,'http://127.0.0.1').pathname);
  const target=path.resolve(base,'.'+(route==='/'?'/index.html':route));
  if(!target.startsWith(base+path.sep)){res.writeHead(403);res.end();return;}
  const bytes=await fs.readFile(target);res.writeHead(200,{'content-type':types[path.extname(target)]||'application/octet-stream','cache-control':'no-store'});res.end(bytes);
 }catch{res.writeHead(404);res.end('Not found');}
}).listen(port,'127.0.0.1',()=>console.log('Huevia prototype http://127.0.0.1:'+port+'/'));
