import {readFile,writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.dirname(fileURLToPath(import.meta.url));
const [markup,css,app,photo]=await Promise.all(['index.html','style.css','app.js','photo.js'].map(file=>readFile(path.join(root,file),'utf8')));
// Function replacements preserve the source's literal $$ and $& sequences.
const output=markup
  .replace('<link rel="stylesheet" href="style.css">',()=>'<style>'+css+'</style>')
  .replace('<script src="photo.js" defer></script>','')
  .replace('<script src="app.js" defer></script>','')
  .replace('</body>',()=>'<script>'+(photo+'\n'+app).replace(/<\/script/gi,'<\\/script')+'</script>\n</body>');
await writeFile(path.join(root,'prototype.html'),output);
const scripts=[...output.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(match=>match[1]);
if(scripts.length!==1||/<script[^>]+src=/.test(output)||/<link[^>]+stylesheet/.test(output))throw new Error('Unexpected external runtime dependency');
await writeFile(path.join(root,'.impeccable/review/standalone-script.js'),scripts[0]);
console.log('Built offline prototype.html with literal source preserved.');
