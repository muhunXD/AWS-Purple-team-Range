# SCP Findings from the Build

No attacks were run this weekend, but three of the six SCPs from the landing zone still
blocked parts of the range build. 

| SCP | Action denied | Blocked operation | Consequence |
|---|---|---|---|
| `deny-guardduty-tampering` | `guardduty:UpdateDetector` | Changing finding publishing frequency from the delegated admin account | Denial proof #4, stronger than the first three |
| `deny-cloudtrail-tampering` | `cloudtrail:PutEventSelectors` | Enabling S3 data events anywhere in the org | Tamper-resistance costs object-level S3 visibility |
| `deny-cloudtrail-tampering` | `UpdateTrail`, `DeleteTrail` | Modifying or removing the range trail | Trail is immutable once created |
| `deny-s3-public-access` | `s3:PutBucketPublicAccessBlock` | Setting a bucket public access block from a workload account | Target bucket exposed via bucket policy instead |

