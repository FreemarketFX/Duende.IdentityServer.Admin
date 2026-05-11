---
name: stylecop-precheck
description: "Audit C# files for common StyleCop and analyzer violations before building. Catches SA1202, SA1413, SA1210, IDE1006, and more. Triggers on: stylecop precheck, check stylecop, precheck build, analyzer check, check before build."
license: MIT
---

# StyleCop Pre-Check

Scan modified C# files for the most common StyleCop/Roslyn analyzer violations **before** running `dotnet build`. Catches ~80% of the mechanical issues that waste build iterations.

> This is a heuristic pre-check, not a replacement for the build. It catches the patterns that appear most frequently in Ralph progress logs.

---

## The Job

1. Identify modified C# files on the current branch
2. Read each file and scan for known anti-patterns
3. Report findings with file, line, rule ID, and suggested fix
4. Offer to auto-fix each finding

---

## Step 0: Load Project Rules

Before scanning, re-read the project's coding rules so they are fresh in context:

1. **Find CLAUDE.md**: Run `Glob("CLAUDE.md")` from the repo root. If not found, try `Glob("**/CLAUDE.md")` and take the first match not inside `claude-shared/`, `node_modules/`, or `.claude/`.
2. **Extract rules**: Look for Code Style, Naming Conventions, and Architecture sections. Treat every bullet as a constraint.
3. **Check for MEMORY.md**: Run `Glob("MEMORY.md")` from the repo root. If found, read it and follow links to any `feedback` type entries.
4. **Carry forward**: Keep these rules as a checklist when scanning.

If no repo-level CLAUDE.md is found, skip this step.

---

## Step 1: Identify Target Files

Find C# files changed on this branch:

```bash
# Files changed vs main
git diff --name-only main...HEAD -- '*.cs'

# If on main or no branch diff, check uncommitted changes
git diff --name-only HEAD -- '*.cs'
git diff --name-only --cached -- '*.cs'
```

Also accept explicit file paths from the user. If no files found, tell the user and stop.

Read every target file with the Read tool before scanning.

---

## Step 2: Scan for Known Anti-Patterns

For each target file, check for these violations. Use the Read tool output (with line numbers) to detect patterns.

### Member Ordering (SA1202, SA1203, SA1214)

**SA1202 — Public members must come before private members.**
Scan each class body for access modifier ordering. The required order is:
1. `public` members
2. `internal` members
3. `protected` members
4. `private` members

Within each access level, the order is:
1. Constants
2. Static readonly fields
3. Static fields
4. Readonly fields
5. Fields
6. Constructors
7. Properties
8. Methods

Flag any `private` field/method/property that appears before a `public` one in the same class.

**SA1203 — Constants must appear before non-constant fields.**
Flag any `const` declaration that appears after a non-const field in the same class.

**SA1214 — Readonly fields must appear before non-readonly fields.**
Flag any `readonly` field that appears after a non-readonly field at the same access level.

### Trailing Commas (SA1413)

**SA1413 — Use trailing comma in multi-line initializers.**
Look for multi-line collection/object/enum initializers where the last element before `}`, `]`, or `)` does NOT have a trailing comma. Common forms:

```csharp
// BAD — missing trailing comma
string[] items =
[
    "one",
    "two"   // <-- needs comma
];

// BAD — enum missing trailing comma
public enum Status
{
    Active,
    Inactive   // <-- needs comma
}
```

### Comment Formatting (SA1512)

**SA1512 — Single-line comment must not be followed by blank line.**
Look for a `//` comment line immediately followed by an empty line.

### Constructor Initializer (SA1128)

**SA1128 — Constructor initializer must be on its own line.**
Look for `: base(` or `: this(` on the same line as the constructor signature closing parenthesis.

```csharp
// BAD
public MyClass(int x) : base(x) { }

// GOOD
public MyClass(int x)
    : base(x)
{
}
```

### Using Directive Ordering (SA1210)

**SA1210 — Using directives must be ordered alphabetically.**
Read the `using` block at the top of the file. Check that directives are in alphabetical order (case-sensitive, `System` namespaces first if the project uses that convention).

### Naming Rules (IDE1006)

**IDE1006 — Naming rule violation.**
Check private fields: they MUST start with `_` followed by a lowercase letter.

```csharp
// BAD
private readonly ILogger logger;
private int count;

// GOOD
private readonly ILogger _logger;
private int _count;
```

Also check: private `const` fields must use `_camelCase` (per `.editorconfig` in most repos — verify against CLAUDE.md).

### Single-Line Bodies (SA1502)

**SA1502 — Element must not be on a single line.**
Look for single-line class/struct/interface/method bodies with braces:

```csharp
// BAD
public void DoNothing() { }

// GOOD
public void DoNothing()
{
}
```

Exception: expression-bodied members (`=>`) and records are fine.

### Parameter Formatting (SA1117)

**SA1117 — Parameters must be on the same line or each on its own line.**
Look for method declarations or calls where parameters are split across lines but some lines have multiple parameters.

---

## Step 3: Report Findings

Output a table grouped by file:

```
### path/to/File.cs

| Line | Rule | Description | Fix |
|------|------|-------------|-----|
| 15 | SA1202 | Private field `_repo` appears before public property `Name` | Move `_repo` after all public members |
| 42 | SA1413 | Missing trailing comma after last enum value | Add comma after `Inactive` |
| 7 | SA1210 | `using System.Linq` should come before `using Xunit` | Reorder alphabetically |
```

End with a summary: `X files scanned, Y violations found (Z auto-fixable)`.

If no violations found, say so and confirm the code looks clean.

---

## Step 4: Auto-Fix

Ask the user: "Want me to fix these? (all / pick individually / skip)"

For each fixable violation, use the Edit tool to apply the fix. After all fixes, re-run Step 2 on the modified files to verify no new issues were introduced.

**Auto-fixable rules:** SA1210 (reorder usings), SA1413 (add trailing comma), SA1512 (remove blank line after comment), IDE1006 (add `_` prefix to private fields).

**Manual-fix rules (report only):** SA1202/SA1203/SA1214 (member reordering — too risky to auto-move), SA1128 (constructor reformatting), SA1502 (body reformatting), SA1117 (parameter reformatting).

---

## Checklist

- [ ] All modified C# files on the branch were scanned
- [ ] Findings include file path, line number, rule ID, and fix description
- [ ] Auto-fixes applied cleanly (no new violations introduced)
- [ ] User informed this is a pre-check — build may still catch additional issues
