-- Digital Transformation Brain SQLite registry
-- Compatible with SQLite 3.35+ and FTS5-enabled builds.

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;

CREATE TABLE IF NOT EXISTS artifacts (
    artifact_id TEXT PRIMARY KEY,
    sha256 TEXT NOT NULL UNIQUE,
    artifact_type TEXT NOT NULL,
    project TEXT,
    domain_json TEXT NOT NULL DEFAULT '[]',
    size_bytes INTEGER,
    modified_at TEXT,
    syntax_status TEXT NOT NULL DEFAULT 'unknown'
      CHECK (syntax_status IN ('unknown','passed','failed','not-applicable')),
    trust_state TEXT NOT NULL DEFAULT 'RAW'
      CHECK (trust_state IN (
        'RAW','PARSED','LIKELY_USEFUL','NEEDS_CONTEXT','BROKEN','RUNNABLE',
        'VERIFIED','PROMOTION_CANDIDATE','PROMOTED','SUPERSEDED','ARCHIVED',
        'RESTRICTED_SECRET'
      )),
    scope_type TEXT NOT NULL DEFAULT 'project',
    scope_value TEXT,
    sensitivity TEXT NOT NULL DEFAULT 'internal'
      CHECK (sensitivity IN ('public','internal','confidential','secret-excluded')),
    shareable INTEGER NOT NULL DEFAULT 0 CHECK (shareable IN (0,1)),
    contains_result_data INTEGER NOT NULL DEFAULT 0 CHECK (contains_result_data IN (0,1)),
    summary TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS artifact_paths (
    path_id INTEGER PRIMARY KEY AUTOINCREMENT,
    artifact_id TEXT NOT NULL REFERENCES artifacts(artifact_id) ON DELETE CASCADE,
    canonical_path TEXT NOT NULL,
    source_root TEXT,
    first_seen_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_current INTEGER NOT NULL DEFAULT 1 CHECK (is_current IN (0,1)),
    UNIQUE (artifact_id, canonical_path)
);

CREATE TABLE IF NOT EXISTS version_families (
    family_id TEXT PRIMARY KEY,
    normalized_name TEXT,
    preferred_artifact_id TEXT REFERENCES artifacts(artifact_id),
    rationale TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS artifact_versions (
    family_id TEXT NOT NULL REFERENCES version_families(family_id) ON DELETE CASCADE,
    artifact_id TEXT NOT NULL REFERENCES artifacts(artifact_id) ON DELETE CASCADE,
    inferred_order INTEGER,
    relationship TEXT CHECK (relationship IN (
      'duplicate','near-duplicate','predecessor','successor','superseded','unknown'
    )),
    evidence_json TEXT NOT NULL DEFAULT '[]',
    PRIMARY KEY (family_id, artifact_id)
);

CREATE TABLE IF NOT EXISTS sessions (
    session_id TEXT PRIMARY KEY,
    project TEXT,
    title TEXT,
    started_at TEXT,
    ended_at TEXT,
    model_aliases_json TEXT NOT NULL DEFAULT '[]',
    raw_export_path TEXT,
    summary TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS session_facts (
    fact_id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
    fact_type TEXT NOT NULL CHECK (fact_type IN (
      'USER_CLAIM','ASSISTANT_CLAIM','COMMAND_EVIDENCE','FILE_EVIDENCE',
      'VALIDATION_EVIDENCE','LATER_SUCCESSFUL_USE'
    )),
    summary TEXT NOT NULL,
    artifact_ids_json TEXT NOT NULL DEFAULT '[]',
    objects_json TEXT NOT NULL DEFAULT '[]',
    filters_json TEXT NOT NULL DEFAULT '{}',
    command_text TEXT,
    exit_code INTEGER,
    observed_at TEXT,
    source_offset TEXT
);

CREATE TABLE IF NOT EXISTS execution_evidence (
    evidence_id TEXT PRIMARY KEY,
    artifact_id TEXT REFERENCES artifacts(artifact_id),
    session_id TEXT REFERENCES sessions(session_id),
    tool TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN (
      'passed','failed','timed-out','blocked','unknown'
    )),
    exit_code INTEGER,
    started_at TEXT,
    finished_at TEXT,
    duration_ms INTEGER CHECK (duration_ms IS NULL OR duration_ms >= 0),
    output_artifacts_json TEXT NOT NULL DEFAULT '[]',
    validation_json TEXT NOT NULL DEFAULT '[]',
    control_totals_json TEXT NOT NULL DEFAULT '{}',
    error_summary TEXT,
    provenance_json TEXT NOT NULL DEFAULT '[]'
);

CREATE TABLE IF NOT EXISTS business_rules (
    rule_id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    claim TEXT NOT NULL,
    systems_json TEXT NOT NULL DEFAULT '[]',
    business_process TEXT,
    scope_type TEXT NOT NULL,
    scope_value TEXT,
    sensitivity TEXT NOT NULL DEFAULT 'internal',
    validation_state TEXT NOT NULL CHECK (validation_state IN (
      'hypothesis','observed','partially-validated','validated','conflicted','retired'
    )),
    filters_json TEXT NOT NULL DEFAULT '{}',
    assumptions_json TEXT NOT NULL DEFAULT '[]',
    exceptions_json TEXT NOT NULL DEFAULT '[]',
    conflicts_json TEXT NOT NULL DEFAULT '[]',
    related_objects_json TEXT NOT NULL DEFAULT '[]',
    permitted_use_json TEXT NOT NULL DEFAULT '[]',
    evidence_json TEXT NOT NULL DEFAULT '[]',
    provenance_json TEXT NOT NULL DEFAULT '[]',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS object_references (
    reference_id INTEGER PRIMARY KEY AUTOINCREMENT,
    owner_type TEXT NOT NULL CHECK (owner_type IN (
      'artifact','session-fact','business-rule','report-profile','recipe','observation'
    )),
    owner_id TEXT NOT NULL,
    system TEXT NOT NULL,
    object_type TEXT NOT NULL,
    object_name TEXT NOT NULL,
    catalog_name TEXT,
    schema_name TEXT,
    confidence TEXT,
    provenance_json TEXT NOT NULL DEFAULT '[]'
);

CREATE INDEX IF NOT EXISTS ix_object_references_lookup
ON object_references(system, object_type, object_name);

CREATE TABLE IF NOT EXISTS report_profiles (
    profile_id TEXT PRIMARY KEY,
    report_family TEXT NOT NULL,
    pbix_names_json TEXT NOT NULL DEFAULT '[]',
    semantic_model_ids_json TEXT NOT NULL DEFAULT '[]',
    measures_json TEXT NOT NULL DEFAULT '[]',
    dimensions_json TEXT NOT NULL DEFAULT '[]',
    relationships_json TEXT NOT NULL DEFAULT '[]',
    source_mapping_ids_json TEXT NOT NULL DEFAULT '[]',
    known_questions_json TEXT NOT NULL DEFAULT '[]',
    unresolved_context_json TEXT NOT NULL DEFAULT '[]',
    trust_state TEXT NOT NULL DEFAULT 'RAW',
    scope_json TEXT NOT NULL DEFAULT '{}',
    provenance_json TEXT NOT NULL DEFAULT '[]',
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS source_mappings (
    mapping_id TEXT PRIMARY KEY,
    semantic_object TEXT NOT NULL,
    source_type TEXT NOT NULL CHECK (source_type IN (
      'uc-table','uc-view','native-query','file','api','unknown'
    )),
    catalog_name TEXT,
    schema_name TEXT,
    object_name TEXT,
    warehouse_path TEXT,
    m_steps_json TEXT NOT NULL DEFAULT '[]',
    confidence TEXT NOT NULL CHECK (confidence IN (
      'exact_m_navigation','native_query_parsed','parameter_resolved',
      'probable_from_name','unresolved_dynamic_expression'
    )),
    validation_state TEXT NOT NULL CHECK (validation_state IN (
      'historical','live-validated','stale','superseded','unknown'
    )),
    provenance_json TEXT NOT NULL DEFAULT '[]',
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS relationships (
    relationship_id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_type TEXT NOT NULL,
    from_id TEXT NOT NULL,
    relation_type TEXT NOT NULL,
    to_type TEXT NOT NULL,
    to_id TEXT NOT NULL,
    confidence REAL,
    evidence_json TEXT NOT NULL DEFAULT '[]',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (from_type, from_id, relation_type, to_type, to_id)
);

CREATE INDEX IF NOT EXISTS ix_relationships_from
ON relationships(from_type, from_id, relation_type);

CREATE INDEX IF NOT EXISTS ix_relationships_to
ON relationships(to_type, to_id, relation_type);

CREATE TABLE IF NOT EXISTS observations (
    observation_id TEXT PRIMARY KEY,
    source TEXT NOT NULL,
    observed_at TEXT NOT NULL,
    object_type TEXT NOT NULL,
    object_id TEXT NOT NULL,
    snapshot_id TEXT,
    previous_observation_id TEXT REFERENCES observations(observation_id),
    change_status TEXT NOT NULL DEFAULT 'unknown'
      CHECK (change_status IN ('new','unchanged','modified','missing','unknown')),
    payload_json TEXT NOT NULL DEFAULT '{}',
    provenance_json TEXT NOT NULL DEFAULT '[]'
);

CREATE INDEX IF NOT EXISTS ix_observations_object_time
ON observations(source, object_type, object_id, observed_at DESC);

CREATE TABLE IF NOT EXISTS recipes (
    recipe_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    recipe_type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft'
      CHECK (status IN ('draft','tested','verified','promoted','retired')),
    task_intent TEXT NOT NULL,
    required_capabilities_json TEXT NOT NULL DEFAULT '[]',
    steps_json TEXT NOT NULL DEFAULT '[]',
    completion_rule TEXT NOT NULL,
    prohibited_completion TEXT,
    scope_json TEXT NOT NULL DEFAULT '{}',
    evidence_json TEXT NOT NULL DEFAULT '[]',
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS reconciliation_profiles (
    profile_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    powerbi_json TEXT NOT NULL,
    source_json TEXT NOT NULL,
    filters_json TEXT NOT NULL DEFAULT '{}',
    dimensions_json TEXT NOT NULL DEFAULT '[]',
    tolerance_absolute REAL NOT NULL,
    tolerance_percent REAL NOT NULL,
    drill_order_json TEXT NOT NULL DEFAULT '[]',
    validation_state TEXT NOT NULL DEFAULT 'draft'
      CHECK (validation_state IN ('draft','tested','verified','promoted')),
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS trust_assignments (
    assignment_id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_type TEXT NOT NULL,
    record_id TEXT NOT NULL,
    trust_state TEXT NOT NULL,
    score INTEGER CHECK (score IS NULL OR (score >= 0 AND score <= 100)),
    positive_components_json TEXT NOT NULL DEFAULT '[]',
    negative_components_json TEXT NOT NULL DEFAULT '[]',
    evidence_json TEXT NOT NULL DEFAULT '[]',
    assigned_by TEXT NOT NULL,
    assigned_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS ix_trust_assignments_record
ON trust_assignments(record_type, record_id, assigned_at DESC);

CREATE TABLE IF NOT EXISTS secret_exclusions (
    exclusion_id INTEGER PRIMARY KEY AUTOINCREMENT,
    canonical_path TEXT NOT NULL,
    secret_category TEXT NOT NULL,
    redacted_fingerprint TEXT NOT NULL,
    detected_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    exclusion_status TEXT NOT NULL DEFAULT 'excluded',
    UNIQUE (canonical_path, secret_category, redacted_fingerprint)
);

CREATE TABLE IF NOT EXISTS model_usage (
    usage_id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id TEXT NOT NULL,
    model_alias TEXT NOT NULL,
    task_type TEXT NOT NULL,
    artifact_count INTEGER NOT NULL DEFAULT 0,
    input_tokens INTEGER,
    output_tokens INTEGER,
    reported_cost REAL,
    latency_ms INTEGER,
    success INTEGER CHECK (success IS NULL OR success IN (0,1)),
    notes TEXT,
    recorded_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS retrieval_log (
    retrieval_id TEXT PRIMARY KEY,
    query_text TEXT NOT NULL,
    method TEXT NOT NULL CHECK (method IN (
      'exact','metadata','fts','relationship','vector','hybrid'
    )),
    filters_json TEXT NOT NULL DEFAULT '{}',
    result_ids_json TEXT NOT NULL DEFAULT '[]',
    metrics_json TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS search_documents (
    rowid INTEGER PRIMARY KEY AUTOINCREMENT,
    record_type TEXT NOT NULL,
    record_id TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    tags TEXT NOT NULL DEFAULT '',
    trust_state TEXT,
    scope_type TEXT,
    UNIQUE (record_type, record_id)
);

CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(
    title,
    body,
    tags,
    content='search_documents',
    content_rowid='rowid',
    tokenize='unicode61'
);

CREATE TRIGGER IF NOT EXISTS search_documents_ai
AFTER INSERT ON search_documents BEGIN
  INSERT INTO search_fts(rowid, title, body, tags)
  VALUES (new.rowid, new.title, new.body, new.tags);
END;

CREATE TRIGGER IF NOT EXISTS search_documents_ad
AFTER DELETE ON search_documents BEGIN
  INSERT INTO search_fts(search_fts, rowid, title, body, tags)
  VALUES ('delete', old.rowid, old.title, old.body, old.tags);
END;

CREATE TRIGGER IF NOT EXISTS search_documents_au
AFTER UPDATE ON search_documents BEGIN
  INSERT INTO search_fts(search_fts, rowid, title, body, tags)
  VALUES ('delete', old.rowid, old.title, old.body, old.tags);
  INSERT INTO search_fts(rowid, title, body, tags)
  VALUES (new.rowid, new.title, new.body, new.tags);
END;

CREATE VIEW IF NOT EXISTS v_preferred_artifacts AS
SELECT
  a.*,
  vf.family_id,
  CASE WHEN vf.preferred_artifact_id = a.artifact_id THEN 1 ELSE 0 END AS is_family_preferred
FROM artifacts a
LEFT JOIN artifact_versions av ON av.artifact_id = a.artifact_id
LEFT JOIN version_families vf ON vf.family_id = av.family_id
WHERE a.trust_state NOT IN ('BROKEN','ARCHIVED','RESTRICTED_SECRET');

CREATE VIEW IF NOT EXISTS v_latest_observations AS
SELECT o.*
FROM observations o
JOIN (
  SELECT source, object_type, object_id, MAX(observed_at) AS max_observed_at
  FROM observations
  GROUP BY source, object_type, object_id
) latest
  ON latest.source = o.source
 AND latest.object_type = o.object_type
 AND latest.object_id = o.object_id
 AND latest.max_observed_at = o.observed_at;
