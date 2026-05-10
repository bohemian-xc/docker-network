#!/usr/bin/env bash
set -euo pipefail

# Load configuration from a git_pull.cfg file.
# Usage: git_pull.sh [path/to/git_pull.cfg]
# If no path is provided, the script looks for $GIT_PULL_CFG env var, then
# ${SCRIPT_DIR}/git_pull.cfg

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG_PATH="${1:-${GIT_PULL_CFG:-$SCRIPT_DIR/git_pull.cfg}}"

if [[ "${1-}" == "--help" || "${1-}" == "-h" ]]; then
  cat <<'USAGE'
Usage: git_pull.sh [config_file]

Reads configuration variables from a text file (KEY=VALUE) and performs a
'git pull' in the configured repository.

Required variables in config file:
  REPO_PATH   - path to the repository
  GIT_EXEC    - path to the git executable

Optional variables:
  REMOTE        - git remote name (default: origin)
  BRANCH        - branch to pull (default: main)
  LOG_FILE      - full path to a log file to append output to (optional)
  GIT_PULL_DESC - short description to include after the timestamp in logs
                   (optional; defaults to repository basename)

Example config file (git_pull.cfg):
  REPO_PATH=~/ssh-repo
  GIT_EXEC=/usr/bin/git
  REMOTE=origin
  BRANCH=main
  LOG_FILE=~/logs/git_pull.log
  GIT_PULL_DESC="Homeserver nightly pull"
USAGE
  exit 0
fi

if [[ ! -f "$CFG_PATH" ]]; then
  echo "Error: configuration file not found: $CFG_PATH" >&2
  echo "Create one at '$CFG_PATH' or pass its path as the first argument." >&2
  exit 2
fi

# shellcheck disable=SC1090
source "$CFG_PATH"

# Expand leading ~ in REPO_PATH if present
if [[ "${REPO_PATH-}" == ~* ]]; then
  REPO_PATH="${REPO_PATH/#~/$HOME}"
fi

# Validate required variables
: "${REPO_PATH:?REPO_PATH must be set in $CFG_PATH}" 
: "${GIT_EXEC:?GIT_EXEC must be set in $CFG_PATH}"

REMOTE="${REMOTE:-origin}"
BRANCH="${BRANCH:-main}"

# Handle optional logging
if [[ -n "${LOG_FILE-}" ]]; then
  # Expand leading ~ in LOG_FILE if present
  if [[ "${LOG_FILE}" == ~* ]]; then
    LOG_FILE="${LOG_FILE/#~/$HOME}"
  fi
  LOG_DIR="$(dirname "$LOG_FILE")"
  if [[ ! -d "$LOG_DIR" ]]; then
    # Try to create the directory for the log file
    if ! mkdir -p "$LOG_DIR"; then
      echo "Error: directory for LOG_FILE '$LOG_DIR' does not exist and could not be created" >&2
      exit 5
    fi
  fi
  # Try to create the file if it does not exist and check writability
  if ! touch "$LOG_FILE" 2>/dev/null; then
    echo "Error: Cannot create or write to log file '$LOG_FILE'" >&2
    exit 6
  fi
  if [[ ! -w "$LOG_FILE" ]]; then
    echo "Error: Log file '$LOG_FILE' is not writable" >&2
    exit 7
  fi
fi

function writelog {
  # write log line with timestamp and description prefix
  local line="$1"
  local formatted
  formatted=$(printf '%s %s %s' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "${DESC-}" "$line")
  if [[ -n "${LOG_FILE-}" ]]; then
    printf '%s\n' "$formatted" | tee -a "$LOG_FILE"
  else
    printf '%s\n' "$formatted" >&2
  fi
}

# Validate paths
if [[ ! -d "$REPO_PATH" ]]; then
  writelog "Error: REPO_PATH '$REPO_PATH' does not exist or is not a directory"
  exit 3
fi
if [[ ! -x "$GIT_EXEC" ]]; then
  writelog "Error: GIT_EXEC '$GIT_EXEC' not found or not executable"
  exit 4
fi

# Resolve description for logs (fallback to repository basename)
GIT_PULL_DESC="${GIT_PULL_DESC-}"
DESC="${GIT_PULL_DESC:-$(basename "$REPO_PATH")}"

# Perform git pull (optionally log output with timestamp and description prefix)
cd "$REPO_PATH" || exit
if [[ -n "${LOG_FILE-}" ]]; then
  # Header
  writelog "START"
  # Stream git output with timestamp+description prefixed per line
  "$GIT_EXEC" pull "$REMOTE" "$BRANCH" 2>&1 | while IFS= read -r line; do
    writelog "$line"
  done
  # Footer
  writelog "END"
else
  "$GIT_EXEC" pull "$REMOTE" "$BRANCH" 2>&1
fi
