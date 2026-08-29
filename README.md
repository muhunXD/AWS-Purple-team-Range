# AWS Purple Team Range

A small, self-contained AWS purple-team lab: Terraform builds a deliberately vulnerable target
environment and a detection/response pipeline, [Stratus Red Team](https://stratus-red-team.cloud/)
detonates real MITRE ATT&CK techniques against it, and CloudWatch/Prowler measure what actually
gets caught.

**Full walkthrough with screenshots:** [docs/overview.md](docs/overview.md)

## Why this exists

This was built on top of a personal AWS landing zone project, specifically to test whether that
landing zone's Service Control Policies actually stop anything rather than just trusting that
attaching a policy means it works. Seven attack techniques were detonated for real, five of the
landing zone's six SCPs were proven with actual denied-API-call evidence, and every detection here
was validated against a real CloudTrail event, not a hypothetical one.

## Results

| Technique | Tactic | Prevented (SCP) | Detected | Detection type | GuardDuty equivalent |
|---|---|---|---|---|---|
| T1562.008 — Stop CloudTrail | Defense Evasion | **Yes** | Yes | Live alarm → Lambda | **Yes** — Low |
| T1552.005 — Steal instance credentials | Credential Access | No | Yes | Live alarm | No |
| T1136.003 — Create admin user | Persistence | No | Yes | Retrospective query | No |
| T1098.001 — Backdoor access key | Persistence | No | Yes | Live alarm + auto-response | No |
| T1530 — Share EBS snapshot | Exfiltration | No | Yes | Retrospective query | No |
| T1580 — SES enumeration | Discovery | No | Yes | Retrospective query | No |
| T1098.001 — Update login profile | Privilege Escalation | No | Yes | Retrospective query | No |

Full detail, methodology, and the Prowler before/after comparison: **[docs/results.md](docs/results.md)**.

## Key numbers

- **Detection: 7/7** techniques produced a CloudTrail event that a documented query or alarm catches.
- **Prevention: 1/7** — only CloudTrail-tampering was actually blocked by an SCP; the rest exist to
  prove detection, not prevention.
- **Mean time to detect: ~3–4 minutes**, driven mostly by the 60-second alarm evaluation window.
- **Mean time to respond: ~6 minutes manual, ~3 minutes automated** (the responder Lambda roughly
  halves manual response time for the one technique it acts on).
- **5 of 6 landing-zone SCPs** proven with real `errorCode` evidence, not just "the policy exists."
- **GuardDuty caught 1 of 7** — only the CloudTrail-stop technique had a native GuardDuty finding
  (`Stealth:IAMUser/CloudTrailLoggingDisabled`, Low severity) covering the same behavior.
- **Prowler's MITRE ATT&CK compliance score: 41.67% → 45.45%** between the baseline and after scans.

## Architecture

![Attack, detect, respond pipeline: Stratus Red Team detonates a MITRE ATT&CK technique; CloudTrail's multi-region trail captures the API call; CloudWatch metric filters and alarms detect it; response is the responder Lambda via SNS or an analyst query. Worked example: CreateAccessKey on another IAM user lands in /aws/cloudtrail/range, fires the range-access-key-created alarm, and range-responder deactivates the key via iam:UpdateAccessKey.](docs/images/architecture.svg)

Two independent Terraform stacks: `terraform/target/` (the attack surface) and
`terraform/logging/` (CloudTrail, alarms, the responder Lambda). Full diagram and detail:
**[docs/architecture.md](docs/architecture.md)**.

## Repo layout

- **`docs/`** — the connective write-ups: [overview](docs/overview.md),
  [architecture](docs/architecture.md), [results](docs/results.md).
- **`attacks/`** — the actual session runbook: setup, detonation order, wrap-up steps.
- **`detections/`** — one doc per technique: the CloudWatch Logs Insights query, a
  fired-vs-clean comparison, and an honest false-positive discussion.
- **`evidence/`** — raw Stratus/AWS CLI transcripts and two full Prowler scans (baseline and
  after), with all account/org/policy identifiers redacted.
- **`terraform/`** — the two stacks described above, plus the shared version/provider scaffolding.

## How to reproduce

You'll need your own AWS sandbox account sitting inside an AWS Organization with SCPs similar to
the ones in `evidence/scp-findings.md` (the prevention half of the results depends on those.The
detection half works against any account with CloudTrail enabled). Then:

1. Apply both Terraform stacks — see [terraform/README.md](terraform/README.md) for the exact
   commands and provider setup.
2. Install [Stratus Red Team](https://stratus-red-team.cloud/) and detonate the techniques listed
   in `attacks/session-runbook.md`, in roughly that order.
3. Run the Logs Insights queries from `detections/` (or wait for the three live alarms) to confirm
   each one fires.
4. Run Prowler before and after to get your own baseline/after comparison.

## Disclaimer

Built and run entirely against a sandbox AWS account I own. Stratus Red Team is a public,
open-source attack-simulation tool no exploit code was authored for this project. Account IDs,
organization IDs, policy IDs, and any credentials or passwords that appeared in raw tool output
have been redacted throughout this repo before publishing.
