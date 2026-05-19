#!/bin/bash
# Smoke harness for the freemarket-monolith-hooks bundle. Pipes a synthetic
# tool-input JSON envelope to each hook, captures exit code + stderr length,
# and asserts against the expected outcome (block / pass).
#
# Run from repo root: bash hooks/freemarket-monolith-hooks/run-tests.sh
#
# Exit code is the number of failing cases.

set -u

DIR="hooks/freemarket-monolith-hooks"
PASS=0
FAIL=0
ROWS=()

run_case() {
    local label="$1" hook="$2" expect="$3" payload="$4"
    local out exit
    out=$(printf '%s' "$payload" | bash "$DIR/$hook" 2>&1)
    exit=$?
    local actual
    if [ "$exit" -eq 0 ] && ! printf '%s' "$out" | grep -q '"continue":false'; then
        actual="pass"
    else
        actual="block"
    fi
    local mark="OK"
    if [ "$actual" != "$expect" ]; then
        mark="FAIL"
        FAIL=$((FAIL+1))
    else
        PASS=$((PASS+1))
    fi
    printf '%s | %-44s | %-50s | %s | %s | exit=%d\n' \
        "$mark" "$hook" "$label" "$expect" "$actual" "$exit"
    ROWS+=("| $([ "$mark" = "OK" ] && echo '✅' || echo '❌') | \`$hook\` | $label | $expect | $actual | $exit |")
}

###############################################################################
# block-pr-approve.sh
###############################################################################
run_case "block: gh pr review --approve" \
    "block-pr-approve.sh" "block" \
    '{"command":"gh pr review 151 --approve"}'
run_case "block: gh pr review -a (short)" \
    "block-pr-approve.sh" "block" \
    '{"command":"gh pr review 151 -a"}'
run_case "block: gh api reviews --field event=APPROVE" \
    "block-pr-approve.sh" "block" \
    '{"command":"gh api -X POST repos/x/y/pulls/1/reviews --field event=APPROVE"}'
run_case "block: gh api reviews JSON event APPROVE" \
    "block-pr-approve.sh" "block" \
    '{"command":"gh api repos/x/y/pulls/1/reviews -F event=APPROVE"}'
run_case "pass: git commit -m mentioning approve in body" \
    "block-pr-approve.sh" "pass" \
    '{"command":"git commit -m \"docs: explain gh pr review --approve workflow\""}'
run_case "pass: git commit -m mentioning event APPROVE" \
    "block-pr-approve.sh" "pass" \
    '{"command":"git commit -m \"refactor: handle event APPROVE branch\""}'
run_case "pass: gh pr view (read-only)" \
    "block-pr-approve.sh" "pass" \
    '{"command":"gh pr view 151"}'
run_case "pass: tool_input.command nesting (read-only)" \
    "block-pr-approve.sh" "pass" \
    '{"tool_input":{"command":"gh pr view 151"}}'
run_case "block: tool_input.command nesting (approve)" \
    "block-pr-approve.sh" "block" \
    '{"tool_input":{"command":"gh pr review 151 --approve"}}'
run_case "pass: nested heredocs different tags + approve string in body" \
    "block-pr-approve.sh" "pass" \
    '{"command":"git commit -m \"$(cat <<EOF\nfoo gh pr review --approve\nEOF\n)\" && cat <<BODY\nfilling\nBODY"}'

###############################################################################
# enforce-no-tasks-current-commits.sh
###############################################################################
run_case "block: git add tasks/current/prd.json" \
    "enforce-no-tasks-current-commits.sh" "block" \
    '{"command":"git add tasks/current/prd.json"}'
run_case "block: tool_input.command nesting" \
    "enforce-no-tasks-current-commits.sh" "block" \
    '{"tool_input":{"command":"git add tasks/current/prd.json"}}'
run_case "pass: git add unrelated path" \
    "enforce-no-tasks-current-commits.sh" "pass" \
    '{"command":"git add src/Foo.cs"}'
run_case "pass: gh pr view (not git add/commit)" \
    "enforce-no-tasks-current-commits.sh" "pass" \
    '{"command":"gh pr view 151"}'

###############################################################################
# enforce-pr-build-doctor.sh
###############################################################################
run_case "pass: unrelated git status" \
    "enforce-pr-build-doctor.sh" "pass" \
    '{"command":"git status"}'

###############################################################################
# enforce-no-dynamic-in-tests.sh
###############################################################################
run_case "block: dynamic in test/ path" \
    "enforce-no-dynamic-in-tests.sh" "block" \
    '{"file_path":"/repo/test/Users.Tests/Foo.cs","content":"dynamic x = q.Single();"}'
run_case "pass: dynamic in src/ (not test)" \
    "enforce-no-dynamic-in-tests.sh" "pass" \
    '{"file_path":"/repo/src/Foo.cs","content":"dynamic x = q.Single();"}'
run_case "pass: typed record in test/" \
    "enforce-no-dynamic-in-tests.sh" "pass" \
    '{"file_path":"/repo/test/Foo.cs","content":"sealed record Row(Guid Id);"}'
run_case "pass: dynamic in comment only" \
    "enforce-no-dynamic-in-tests.sh" "pass" \
    '{"file_path":"/repo/test/Foo.cs","content":"// dynamic was removed last sprint"}'

###############################################################################
# enforce-no-empty-self-link.sh
###############################################################################
run_case "block: HateoasLink(\"self\", string.Empty)" \
    "enforce-no-empty-self-link.sh" "block" \
    '{"file_path":"X.cs","content":"new HateoasLink(\"self\", string.Empty)"}'
run_case "block: HateoasLink(\"self\", \"\")" \
    "enforce-no-empty-self-link.sh" "block" \
    '{"file_path":"X.cs","content":"new HateoasLink(\"self\", \"\")"}'
run_case "pass: real route" \
    "enforce-no-empty-self-link.sh" "pass" \
    '{"file_path":"X.cs","content":"new HateoasLink(\"self\", route)"}'
run_case "pass: non-cs file" \
    "enforce-no-empty-self-link.sh" "pass" \
    '{"file_path":"X.md","content":"new HateoasLink(\"self\", string.Empty)"}'
run_case "pass: in comment (stripped before match)" \
    "enforce-no-empty-self-link.sh" "pass" \
    '{"file_path":"X.cs","content":"// new HateoasLink(\"self\", \"\") removed"}'

###############################################################################
# enforce-bdd-when-step.sh
###############################################################################
run_case "block: Then without When (Task)" \
    "enforce-bdd-when-step.sh" "block" \
    '{"file_path":"test/Foo.Specs.cs","content":"[Fact]\npublic async Task T() { Then(X); }"}'
run_case "block: Then without When (ValueTask)" \
    "enforce-bdd-when-step.sh" "block" \
    '{"file_path":"test/Foo.Specs.cs","content":"[Fact]\npublic async ValueTask T() { Then(X); }"}'
run_case "pass: When + Then both present" \
    "enforce-bdd-when-step.sh" "pass" \
    '{"file_path":"test/Foo.Specs.cs","content":"[Fact]\npublic async Task T() { When(D); Then(H); }"}'
run_case "pass: not a Specs.cs file" \
    "enforce-bdd-when-step.sh" "pass" \
    '{"file_path":"src/Foo.cs","content":"[Fact]\npublic async Task T() { Then(X); }"}'

###############################################################################
# enforce-no-callerUserId-property.sh
###############################################################################
run_case "block: CallerUserId property" \
    "enforce-no-callerUserId-property.sh" "block" \
    '{"file_path":"X.Command.cs","content":"public Guid CallerUserId { get; init; }"}'
run_case "pass: only AuthorizationId" \
    "enforce-no-callerUserId-property.sh" "pass" \
    '{"file_path":"X.Command.cs","content":"public Guid AuthorizationId { get; init; }"}'
run_case "pass: not a Command.cs" \
    "enforce-no-callerUserId-property.sh" "pass" \
    '{"file_path":"X.Handler.cs","content":"public Guid CallerUserId { get; init; }"}'

###############################################################################
# enforce-permission-before-notfound.sh
###############################################################################
run_case "block: NotFound before HasPermission in HandleAsync" \
    "enforce-permission-before-notfound.sh" "block" \
    '{"file_path":"X.Command.cs","content":"public class H { public async Task HandleAsync(C c, CancellationToken ct) { if (e == null) { c.Result = new NotFound(); return; } if (!c.Permissions.HasPermission(\"X\")) {} } }"}'
run_case "pass: HasPermission first in HandleAsync" \
    "enforce-permission-before-notfound.sh" "pass" \
    '{"file_path":"X.Command.cs","content":"public class H { public async Task HandleAsync(C c, CancellationToken ct) { if (!c.Permissions.HasPermission(\"X\")) return; if (e == null) c.Result = new NotFound(); } }"}'
run_case "pass: NotFound in sibling class only (HandleAsync OK)" \
    "enforce-permission-before-notfound.sh" "pass" \
    '{"file_path":"X.Command.cs","content":"public class V { void M() { return new NotFound(); } } public class H { public async Task HandleAsync(C c, CancellationToken ct) { if (!c.Permissions.HasPermission(\"X\")) return; } }"}'

###############################################################################
# enforce-no-utcnow-in-readmodel.sh
###############################################################################
run_case "block: DateTimeOffset.UtcNow in *.Query.cs" \
    "enforce-no-utcnow-in-readmodel.sh" "block" \
    '{"file_path":"X.Query.cs","content":"var now = DateTimeOffset.UtcNow;"}'
run_case "pass: DateTimeOffset.UtcNow in *.Command.cs" \
    "enforce-no-utcnow-in-readmodel.sh" "pass" \
    '{"file_path":"X.Command.cs","content":"var now = DateTimeOffset.UtcNow;"}'

###############################################################################
# enforce-sql-migration-rules.sh
###############################################################################
run_case "block: CREATE TABLE without GRANTs / IsDeleted" \
    "enforce-sql-migration-rules.sh" "block" \
    '{"file_path":"src/Foo/Migrations/Scripts/0042-Foo.sql","content":"CREATE TABLE [dbo].[Bar] ( Id INT );"}'
run_case "block: <3 GRANTs" \
    "enforce-sql-migration-rules.sh" "block" \
    '{"file_path":"src/Foo/Migrations/Scripts/0042-Foo.sql","content":"CREATE TABLE [dbo].[Bar] ( Id INT, IsDeleted BIT NOT NULL DEFAULT 0 );\nGRANT SELECT ON [dbo].[Bar] TO [RoleA];"}'
run_case "pass: 3 GRANTs (any role names) + IsDeleted" \
    "enforce-sql-migration-rules.sh" "pass" \
    '{"file_path":"src/Foo/Migrations/Scripts/0042-Foo.sql","content":"CREATE TABLE [dbo].[Bar] ( Id INT, IsDeleted BIT NOT NULL DEFAULT 0 );\nGRANT SELECT ON [dbo].[Bar] TO [RoleA];\nGRANT SELECT ON [dbo].[Bar] TO [RoleB];\nGRANT SELECT ON [dbo].[Bar] TO [RoleC];"}'
run_case "pass: not a migration path" \
    "enforce-sql-migration-rules.sh" "pass" \
    '{"file_path":"src/Foo/Other.sql","content":"CREATE TABLE [dbo].[Bar] ( Id INT );"}'

###############################################################################
# enforce-prd-research.sh
###############################################################################
run_case "block: TBD without research" \
    "enforce-prd-research.sh" "block" \
    '{"file_path":"/repo/tasks/prd-foo.md","content":"# Foo\nTBD"}'
run_case "pass: deferral with research evidence" \
    "enforce-prd-research.sh" "pass" \
    '{"file_path":"/repo/tasks/prd-foo.md","content":"TBD\nSearched: gh search code returned no match in codebase."}'
run_case "pass: not a PRD/ADR file" \
    "enforce-prd-research.sh" "pass" \
    '{"file_path":"/repo/docs/notes.md","content":"TBD"}'

###############################################################################
# enforce-askuserquestion-rules.sh
###############################################################################
run_case "block: option label '(Recommended)'" \
    "enforce-askuserquestion-rules.sh" "block" \
    '{"questions":[{"options":[{"label":"Use FluentValidation (Recommended)"}]}]}'
run_case "pass: genuine ambiguous question" \
    "enforce-askuserquestion-rules.sh" "pass" \
    '{"questions":[{"options":[{"label":"Approach A"},{"label":"Approach B"}]}]}'

###############################################################################
# Microservice no-op cross-checks (out-of-scope file paths)
###############################################################################
run_case "microservice no-op: src/Foo.cs (BDD hook)" \
    "enforce-bdd-when-step.sh" "pass" \
    '{"file_path":"src/Foo.cs","content":"Then(x);"}'
run_case "microservice no-op: src/Foo.cs (CallerUserId)" \
    "enforce-no-callerUserId-property.sh" "pass" \
    '{"file_path":"src/Foo.cs","content":"public Guid CallerUserId { get; init; }"}'
run_case "microservice no-op: src/Foo.cs (dynamic)" \
    "enforce-no-dynamic-in-tests.sh" "pass" \
    '{"file_path":"src/Foo.cs","content":"dynamic x;"}'
run_case "microservice no-op: src/Foo.cs (perm-before-nf)" \
    "enforce-permission-before-notfound.sh" "pass" \
    '{"file_path":"src/Foo.cs","content":"new NotFound(); HasPermission();"}'
run_case "microservice no-op: src/integration.sql (sql)" \
    "enforce-sql-migration-rules.sh" "pass" \
    '{"file_path":"src/integration.sql","content":"CREATE TABLE [dbo].[Bar] (Id INT);"}'

echo ""
echo "==============================================="
echo "PASS: $PASS / $((PASS+FAIL))"
echo "FAIL: $FAIL"
echo "==============================================="

if [ "${EMIT_PR_TABLE:-0}" = "1" ]; then
    echo ""
    echo "| | Hook | Scenario | Expected | Actual | Exit |"
    echo "|---|---|---|---|---|---|"
    for row in "${ROWS[@]}"; do echo "$row"; done
fi

exit "$FAIL"
