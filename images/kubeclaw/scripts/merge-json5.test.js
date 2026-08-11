#!/usr/bin/env node
'use strict';

// Tests for merge-json5.js, which implements JSON Merge Patch (RFC 7386).
//
// The case that matters most is a `null` tombstone landing under a key the base
// does not have. render-skills-config.js emits `entries.<skill>: null` to mean
// "forget this skill", and RFC 7386 says null means delete, never a literal
// value. If a null ever survives into openclaw.json the gateway refuses to
// start ("skills.entries.<name>: Invalid input") and the tenant is down until
// something rewrites the config.
//
// Run: node images/kubeclaw/scripts/merge-json5.test.js

const assert = require('assert');
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const SCRIPT = path.join(__dirname, 'merge-json5.js');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'merge-json5-'));

function merge(base, patch) {
  const basePath = path.join(tmp, 'base.json');
  const patchPath = path.join(tmp, 'patch.json');
  fs.writeFileSync(basePath, typeof base === 'string' ? base : JSON.stringify(base));
  fs.writeFileSync(patchPath, JSON.stringify(patch));
  return JSON.parse(execFileSync('node', [SCRIPT, basePath, patchPath], { encoding: 'utf8' }));
}

let failures = 0;
function test(name, fn) {
  try {
    fn();
    console.log('ok   - ' + name);
  } catch (err) {
    failures += 1;
    console.error('FAIL - ' + name);
    console.error('       ' + err.message.split('\n')[0]);
  }
}

// --- the regression -------------------------------------------------------

test('strips null tombstones when the base LACKS the parent key', () => {
  // Exactly the shape that took the gateway down: the provisioner's desired
  // config has no top-level `skills`, and the skills patch tombstones the seven
  // platform-engineering skills that skillStacks=false had just removed.
  const out = merge(
    { gateway: { x: 1 } },
    {
      skills: {
        load: { watch: true },
        entries: {
          'cicd-pipelines': null,
          'k8s-troubleshooting': null,
          'terraform-iac': null,
        },
      },
    }
  );
  assert.deepStrictEqual(out.skills.entries, {}, 'tombstones must not survive');
  assert.strictEqual(out.skills.load.watch, true, 'real values must survive');
  assert.strictEqual(out.gateway.x, 1, 'untouched base keys must survive');
});

test('strips null tombstones when the base HAS the parent key', () => {
  const out = merge(
    { skills: { entries: { 'keep-me': { enabled: true } } } },
    { skills: { entries: { 'drop-me': null } } }
  );
  assert.deepStrictEqual(out.skills.entries, { 'keep-me': { enabled: true } });
});

test('null deletes an existing key', () => {
  const out = merge({ a: 1, b: 2 }, { b: null });
  assert.deepStrictEqual(out, { a: 1 });
});

test('null under a non-object base value does not survive', () => {
  // Base has a scalar where the patch has an object. RFC 7386: replace the
  // scalar with {} then apply, which drops nulls.
  const out = merge({ skills: 'nonsense' }, { skills: { entries: { gone: null } } });
  assert.deepStrictEqual(out.skills.entries, {});
});

test('nested tombstones are stripped at every depth', () => {
  const out = merge({}, { a: { b: { c: null, d: 1 } } });
  assert.deepStrictEqual(out, { a: { b: { d: 1 } } });
});

// --- ordinary merge behaviour must not regress ----------------------------

test('deep merge preserves sibling keys', () => {
  const out = merge({ a: { x: 1, y: 2 } }, { a: { y: 3, z: 4 } });
  assert.deepStrictEqual(out, { a: { x: 1, y: 3, z: 4 } });
});

test('arrays are replaced wholesale, not merged', () => {
  const out = merge({ list: [1, 2, 3] }, { list: [9] });
  assert.deepStrictEqual(out.list, [9]);
});

test('an array value containing no nulls is untouched', () => {
  const out = merge({}, { extraDirs: ['/vaults'] });
  assert.deepStrictEqual(out.extraDirs, ['/vaults']);
});

test('JSON5 input is accepted', () => {
  // json5 ships at /opt/kubeclaw/deps inside the image and is usually absent on
  // a dev machine. Skip rather than fail, so this suite stays runnable in both
  // places; the image itself is where the JSON5 path actually matters.
  try {
    require.resolve('json5');
  } catch (_) {
    console.log('     (skipped: json5 not installed outside the image)');
    return;
  }
  const out = merge('{ /* comment */ a: 1, }', { b: 2 });
  assert.deepStrictEqual(out, { a: 1, b: 2 });
});

fs.rmSync(tmp, { recursive: true, force: true });

if (failures > 0) {
  console.error('\n' + failures + ' test(s) failed');
  process.exit(1);
}
console.log('\nall tests passed');
