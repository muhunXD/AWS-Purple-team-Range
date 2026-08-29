import json
import time
import boto3
from datetime import datetime, timezone

iam = boto3.client("iam")
logs = boto3.client("logs")

LOG_GROUP = "/aws/cloudtrail/range"


def find_latest_created_key():
    """Query CloudTrail logs for the most recent CreateAccessKey and return (user, key_id)."""
    query = logs.start_query(
        logGroupName=LOG_GROUP,
        startTime=int(time.time()) - 900,   # last 15 min
        endTime=int(time.time()),
        queryString=(
            'fields requestParameters.userName, responseElements.accessKey.accessKeyId '
            '| filter eventName = "CreateAccessKey" '
            '| sort @timestamp desc | limit 1'
        ),
    )
    qid = query["queryId"]

    # Poll until the query finishes
    for _ in range(15):
        result = logs.get_query_results(queryId=qid)
        if result["status"] == "Complete":
            if not result["results"]:
                return None, None
            row = {f["field"]: f["value"] for f in result["results"][0]}
            return (
                row.get("requestParameters.userName"),
                row.get("responseElements.accessKey.accessKeyId"),
            )
        time.sleep(1)
    return None, None


def handler(event, context):
    print("Responder triggered:", json.dumps(event))
    now = datetime.now(timezone.utc).isoformat()

    # ── Path A: SNS from a CloudWatch alarm ──
    if "Records" in event:
        for record in event["Records"]:
            if record.get("EventSource") == "aws:sns":
                msg = json.loads(record["Sns"]["Message"])
                alarm = msg.get("AlarmName", "unknown")

                # Access-key-created alarm → look up the key and deactivate it
                if "access-key-created" in alarm:
                    username, key_id = find_latest_created_key()
                    if username and key_id and key_id.startswith("AKIA"):
                        iam.update_access_key(
                            UserName=username, AccessKeyId=key_id, Status="Inactive"
                        )
                        print(f"[{now}] AUTOMATED RESPONSE: alarm '{alarm}' → "
                              f"deactivated key {key_id} on {username}")
                        return {"action": "deactivated_key", "user": username,
                                "key": key_id, "time": now}
                    print(f"[{now}] alarm '{alarm}' fired but no AKIA key found to act on")
                    return {"action": "no_key_found", "time": now}

                # CloudTrail-tampering alarm → notify only (SCP already blocked it)
                print(f"[{now}] AUTOMATED RESPONSE: alarm '{alarm}' fired. "
                      f"Attempt contained and logged.")
                return {"action": "contained", "alarm": alarm, "time": now}

    # ── Path B: GuardDuty finding (kept for completeness) ──
    detail = event.get("detail", {})
    finding_type = detail.get("type", "")
    if "Persistence" in finding_type or "InstanceCredentialExfiltration" in finding_type:
        resource = detail.get("resource", {})
        key = resource.get("accessKeyDetails", {})
        username = (key.get("userName") or "").strip()
        key_id = (key.get("accessKeyId") or "").strip()
        if username and key_id and key_id.startswith("AKIA"):
            iam.update_access_key(UserName=username, AccessKeyId=key_id, Status="Inactive")
            print(f"[{now}] Deactivated key {key_id} on {username}")
            return {"action": "deactivated_key", "user": username, "time": now}

    print(f"[{now}] No automated action taken")
    return {"action": "none", "time": now}