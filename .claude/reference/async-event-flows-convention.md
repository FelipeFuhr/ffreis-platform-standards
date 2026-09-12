## Async event flows — convention

Two-axis decision model for every new async flow in the fleet. Full decision tables
and worked examples live in
`platform/ffreis-platform-terraform-modules/modules/async-event-queue/README.md`
(consumer_mode) and `modules/async-job-status/README.md` (honest-success UX).

**Axis 1 — last-hop trigger** (`consumer_mode`):

| Choice | When to use | Module value |
|---|---|---|
| **Push** (`real_time`) | Downstream not rate-limited (SES, DynamoDB, low-volume HTTP); ~free at idle | `consumer_mode = "real_time"` |
| **ESM** (`event_driven`) | Rate-limited or expensive downstream (Bedrock, Rekognition); bursty; needs backpressure / concurrency cap | `consumer_mode = "event_driven"` |

**Axis 2 — delivery acknowledgement**:

| Choice | When to use |
|---|---|
| **Await-result** (default) | User needs the outcome before the page resolves — use `submitAndAwait` in the tracker SDK |
| **`ack_only`** | Best-effort side-effects where the user does not wait (analytics events, non-critical notifications) |

**Key identity contract** (prevents the most common mix-up):

- `job_id` = `DomainEvent.event_id` — **unique per submission**, the jobs-table key.
- `correlation_id` = the ux session_id (the `x-tracker-session` request header) — **groups a session**, not a submission.

Never confuse the two: `job_id` uniquely identifies one async work item;
`correlation_id` links many events in a browser session.

Always: publish a `DomainEvent`; set `create_archive = true` except on PII/auth flows;
choose both axes from the tables above.
