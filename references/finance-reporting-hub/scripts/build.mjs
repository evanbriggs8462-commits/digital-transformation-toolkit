import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { serializeCatalog } from './catalog.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const input = resolve(process.argv[2] || `${root}/data/catalog.example.json`);
const output = resolve(process.argv[3] || `${root}/demo/index.html`);
const [template, source, css, app] = await Promise.all([
  readFile(`${root}/src/index.template.html`, 'utf8'), readFile(input, 'utf8'),
  readFile(`${root}/src/styles.css`, 'utf8'), readFile(`${root}/src/app.js`, 'utf8')
]);
const html = template.replace('/* HUB_STYLES */', () => css)
  .replace('CATALOG_JSON', () => serializeCatalog(JSON.parse(source)))
  .replace('/* HUB_SCRIPT */', () => app);
await mkdir(dirname(output), { recursive: true });
await writeFile(output, html);
console.log(`Built ${output}`);
