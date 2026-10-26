// Checks every question file before it goes live.
// Run from the repository root:  node tools/validate.mjs
// Exits with code 1 if anything would break the game. Warnings are printed but don't fail.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.cwd();
const DAYS = join(ROOT, 'content', 'days');
const CATS = ['history', 'pop', 'geo', 'sports', 'news'];
const TIERS = ['easy', 'medium', 'hard'];
const TARGET = { news: 2, easy: 5, medium: 5, hard: 4 };
const METRIC = /\b(meters?|metres?|kilometers?|kilometres?|km|kg|kilograms?|grams?|liters?|litres?|centimeters?|cm|millimeters?|mm|hectares?|°c|celsius)\b/i;
const errors = [], warnings = [];
const seenIds = new Map(), seenText = new Map();
const now = new Date();
const today = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;

const norm = s => String(s).toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

function checkQ(q, where, isNews) {
  const at = `${where} "${String(q && q.q || '').slice(0, 60)}"`;
  if (!q || typeof q !== 'object') { errors.push(`${where}: not a question object`); return; }
  for (const k of ['id', 'cat', 'q', 'a', 'type', 'unit', 'fact']) {
    if (q[k] === undefined || q[k] === null || q[k] === '') errors.push(`${at}: missing "${k}"`);
  }
  if (q.id && !/^[a-z0-9_-]{3,40}$/i.test(q.id)) errors.push(`${at}: id must be letters, numbers, - or _`);
  if (q.cat && !CATS.includes(q.cat)) errors.push(`${at}: cat must be one of ${CATS.join(', ')}`);
  if (isNews && q.cat !== 'news') warnings.push(`${at}: news slot holds a "${q.cat}" question`);
  if (q.type && !['year', 'number'].includes(q.type)) errors.push(`${at}: type must be "year" or "number"`);
  if (typeof q.a !== 'number' || !Number.isFinite(q.a)) errors.push(`${at}: answer "a" must be a plain number, no quotes or commas`);
  else {
    if (!Number.isInteger(q.a)) errors.push(`${at}: answer must be a whole number`);
    if (q.a < 0) errors.push(`${at}: answer can't be negative`);
    if (q.type === 'year' && q.a > now.getFullYear() + 1) errors.push(`${at}: year ${q.a} is in the future`);
    if (q.a > 9999999) errors.push(`${at}: answer is too long for the input box (max 7 digits)`);
  }
  if (q.q && !/\?\s*$/.test(q.q)) warnings.push(`${at}: question should end with "?"`);
  if (q.q && q.q.length > 170) warnings.push(`${at}: question is long (${q.q.length} characters)`);
  if ((q.q && METRIC.test(q.q)) || (q.unit && METRIC.test(q.unit))) errors.push(`${at}: use U.S. units (feet, miles, pounds, °F)`);
  if (q.id) {
    if (seenIds.has(q.id)) errors.push(`${at}: id "${q.id}" is also used in ${seenIds.get(q.id)}`);
    else seenIds.set(q.id, where);
  }
  if (q.q) {
    const t = norm(q.q);
    if (seenText.has(t)) errors.push(`${at}: same question already in ${seenText.get(t)}`);
    else seenText.set(t, where);
  }
}

if (!existsSync(DAYS)) { console.error('content/days is missing. Run this from the repository root.'); process.exit(1); }
const files = readdirSync(DAYS).filter(f => f.endsWith('.json')).sort();
for (const f of files) {
  const where = `days/${f}`;
  let pack;
  try { pack = JSON.parse(readFileSync(join(DAYS, f), 'utf8')); }
  catch (e) { errors.push(`${where}: not valid JSON (${e.message})`); continue; }
  const date = f.replace(/\.json$/, '');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) errors.push(`${where}: file name must be YYYY-MM-DD.json`);
  if (pack.date !== date) errors.push(`${where}: "date" inside the file should be "${date}"`);
  if (!Array.isArray(pack.news)) errors.push(`${where}: "news" must be a list`);
  else {
    if (pack.news.length > 2) errors.push(`${where}: at most 2 news questions (tee shots on holes 1 and 2)`);
    if (pack.news.length < 2 && date >= today) warnings.push(`${where}: ${pack.news.length} of 2 news questions`);
    pack.news.forEach((q, i) => checkQ(q, `${where} news[${i}]`, true));
  }
  for (const t of TIERS) {
    if (!Array.isArray(pack[t])) { errors.push(`${where}: "${t}" must be a list`); continue; }
    if (pack[t].length < TARGET[t] && date >= today) warnings.push(`${where}: ${pack[t].length} ${t} questions (target ${TARGET[t]})`);
    pack[t].forEach((q, i) => checkQ(q, `${where} ${t}[${i}]`, false));
  }
}
const resPath = join(ROOT, 'content', 'reserve.json');
if (existsSync(resPath)) {
  let res;
  try { res = JSON.parse(readFileSync(resPath, 'utf8')); }
  catch (e) { errors.push(`reserve.json: not valid JSON (${e.message})`); }
  if (res) for (const t of TIERS) {
    if (!Array.isArray(res[t])) { errors.push(`reserve.json: "${t}" must be a list`); continue; }
    res[t].forEach((q, i) => checkQ(q, `reserve ${t}[${i}]`, false));
    if (res[t].length < 6) warnings.push(`reserve.json: only ${res[t].length} ${t} questions left in reserve`);
  }
} else warnings.push('content/reserve.json is missing');

const future = files.map(f => f.replace(/\.json$/, '')).filter(d => d >= today);
const ahead = future.length ? future[future.length - 1] : 'none';
console.log(`Checked ${files.length} days and the reserve: ${seenIds.size} questions. Questions are ready through ${ahead}.`);
warnings.forEach(w => console.log('  warning: ' + w));
if (errors.length) {
  errors.forEach(e => console.log('  ERROR: ' + e));
  console.log(`${errors.length} problem(s) to fix before this goes live.`);
  process.exit(1);
}
console.log('All good.');
