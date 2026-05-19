#!/usr/bin/env bash
# Standalone test harness for version-check.sh.
#
# Stages a temporary plugin root, mocks the upstream fetch by priming the
# cache file, and exercises every interesting path:
#
#   1. up-to-date         → exit 0, no stdout
#   2. stale              → exit 0, additionalContext JSON on stdout
#   3. gh_missing         → exit 0, install-gh additionalContext on stdout
#   4. negative cache hit → exit 0, no stdout
#   5. invalid installed  → exit 0, no stdout (fail-open)
#   6. missing plugin.json → exit 0, no stdout (fail-open)
#
# Does NOT exercise the real network — mirrors the PowerShell harness so the
# bash semver/JSON paths stay locked down across refactors.
#
# Run from the plugin root:
#   bash hooks/version-check/test-version-check.sh

set -u

script_dir="$(cd "$(dirname "$0")" && pwd)"
script="$script_dir/version-check.sh"
cache_path="${TMPDIR:-/tmp}/freemarket-claude-skills-version-check.json"
failures=0

new_plugin_root() {
  local version="$1"
  local root
  root="$(mktemp -d -t vc-test.XXXXXX)"
  mkdir -p "$root/.claude-plugin"
  printf '{"name":"freemarket-tools","metadata":{"version":"%s"}}' "$version" > "$root/.claude-plugin/marketplace.json"
  printf '%s' "$root"
}

set_cache() {
  local outcome="$1" latest="$2" age_seconds="${3:-30}" reason="${4:-network}"
  local checked
  if date -u -d "@$(($(date -u +%s) - age_seconds))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null > /tmp/.vc_iso; then
    checked="$(cat /tmp/.vc_iso)"
  else
    # macOS BSD date
    checked="$(date -u -j -v "-${age_seconds}S" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  fi
  rm -f /tmp/.vc_iso
  if [ "$outcome" = "ok" ]; then
    printf '{"checked_at":"%s","outcome":"ok","latest_version":"%s"}' "$checked" "$latest" > "$cache_path"
  else
    printf '{"checked_at":"%s","outcome":"%s","reason":"%s"}' "$checked" "$outcome" "$reason" > "$cache_path"
  fi
}

remove_cache() { rm -f "$cache_path"; }

invoke_hook() {
  local root="$1"
  CLAUDE_PLUGIN_ROOT="$root" bash "$script" 2>/dev/null
  echo "__EXIT__$?"
}

assert() {
  local name="$1" pass="$2" detail="${3:-}"
  if [ "$pass" = "1" ]; then
    printf '  PASS  %s\n' "$name"
  else
    printf '  FAIL  %s  %s\n' "$name" "$detail" >&2
    failures=$((failures + 1))
  fi
}

split_output() {
  # Splits the captured `<stdout>__EXIT__<rc>` into stdout (no trailing newline) + rc.
  local raw="$1"
  rc="${raw##*__EXIT__}"
  out="${raw%__EXIT__*}"
  # Trim trailing newline that bash adds.
  out="${out%$'\n'}"
}

echo 'version-check.sh — standalone tests'

# 1. up-to-date
remove_cache
root="$(new_plugin_root '1.21.0')"
set_cache ok '1.21.0'
raw="$(invoke_hook "$root")"
split_output "$raw"
[ -z "$out" ]   && a=1 || a=0; assert 'up-to-date emits no stdout' "$a" "stdout='$out'"
[ "$rc" = '0' ] && a=1 || a=0; assert 'up-to-date exits 0'         "$a" "rc=$rc"
rm -rf "$root"

# 2. stale
remove_cache
root="$(new_plugin_root '1.0.0')"
set_cache ok '1.21.0'
raw="$(invoke_hook "$root")"
split_output "$raw"
echo "$out" | grep -q '"hookEventName":"SessionStart"' && a=1 || a=0; assert 'stale emits SessionStart JSON' "$a" "stdout='$out'"
echo "$out" | grep -q '1\.0\.0' && echo "$out" | grep -q '1\.21\.0' && a=1 || a=0; assert 'stale mentions both versions' "$a" "stdout='$out'"
echo "$out" | grep -q '/plugin update' && a=1 || a=0; assert 'stale mentions /plugin update' "$a" "stdout='$out'"
[ "$rc" = '0' ] && a=1 || a=0; assert 'stale exits 0' "$a" "rc=$rc"
rm -rf "$root"

# 3. gh_missing cache hit — should warn but never call the network
remove_cache
root="$(new_plugin_root '1.21.0')"
set_cache gh_missing '' 60 gh_not_on_path
raw="$(invoke_hook "$root")"
split_output "$raw"
echo "$out" | grep -q '"hookEventName":"SessionStart"' && a=1 || a=0; assert 'gh_missing emits SessionStart JSON' "$a" "stdout='$out'"
echo "$out" | grep -qi 'github cli\|gh ' && a=1 || a=0; assert 'gh_missing mentions gh / GitHub CLI' "$a" "stdout='$out'"
echo "$out" | grep -q 'gh auth login' && a=1 || a=0; assert 'gh_missing mentions gh auth login' "$a" "stdout='$out'"
[ "$rc" = '0' ] && a=1 || a=0; assert 'gh_missing exits 0' "$a" "rc=$rc"
rm -rf "$root"

# 4. negative cache hit
remove_cache
root="$(new_plugin_root '1.0.0')"
set_cache gh_fetch_failed '' 60
raw="$(invoke_hook "$root")"
split_output "$raw"
[ -z "$out" ]   && a=1 || a=0; assert 'negative cache emits no stdout' "$a" "stdout='$out'"
[ "$rc" = '0' ] && a=1 || a=0; assert 'negative cache exits 0'         "$a" "rc=$rc"
rm -rf "$root"

# 5. invalid installed version
remove_cache
root="$(new_plugin_root 'not-a-semver')"
raw="$(invoke_hook "$root")"
split_output "$raw"
[ -z "$out" ]   && a=1 || a=0; assert 'invalid installed emits no stdout' "$a" "stdout='$out'"
[ "$rc" = '0' ] && a=1 || a=0; assert 'invalid installed exits 0'         "$a" "rc=$rc"
rm -rf "$root"

# 6. missing marketplace.json
remove_cache
root="$(mktemp -d -t vc-test.XXXXXX)"
raw="$(invoke_hook "$root")"
split_output "$raw"
[ -z "$out" ]   && a=1 || a=0; assert 'missing marketplace.json emits no stdout' "$a" "stdout='$out'"
[ "$rc" = '0' ] && a=1 || a=0; assert 'missing marketplace.json exits 0'         "$a" "rc=$rc"
rm -rf "$root"

remove_cache

echo ""
if [ "$failures" -gt 0 ]; then
  echo "FAILED: $failures test(s)" >&2
  exit 1
fi
echo "ALL TESTS PASSED"
exit 0
