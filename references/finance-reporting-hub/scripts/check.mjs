import { readFile, readdir } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateCatalog } from './catalog.mjs';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const catalog = validateCatalog(JSON.parse(await readFile(`${root}/data/catalog.example.json`, 'utf8')));
async function walk(dir) { const paths=[];for(const e of await readdir(dir,{withFileTypes:true})){const p=`${dir}/${e.name}`;if(e.isDirectory())paths.push(...await walk(p));else paths.push(p);}return paths; }
const htmlFiles=(await Promise.all(['demo','examples'].map(d=>walk(`${root}/${d}`)))).flat().filter(p=>p.endsWith('.html'));
let scripts=0;
for(const path of htmlFiles) {
  const html=await readFile(path,'utf8');
  if(!html.toLowerCase().includes('<!doctype html>'))throw new Error(`Missing doctype: ${path}`);
  for(const match of html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)) {
    if(match[1].includes('application/json'))JSON.parse(match[2]);else {new Function(match[2]);scripts++;}
  }
}
console.log(`Validated ${catalog.reports.length} draft catalog entries and ${scripts} scripts across ${htmlFiles.length} standalone HTML examples.`);
console.log('Static and syntax checks only. Real browser and Power BI/n8n deployment checks remain manual.');
