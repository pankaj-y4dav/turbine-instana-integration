import base64
import gzip
import json
import logging
import os
import urllib.request
import urllib.error

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    api_key = os.environ["INSTANA_API_KEY"]
    base_url = os.environ["INSTANA_BASE_URL"].rstrip("/")
    service = os.environ.get("LOG_SERVICE_NAME", "cloudwatch")

    all_entries = []
    records_out = []

    for record in event["records"]:
        try:
            entries = extract_log_entries(record["data"], service)
            all_entries.extend(entries)
            records_out.append({"recordId": record["recordId"], "result": "Ok", "data": record["data"]})
        except Exception as e:
            logger.error("Failed to process record %s: %s", record["recordId"], e)
            records_out.append({"recordId": record["recordId"], "result": "ProcessingFailed", "data": record["data"]})

    if all_entries:
        send_to_instana(base_url, api_key, all_entries)
        logger.info("Forwarded %d log entries to Instana in one batch", len(all_entries))

    return {"records": records_out}


def extract_log_entries(data: str, service: str) -> list:
    decoded = base64.b64decode(data)
    raw = gzip.decompress(decoded)
    cwl = json.loads(raw)

    entries = []
    for event in cwl.get("logEvents", []):
        entries.append({
            "timestamp": event["timestamp"],
            "message": event["message"],
            "level": "INFO",
            "service": service,
        })
    return entries


def send_to_instana(base_url: str, api_key: str, entries: list) -> None:
    body = json.dumps(entries).encode("utf-8")
    req = urllib.request.Request(
        url=f"{base_url}/api/logs",
        data=body,
        headers={
            "Authorization": f"apiToken {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            logger.info("Instana response: %s", resp.status)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"Instana returned {e.code}: {e.read().decode()}") from e
