# bash-command-guard — implementation notes

Autoloaded when editing files in this directory. See [`README.md`](./README.md) for usage.

## Regex design rationale

- **`\baz\b` (not `az\b` or `\baz`)** — the Azure CLI is two letters, so almost any single-anchor variant collides with another token. The full word boundary catches `az login`, `az account`, `bash -c "az ..."` and skips `azcopy`, `azure`, `tar -azxvf` (no leading word).
- **`[A-Za-z]+-Az[A-Za-z]+` (Verb-Az*)** — covers the user's `*-Az*` PowerShell module pattern. Requires letters on both sides of the dash, so `tar -azxvf` (no letters before the dash) does NOT match. There's a test case asserting this — keep it.
- **`(get|print)-access-token`** — gcloud uses `print-access-token`, AWS/Azure use `get-access-token`. Easy to forget; the matrix has a `gcloud auth print-access-token` case so we don't regress.
- **Hostname patterns** escape literal dots (`management\.azure\.com`). Without escaping, `managementXazureXcom` would match. Cheap mistake; the test cases catch it.
- **Path patterns vs CLI patterns can collide.** `\.ssh/id_[a-z0-9_]+` matches `ssh-add ~/.ssh/id_ed25519` before the warn-list `\bssh-add\b` rule fires. Block precedence is correct (we'd rather catch the path read than the CLI invocation), so the test matrix uses `ssh-add -L` instead.
- **Short tokens (`swa`, `ksm`) need a tighter left boundary than `\b`.** Plain `\bksm\b` matches `linux-ksm-tools` and `redhat-ksm-tuned` because hyphens are word boundaries. We use `(^|[^[:alnum:]_-])token\b` for any 3-char token: start-of-string, or a char that is not alnum/underscore/hyphen, before the token. The test matrix has explicit negative cases (`linux-ksm-tools status`, `static-swa-bin --version`). If you add another short token, follow this shape.

## Why list files store regexes (not substrings)

We considered a substring-only DSL with `\b` as a special prefix. Regex won — the only thing it costs us is escaping literal dots in URLs, and the matrix catches mistakes. Inventing a DSL would have been more code and less expressive.

## Why we kept the `Bash(az *)` permission deny

Defense-in-depth. The permission layer rejects literal `az ...` invocations before the hook fires, so there are two independent layers an attacker would need to bypass. Removing the permission deny is fine the day this hook ships everywhere with high confidence — until then, both stay.

## DD helper integration

The shared helper at `hooks/lib/datadog-log/post.{sh,ps1}` accepts `OUTCOME` / `REASON` / `STATUS` as pass-through values, so the warn path (`OUTCOME=warn`, `STATUS=warning`) works without changes to the helper. Don't add hook-specific fields to the helper — pass them through `MESSAGE` instead.

The helper is fail-open by design (missing token, no `python3`/`jq`, missing `curl` → silent return). The hook's `emit_dd_log` wrapper adds another `|| true` belt — telemetry must never wedge Bash.

## Test harness contract

`BASH_GUARD_TEST_MODE=1` makes the hook print `<outcome>\t<pattern>` to stdout and suppress stderr. The runners parse that line; if you change the contract, both `test-guard.sh` and `test-guard.ps1` need to follow.

The PS runner uses `[System.Diagnostics.Process]` with explicit stdin redirection rather than `$payload | & powershell.exe`. Reason: PowerShell's pipe to `powershell.exe -File` doesn't reliably forward as raw stdin (the parent shell tries to object-serialize and the child gets either nothing or wrapped objects). Don't switch back to the pipe form.

## Adding new patterns

1. Add the regex to the right list.
2. Add at least one positive case to `test-cases.json`. If the pattern is short or could collide with common shell flags/words (e.g. anything ≤ 3 chars or with a common substring), add a negative case too.
3. Run `./test-guard.sh` and `.\test-guard.ps1` — both must be green before commit.
4. Bump the plugin version in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` per project `CLAUDE.md`.

## Things NOT to do

- Don't move pattern-loading into the DD helper. Keep the helper generic.
- Don't read the lists once at script-source-time and cache them — they're tiny, and re-reading per invocation makes hot-reload Just Work for development.
- Don't add `--allow-once` / per-session bypass plumbing here. If you need that, it belongs in a separate hook layer.
- Don't log the full command — only a 200-char preview. The full command can contain secrets pasted by the user; we log the matched pattern + preview only.
