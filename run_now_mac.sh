#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Add Homebrew to PATH (needed for ollama)
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

source "$SCRIPT_DIR/venv/bin/activate"

OLLAMA_STARTED_BY_SCRIPT=0
OLLAMA_PID=""

ensure_ollama() {
  # Check if server is running AND version matches CLI
  OLLAMA_OUTPUT="$(ollama list 2>&1 || true)"
  if echo "$OLLAMA_OUTPUT" | grep -q "client version is"; then
    # Version mismatch — kill stale server/app, restart from CLI
    echo "Detected Ollama version mismatch. Restarting server..."
    pkill -f "ollama serve" >/dev/null 2>&1 || true
    osascript -e 'quit app "Ollama"' >/dev/null 2>&1 || true
    sleep 2
  elif ollama list >/dev/null 2>&1; then
    return 0
  fi

  nohup ollama serve >/tmp/ollama-serve.log 2>&1 &
  OLLAMA_PID=$!
  OLLAMA_STARTED_BY_SCRIPT=1

  for i in {1..30}; do
    sleep 1
    if ollama list >/dev/null 2>&1; then
      return 0
    fi
  done

  echo "Could not start Ollama server."
  return 1
}

cleanup_ollama() {
  if [ "$OLLAMA_STARTED_BY_SCRIPT" -eq 1 ] && [ -n "$OLLAMA_PID" ]; then
    kill "$OLLAMA_PID" >/dev/null 2>&1 || true
    wait "$OLLAMA_PID" >/dev/null 2>&1 || true
  fi
}

trap cleanup_ollama EXIT

ensure_ollama
python "$SCRIPT_DIR/run.py" "$@"
