# Palm analysis failure tracking

Every failed palm analysis writes exactly one row to `public.palm_analysis_failures`.
Before this table a failure left only `palm_scans.status = 'failed'` and a free-text
`palm_analysis.error_message`, so questions like *"why did User C's left palm fail on
attempt 1?"* were unanswerable once the device log rotated.

## Apply

```bash
supabase db push          # or run supabase/migrations/20260817120000_palm_analysis_failures.sql
supabase functions deploy palm-analysis
```

The Edge Function must be redeployed — it is what writes the server-side rows and
returns the specific `reason` code the app renders its message from.

## Who writes what

| Stage          | Written by     | Covers                                        |
|----------------|----------------|-----------------------------------------------|
| `quota`        | Edge Function  | Monthly free-scan limit reached               |
| `stage_a`      | Edge Function  | Feature extraction failed (busy/timeout/error)|
| `quality_gate` | Edge Function  | Image rejected — carries the specific reason  |
| `stage_b`      | Edge Function  | Reading generation failed                     |
| `persist`      | Edge Function  | Reading generated but could not be saved      |
| `unknown`      | Edge Function  | Unexpected server error                       |
| `client`       | App            | No connectivity, upload errors — never reach the server |

The app skips writing when the Edge Function already logged the failure, so there is
one row per failed attempt, not two.

## Failure codes

Capture problems (user can fix — the app shows a correction tip for each):
`NO_PALM_DETECTED`, `PARTIAL_PALM`, `TOO_BLURRY`, `TOO_DARK`, `TOO_BRIGHT`,
`TOO_FAR`, `TOO_CLOSE`, `OBSTRUCTED`, `WRONG_SIDE`, `LOW_QUALITY_IMAGE`

Service-side (retry may help):
`AI_SERVICE_BUSY`, `AI_TIMEOUT`, `AI_RESPONSE_TRUNCATED`, `STAGE_A_FAILED`,
`STAGE_B_FAILED`, `PERSIST_FAILED`

Client / account:
`FREE_LIMIT_REACHED`, `NETWORK_ERROR`, `UPLOAD_FAILED`, `UNKNOWN`

The set is mirrored in `lib/services/palm_failure_reason.dart`. An unrecognised code
degrades to `UNKNOWN` on the client rather than crashing, so the server can add one
without a forced app update.

## Queries

**One user's attempts in order** — the "User C" question:

```sql
SELECT created_at, hand_side, attempt_number, stage, failure_code,
       reason, quality_score, palm_detected, quality_issues, device_model
FROM public.palm_analysis_failures
WHERE user_id = '<uuid>'
ORDER BY created_at;
```

**Find the user first, by email:**

```sql
SELECT id, email FROM auth.users WHERE email ILIKE '%<partial>%';
```

**Most common failure reasons this week:**

```sql
SELECT failure_code, COUNT(*) AS hits,
       ROUND(AVG(quality_score)::numeric, 3) AS avg_score
FROM public.palm_analysis_failures
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY failure_code
ORDER BY hits DESC;
```

**Is one hand failing more than the other?**

```sql
SELECT hand_side, failure_code, COUNT(*)
FROM public.palm_analysis_failures
WHERE created_at > NOW() - INTERVAL '30 days'
GROUP BY hand_side, failure_code
ORDER BY hand_side, COUNT(*) DESC;
```

**Users who failed then immediately succeeded** — quantifies the
"attempt 1 fails, attempt 2 works" pattern:

```sql
SELECT f.user_id, f.hand_side, f.failure_code, f.created_at AS failed_at,
       MIN(s.created_at) AS succeeded_at,
       MIN(s.created_at) - f.created_at AS gap
FROM public.palm_analysis_failures f
JOIN public.palm_scans s
  ON s.user_id = f.user_id
 AND s.status = 'completed'
 AND s.created_at > f.created_at
WHERE f.created_at > NOW() - INTERVAL '30 days'
GROUP BY f.id, f.user_id, f.hand_side, f.failure_code, f.created_at
HAVING MIN(s.created_at) - f.created_at < INTERVAL '10 minutes'
ORDER BY f.created_at DESC;
```

**Per-device capture problems** — a model over-represented here points at a
camera/capture issue rather than user technique:

```sql
SELECT device_model, COUNT(*) FILTER (WHERE stage = 'quality_gate') AS capture_fails,
       COUNT(*) AS total_fails
FROM public.palm_analysis_failures
WHERE created_at > NOW() - INTERVAL '30 days'
GROUP BY device_model
ORDER BY capture_fails DESC;
```

`image_path` is recorded on quality-gate rows, so the exact rejected frame can be
pulled from storage and re-inspected.

## Privacy

Rows never contain the palm image, reading content or PII. Upstream error text is
run through a redaction pass before it is stored. RLS: users read only their own
rows; only `service_role` can read across users.
