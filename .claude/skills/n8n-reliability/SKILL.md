---
name: n8n-reliability
description: Make n8n Cloud monthly close tracking reliable with idempotent writes, concurrency control, notification outboxes, explicit error handling, bounded API retries, durable audit records, and cached dashboard snapshots. Use when duplicate submissions, email failures, dashboard traffic, or month-end consistency matter.
---

# n8n reliability

Define the durable business result before optimizing workflow execution. Read [sources](references/sources.md) for current Cloud and node behavior. Treat a close submission, its audit event, and its email notification as related but separately observable outcomes.

## Persist predictable state

Create the expected BU/OU requirements for each reporting period independently of submissions. Define whether the current state is one row per `(period, bu, ou)` or includes an additional close stage. Keep prior events in an append-only audit table with actor, server timestamp, receipt ID, status, and previous version.

Generate a request ID once per logical submission and reuse it on client retries. Distinguish identical retries from legitimate corrections. For strict concurrency, use a database unique constraint on the request ID and a unique business key on the current-state row; update conditionally against an expected version inside a transaction. Return the existing receipt for an identical duplicate, and reject a reused request ID with conflicting content.

Use Data Tables for light to moderate lookup/state storage. Current documentation specifies a default **200 MiB total per instance**, project-level access, and no direct Code-node access. Verify actual instance limits. Do not infer transactional uniqueness, row locking, or compare-and-swap guarantees from a Data Table upsert. If simultaneous writes matter, use a backing database with documented atomic operations or a proven single-writer design encompassing every submission path. Cloud execution concurrency is not a per-business-key lock.

## Separate notifications from acceptance

Persist a notification intent with the close event, ideally in the same database transaction. Track:

```text
notification_id | close_event_id | recipient | state
attempt_count | next_attempt_at | provider_message_id | last_error
```

Dispatch pending intents in a separate workflow and claim each job atomically where the store supports it. Mark sent only after provider acceptance. If a request times out after a provider may have accepted it, record an **unknown** result; reconcile provider logs or use provider-supported idempotency before resending. Do not promise exactly-once email from a retrying node. Show saved close status separately from pending or failed notification status.

## Handle failures deliberately

Attach an Error Trigger workflow in the main workflow settings. It runs for automatic workflow failures, not manual test executions. Handle missing execution IDs/URLs when failures occur at the trigger or when execution data is not saved.

Use node error outputs for recoverable conditions and route them to explicit recovery or failure paths. Continuing after an error can prevent a workflow-level failure; never assume Error Trigger will catch swallowed errors. Use Stop And Error for unrecoverable processing failures. Return a denial or validation response for expected user mistakes without exposing internal stacks.

Set HTTP timeouts, bounded attempts, and backoff for transient errors. For 429, honor `Retry-After` where available; otherwise use bounded exponential backoff with jitter. Retry mutations only with a safe idempotency strategy. Paginate using the downstream API's documented cursor or termination condition; cap pages and reject repeated cursors. When enabling HTTP Request **Never Error**, explicitly branch on status codes.

## Serve small, trustworthy dashboard snapshots

For this monthly Cloud workload, aggregate after accepted writes or on a short schedule and serve an authenticated snapshot with `generated_at` and period. Cache by authorized scope; do not reuse one user's restricted snapshot for another. Avoid launching expensive multi-node queries for every dropdown change or polling every few seconds. Preserve filter and drill-through consistency within the same snapshot version.

Check Cloud concurrency and execution allowances before choosing polling intervals. Keep audit history outside execution logs: Cloud prunes logs according to plan retention and storage limits. Verify duplicate requests, simultaneous corrections, API throttling, notification ambiguity, automatic error handling, and stale snapshot behavior before production.
