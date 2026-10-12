from pathlib import Path
import json
import zipfile

root = Path(__file__).parent
template = (root / 'dashboard.html').read_text()
validator = r'''
// Run Once for All Items. Receives ONE object from a trusted preparation step.
// This renderer does not authenticate requests. Authenticate and filter rows upstream.
function renderDashboard(data) {
  if (!data || data.viewer?.authenticated !== true || !data.viewer?.id) {
    throw new Error('Verified viewer identity is required. Authenticate the request upstream.');
  }
  if (!Array.isArray(data.rows)) throw new Error('Expected a rows array of permitted closing records.');
  const timestamp = value => typeof value === 'string' && /(?:Z|[+-]\d{2}:\d{2})$/.test(value) && Number.isFinite(Date.parse(value));
  if (!timestamp(data.generatedAt)) throw new Error('generatedAt must be an ISO timestamp with timezone.');
  const known = new Set(), statuses = new Set(['open','closed','reopened']);
  const rows = data.rows.map((row, index) => {
    for (const key of ['id','period','bu','ou','entity','erp','status']) {
      if (typeof row[key] !== 'string' || !row[key].trim()) throw new Error(`Record ${index}: ${key} must be a nonempty string.`);
    }
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(row.period)) throw new Error(`Record ${index}: invalid close period.`);
    const uniqueKey = JSON.stringify([row.period, row.id]);
    if (known.has(uniqueKey)) throw new Error(`Duplicate closing item: ${row.period} / ${row.id}`);
    known.add(uniqueKey);
    if (!statuses.has(row.status)) throw new Error(`Record ${index}: unsupported status.`);
    if (typeof row.required !== 'boolean') throw new Error(`Record ${index}: required must be boolean.`);
    if (!timestamp(row.targetAt)) throw new Error(`Record ${index}: targetAt needs an ISO timestamp with timezone.`);
    if (row.status === 'closed' && !timestamp(row.closedAt)) throw new Error(`Record ${index}: closedAt required for closed items.`);
    return {
      id: row.id, period: row.period, bu: row.bu, ou: row.ou,
      entity: row.entity, erp: row.erp, status: row.status,
      required: row.required, targetAt: row.targetAt,
      closedAt: row.status === 'closed' ? row.closedAt : null,
      taskType: typeof row.taskType === 'string' ? row.taskType : 'Entity close',
      owner: typeof row.owner === 'string' ? row.owner : '',
      closedBy: row.status === 'closed' && typeof row.closedBy === 'string' ? row.closedBy : ''
    };
  });
  const secureURL = (value, label) => {
    if (!value) return null;
    try { const u = new URL(value); if (u.protocol === 'https:' && !u.username && !u.password) return u.href; } catch {}
    throw new Error(`${label} must be an absolute HTTPS URL without embedded credentials.`);
  };
  const timeZone = data.timeZone || 'UTC';
  try { new Intl.DateTimeFormat('en-US',{timeZone}).format(); } catch { throw new Error('Invalid IANA timezone.'); }
  const clean = {
    mode: 'live', generatedAt: data.generatedAt, timeZone,
    defaultPeriod: data.defaultPeriod,
    dashboardUrl: secureURL(data.dashboardUrl, 'dashboardUrl'),
    formUrl: secureURL(data.formUrl, 'formUrl'),
    viewer: {name: String(data.viewer.name || 'Authorized viewer'), scopeLabel: String(data.viewer.scopeLabel || 'Viewing permitted scope')},
    rows
  };
  // JSON is embedded as inert script text; escape characters that can break out of it.
  const safeJSON = JSON.stringify(clean).replace(/</g,'\\u003c').replace(/>/g,'\\u003e').replace(/&/g,'\\u0026').replace(/\u2028/g,'\\u2028').replace(/\u2029/g,'\\u2029');
  return DASHBOARD_TEMPLATE.replace('<script id="closing-data" type="application/json">{"mode":"demo"}</script>', () => '<script id="closing-data" type="application/json">' + safeJSON + '</script>');
}
const data = $input.first().json;
return [{json: {html: renderDashboard(data)}}];
'''
# The generated file is standalone JavaScript; n8n needs no filesystem access.
(root / 'n8n-render-dashboard.code.js').write_text(
    'const DASHBOARD_TEMPLATE = ' + json.dumps(template, ensure_ascii=True) + ';\n' + validator
)
payload = {
    'generatedAt': '2026-10-06T15:30:00Z',
    'defaultPeriod': '2026-09', 'timeZone': 'America/New_York',
    'dashboardUrl': 'https://YOUR-INSTANCE.app.n8n.cloud/webhook/closing-dashboard',
    'formUrl': 'https://YOUR-INSTANCE.app.n8n.cloud/form/YOUR-CLOSING-FORM',
    'viewer': {'authenticated': True, 'id': 'EXAMPLE-VERIFIED-SUBJECT', 'name': 'Example controller', 'scopeLabel': 'Optical Connectivity · permitted OUs'},
    'rows': [
      {'id':'2026-09-US10-10301067-entity', 'period':'2026-09','bu':'Optical Connectivity','ou':'10301067','entity':'Hickory · NC Engineering Services','erp':'SAP · US10','taskType':'Entity close','required':True,'status':'closed','targetAt':'2026-10-05T19:00:00Z','closedAt':'2026-10-05T16:00:00Z','owner':'Plant controller','closedBy':'Example authorized controller'},
      {'id':'2026-09-MX10-10271193-entity','period':'2026-09','bu':'Optical Connectivity','ou':'10271193','entity':'Corning Optical Communications','erp':'SAP · MX10','taskType':'Entity close','required':True,'status':'open','targetAt':'2026-10-05T18:00:00Z','closedAt':None,'owner':'Plant controller'},
      {'id':'2026-09-TASK-revenue','period':'2026-09','bu':'Optical Connectivity','ou':'COC-JE','entity':'Commercial Revenue Entries','erp':'COC TASK','taskType':'Finance task','required':True,'status':'reopened','targetAt':'2026-10-06T16:00:00Z','closedAt':None,'owner':'Corporate finance'}
    ]
}
if not (root/'sample-payload.json').exists():
    (root/'sample-payload.json').write_text(json.dumps(payload, indent=2))
archive = root.parent / 'Closing_Dashboard_n8n.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for p in sorted(root.rglob('*')):
        if p.is_file():
            z.write(p, 'closing-dashboard/' + str(p.relative_to(root)))
print(archive)
