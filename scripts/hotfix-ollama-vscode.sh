#!/usr/bin/env bash
set -euo pipefail

# Temporary workaround for the Ollama VS Code extension 0.0.8
# streaming/tool-call bug.
#
# The extension's streaming path can fail during VS Code Agent tool loops with:
#   Did not receive done or success response in stream.
#
# This patch changes only the compiled chat provider to use Ollama's
# non-streaming chat response while preserving content, tool calls, usage
# accounting, context checking, and the surrounding error/cancellation logic.
#
# Review and remove this workaround when the extension is updated.

EXPECTED_VERSION="0.0.8"
EXT_DIR="$HOME/.vscode/extensions/ollama.ollama-${EXPECTED_VERSION}"
PACKAGE_JSON="$EXT_DIR/package.json"
PROVIDER_JS="$EXT_DIR/out/provider.js"
BACKUP="$PROVIDER_JS.helix-original"

usage() {
  printf 'Usage: %s {check|apply|restore}\n' "${0##*/}" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 3
fi

command=$1

if [[ ! -f "$PACKAGE_JSON" ]]; then
  printf 'Error: %s not found\n' "$PACKAGE_JSON" >&2
  exit 2
fi

if [[ ! -f "$PROVIDER_JS" ]]; then
  printf 'Error: %s not found\n' "$PROVIDER_JS" >&2
  exit 2
fi

version=$(
  python3 - "$PACKAGE_JSON" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    print(json.load(f).get("version", ""))
PY
)

if [[ "$version" != "$EXPECTED_VERSION" ]]; then
  printf 'Unsupported Ollama extension version: %s (expected %s)\n' \
    "$version" "$EXPECTED_VERSION" >&2
  exit 2
fi

provider_state() {
  python3 - "$PROVIDER_JS" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()

patched = (
    "const chatRequest = ollama.chat({" in text
    and "stream: false," in text
    and "const response = await chatRequest;" in text
    and "for await (const chunk of stream)" not in text
)

stock = (
    "const streamRequest = ollama.chat({" in text
    and "stream: true," in text
    and "const stream = await streamRequest;" in text
    and "for await (const chunk of stream)" in text
)

if patched and not stock:
    print("patched")
    raise SystemExit(0)

if stock and not patched:
    print("unpatched")
    raise SystemExit(1)

print("unknown provider state")
raise SystemExit(2)
PY
}

apply_patch() {
  state=$(provider_state) && status=0 || status=$?

  if [[ $status -eq 0 && "$state" == "patched" ]]; then
    printf 'Already patched. No changes made.\n'
    return 0
  fi

  if [[ $status -ne 1 || "$state" != "unpatched" ]]; then
    printf 'Refusing to patch: %s\n' "$state" >&2
    return 2
  fi

  if [[ ! -f "$BACKUP" ]]; then
    cp -a "$PROVIDER_JS" "$BACKUP"
    printf 'Saved original provider to %s\n' "$BACKUP"
  fi

  python3 - "$PROVIDER_JS" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

old = '''            let chatRequestSettled = false;
            const streamRequest = ollama.chat({
                model: model.model,
                messages: ollamaMessages,
                stream: true,
                tools: tools.length > 0 ? tools : undefined,
                options: options.modelOptions ? { ...options.modelOptions } : undefined
            });
            void streamRequest.then(() => { chatRequestSettled = true; }, () => { chatRequestSettled = true; });
            let contextLengthCheck;
            if (model.local) {
                machineContextSource = new vscode.CancellationTokenSource();
                const cancelMachineContextCheck = token.onCancellationRequested(() => machineContextSource?.cancel());
                disposables.push(machineContextSource, cancelMachineContextCheck);
                if (token.isCancellationRequested) {
                    machineContextSource.cancel();
                }
                const contextOllama = new ollama_1.Ollama({
                    host: model.url,
                    headers: model.headers,
                    fetch: createFetch(machineContextSource.token, disposables)
                });
                contextLengthCheck = this.checkMachineContextLength(contextOllama, model, () => chatRequestSettled, machineContextSource.token);
            }
            const stream = await streamRequest;
            const streamDisposable = token.onCancellationRequested(() => stream.abort());
            disposables.push(streamDisposable);
            if (contextLengthCheck && machineContextSource) {
                const contextSource = machineContextSource;
                // Hold buffered chunks briefly while confirming the loaded model's context.
                await (0, contextLength_1.waitForMachineContextCheckBeforeStreaming)(contextLengthCheck, () => waitForContextCheck(machineContextCheckTimeoutMS, contextSource.token).then(() => undefined), () => contextSource.cancel());
                contextSource.cancel();
            }
            for await (const chunk of stream) {
                const response = chunk;
                if (typeof chunk.prompt_eval_count === 'number' && chunk.prompt_eval_count >= 0) {
                    promptTokenCount = chunk.prompt_eval_count;
                }
                if (typeof chunk.eval_count === 'number' && chunk.eval_count >= 0) {
                    completionTokenCount = chunk.eval_count;
                }
                const content = response.message?.content;
                if (content) {
                    progress.report(new vscode.LanguageModelTextPart(content));
                }
                for (const toolCall of response.message?.tool_calls ?? []) {
                    progress.report(new vscode.LanguageModelToolCallPart(toolCall.id ?? (0, crypto_1.randomUUID)(), toolCall.function.name, toolCall.function.arguments));
                }
            }'''

new = '''            let chatRequestSettled = false;
            const chatRequest = ollama.chat({
                model: model.model,
                messages: ollamaMessages,
                stream: false,
                tools: tools.length > 0 ? tools : undefined,
                options: options.modelOptions ? { ...options.modelOptions } : undefined
            });
            void chatRequest.then(() => { chatRequestSettled = true; }, () => { chatRequestSettled = true; });
            let contextLengthCheck;
            if (model.local) {
                machineContextSource = new vscode.CancellationTokenSource();
                const cancelMachineContextCheck = token.onCancellationRequested(() => machineContextSource?.cancel());
                disposables.push(machineContextSource, cancelMachineContextCheck);
                if (token.isCancellationRequested) {
                    machineContextSource.cancel();
                }
                const contextOllama = new ollama_1.Ollama({
                    host: model.url,
                    headers: model.headers,
                    fetch: createFetch(machineContextSource.token, disposables)
                });
                contextLengthCheck = this.checkMachineContextLength(contextOllama, model, () => chatRequestSettled, machineContextSource.token);
            }
            const response = await chatRequest;
            if (contextLengthCheck && machineContextSource) {
                const contextSource = machineContextSource;
                await (0, contextLength_1.waitForMachineContextCheckBeforeStreaming)(contextLengthCheck, () => waitForContextCheck(machineContextCheckTimeoutMS, contextSource.token).then(() => undefined), () => contextSource.cancel());
                contextSource.cancel();
            }
            if (typeof response.prompt_eval_count === 'number' && response.prompt_eval_count >= 0) {
                promptTokenCount = response.prompt_eval_count;
            }
            if (typeof response.eval_count === 'number' && response.eval_count >= 0) {
                completionTokenCount = response.eval_count;
            }
            const content = response.message?.content;
            if (content) {
                progress.report(new vscode.LanguageModelTextPart(content));
            }
            for (const toolCall of response.message?.tool_calls ?? []) {
                progress.report(new vscode.LanguageModelToolCallPart(toolCall.id ?? (0, crypto_1.randomUUID)(), toolCall.function.name, toolCall.function.arguments));
            }'''

count = text.count(old)

if count != 1:
    raise SystemExit(
        f"Refusing to patch: expected exactly one known stock provider block, found {count}"
    )

path.write_text(text.replace(old, new, 1))
PY

  state=$(provider_state) && status=0 || status=$?
  if [[ $status -ne 0 || "$state" != "patched" ]]; then
    printf 'Patch verification failed; restoring original provider.\n' >&2
    cp -a "$BACKUP" "$PROVIDER_JS"
    return 2
  fi

  printf 'Patch applied successfully.\n'
}

restore_patch() {
  if [[ ! -f "$BACKUP" ]]; then
    printf 'Cannot restore: %s does not exist\n' "$BACKUP" >&2
    return 2
  fi

  cp -a "$BACKUP" "$PROVIDER_JS"

  state=$(provider_state) && status=0 || status=$?
  if [[ $status -ne 1 || "$state" != "unpatched" ]]; then
    printf 'Restore verification failed: %s\n' "$state" >&2
    return 2
  fi

  printf 'Original provider restored successfully.\n'
}

case "$command" in
  check)
    provider_state
    ;;
  apply)
    apply_patch
    ;;
  restore)
    restore_patch
    ;;
  *)
    usage
    exit 3
    ;;
esac
