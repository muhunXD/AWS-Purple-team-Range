# T1530 — Data from Cloud Storage

Catches an EBS snapshot being shared outside the account, which is a way to move data
out through the storage layer instead of over the network.

Detonated `2026-08-20 <FILL IN> UTC` in `<FILL IN REGION>` using
`aws.exfiltration.ec2-share-ebs-snapshot`.

```
fields @timestamp, eventName, requestParameters.createVolumePermission, requestParameters.snapshotId, userIdentity.arn, sourceIPAddress
| filter eventName = "ModifySnapshotAttribute"
| sort @timestamp desc
| limit 50
```

`ModifySnapshotAttribute` is the call that changes who can create a volume from a
snapshot. The `createVolumePermission` field shows the target — an external account ID,
or `all` if the snapshot is being made public. Either means a copy of the disk can now
be restored somewhere outside this account.

| Detonation window | Clean window |
|---|---|
| Fired — snapshot shared externally | Did not fire |

Cross account snapshot sharing is a real thing people do for backups and migrations, so
the event itself is not automatically bad. The signal is the target. Sharing to `all` or
to an account ID that is not in the organisation is the concern, and that is what a
tuned version of this would filter on.

This technique was chosen over the S3 variant on purpose. The `deny-cloudtrail-tampering`
SCP blocks `PutEventSelectors` org wide, so S3 data events can never be enabled and
object level reads would be invisible. Snapshot sharing is a management plane event, so
it shows up in CloudTrail regardless. The blind spot is written up in
`evidence/scp-findings.md`.
