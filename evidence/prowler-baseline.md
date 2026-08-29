# Prowler Baseline

Ran Prowler 5.37.1 against the sandbox account on 2026-08-19,
with the target environment deployed. 630 checks, 88 failed and 70 passed. Full output
is in `evidence/prowler-baseline/`.

| Service | Fails | Critical | High | Medium | Low |
|---|---|---|---|---|---|
| iam | 20 | 3 | 5 | 9 | 3 |
| s3 | 18 | 0 | 1 | 10 | 7 |
| cloudwatch | 17 | 0 | 0 | 17 | 0 |
| cloudtrail | 9 | 0 | 0 | 4 | 5 |
| guardduty | 8 | 0 | 7 | 1 | 0 |
| sagemaker | 3 | 0 | 0 | 0 | 3 |
| bedrock | 2 | 0 | 0 | 2 | 0 |
| config | 2 | 0 | 1 | 1 | 0 |
| securityhub | 2 | 0 | 2 | 0 | 0 |
| accessanalyzer | 1 | 0 | 0 | 0 | 1 |
| account | 1 | 0 | 0 | 1 | 0 |
| backup | 1 | 0 | 0 | 0 | 1 |
| inspector2 | 1 | 0 | 0 | 1 | 0 |
| ssmincidents | 1 | 0 | 0 | 1 | 0 |
| trustedadvisor | 1 | 0 | 0 | 0 | 1 |
| vpc | 1 | 0 | 0 | 1 | 0 |
| **Total** | **88** | **3** | **16** | **48** | **21** |

The iam and s3 fails are mostly the weak role and bucket I built on purpose, so those
are expected. What I did not expect was the 17 CloudWatch fails — those are CIS checks
asking for log metric filters and alarms, which is exactly what I am building next
weekend, so I can use them as a scoreboard. The 7 High GuardDuty fails are protection
plans I never turned on, and Config and Security Hub are not enabled at all. Those came
from my landing zone, not from the range.

MITRE ATT&CK framework coverage is at 41.67% passing. That is the number I want to
improve by the end.

Still to check: the 3 Critical IAM findings, to confirm they are my target resources and
not a real gap.
