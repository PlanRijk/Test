# Supabase Free plan — 26 November 2026

The owner supplied a current-cycle dashboard screenshot. It reports 0.25 / 5 GB
egress, 152 / 500 MB database, 4 / 50,000 monthly active users, 0.02 / 1 GB
files, 0.11 / 1 GB log ingestion and 1.97 / 100 GB log queries. These are
owner-reported observations, not live provider API measurements. The screenshot
does not establish the billing period start/end. Existing management credentials
cannot read the provider's billing usage endpoints. No new paid resource is used.

## Independent capacity limits

| Meter | Included | Warning | Pause new work | Hard internal limit |
|---|---:|---:|---:|---:|
| Uncached egress | 5 GB | 3.5 GB | 4 GB | 4.5 GB |
| Database | 500 MB | 350 MB | 400 MB | 450 MB |
| Private files | 1 GB | 700 MB | — | 900 MB |

Cached egress is separate; it is never added to the uncached allowance. MAU/logs
are stored as screenshot observations, without claiming live monitoring or
application enforcement. Database and object admission use local SQL measurements,
which can differ from the provider's delayed dashboard accounting.

## Why the previous work meter was misleading

`free_usage.estimated_worker_egress_bytes` counts mixed work: source downloads,
reservations and estimated serialized data, rather than strictly billed Supabase
outbound traffic. It is retained unchanged as the raw work meter. Migration 048
and `scripts/free_plan.py` record an auditable private provider observation and
calibrate a separate safety estimate:

    owner-reported egress + 250 MB lag reserve + positive work charges since checkpoint

This remains conservative: subsequent charges still include incoming external
source downloads and reservation overhead. Refunds grant no extra allowance.
A trigger serializes concurrent charges and rejects any positive increment that
would exceed 4.5 GB. The checkpoint carries across UTC work months; a calendar
rollover does not imply the unknown provider billing period has reset. Further
untracked organization usage can invalidate the estimate, so the provider
dashboard remains authoritative and should be checked periodically.

Existing worker guards use `traffic_limit()` to translate egress limits into the
equivalent raw work threshold. `free_usage.max_worker_egress_bytes` consequently
expresses **raw work admission**, and may exceed 5 GB: it is not the provider cap.
The independent calibrated trigger still enforces 4.5 GB. Deliberately lower
custom raw caps are retained. Owner read RPCs display the calibrated safety
estimate, provider observation and raw counter separately. No API/auth routes,
financial rules, trade records, model limits or provider cooldowns are changed.

## Updating the checkpoint

Only administrative SQL can call `paperlab.record_provider_usage(id, metrics,
source)`. Use a new identifier for a newly checked dashboard observation. Metrics
must include nonnegative `egress_bytes` at most 5 GB. Record the observation's
source and actual time; the stored time is when it was recorded, not a fabricated
provider timestamp. Reusing an identifier is idempotent; changing its metrics is
rejected. Private observation/runtime tables use RLS and revoke all API roles.
The existing owner/MFA-protected reads expose the observation to the owner only.

Run `python managed/tests/test_free_plan_database.py` in the isolated PostgreSQL
container. It checks unchanged raw history, idempotence, lower caps, no refund or
month rollover credit, concurrent hard-limit enforcement and permission isolation.
