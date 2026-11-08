# Script remediation — 8 November 2026

All eleven shell sources were revised. Nothing merged or deployed.

- lib_common: private per-run output under an existing owned protected parent, no shared /tmp fallback, restrictive umask, bounded collector helper, persistent UNKNOWN markers across subshells, parent-shell loop counters.
- 01: retained disk/inode thresholds now affect exit status; malformed/failed/empty df is UNKNOWN; expensive size walks opt-in and bounded.
- 02: private failure-IP data, bounded retained-journal queries, validated thresholds; inaccessible btmp is incomplete.
- 03: one explicit single-filesystem permission walk with NUL-safe records; no full-root default. Orphan ownership, ACL and SELinux assessments are explicitly outside this narrower collector.
- 04: explicit expected service units; failed/missing unit queries cannot be healthy. Static units are not incorrectly assumed broken.
- 05: explicit log files, one read/decompression per input, bounded streaming status/error counts. Summaries cover whole files, not a claimed event-time window; old hours_back option removed. Top-IP/URL analytics are no longer collected.
- 06: one memory/swap collection, validated samples and thresholds, bounded load/CPU inventory.
- 07/08/09: collector failure tracking; cron world-write bit test corrected and counters retained; automatic gateway ping removed. Local account/cron/firewall snapshots are not exhaustive policy assessments.
- 10: exact expected child list, missing/nonstandard/timeout child status is UNKNOWN; no automatic email/webhooks. Delivery must be separately configured in approved monitoring.

Migration: provision AUDIT_LOGDIR owned by the execution account, not group/world writable, with trusted ancestors. No ACL is changed by the toolkit. Set AUDIT_SCAN_ROOT, AUDIT_SERVICE_UNITS (space-separated), AUDIT_WEB_LOGS (newline-separated absolute files). Unconfigured required scope returns UNKNOWN, never clean. AUDIT_TIMEOUT defaults 60 seconds per collector; AUDIT_CHILD_TIMEOUT defaults 300 per child. Exit 0 clean for requested checks, 1 warning, 2 critical, 3 incomplete. Integrations must preserve UNKNOWN even if other critical findings exist. Reports retained in run.* directories; review retention/capacity separately. Set logrotate/retention for the new path layout before scheduling.

Validation: 10 isolated local unittest methods cover disk failure/threshold/counter behavior, child failures/missing checks, no notification, protected output, service failure, corrupt gzip, syntax. Collectors in executed tests are mocked or local fixtures. Filesystem/cron/firewall/retention integration still needs disposable RHEL/Ubuntu labs. No numerical performance claims.
