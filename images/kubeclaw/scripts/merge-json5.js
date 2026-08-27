#!/usr/bin/env node
'use strict';

const fs = require('fs');

function tryParse(text) {
  try {
    return JSON.parse(text);
  } catch (_) {}

  let JSON5;
  try {
    JSON5 = require('json5');
  } catch (_) {
    try {
      JSON5 = require('/opt/kubeclaw/deps/node_modules/json5');
    } catch (err) {
      throw new Error(
        'Failed to parse input as strict JSON, and JSON5 parser is unavailable. ' +
          'Install json5 or provide valid JSON.'
      );
    }
  }

  return JSON5.parse(text);
}

const isPlainObject = (value) =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

// JSON Merge Patch, RFC 7386.
//
// The subtle part is what happens when the patch has an object at a key the
// TARGET does not have. This previously assigned the patch subtree wholesale,
// which quietly carried `null` tombstones into the output instead of treating
// them as deletions. That is not cosmetic: render-skills-config.js emits
// `skills.entries.<name>: null` to mean "forget this skill", and the tenant
// config has no top-level `skills` key at all, so every tombstone landed in
// openclaw.json as a literal null. The gateway then refused to start with
// "skills.entries.<name>: Invalid input" and the tenant stayed down until
// something else rewrote the config.
//
// RFC 7386 handles this by replacing a non-object target with {} and RECURSING
// rather than assigning. Recursion is what strips the nulls, so it must happen
// even when there is nothing in the target to merge into.
function mergePatch(base, patch) {
  // A non-object patch (scalar, array, or null) replaces the target outright.
  // Arrays are values, not merge targets.
  if (!isPlainObject(patch)) {
    return patch;
  }

  const result = isPlainObject(base) ? Object.assign({}, base) : {};

  for (const [key, value] of Object.entries(patch)) {
    if (value === null) {
      delete result[key];
    } else {
      result[key] = mergePatch(result[key], value);
    }
  }

  return result;
}

const [, , baseFile, patchFile] = process.argv;
if (!baseFile || !patchFile) {
  console.error('Usage: merge-json5.js <base-file> <patch-file>');
  process.exit(1);
}

const base = tryParse(fs.readFileSync(baseFile, 'utf8'));
const patch = tryParse(fs.readFileSync(patchFile, 'utf8'));

const merged = mergePatch(base, patch);
process.stdout.write(JSON.stringify(merged, null, 2) + '\n');
