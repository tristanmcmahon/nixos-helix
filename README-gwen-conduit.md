# Gwen ↔ Ollama Conduit (v1)

This folder contains a minimal v1 relay that accepts Gwen task JSON, validates it, calls the local Ollama HTTP API, and outputs a minimal HELIX-RESULT message.

Quick start (local manual run):

1. Create a Python virtualenv and install requirements:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

2. Run the example task through the relay (this will attempt to call Ollama at the configured local endpoint):

```bash
python tools/relay_to_ollama.py examples/task-example.json
```

Notes:
- v1 does not send emails — it prints an example HELIX-RESULT to stdout when successful.
- Tracing is minimal and off by default (`metadata.log: false`). When enabled the relay writes minimal operational metadata to `.gwen-traces/{task_id}.json` (no prompts or responses).
- Retry behaviour: up to 3 attempts for retryable Ollama errors (2s, 5s, 10s backoff).

Optional: enable Gmail HELIX-RESULT delivery
-------------------------------------------

To have the runner actually send the HELIX-RESULT email via Gmail API, set these environment variables and provide local credential files (do not store credentials in this repo):

```bash
export GMAIL_ENABLED=true
export GMAIL_CREDENTIALS=/path/to/credentials.json    # OAuth client secrets
export GMAIL_TOKEN=/path/to/token.json                # file to store OAuth tokens (created locally)
export GMAIL_USER=you@example.com                     # optional 'from' address; otherwise API uses 'me'
export HELIX_RESULT_SUBJECT="HELIX-RESULT"
```

When enabled, the runner will look for the recipient in task `metadata.reply_to` (or `sender_email`/`recipient`). If not found the runner will not send and will return a non-zero exit code.

The runner performs an OAuth flow locally if `token.json` is missing; that flow runs in your browser and stores the token at the supplied `GMAIL_TOKEN` path. Keep those files secure and out of source control.
