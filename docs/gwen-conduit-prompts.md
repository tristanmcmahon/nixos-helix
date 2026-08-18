# Gwen↔ChatGPT Conduit — Example Prompts & Next Customizations

## Example activation prompts

- Relay a Gwen task to the model and return the HELIX-RESULT JSON:

  "Relay this Gwen payload to the model and return a HELIX-RESULT JSON suitable for sending back via email. Preserve `id` and `timestamp` in the response."

- Summarize and redact sensitive tokens before returning:

  "Summarize the payload text in three bullets. Do not include any OAuth tokens or Authorization headers; redact them if present and note redaction in the trace."

- Translate format for another system:

  "Convert the Gwen payload into a short actionable task list for an ops engineer (3 items). Return only the `response` JSON block in the HELIX-RESULT."

- Debugging mode (developer):

  "Run schema validation and return either `ok` or a schema error list. Do not call the model."

## How to phrase model instructions inside Gwen tasks

- Keep the `INSTRUCTIONS:` block concise and action-oriented (one sentence).
- Provide `CONTEXT:` only when necessary; keep context < 500 words for v1.
- Ask the model to include an optional `structured` JSON block for machine parsing.

## Suggested next customizations (small, safe, high-impact)

- Add `tests/test_gmail_send.py` that mocks the Gmail API to assert the runner's send path.
- Add a small CLI wrapper `tools/batch_relay.py` to process multiple `examples/*.json` files for manual QA.
- Implement a lightweight anonymizer module with a few conservative regexes (emails, credit-card-like digits) behind a feature flag.
- Add CI (GitHub Actions) to run `pytest` and `flake8` on PRs.

## Longer-term ideas (post-v1)

- Add a secure audit mode that encrypts traces at rest (vault integration). 
- Implement a persistent queue (SQLite) for task state to make retries and backoff durable across worker restarts.
- Add pluggable model adapters so Ollama vs other local LLM hosts are configurable via `config.yaml`.

## Quick references

- Runner: `tools/relay_to_ollama.py`
- Schema: `gwen-schema.json`
- Examples: `examples/task-example.json`, `examples/result-example.json`
