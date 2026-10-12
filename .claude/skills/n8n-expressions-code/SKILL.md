---
name: n8n-expressions-code
description: Write and debug n8n expressions and JavaScript Code nodes with correct JSON item shape, all-items versus per-item modes, item linkage, nullable fields, numeric validation, and timezone-aware dates. Use for n8n data transformations and expression errors.
---

# Inspect data before writing code

Read a sanitized input item, its types, the Code-node mode, and the expected output contract. Prefer an expression for one field and Edit Fields for straightforward mapping; use Code for transformations that require several coordinated steps. Load [references/quick-reference.md](references/quick-reference.md) for official sources and limits.

Represent workflow data explicitly as items:

```json
[{ "json": { "period": "2026-09", "bu": "Example BU", "closed": false } }]
```

Keep `json` an object. Preserve `binary` when returning a transformed item that must retain attachments. Use the actual inbound path: Webhook inputs often nest request data under `body`; inspect instead of assuming `$json.email`.

# Choose the intended reference

Use these in node parameter expressions:

```javascript
{{ $json.body?.period ?? null }}
{{ $json.owner?.email ?? '' }}
{{ $('Lookup owner').item.json.email }}
{{ $('Load settings').first().json.closeTimezone }}
{{ $('Load records').all().map(item => item.json.id) }}
{{ $now.toUTC().toISO() }}
```

Use `.item` for the upstream record linked to the current item. Use `.first()` only when a deliberate single shared value is intended; it does not repair missing linkage. Use `.all()` for explicit aggregation. Confirm a referenced branch executed before accessing it. In Code, write JavaScript directly without expression braces. For exported workflow JSON, expression-valued parameter strings normally begin with `=`; inspect the target node's expected parameter structure.

# Return the right shape and linkage

In **Run Once for All Items**, return an array. When creating new outputs, preserve each output's association with its source input index:

```javascript
return $input.all().map((item, index) => ({
  ...item,
  json: {
    ...item.json,
    bu: String(item.json.bu ?? '').trim(),
    status: item.json.closed === true ? 'closed' : 'pending',
  },
  pairedItem: { item: index },
}));
```

In **Run Once for Each Item**, return one item:

```javascript
const item = $input.item;
return {
  ...item,
  json: { ...item.json, bu: String(item.json.bu ?? '').trim() },
};
```

If filtering in all-items mode, retain each item's original input index when setting `pairedItem`; do not renumber survivors. If reducing many records to a KPI item, avoid pretending that the KPI has one unique ancestor. Use a documented many-input linkage or carry required group fields explicitly, and avoid ambiguous downstream `.item` references.

# Validate values and dates

Use `??` to default missing/null values while preserving `0` and `false`. Treat blank numeric strings as missing before conversion; `Number('')` gives zero. Check `Number.isFinite` and reject invalid business inputs rather than silently substituting zero. Normalize email with trim/lowercase only after obtaining identity from a trusted authenticated source.

Use Luxon `DateTime.fromISO` or `fromFormat`; check `.isValid`. For instants, require an offset or explicit source timezone and serialize UTC ISO timestamps. Preserve date-only business deadlines separately and compute the period in the agreed business timezone. Native `Date` does not follow the workflow timezone automatically.

Use HTTP Request for network calls. Do not assume filesystem access or npm imports inside Code: Cloud prohibits external npm imports; self-hosted modules require configuration. Test empty input, nulls, zero, false, multiple items, reordered joins, and invalid dates before publishing.
