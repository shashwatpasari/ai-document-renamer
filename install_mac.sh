#!/bin/bash
set -euo pipefail

# Project folder
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODEL_NAME="gemma3:4b"

# Track if this script started Ollama
OLLAMA_STARTED_BY_SCRIPT=0
OLLAMA_PID=""

load_brew_env() {
  # Add brew to PATH for Apple Silicon and Intel
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

wait_for_ollama() {
  for _ in {1..30}; do
    if ollama list >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

start_ollama_from_cli() {
  nohup "$(command -v ollama)" serve >/tmp/ollama-serve.log 2>&1 &
  OLLAMA_PID=$!
  OLLAMA_STARTED_BY_SCRIPT=1
  wait_for_ollama
}

cleanup_ollama() {
  # Stop only if this script started it
  if [ "$OLLAMA_STARTED_BY_SCRIPT" -eq 1 ] && [ -n "$OLLAMA_PID" ]; then
    kill "$OLLAMA_PID" >/dev/null 2>&1 || true
    wait "$OLLAMA_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup_ollama EXIT

# 1) Install Homebrew if missing
if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
load_brew_env

# 2) Install Python 3.14 if missing
if ! command -v python3.14 >/dev/null 2>&1; then
  brew install python@3.14
fi

# Find Python 3.14 binary
PYTHON_BIN="$(brew --prefix)/opt/python@3.14/bin/python3.14"
if [ ! -x "$PYTHON_BIN" ]; then
  PYTHON_BIN="$(command -v python3.14 || true)"
fi
if [ -z "${PYTHON_BIN:-}" ] || [ ! -x "$PYTHON_BIN" ]; then
  echo "Python 3.14 not found after install."
  exit 1
fi

# 3) Install or upgrade Ollama
if command -v ollama >/dev/null 2>&1; then
  brew upgrade ollama 2>/dev/null || true
else
  brew install ollama || brew install --cask ollama
fi

# 4) If an old app/server is running, restart from current CLI
OLLAMA_CHECK="$(ollama list 2>&1 || true)"
if echo "$OLLAMA_CHECK" | grep -q "client version is"; then
  pkill -f "ollama serve" >/dev/null 2>&1 || true
  osascript -e 'quit app "Ollama"' >/dev/null 2>&1 || true
  sleep 2
fi

# 5) Ensure Ollama server is running
if ! ollama list >/dev/null 2>&1; then
  start_ollama_from_cli || {
    echo "Could not start Ollama automatically."
    echo "Check /tmp/ollama-serve.log and rerun."
    exit 1
  }
fi

# 6) Pull model if missing
if ! ollama show "$MODEL_NAME" >/dev/null 2>&1; then
  ollama pull "$MODEL_NAME"
fi

# 7) Create venv if missing
if [ ! -d "$SCRIPT_DIR/venv" ]; then
  "$PYTHON_BIN" -m venv "$SCRIPT_DIR/venv"
fi

# 8) Activate venv
source "$SCRIPT_DIR/venv/bin/activate"

# 9) Install Python libs
pip show pymupdf >/dev/null 2>&1 || pip install pymupdf
pip show ollama >/dev/null 2>&1 || pip install ollama

# 10) Ask for input folder
echo ""
echo "Where is the folder containing your documents?"
echo "Tip: Drag and drop the folder here, then press Enter."
read -r -p "Folder path: " INPUT_FOLDER

# Clean path
INPUT_FOLDER="${INPUT_FOLDER%/}"
INPUT_FOLDER="${INPUT_FOLDER%\"}"
INPUT_FOLDER="${INPUT_FOLDER#\"}"
INPUT_FOLDER="${INPUT_FOLDER//\'/}"
INPUT_FOLDER="${INPUT_FOLDER/#\~/$HOME}"

# Validate
if [ ! -d "$INPUT_FOLDER" ]; then
  echo "Folder not found. Please run setup again."
  exit 1
fi

# 11) Create output folder
OUTPUT_FOLDER="$(dirname "$INPUT_FOLDER")/Renamed Documents"
mkdir -p "$OUTPUT_FOLDER"

# 12) Write config.py
cat > "$SCRIPT_DIR/config.py" << EOF
INPUT_FOLDER = r"$INPUT_FOLDER"
OUTPUT_FOLDER = r"$OUTPUT_FOLDER"
MODEL = "$MODEL_NAME"
SUPPORTED_EXTENSIONS = [".pdf", ".jpg", ".jpeg", ".png"]
DRY_RUN = False
EOF



echo ""
echo "Done! Runs every Monday at 9:00 AM."
echo "Output folder: $OUTPUT_FOLDER"
echo "Run now: bash \"$SCRIPT_DIR/run_now_mac.sh\""
