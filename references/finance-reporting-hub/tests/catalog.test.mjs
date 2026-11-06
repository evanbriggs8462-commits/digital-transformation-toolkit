import test from 'node:test';
import assert from 'node:assert/strict';
import { validateCatalog, serializeCatalog } from '../scripts/catalog.mjs';
const example = () => ({ title:'Hub', intro:'Find a report', reports:[{id:'report-a',title:'Example',summary:'Example report',category:'Revenue',topics:['Revenue'],keyTabs:[],url:null}] });
test('duplicate report identities are rejected', () => { const c=example(); c.reports.push({...c.reports[0]}); assert.throws(()=>validateCatalog(c), /Duplicate/); });
test('only absolute HTTPS report destinations are accepted', () => { for(const url of ['javascript:alert(1)','/report','http://example.com','https://user:password@example.com']) {const c=example();c.reports[0].url=url;assert.throws(()=>validateCatalog(c));} const c=example();c.reports[0].url='https://example.com/report';assert.equal(validateCatalog(c),c); });
test('catalog content cannot end its JSON script element', () => { const c=example();c.reports[0].summary='</script><script>alert(1)</script>';const text=serializeCatalog(c);assert.ok(!text.includes('<'));assert.deepEqual(JSON.parse(text),c); });
