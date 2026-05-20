import base64
import gzip
import json
import logging
import os
import urllib.request
import urllib.error

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# OTLP severity mapping
SEVERITY_MAP = {
    "ERROR": (17, "ERROR"),
    "WARN":  (13, "WARN"),
    "INFO":  (9,  "INFO"),
    "DEBUG": (5,  "DEBUG"),
    "TRACE": (1,  "TRACE"),
}


def lambda_handler(event, context):
    api_key  = os.environ["INSTANA_API_KEY"]
    otlp_url = os.environ["INSTANA_OTLP_URL"].rstrip("/")
    service  = os.environ.get("LOG_SERVICE_NAME", "cloudwatch")

    all_log_records = []
    records_out = []

    for record in event["records"]:
        try:
            log_records = extract_log_records(record["data"])
            all_log_records.extend(log_records)
            records_out.append({
                "recordId": record["recordId"],
                "result": "Ok",
                "data": record["data"],
            })
        except Exception as e:
            logger.error("Failed to process record %s: %s", record["recordId"], e)
            records_out.append({
                "recordId": record["recordId"],
                "result": "ProcessingFailed",
                "data": record["data"],
            })

    if all_log_records:
        otlp_payload = build_otlp_payload(all_log_records, service)
        send_otlp(otlp_url, api_key, otlp_payload)
        logger.info("Forwarded %d log records to Instana via OTLP", len(all_log_records))

    return {"records": records_out}


def extract_log_records(data: str) -> list:
    decoded = base64.b64decode(data)
    raw = gzip.decompress(decoded)
    cwl = json.loads(raw)
    return cwl.get("logEvents", [])


def build_otlp_payload(log_events: list, service: str) -> dict:
    log_records = []
    for event in log_events:
        message = event.get("message", "")
        severity_text, severity_number = detect_severity(message)
        log_records.append({
            # OTLP timestamps are in nanoseconds
            "timeUnixNano": str(event["timestamp"] * 1_000_000),
            "severityNumber": severity_number,
            "severityText": severity_text,
            "body": {"stringValue": message},
        })

    return {
        "resourceLogs": [{
            "resource": {
                "attributes": [
                    {"key": "service.name", "value": {"stringValue": service}},
                    {"key": "telemetry.sdk.name", "value": {"stringValue": "cloudwatch-firehose"}},
                ]
            },
            "scopeLogs": [{
                "scope": {"name": "cloudwatch-forwarder"},
                "logRecords": log_records,
            }]
        }]
    }


def detect_severity(message: str) -> tuple:
    upper = message.upper()
    for keyword, (number, text) in SEVERITY_MAP.items():
        if keyword in upper:
            return text, number
    return "INFO", 9


def send_otlp(otlp_url: str, api_key: str, payload: dict) -> None:
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url=f"{otlp_url}",
        data=body,
        headers={
            "x-instana-key": api_key,
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            logger.info("Instana OTLP response: %s", resp.status)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"Instana OTLP returned {e.code}: {e.read().decode()}") from e
