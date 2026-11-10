// Environment-only change: append the requested admin origin; preserve every other variable and code.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { cloudApi, ENV_ID, FUNCTION_NAME } from './cloud-tools.mjs';
if (!process.argv.includes('--apply')) throw Error('Use --apply for the requested admin-origin change.');
const current = cloudApi('scf', 'GetFunction', { Namespace: ENV_ID, FunctionName: FUNCTION_NAME, ShowCode: 'FALSE' });
if (current.Status !== 'Active' || !Array.isArray(current.Environment?.Variables)) throw Error('Function is not ready.');
await mkdir(new URL('../.local/homepage-migration/', import.meta.url), { recursive: true });
const before = current.Environment.Variables;
const snapshot = new URL('../.local/homepage-migration/environment-before.json', import.meta.url);
try { await readFile(snapshot); } catch (error) { if (error.code !== 'ENOENT') throw error; await writeFile(snapshot, JSON.stringify({ environmentId: ENV_ID, variables: before }), { mode: 0o600 }); }
const next = before.map(variable => ({ ...variable }));
let entry = next.find(variable => variable.Key === 'ALLOWED_BROWSER_ORIGINS');
if (!entry) { entry = { Key: 'ALLOWED_BROWSER_ORIGINS', Value: '' }; next.push(entry); }
const origins = new Set(entry.Value.split(',').map(value => value.trim()).filter(Boolean));
origins.add('https://huevia.cc'); origins.add('https://admin.huevia.cc'); entry.Value = [...origins].join(',');
const stable = variables => JSON.stringify(variables.filter(variable => variable.Key !== 'ALLOWED_BROWSER_ORIGINS').sort((a, b) => a.Key.localeCompare(b.Key)));
const sha = value => createHash('sha256').update(value).digest('hex');
if (stable(before) !== stable(next)) throw Error('Unexpected environment change.');
if (JSON.stringify(before) !== JSON.stringify(next)) cloudApi('scf', 'UpdateFunctionConfiguration', { Namespace: ENV_ID, FunctionName: FUNCTION_NAME, Environment: { Variables: next } });
let result;
for (let n = 0; n < 30; n++) {
  result = cloudApi('scf', 'GetFunction', { Namespace: ENV_ID, FunctionName: FUNCTION_NAME, ShowCode: 'FALSE' });
  if (result.Status === 'Active') break;
  await new Promise(resolve => setTimeout(resolve, 3000));
}
if (result.Status !== 'Active' || stable(result.Environment.Variables) !== stable(before)
    || result.Environment.Variables.find(variable => variable.Key === entry.Key)?.Value !== entry.Value) throw Error('Environment verification incomplete.');
const report = { environmentId: ENV_ID, functionName: FUNCTION_NAME, status: result.Status, allowedBrowserOrigins: [...origins],
  unchangedOtherVariableCount: before.filter(variable => variable.Key !== entry.Key).length, unchangedOtherVariablesSha256: sha(stable(before)), codeRedeployed: false, verifiedAt: new Date().toISOString() };
await mkdir(new URL('../../docs/validation/homepage-20261107/', import.meta.url), { recursive: true });
await writeFile(new URL('../../docs/validation/homepage-20261107/admin-origin.json', import.meta.url), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report));
