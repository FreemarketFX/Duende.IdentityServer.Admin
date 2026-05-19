#!/usr/bin/env bash
# SessionStart plugin-version-check hook (*nix).
#
# Compares the installed plugin version (from
# ${CLAUDE_PLUGIN_ROOT}/.claude-plugin/marketplace.json metadata.version)
# against the same field on `main` upstream. Fetch goes through the GitHub
# CLI (`gh api`), reusing whatever auth token the user already has from
# `gh auth login` — works for our private source repo, no extra setup. When
# stale, emits SessionStart additionalContext JSON to stdout so Claude can
# prompt the user to /plugin update.
#
# If `gh` is not on PATH the hook emits a one-time-per-hour additionalContext
# warning advising the user to install it. All other error paths exit 0
# silently.
#
# Telemetry contract:
#   outcome ∈ { ok, warn, error }
#   status  matches outcome (ok→info, warn→warn, error→error)
#   reason  ∈ { fresh_check, cache_hit, gh_missing, gh_fetch_failed,
#               invalid_version, marketplace_json_missing }
#   installed_version / latest_version are present whenever the script
#   successfully read them, irrespective of outcome.

trap 'exit 0' ERR

PLUGIN_NAME='freemarket-claude-skills'
REPO_OWNER='FreemarketFX'
REPO_NAME='claude-shared'
CACHE_TTL_OK=3600     # 1h — also used for gh_missing
CACHE_TTL_FAIL=900    # 15min — gh_fetch_failed
CACHE_PATH="${TMPDIR:-/tmp}/${PLUGIN_NAME}-version-check.json"
FETCH_TIMEOUT=3

# SessionStart additionalContext is injected into Claude's session context but
# Claude won't surface it to the user unless prompted to. Phrase as an
# imperative instruction directed at Claude so the warning actually reaches
# the user on their first turn — and instruct Claude to use a markdown
# blockquote + emoji + bold so the warning is visually distinct from the
# rest of the response and can't be missed as a stray bullet point.
GH_MISSING_MESSAGE=$'Display this prominently at the very top of your next response, as a markdown blockquote on its own line, prefixed with the warning emoji and using **bold** for the key phrase. Do not paraphrase, but include all of the information given here. Do not summarise it under another heading. Exact format:\n\n> \xe2\x9a\xa0\xef\xb8\x8f **'"${PLUGIN_NAME}"$' plugin update-check disabled** \xe2\x80\x94 install the GitHub CLI (`gh`) and run `gh auth login` so plugin update prompts can work. See https://cli.github.com/.'

# Best-effort capture of SessionStart stdin payload for telemetry.
raw_stdin=""
if [ ! -t 0 ]; then
  raw_stdin="$(cat || true)"
fi

# Source the Datadog helper once. All telemetry calls are best-effort.
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/datadog-log/post.sh" 2>/dev/null || true

# Single telemetry sink. Outcome ∈ { ok | warn | error } maps 1-1 to
# Datadog log status (ok→info, warn→warn, error→error). installed_version
# and latest_version flow through as EXTRA_JSON whenever they're known.
#
# Args:
#   $1 outcome (ok | warn | error)   required
#   $2 reason  (machine-stable code) required
#   $3 message (human one-liner)     optional
#   $4 installed_version             optional
#   $5 latest_version                optional
send_telemetry() {
  local outcome="$1" reason="$2" message="${3:-}" installed_arg="${4:-}" latest_arg="${5:-}"
  local status='info'
  case "$outcome" in
    warn)  status='warn' ;;
    error) status='error' ;;
  esac

  local extra=''
  if [ -n "$installed_arg" ] || [ -n "$latest_arg" ]; then
    if python3 -c 'pass' >/dev/null 2>&1; then
      extra="$(INSTALLED="$installed_arg" LATEST="$latest_arg" python3 -c 'import json,os
d={}
v=os.environ.get("INSTALLED")
l=os.environ.get("LATEST")
if v: d["installed_version"]=v
if l: d["latest_version"]=l
print(json.dumps(d))' 2>/dev/null)"
    elif command -v jq >/dev/null 2>&1; then
      extra="$(jq -nc --arg installed "$installed_arg" --arg latest "$latest_arg" '
        ({} +
         (if ($installed | length) > 0 then {installed_version: $installed} else {} end) +
         (if ($latest    | length) > 0 then {latest_version:    $latest}    else {} end))
      ' 2>/dev/null)"
    fi
  fi

  HOOK=version-check \
  HOOK_EVENT=SessionStart \
  TOOL_NAME='' \
  OUTCOME="$outcome" \
  REASON="$reason" \
  EVENT_NAME=freemarket_tools_version_check \
  STATUS="$status" \
  MESSAGE="$message" \
  STDIN_JSON="$raw_stdin" \
  EXTRA_JSON="$extra" \
    send_datadog_hook_log 2>/dev/null || true
}

write_additional_context() {
  # Build the JSON via python3 / jq rather than printf string interpolation.
  # Today's messages contain only controlled chars (backticks are JSON-safe;
  # version components are validated semver), but a future contributor adding
  # a `"` or `\` to either of the two messages would silently break the JSON.
  # No trailing newline — match the PowerShell side and the SessionStart
  # hook contract (Claude Code accepts either, but consistency aids byte-
  # level diff debugging across platforms).
  local message="$1" body=''
  if python3 -c 'pass' >/dev/null 2>&1; then
    body="$(MSG="$message" python3 -c 'import json,os
print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":os.environ["MSG"]}}), end="")' 2>/dev/null)"
  elif command -v jq >/dev/null 2>&1; then
    body="$(jq -nc --arg m "$message" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}' 2>/dev/null | tr -d '\n')"
  fi
  if [ -z "$body" ]; then
    # Last-ditch fallback for stripped containers without python3 or jq.
    # Inputs are controlled today; if you ever introduce `"` or `\` into the
    # messages, this branch will break — fix python3/jq availability instead.
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}' "$message"
    return
  fi
  printf '%s' "$body"
}

is_semver() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# Returns 0 if A==B, 1 if A<B, 2 if A>B. Both args must already be valid semver.
# 10#$x forces base-10 evaluation: bash's (( )) treats a leading-zero literal
# as octal, so a version like "1.08.0" would otherwise error on the comparison.
# Our regex accepts leading zeros even though canonical semver doesn't, so be
# defensive here.
cmp_semver() {
  local a="$1" b="$2"
  IFS='.' read -r a1 a2 a3 <<< "$a"
  IFS='.' read -r b1 b2 b3 <<< "$b"
  if   (( 10#$a1 < 10#$b1 )); then return 1
  elif (( 10#$a1 > 10#$b1 )); then return 2
  fi
  if   (( 10#$a2 < 10#$b2 )); then return 1
  elif (( 10#$a2 > 10#$b2 )); then return 2
  fi
  if   (( 10#$a3 < 10#$b3 )); then return 1
  elif (( 10#$a3 > 10#$b3 )); then return 2
  fi
  return 0
}

# Tiny JSON value extractor — works for top-level string fields. Good enough
# for our own cache file. Uses python3 if available for robustness, falls
# back to sed.
read_json_string() {
  local file="$1" key="$2"
  if python3 -c 'pass' >/dev/null 2>&1; then
    python3 -c "import json,sys; d=json.load(open(sys.argv[1])); v=d.get(sys.argv[2],''); print(v if isinstance(v,str) else '')" "$file" "$key" 2>/dev/null
  else
    sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$file" 2>/dev/null | head -n1
  fi
}

read_json_string_from_stdin() {
  local key="$1" body="$2"
  if python3 -c 'pass' >/dev/null 2>&1; then
    BODY="$body" KEY="$key" python3 -c "import json,os; d=json.loads(os.environ['BODY']); v=d.get(os.environ['KEY'],''); print(v if isinstance(v,str) else '')" 2>/dev/null
  else
    printf '%s' "$body" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n1
  fi
}

# Extract metadata.version from a marketplace.json file. Both installed
# (${CLAUDE_PLUGIN_ROOT}/.claude-plugin/marketplace.json) and the upstream
# `gh api` body share this shape. python3 path; sed fallback that scopes to
# the metadata block to avoid matching the per-plugin version field.
read_metadata_version_from_file() {
  local file="$1"
  if python3 -c 'pass' >/dev/null 2>&1; then
    python3 -c "import json,sys; d=json.load(open(sys.argv[1])); m=d.get('metadata',{}); v=m.get('version','') if isinstance(m,dict) else ''; print(v if isinstance(v,str) else '')" "$file" 2>/dev/null
  else
    awk '/"metadata"[[:space:]]*:[[:space:]]*\{/{flag=1} flag{print} /\}/{if(flag){flag=0}}' "$file" 2>/dev/null | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
  fi
}

read_metadata_version_from_stdin() {
  local body="$1"
  if python3 -c 'pass' >/dev/null 2>&1; then
    BODY="$body" python3 -c "import json,os; d=json.loads(os.environ['BODY']); m=d.get('metadata',{}); v=m.get('version','') if isinstance(m,dict) else ''; print(v if isinstance(v,str) else '')" 2>/dev/null
  else
    printf '%s' "$body" | awk '/"metadata"[[:space:]]*:[[:space:]]*\{/{flag=1} flag{print} /\}/{if(flag){flag=0}}' | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
  fi
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

now_epoch() { date -u +%s; }

epoch_of_iso() {
  # macOS: date -j -f, Linux: date -d. Try Linux form first.
  date -u -d "$1" +%s 2>/dev/null || date -ju -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || echo 0
}

# Cache file uses an internal `outcome` field with three values that drive
# the next session's hot path. NOT the same vocabulary as the Datadog
# `outcome` — we map at log time:
#   cache.outcome=ok              (1h TTL) → log outcome=ok|warn (depends on compare)
#   cache.outcome=gh_missing      (1h TTL) → log outcome=error reason=gh_missing
#   cache.outcome=gh_fetch_failed (15min TTL) → log outcome=error reason=gh_fetch_failed
write_cache() {
  local cache_outcome="$1" latest="$2"
  if [ -n "$latest" ]; then
    printf '{"checked_at":"%s","outcome":"%s","latest_version":"%s"}' "$(now_iso)" "$cache_outcome" "$latest" > "$CACHE_PATH" 2>/dev/null || true
  else
    printf '{"checked_at":"%s","outcome":"%s"}' "$(now_iso)" "$cache_outcome" > "$CACHE_PATH" 2>/dev/null || true
  fi
}

# Wraps an external command with an optional timeout. `timeout` is GNU
# coreutils (default on Linux, optional on macOS via Homebrew); fall through
# without it when missing — the 5s Claude hook timeout is the backstop.
run_with_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$FETCH_TIMEOUT" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$FETCH_TIMEOUT" "$@"
  else
    "$@"
  fi
}

# Resolve plugin root.
plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$plugin_root" ]; then
  plugin_root="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)"
fi

installed_path="$plugin_root/.claude-plugin/marketplace.json"
if [ ! -r "$installed_path" ]; then
  send_telemetry error marketplace_json_missing "marketplace.json not found at $installed_path"
  exit 0
fi

installed="$(read_metadata_version_from_file "$installed_path")"
if [ -z "$installed" ]; then
  send_telemetry error marketplace_json_missing 'marketplace.json present but unparseable'
  exit 0
fi
if ! is_semver "$installed"; then
  # Don't echo the unparseable string back as installed_version — only
  # valid semver values flow into the version extras, so dashboards stay
  # clean and the field type stays stable.
  send_telemetry error invalid_version 'installed metadata.version is not semver'
  exit 0
fi

# Cache lookup. Hot path — three internal cached states.
latest=""
from_cache=0
if [ -r "$CACHE_PATH" ]; then
  cache_body="$(cat "$CACHE_PATH" 2>/dev/null || true)"
  if [ -n "$cache_body" ]; then
    cached_at="$(read_json_string_from_stdin checked_at "$cache_body")"
    cached_outcome="$(read_json_string_from_stdin outcome "$cache_body")"
    cached_latest="$(read_json_string_from_stdin latest_version "$cache_body")"
    if [ -n "$cached_at" ]; then
      cached_epoch="$(epoch_of_iso "$cached_at")"
      age=$(( $(now_epoch) - cached_epoch ))
      ttl=$CACHE_TTL_OK
      [ "$cached_outcome" = "gh_fetch_failed" ] && ttl=$CACHE_TTL_FAIL
      if (( age >= 0 )) && (( age < ttl )); then
        case "$cached_outcome" in
          ok)
            if is_semver "$cached_latest"; then
              latest="$cached_latest"
              from_cache=1
            fi
            ;;
          gh_missing)
            write_additional_context "$GH_MISSING_MESSAGE"
            send_telemetry error gh_missing "$GH_MISSING_MESSAGE" "$installed"
            exit 0
            ;;
          gh_fetch_failed)
            # Negative cache hit — log so misconfigured clients are still
            # tracked, but no stdout (transient errors don't warn the user).
            send_telemetry error gh_fetch_failed '' "$installed"
            exit 0
            ;;
        esac
      fi
    fi
  fi
fi

if [ -z "$latest" ]; then
  if ! command -v gh >/dev/null 2>&1; then
    # gh missing is a stable user-facing condition. Cache for the full 1h
    # TTL and surface the install-gh warning so the user is prompted at
    # most once an hour, not on every session start.
    write_cache gh_missing ""
    write_additional_context "$GH_MISSING_MESSAGE"
    send_telemetry error gh_missing "$GH_MISSING_MESSAGE" "$installed"
    exit 0
  fi

  # `gh api` with the raw Accept header returns the file body verbatim. Auth
  # is whatever `gh auth login` already configured. We compare against
  # marketplace.json's metadata.version because that's the field the
  # marketplace itself consumes; plugin.json's `version` is kept in
  # lockstep by convention (CLAUDE.md) but the marketplace value is the
  # load-bearing one.
  api_path="repos/${REPO_OWNER}/${REPO_NAME}/contents/.claude-plugin/marketplace.json"
  upstream_body="$(run_with_timeout gh api "$api_path" -H 'Accept: application/vnd.github.raw' 2>/dev/null)"
  rc=$?
  if [ $rc -ne 0 ] || [ -z "$upstream_body" ]; then
    send_telemetry error gh_fetch_failed "gh api failed (rc=$rc)" "$installed"
    write_cache gh_fetch_failed ""
    exit 0
  fi

  latest="$(read_metadata_version_from_stdin "$upstream_body")"
  if [ -z "$latest" ]; then
    send_telemetry error gh_fetch_failed 'upstream marketplace.json unparseable' "$installed"
    write_cache gh_fetch_failed ""
    exit 0
  fi
  if ! is_semver "$latest"; then
    # installed is valid here (we checked earlier); drop only the bad
    # latest value rather than echoing junk into extras.
    send_telemetry error invalid_version 'upstream metadata.version is not semver' "$installed"
    write_cache gh_fetch_failed ""
    exit 0
  fi
  write_cache ok "$latest"
fi

reason='fresh_check'
[ "$from_cache" = "1" ] && reason='cache_hit'

# cmp_semver returns 0/1/2 to encode equal/less/greater. Wrap the call in
# `|| cmp=$?` so the non-zero return doesn't trip the ERR trap (which would
# silently `exit 0` before we reach the warn-output branch below).
cmp=0
cmp_semver "$installed" "$latest" || cmp=$?

if [ "$cmp" = "1" ]; then
  msg=$'Display this prominently at the very top of your next response, as a markdown blockquote on its own line, prefixed with the warning emoji and using **bold** for the key phrase. Do not paraphrase, but include all of the information given here. Do not summarise it under another heading. Exact format:\n\n> \xe2\x9a\xa0\xef\xb8\x8f **'"$PLUGIN_NAME"$' plugin is outdated** \xe2\x80\x94 installed '"$installed"$', latest '"$latest"$'. Run `/plugin marketplace update freemarket-tools` then `/reload-plugins` to upgrade.'
  # Hand-built JSON — fields are all controlled strings, no escaping concerns.
  write_additional_context "$msg"
  send_telemetry warn "$reason" "$msg" "$installed" "$latest"
else
  send_telemetry ok "$reason" '' "$installed" "$latest"
fi

exit 0
