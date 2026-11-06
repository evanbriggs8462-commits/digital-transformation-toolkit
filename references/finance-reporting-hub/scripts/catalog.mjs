export function validateCatalog(catalog) {
  const fail = (message) => { throw new Error(message); };
  if (!catalog || typeof catalog !== 'object' || Array.isArray(catalog)) fail('Catalog must be an object');
  for (const key of ['title', 'intro']) if (typeof catalog[key] !== 'string' || !catalog[key].trim()) fail(`${key} must be a nonempty string`);
  if (!Array.isArray(catalog.reports) || !catalog.reports.length) fail('reports must be a nonempty array');
  if (catalog.filters && (!Array.isArray(catalog.filters) || catalog.filters.some(t => typeof t !== 'string' || !t.trim() || t === 'All'))) fail('filters must be nonempty topic strings, without the reserved All value');
  const ids = new Set();
  for (const report of catalog.reports) {
    if (!report || typeof report !== 'object') fail('Each report must be an object');
    if (typeof report.id !== 'string' || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(report.id)) fail('Each report needs a stable lowercase hyphenated id');
    if (ids.has(report.id)) fail(`Duplicate report id: ${report.id}`);
    ids.add(report.id);
    for (const key of ['title', 'summary', 'category']) if (typeof report[key] !== 'string' || !report[key].trim()) fail(`${report.id}: ${key} must be a nonempty string`);
    for (const key of ['topics', 'keyTabs']) if (!Array.isArray(report[key]) || report[key].some(v => typeof v !== 'string' || !v.trim())) fail(`${report.id}: ${key} must be an array of nonempty strings`);
    if (report.url !== null) {
      if (typeof report.url !== 'string') fail(`${report.id}: url must be HTTPS or null`);
      let url; try { url = new URL(report.url); } catch { fail(`${report.id}: invalid URL`); }
      if (url.protocol !== 'https:' || url.username || url.password) fail(`${report.id}: only absolute HTTPS URLs without embedded credentials are supported`);
    }
    if (report.descriptionStatus && !['draft', 'reviewed'].includes(report.descriptionStatus)) fail(`${report.id}: invalid descriptionStatus`);
  }
  return catalog;
}

// JSON is embedded in a non-executable script element. Escaping '<' prevents an
// arbitrary catalog string containing </script> from terminating that element.
export function serializeCatalog(catalog) {
  return JSON.stringify(validateCatalog(catalog)).replace(/</g, '\\u003c').replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
}
