# Attack Session Runbook

Reconstructed from the real Stratus Red Team / AWS CLI transcripts in `evidence/denials/` and the
timestamps in `detections/`. All times below are UTC, converted from the local capture times in
the raw transcripts (local time is UTC+7). This documents the sessions that already happened —
it isn't a new run.

## Start

1. Assume the SSO admin role in the sandbox account and confirm identity
   (`aws sts get-caller-identity`) before touching anything. Every Stratus transcript opens with
   `Checking your authentication against AWS` for the same reason — never detonate against the
   wrong account.
2. `terraform apply` `terraform/target/` and `terraform/logging/` first, in that order, so the
   attack surface (the `crown_jewels` bucket, the over-permissive role) and the detection pipeline
   (CloudTrail, the metric filters/alarms, the responder Lambda) both exist before anything is
   detonated. Detonating before the logging stack exists means the technique runs with nothing to
   catch it.
3. Confirm the multi-region trail is actually delivering to CloudWatch Logs before starting —
   `T1098.001-backdoor-user.md` calls this out explicitly, since IAM events land in `us-east-1`
   regardless of which region the range runs in, and that's a good sanity check that the trail's
   `is_multi_region_trail` setting is doing its job.

## During — detonation order actually used

**Session 1 — 2026-08-20 (defense evasion, credential access, persistence, exfiltration):**

| Time (UTC) | Technique | Stratus command |
|---|---|---|
| ~10:31 | T1562.008 — Stop CloudTrail | `aws.defense-evasion.cloudtrail-stop` |
| ~12:28 | T1552.005 — Steal instance credentials | `aws.credential-access.ec2-steal-instance-credentials` |
| ~14:07 | T1136.003 — Create admin user | `aws.persistence.iam-create-admin-user` |
| ~14:27 | T1098.001 — Backdoor access key | `aws.persistence.iam-backdoor-user` |
| ~14:42 | T1530 — Share EBS snapshot | `aws.exfiltration.ec2-share-ebs-snapshot` |

**Session 2 — 2026-08-24 (SCP boundary probing, no attack techniques):**

Deliberately tried three actions expected to be blocked by the landing zone's SCPs, to get
`errorCode` evidence rather than just trusting the SCP is attached: `ec2:DescribeInstances`
outside the allowed region, `s3:PutAccountPublicAccessBlock`, and `organizations:LeaveOrganization`.
All three came back `AccessDenied`/`UnauthorizedOperation` with the denying policy ARN in the
error, which is what's captured in `evidence/denials/scp-*.txt`.

**Session 3 — 2026-08-26 (discovery, privilege escalation):**

| Time (UTC) | Technique | Stratus command |
|---|---|---|
| ~16:25 | T1580 — SES enumeration | `aws.discovery.ses-enumerate` (run in `ap-southeast-1`, no SES in the primary region) |
| ~17:41 | T1098.001 — Update login profile | `aws.privilege-escalation.iam-update-user-login-profile` |

**Session 4 — 2026-08-27 (response layer build, not an attack session):**

Built and deployed the responder Lambda (`terraform/logging/lambda/responder.py`,
`terraform/logging/responders.tf`) and wired the `access-key-created` alarm to it. Re-triggered
the access-key backdoor path to confirm the automated response actually fires end-to-end — see
`evidence/lambda-response-proof.json`, captured the same day.

## End

1. After each detonation, check CloudWatch Logs Insights with the query documented in the
   matching `detections/*.md` file (or wait for the alarm, for the three techniques that have
   one) to confirm the event actually landed and the detection fires.
2. Note anything Stratus reports as "already warm" — a repeated detonation without `--force`
   reuses existing warm-up resources and can produce a stale timestamp if you're trying to
   correlate against a fresh CloudTrail event.
3. Run a full Prowler scan (`prowler aws ... -M csv json-ocsf`) before the first detonation
   (baseline) and again after the environment has meaningfully changed (after), so the
   before/after comparison in `docs/results.md` reflects the same account at two points in time.
4. Save every denial/detonation transcript verbatim into `evidence/denials/` — they're the primary
   evidence behind every detection doc's "Detonated ... using ..." line and every SCP proof in
   `evidence/scp-findings.md`.
