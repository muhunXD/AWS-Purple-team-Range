# Terraform

Two independent stacks, each with its own state and its own `terraform.tfvars` (copy
`terraform.tfvars.example` to `terraform.tfvars` in each and fill in your own sandbox account ID
— never commit the real file, it's gitignored).

- **`target/`** — the deliberately vulnerable environment: an S3 bucket seeded with synthetic
  "crown jewels" data and exposed via an over-permissive bucket policy, plus an over-permissive
  IAM role. This is what Stratus Red Team's techniques act against.
- **`logging/`** — the detection and response pipeline: the multi-region CloudTrail trail, its
  CloudWatch Logs group, the three metric filters/alarms, the SNS topic, the EventBridge rule for
  GuardDuty findings, and the `responder` Lambda that auto-deactivates backdoored access keys.

Neither stack references the other's state (no `terraform_remote_state`, no cross-stack data
sources), so they can be applied in either order — but apply **`logging/` before you detonate
anything**, or the attack techniques will run with nothing in place to catch them.

```
cd terraform/logging && cp terraform.tfvars.example terraform.tfvars   # fill in your account id
terraform init && terraform apply

cd ../target && cp terraform.tfvars.example terraform.tfvars           # same account id
terraform init && terraform apply
```

Both assume `OrganizationAccountAccessRole` in the sandbox account from a management-account
profile named `mgmt` (see `providers.tf` in each stack) — adjust the profile name and role ARN if
your setup differs. Both also assume the account already sits under a landing zone with the SCPs
described in `evidence/scp-findings.md`; without those, the "prevented" half of the results in
`docs/results.md` won't reproduce (the detection half still will).

The root-level `versions.tf` / `variables.tf` / `locals.tf` / `providers.tf` /
`terraform.tfvars.example` in this directory are left over from before the project was split into
the two stacks above. They don't declare any resources — `target/` and `logging/` are the two
stacks that actually get applied. They're kept for reference rather than deleted, since the
per-stack copies are identical to them.

### Provider plugins

Each stack's `.terraform/` directory (gitignored) holds its own copy of the downloaded AWS
provider binary — roughly 685 MB each, about 1.4 GB combined across both stacks plus the root.
Run `terraform init` in whichever stack you're using; don't expect these to be committed or
shipped with the repo.
