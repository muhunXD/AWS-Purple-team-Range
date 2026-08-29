# Architecture

## Two Terraform stacks

```
terraform/target/    →  the attack surface (crown-jewels S3 bucket, over-permissive IAM role)
terraform/logging/   →  the detection & response pipeline (CloudTrail → CloudWatch → alarms → Lambda)
```

They're independent stacks with independent state — nothing in `target/` references `logging/`
or vice versa. See `terraform/README.md` for the exact apply order and provider setup.

## Attack → detect → respond flow

![Attack, detect, respond pipeline: Stratus Red Team detonates a MITRE ATT&CK technique; CloudTrail's multi-region trail captures the API call; CloudWatch metric filters and alarms detect it; response is the responder Lambda via SNS or an analyst query. Worked example: CreateAccessKey on another IAM user lands in /aws/cloudtrail/range, fires the range-access-key-created alarm, and range-responder deactivates the key via iam:UpdateAccessKey.](images/architecture.svg)

Three of the seven detonated techniques have a **live alarm** wired all the way to SNS:

- `range-cloudtrail-tampering` — `StopLogging` / `DeleteTrail` / `UpdateTrail` / `PutEventSelectors`
- `range-instance-cred-theft` — an instance-role ARN calling from a non-AWS source IP
- `range-access-key-created` — any `CreateAccessKey`, the only one with an **automated response**:
  the `responder` Lambda queries Logs Insights for the key that was just created and deactivates
  it via `iam:UpdateAccessKey`.

A separate EventBridge rule routes GuardDuty findings (severity ≥ Medium) to the same Lambda, so a
real GuardDuty finding gets the same automated response as the CloudTrail-derived alarms.

The other four techniques (`T1136.003`, `T1530`, `T1580`, and the login-profile variant of
`T1098.001`) are documented as **retrospective Logs Insights queries** — the kind an analyst runs
during triage rather than something wired to an alarm. Extending any of them into a live alarm is
a straightforward copy of the pattern already used in `terraform/logging/main.tf` and
`responders.tf`.

## Where prevention fits in

The range's SCPs (from the landing zone this project sits on top of, not built by this project)
sit *outside* this flow entirely — they block or allow the underlying API call before CloudTrail
even has anything interesting to log a violation of. Only one of the seven attack techniques
(`T1562.008`, stopping CloudTrail) touches an action any SCP actually restricts; see
`docs/results.md` for why prevention and detection are measured separately here.
