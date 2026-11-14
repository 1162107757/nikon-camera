import assert from 'node:assert/strict';
import test from 'node:test';
import { hashUserPassword, verifyPassword } from '../server/auth.mjs';

test('app passwords use only the existing 8–128 length bounds and retain whitespace', async () => {
  for (const password of ['12345678', 'abcdefgh', ' abcdefg ']) {
    const hash = await hashUserPassword(password);
    assert.equal(await verifyPassword(password, hash), true);
    if (password !== password.trim()) assert.equal(await verifyPassword(password.trim(), hash), false);
  }
  await assert.rejects(hashUserPassword('1234567'));
  await assert.rejects(hashUserPassword('a'.repeat(129)));
});
