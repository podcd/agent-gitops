#!/usr/bin/env bash
# Install the editor half of the stack. Idempotent; `code` skips an
# extension that is already present at the requested version.
#
# The extension itself cannot be reconciled by podcd - it is not a
# container - so this is a host preparation step like bootstrap.sh, not a
# document in the repository.
set -euo pipefail

command -v code >/dev/null || { echo "the VS Code 'code' CLI is not on PATH" >&2; exit 1; }

# Cline: open source, plans and executes multi-file edits with approval,
# and takes an OpenAI-compatible base URL, which is what litellm exposes.
code --install-extension saoudrizwan.claude-dev --force

cat <<'TXT'

Extension installed. Point it at the proxy, so choosing between a local and
a cloud model is a model name rather than a reconfiguration:

  Cline -> settings -> API Provider: OpenAI Compatible
    Base URL: http://127.0.0.1:4000/v1
    API Key:  the LITELLM_MASTER_KEY printed by `make endpoints`
    Model ID: local/qwen2.5-coder-7b

Cline stores this in the editor's own state, not in a file this repository
can own, so it is set once by hand.
TXT
