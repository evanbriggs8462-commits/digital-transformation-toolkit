# Sources

Checked 2026-10-12. Verify the instance's plan and installed version before assuming limits or features.

- [n8n Data Tables](https://docs.n8n.io/build/work-with-data/data-tables.md): intended storage workload, 200 MiB default total, project access, no direct Code-node access.
- [n8n Cloud concurrency](https://docs.n8n.io/deploy/use-n8n-cloud/understand-concurrency.md): plan-specific limits, production-only control, FIFO queuing, excluded execution types.
- [n8n Error Trigger](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.errortrigger): automatic-only errors, workflow attachment, missing execution metadata.
- [n8n HTTP Request](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.httprequest): pagination, batching, response statuses, Never Error.
- [n8n Workflow settings](https://docs.n8n.io/build/manage-workflows/configure-workflow-settings.md): saved executions, workflow timeout, execution-data settings.
- [n8n Cloud data management](https://docs.n8n.io/deploy/use-n8n-cloud/configure-cloud/manage-your-data.md): execution-log retention and pruning.

Unique constraints, transactions, conditional writes, outbox states, scoped caching, and email reconciliation are application design recommendations. Do not attribute these atomic guarantees to n8n Data Tables without separate documented evidence.
