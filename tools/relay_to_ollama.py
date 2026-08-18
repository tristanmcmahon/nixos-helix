#!/usr/bin/env python3
"""Simple v1 relay: validate a Gwen task JSON, send prompt to Ollama, and emit a result.

This keeps v1 intentionally small: schema validation, Ollama call with retries,
minimal operational logging (only when metadata.log true), and example output.

Usage: python tools/relay_to_ollama.py examples/task-example.json
"""
import json
import sys
import time
import os
from pathlib import Path
from typing import Any, Dict

import requests
import base64
import os
from email.mime.text import MIMEText
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from jsonschema import validate, ValidationError

OLLUAMA_URL = "http://127.0.0.1:11434/api/generate"
DEFAULT_MODEL = "helix-qwen:latest"
TRACES_DIR = Path(".gwen-traces")
GMAIL_SCOPES = ["https://www.googleapis.com/auth/gmail.send"]


def send_gmail_message_raw(sender: str, to: str, subject: str, body_text: str, attempts: int = 3) -> Dict[str, Any]:
    """Send an email via Gmail API using local credentials.

    Credentials are NOT stored in this repo. The runner expects env vars:
      GMAIL_ENABLED=true
      GMAIL_CREDENTIALS=/path/to/credentials.json
      GMAIL_TOKEN=/path/to/token.json
    If not configured, calling code should fall back to printing the result.
    """
    creds_path = os.environ.get("GMAIL_CREDENTIALS")
    token_path = os.environ.get("GMAIL_TOKEN")
    if not creds_path or not token_path:
        return {"ok": False, "error": "gmail_not_configured"}

    creds = None
    try:
        if Path(token_path).exists():
            creds = Credentials.from_authorized_user_file(token_path, GMAIL_SCOPES)
        # If there are no (valid) credentials available, let the caller run the OAuth flow locally
        if not creds or not creds.valid:
            if creds and creds.expired and creds.refresh_token:
                creds.refresh(Request())
            else:
                flow = InstalledAppFlow.from_client_secrets_file(creds_path, GMAIL_SCOPES)
                creds = flow.run_local_server(port=0)
            # Save the credentials for the next run
            with open(token_path, "w", encoding="utf-8") as f:
                f.write(creds.to_json())
    except Exception as e:
        return {"ok": False, "error": f"gmail_creds_error: {e}"}

    service = build("gmail", "v1", credentials=creds)

    message = MIMEText(body_text, _charset="utf-8")
    message["to"] = to
    message["from"] = sender
    message["subject"] = subject
    raw = base64.urlsafe_b64encode(message.as_bytes()).decode()
    body = {"raw": raw}

    last_exc = None
    backoffs = [2, 5, 10]
    for attempt in range(1, attempts + 1):
        try:
            sent = service.users().messages().send(userId="me", body=body).execute()
            return {"ok": True, "id": sent.get("id")}
        except Exception as e:
            last_exc = e
        if attempt < attempts:
            time.sleep(backoffs[min(attempt - 1, len(backoffs) - 1)])
    return {"ok": False, "error": str(last_exc)}


def load_json(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def save_minimal_trace(task_id: str, metadata: Dict[str, Any]) -> None:
    TRACES_DIR.mkdir(exist_ok=True)
    out = TRACES_DIR / f"{task_id}.json"
    # Only save minimal operational metadata
    minimal = {
        "gmail_message_id": metadata.get("gmail_message_id"),
        "task_id": task_id,
        "status": metadata.get("status"),
        "model": metadata.get("model"),
        "start_ts": metadata.get("start_ts"),
        "end_ts": metadata.get("end_ts"),
        "elapsed_ms": metadata.get("elapsed_ms"),
        "error_category": metadata.get("error_category"),
    }
    with out.open("w", encoding="utf-8") as f:
        json.dump(minimal, f, indent=2, ensure_ascii=False)


def redact_for_log(s: str) -> str:
    # Minimal redaction: remove common bearer/token patterns
    # Do not try to redact arbitrary PII in v1.
    return s.replace("Authorization: Bearer ", "Authorization: Bearer <REDACTED>")


def call_ollama(prompt: str, model: str = DEFAULT_MODEL, attempts: int = 3) -> Dict[str, Any]:
    backoffs = [2, 5, 10]
    last_exc = None
    for attempt in range(1, attempts + 1):
        try:
            payload = {"model": model, "prompt": prompt, "stream": False}
            # Allow longer responses for larger models or cold-starts
            resp = requests.post(OLLUAMA_URL, json=payload, timeout=120)
            if resp.status_code == 200:
                return {"ok": True, "status_code": resp.status_code, "body": resp.json()}
            # 429 and 5xx are retryable
            if resp.status_code == 429 or resp.status_code >= 500:
                last_exc = Exception(f"Retryable status {resp.status_code}")
            else:
                return {"ok": False, "status_code": resp.status_code, "body": resp.text}
        except requests.RequestException as e:
            last_exc = e
        if attempt < attempts:
            time.sleep(backoffs[min(attempt - 1, len(backoffs) - 1)])
    return {"ok": False, "error": str(last_exc)}


def main(argv):
    if len(argv) < 2:
        print("Usage: relay_to_ollama.py <task.json>")
        return 2
    task_path = Path(argv[1])
    try:
        task = load_json(task_path)
    except Exception as e:
        print("Failed to load task JSON:", e)
        return 3

    # Load schema and validate
    schema_path = Path("gwen-schema.json")
    try:
        schema = load_json(schema_path)
        validate(instance=task, schema=schema)
    except (ValidationError, FileNotFoundError) as e:
        print("Task validation failed:", e)
        return 4

    task_id = task.get("id")
    metadata = task.get("metadata", {})
    model = metadata.get("model") or DEFAULT_MODEL
    prompt = task["payload"].get("text") or task["payload"].get("task_body") or ""

    op_meta = {
        "gmail_message_id": metadata.get("gmail_message_id"),
        "model": model,
        "start_ts": time.time(),
    }

    # Call Ollama
    result = call_ollama(prompt, model=model, attempts=3)

    op_meta["end_ts"] = time.time()
    op_meta["elapsed_ms"] = int((op_meta["end_ts"] - op_meta["start_ts"]) * 1000)

    if result.get("ok"):
        op_meta["status"] = "ok"
        metadata["status"] = "ok"
        metadata["model"] = model

        helix_result = {
            "id": task_id,
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "response": {"status": "ok", "model": model},
            "status": "sent",
        }

        # Optionally send HELIX-RESULT via Gmail API if enabled and recipient provided.
        gmail_enabled = os.environ.get("GMAIL_ENABLED", "false").lower() in ("1", "true", "yes")
        recipient = metadata.get("reply_to") or metadata.get("sender_email") or metadata.get("recipient")
        sender = os.environ.get("GMAIL_USER")
        subject = os.environ.get("HELIX_RESULT_SUBJECT", "HELIX-RESULT")

        if gmail_enabled:
            if not recipient:
                op_meta["status"] = "failed"
                op_meta["error_category"] = "missing_recipient"
                if metadata.get("log"):
                    save_minimal_trace(task_id, op_meta)
                print("Gmail enabled but no recipient found in task metadata; not sending.")
                return 6
            body_text = json.dumps(helix_result, indent=2, ensure_ascii=False)
            send_res = send_gmail_message_raw(sender or "me", recipient, subject, body_text, attempts=3)
            if not send_res.get("ok"):
                op_meta["status"] = "failed"
                op_meta["error_category"] = "gmail_send_failure"
                if metadata.get("log"):
                    save_minimal_trace(task_id, op_meta)
                print("Failed to send HELIX-RESULT via Gmail:", send_res.get("error"))
                return 7
            # success
        else:
            # Not sending; print the HELIX-RESULT for manual processing.
            print(json.dumps(helix_result, indent=2))

        if metadata.get("log"):
            op_meta["error_category"] = None
            op_meta["status"] = "ok"
            save_minimal_trace(task_id, op_meta)
        return 0
    else:
        op_meta["status"] = "failed"
        err = result.get("error") or result.get("body")
        op_meta["error_category"] = "ollama_http_failure"
        if metadata.get("log"):
            save_minimal_trace(task_id, op_meta)
        print("Failed to get model response:", redact_for_log(str(err)))
        # Do not mark processed; worker should leave message for next poll
        return 5


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
