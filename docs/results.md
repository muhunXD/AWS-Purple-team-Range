# Results

Seven MITRE ATT&CK techniques were detonated against the range with Stratus Red Team. This is
the consolidated scorecard; the per-technique detail and CloudWatch Logs Insights queries live in
`detections/`, the full narrative and screenshots are in `docs/overview.md`, and the raw evidence
behind every row is in `evidence/`.

## Master results table

| Technique | Tactic | Prevented (SCP) | Detected | Detection type | GuardDuty equivalent |
|---|---|---|---|---|---|
| T1562.008 — Stop CloudTrail | Defense Evasion | **Yes** — `deny-cloudtrail-tampering` | Yes | Live alarm → SNS → Lambda (logged as contained) | **Yes** — `Stealth:IAMUser/CloudTrailLoggingDisabled` (Low) |
| T1552.005 — Steal instance credentials | Credential Access | No | Yes | Live alarm (`range-instance-cred-theft`) | No |
| T1136.003 — Create admin user | Persistence | No | Yes | Retrospective Logs Insights query | No |
| T1098.001 — Backdoor access key | Persistence | No | Yes | Live alarm (`range-access-key-created`) + automated response | No |
| T1530 — Share EBS snapshot | Exfiltration | No | Yes | Retrospective Logs Insights query | No |
| T1580 — SES enumeration | Discovery | No | Yes | Retrospective Logs Insights query | No |
| T1098.001 — Update login profile | Privilege Escalation / Persistence | No | Yes | Retrospective Logs Insights query | No |

**Prevention: 1/7.** Only the CloudTrail-tampering attempt was actually blocked at the API level —
every other technique's underlying action (creating a key, reading instance metadata, sharing a
snapshot, enumerating SES, changing a password) is a normal, un-privileged-by-SCP action, so the
range's SCPs were never going to stop it. That's by design: those seven techniques exist to prove
the *detection* layer, not the prevention layer.

**Detection: 7/7.** Every technique produced a CloudTrail event that a documented query (or a live
alarm) catches. **3/7** have a real-time CloudWatch alarm wired to SNS; the other 4 are
retrospective Logs Insights queries an analyst would run during triage.

**Automated response: 1/7.** Only the access-key backdoor path has an automated remediation — the
`range-responder` Lambda deactivates the key it finds via a Logs Insights query triggered off the
`range-access-key-created` alarm. `evidence/lambda-response-proof.json` is a captured example of
it actually firing.

**GuardDuty: 1/7.** Only the CloudTrail-stop technique (T1562.008) has a matching GuardDuty finding
— `Stealth:IAMUser/CloudTrailLoggingDisabled`, Low severity — from the same detonation. The other
six, including the instance-credential-theft technique, were **not** caught by GuardDuty in this
run. GuardDuty was not enabled with every protection plan turned on, so this isn't a claim that
GuardDuty categorically misses those six — only that it wasn't the tool that caught them here.

## Detection speed (alarm-covered techniques)

These are measured, not theoretical — from CloudTrail event delivery through alarm evaluation to
either an analyst noticing or the Lambda acting:

- **Mean time to detect (MTTD): ~3–4 minutes** — driven mostly by the 60-second alarm evaluation
  period plus CloudWatch Logs' own delivery latency from CloudTrail.
- **Mean time to respond (MTTR), manual: ~6 minutes** — the time to notice the alarm, look up the
  access key via Logs Insights by hand, and deactivate it through the console/CLI.
- **Mean time to respond (MTTR), automated: ~3 minutes** — the `range-responder` Lambda doing the
  same lookup-and-deactivate automatically once the alarm fires, roughly halving manual response
  time.

> **MTTD conflict, flagged rather than resolved:** the session notes' Phase 2 "Summarize" table
> records **5 minutes** as the MTTD for both the T1562.008 and T1552.005 alarms, measured during
> the initial alarm test. The ~3–4 minute figure above comes from later runs. Both numbers are
> genuine measurements, not a typo — CloudTrail delivery latency varies from run to run, and the
> two figures were captured at different points in testing. Rather than silently picking one, both
> are shown here and in `docs/overview.md`: measured 5 min in the initial alarm test; ~3–4 min on
> later runs.

## SCP proofs (build-time, not attack-time)

Separately from the seven attack techniques, five of the landing zone's six SCPs were directly
proven with `errorCode` evidence in `evidence/denials/` — either while building the range or while
deliberately probing the boundary:

| SCP | Proven via | Evidence |
|---|---|---|
| `deny-cloudtrail-tampering` | `StopLogging` (T1562.008), plus `UpdateTrail`/`DeleteTrail`/`PutEventSelectors` during the build | `t1562-stop-logging.txt`, `scp-findings.md` |
| `deny-s3-public-access` | `s3:PutAccountPublicAccessBlock` and `s3:PutBucketPublicAccessBlock` denied | `scp-s3-public.txt`, `scp-findings.md` |
| `deny-guardduty-tampering` | `guardduty:UpdateDetector` denied | `scp-findings.md` |
| Region-restriction SCP | `ec2:DescribeInstances` denied outside the allowed region | `scp-region.txt` |
| Leave-organization restriction | `organizations:LeaveOrganization` denied | `scp-leave-org.txt` |

The sixth SCP in the landing zone hasn't been directly tested against a real API call in this
project yet.

## Prowler: baseline vs. after

Same account, same methodology (Prowler 5.37.1), two points in time — 2026-08-19 (target
environment only) and 2026-08-29 (target + logging + response stack all deployed):

| | Baseline (08-19) | After (08-29) |
|---|---|---|
| Total findings evaluated | 167 | 220 |
| PASS | 70 | 103 |
| FAIL | 88 | 108 |
| MANUAL | 9 | 9 |
| Critical fails | 3 | 3 |
| High fails | 16 | 18 |
| Medium fails | 48 | 58 |
| Low fails | 21 | 29 |
| Prowler's MITRE ATT&CK framework compliance score | 41.67% | 45.45% |

Fails grew in absolute terms alongside total findings — the logging pipeline, the responder
Lambda, and the extra CloudWatch/SNS resources all added more things for Prowler to check, not
just more things to fail. Critical fails held steady at 3 across both scans (the intentionally
weak target resources). The MITRE ATT&CK framework score matches the project's own source
documentation (`docs/overview.md`) exactly: 41.67% → 45.45%.
