// Rebuild from pinned official npm packages installed in the isolated build tool directory.
import { createRequire } from 'node:module';
import { readFile, writeFile, mkdir, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
const modules = new URL('../../.tooling/cos-runtime/node_modules/', import.meta.url);
const require = createRequire(new URL('package.json', modules));
const { build, version: builderVersion } = require('esbuild');
const sdkPackage = JSON.parse(await readFile(new URL('cos-nodejs-sdk-v5/package.json', modules), 'utf8'));
if (sdkPackage.version !== '3.0.0' || builderVersion !== '0.28.2') throw Error('Pinned COS build dependencies required.');
const output = new URL('../server/vendor/', import.meta.url); await mkdir(output, { recursive: true });
await build({ entryPoints: [fileURLToPath(new URL('cos-nodejs-sdk-v5/index.js', modules))], outfile: fileURLToPath(new URL('cos-sdk.cjs', output)),
  platform: 'node', target: 'node20', format: 'cjs', bundle: true, minify: true, legalComments: 'eof', logLevel: 'silent' });
const packages = [], notices = [];
async function visit(dir) {
  for (const file of await readdir(dir, { withFileTypes: true })) {
    if (!file.isDirectory() || file.name.startsWith('.')) continue;
    const folder = new URL(file.name + '/', dir);
    if (file.name.startsWith('@')) { await visit(folder); continue; }
    let p; try { p = JSON.parse(await readFile(new URL('package.json', folder), 'utf8')); } catch { continue; }
    if (p.name === 'esbuild' || p.name.startsWith('@esbuild/')) continue;
    packages.push({ name: p.name, version: p.version, license: p.license });
    for (const name of await readdir(folder)) if (/^(?:licen[sc]e|copying|notice)(?:\..*)?$/i.test(name)) {
      try { notices.push(`\n===== ${p.name}@${p.version} / ${name} =====\n` + await readFile(new URL(name, folder), 'utf8')); } catch {}
    }
  }
}
await visit(modules);
const bytes = await readFile(new URL('cos-sdk.cjs', output));
await writeFile(new URL('COS-NOTICES.txt', output), notices.join('\n'));
await writeFile(new URL('cos-sdk.manifest.json', output), JSON.stringify({ sdk: 'cos-nodejs-sdk-v5', version: sdkPackage.version, builder: 'esbuild@' + builderVersion,
  source: 'https://www.npmjs.com/package/cos-nodejs-sdk-v5/v/3.0.0', npmIntegrity: 'sha512-xUqiDdUxfEjfaWoyBA3qsSnlQVHPz13DRFErL+NliadBVUeeZhAPHGVa2inGpUvPTOs52ALIKkMbzL+inSqvXg==',
  sha256: createHash('sha256').update(bytes).digest('hex'), bytes: bytes.length, packages }, null, 2) + '\n');
console.log(JSON.stringify({ sdk: sdkPackage.version, bytes: bytes.length, notices: notices.length }));
