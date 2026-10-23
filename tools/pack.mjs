#!/usr/bin/env node
// Packs the tg-ai-agent skill.
//
//   node tools/pack.mjs [--src <skill dir>] [--out <output dir>]
//
// Output directory (default `build/skill/` under the current directory, which
// is git-ignored):
//   tg-ai-agent-<version>.tar.gz   the skill: SKILL.md, scripts/, references/, SHA256SUMS
//   install.sh, install.ps1        the installers, shipped NEXT TO the archive (not inside:
//                                  SHA256SUMS describes the skill directory, and
//                                  `tgai self-check` verifies the installed directory)
//
// The archive is byte-for-byte reproducible: entries sorted by path bytes
// (as `LC_ALL=C sort`), mtime 0, uid/gid 0, no user names, fixed modes
// (0755 for scripts/tgai.mjs, 0644 for the rest), fixed gzip header. Every
// entry sits under `tg-ai-agent/`.
//
// SHA256SUMS: lines `<hex64>␣␣<path relative to the skill directory>\n`, as
// `sha256sum` prints them; paths in byte order; without SHA256SUMS itself and
// without install/. It is the format `tgai self-check` expects.
//
// Byte-for-byte reproducibility holds for one zlib: the compressed bytes can
// differ between Node.js versions (the content of the tar never does). Pack a
// release with one Node.js version and hand out that very file.
//
// No dependencies: node:fs, node:path, node:crypto, node:zlib only.

import { createHash } from 'node:crypto';
import {
  chmodSync,
  copyFileSync,
  existsSync,
  lstatSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';

const SKILL_NAME = 'tg-ai-agent';
const SUMS_NAME = 'SHA256SUMS';
const TOP_FILES = ['SKILL.md'];
const TOP_DIRS = ['scripts', 'references'];
const EXECUTABLE = new Set(['scripts/tgai.mjs']);
const PATH_COMPONENT = /^[A-Za-z0-9_][A-Za-z0-9._-]*$/;
const MAX_NAME_BYTES = 100; // ustar `name` field, no `prefix` is used
const GZIP_OS_UNIX = 3;

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '..');

class PackError extends Error {}

function fail(message) {
  throw new PackError(message);
}

function parseArgs(argv) {
  const args = {
    src: join(repoRoot, SKILL_NAME),
    out: resolve('build', 'skill'),
  };
  for (let i = 0; i < argv.length; i += 2) {
    const flag = argv[i];
    const value = argv[i + 1];
    if ((flag !== '--src' && flag !== '--out') || value === undefined) {
      fail(
        'usage: pack.mjs [--src <skill directory>] [--out <output directory>]',
      );
    }
    args[flag.slice(2)] = resolve(value);
  }
  return args;
}

/** Byte-order comparison of UTF-8 strings (as `LC_ALL=C sort`). */
const byBytes = (a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b));

/** Collects the regular files of one top-level directory; anything else is an error. */
function walk(root, rel, out) {
  for (const name of readdirSync(join(root, rel)).sort(byBytes)) {
    const path = `${rel}/${name}`;
    if (!PATH_COMPONENT.test(name)) {
      fail(`unsafe file name in the skill directory: ${JSON.stringify(path)}`);
    }
    const st = lstatSync(join(root, path));
    if (st.isDirectory()) walk(root, path, out);
    else if (st.isFile()) out.push(path);
    else fail(`not a regular file or directory (link, socket?): ${path}`);
  }
}

/** The whitelisted files of the skill directory, sorted by path bytes. */
function collectFiles(src) {
  const top = readdirSync(src);
  for (const name of top) {
    if (name === SUMS_NAME || name === 'install') continue;
    if (!TOP_FILES.includes(name) && !TOP_DIRS.includes(name)) {
      fail(
        `unexpected entry in the skill directory: ${name} ` +
          `(allowed: ${[...TOP_FILES, ...TOP_DIRS].join(', ')}, install/, ${SUMS_NAME})`,
      );
    }
  }
  const files = [];
  for (const name of TOP_FILES) {
    if (!top.includes(name)) fail(`missing ${name}`);
    if (!lstatSync(join(src, name)).isFile())
      fail(`${name} is not a regular file`);
    files.push(name);
  }
  for (const name of TOP_DIRS) {
    if (!top.includes(name)) fail(`missing ${name}/`);
    if (!lstatSync(join(src, name)).isDirectory())
      fail(`${name} is not a directory`);
    walk(src, name, files);
  }
  if (!files.includes('scripts/tgai.mjs')) fail('missing scripts/tgai.mjs');
  for (const path of files) {
    if (Buffer.byteLength(`${SKILL_NAME}/${path}`) > MAX_NAME_BYTES) {
      fail(`path is too long: ${path}`);
    }
  }
  return files.sort(byBytes);
}

/** metadata.version of SKILL.md, checked against SKILL_VERSION of the script. */
function releaseVersion(skillMd, script) {
  const fm = /^---\n([\s\S]*?)\n---\n/.exec(skillMd);
  const m = fm && /^[ \t]+version:\s*"?(\d+\.\d+\.\d+)"?\s*$/m.exec(fm[1]);
  if (m === null || m === undefined)
    fail('SKILL.md has no metadata.version (x.y.z)');
  const c = /^const SKILL_VERSION = '(\d+\.\d+\.\d+)';$/m.exec(script);
  if (c === null)
    fail("scripts/tgai.mjs has no `const SKILL_VERSION = 'x.y.z';`");
  if (c[1] !== m[1]) {
    fail(
      `SKILL.md metadata.version ${m[1]} differs from SKILL_VERSION ${c[1]} in scripts/tgai.mjs`,
    );
  }
  return m[1];
}

function sumsText(entries) {
  return entries
    .map(
      (e) =>
        `${createHash('sha256').update(e.data).digest('hex')}  ${e.path}\n`,
    )
    .join('');
}

function octal(value, width) {
  return value.toString(8).padStart(width - 1, '0') + '\0';
}

function ustarHeader(name, size, mode) {
  const h = Buffer.alloc(512, 0);
  h.write(name, 0, 'utf8');
  h.write(octal(mode, 8), 100, 'ascii');
  h.write(octal(0, 8), 108, 'ascii'); // uid
  h.write(octal(0, 8), 116, 'ascii'); // gid
  h.write(octal(size, 12), 124, 'ascii');
  h.write(octal(0, 12), 136, 'ascii'); // mtime
  h.fill(0x20, 148, 156); // checksum counted as spaces
  h.write('0', 156, 'ascii'); // regular file
  h.write('ustar\0', 257, 'ascii');
  h.write('00', 263, 'ascii');
  let sum = 0;
  for (const b of h) sum += b;
  h.write(`${sum.toString(8).padStart(6, '0')}\0 `, 148, 'ascii');
  return h;
}

function tar(entries) {
  const parts = [];
  for (const e of entries) {
    parts.push(ustarHeader(`${SKILL_NAME}/${e.path}`, e.data.length, e.mode));
    parts.push(e.data);
    const pad = (512 - (e.data.length % 512)) % 512;
    if (pad > 0) parts.push(Buffer.alloc(pad, 0));
  }
  parts.push(Buffer.alloc(1024, 0));
  return Buffer.concat(parts);
}

function pack({ src, out }) {
  if (!existsSync(src) || !lstatSync(src).isDirectory()) {
    fail(`the skill directory does not exist: ${src}`);
  }
  const files = collectFiles(src);
  const entries = files.map((path) => ({
    path,
    data: readFileSync(join(src, path)),
    mode: EXECUTABLE.has(path) ? 0o755 : 0o644,
  }));
  const script = entries.find((e) => e.path === 'scripts/tgai.mjs');
  const skillMd = entries.find((e) => e.path === 'SKILL.md');
  const version = releaseVersion(
    skillMd.data.toString('utf8'),
    script.data.toString('utf8'),
  );
  const installers = ['install.sh', 'install.ps1'];
  for (const name of installers) {
    const p = join(src, 'install', name);
    if (!existsSync(p) || !lstatSync(p).isFile())
      fail(`missing install/${name}`);
  }

  // SHA256SUMS comes from the same bytes that go into the archive.
  const sums = Buffer.from(sumsText(entries));
  const all = [...entries, { path: SUMS_NAME, data: sums, mode: 0o644 }].sort(
    (a, b) => byBytes(a.path, b.path),
  );
  const gz = gzipSync(tar(all), { level: 9 });
  gz[9] = GZIP_OS_UNIX; // the OS byte of the header depends on the platform

  mkdirSync(out, { recursive: true });
  const archiveName = `${SKILL_NAME}-${version}.tar.gz`;
  const archive = join(out, archiveName);
  const tmp = join(out, `.${archiveName}.${process.pid}.tmp`);
  writeFileSync(tmp, gz);
  renameSync(tmp, archive);
  // Archives of other versions would make the installer ask which one to take.
  for (const name of readdirSync(out)) {
    if (
      name !== archiveName &&
      /^tg-ai-agent-\d+\.\d+\.\d+\.tar\.gz$/.test(name)
    ) {
      rmSync(join(out, name));
    }
  }
  for (const name of installers) {
    const target = join(out, name);
    copyFileSync(join(src, 'install', name), target);
    chmodSync(target, name.endsWith('.sh') ? 0o755 : 0o644);
  }
  return {
    archive,
    version,
    sha256: createHash('sha256').update(gz).digest('hex'),
    files: all.map((e) => e.path),
    installers: installers.map((n) => join(out, n)),
  };
}

try {
  const result = pack(parseArgs(process.argv.slice(2)));
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
} catch (e) {
  if (e instanceof PackError) {
    process.stderr.write(`skill:pack: ${e.message}\n`);
    process.exit(1);
  }
  throw e;
}
