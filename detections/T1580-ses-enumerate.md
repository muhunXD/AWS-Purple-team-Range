# T1580 — Cloud Infrastructure Discovery

Catches an identity enumerating SES sending configuration, verified identities, and quotas in
quick succession — reconnaissance of a service that isn't otherwise touched in normal operation
of this range.

Detonated `2026-08-26 ~16:25 UTC` using `aws.discovery.ses-enumerate`. Run in `ap-southeast-1`,
since SES isn't available in the range's primary region (`ap-southeast-7`).

```
fields @timestamp, eventName, userIdentity.arn, sourceIPAddress
| filter eventName in ["GetAccountSendingEnabled", "ListIdentities", "GetSendQuota"]
| stats count(*) as calls, earliest(@timestamp) as first_seen, latest(@timestamp) as last_seen
    by userIdentity.arn, sourceIPAddress
| sort calls desc
```

The Stratus log shows the full sequence in the same second: check whether SES sending is
enabled, list verified identities (none found), then pull the account's sending quotas
(`max24hoursend: 200`, `maxsendrate: 1`, `sentlast24hours: 0`). Any one of these calls on its own
is unremarkable — apps that send email check their own quota routinely. What's interesting is an
identity hitting all three SES read-only APIs back-to-back with no corresponding `SendEmail`
call before or after, which looks like enumeration rather than a service actually being used.

| Detonation window | Clean window |
|---|---|
| Fired — 3 calls (`GetAccountSendingEnabled`, `ListIdentities`, `GetSendQuota`) inside one second | Did not fire |

False positive risk is moderate: a legitimate SES health-check script or a new team standing up
email sending would trigger the same three calls. The `stats ... by userIdentity.arn` grouping is
there so a production version of this can allowlist known application roles and only alert when
an *unfamiliar* identity runs the sequence.

No SCP in this landing zone restricts SES read access, so this technique was not blocked — the
value here is purely in detection, same as most of the other techniques in this range.
