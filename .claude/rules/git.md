# Git Concurrency & Lock Recovery

Applies any time git is run from an automated session (interactive Claude, Ralph, etc.).

## Concurrency

Git is NOT concurrent-safe within a single repository. Never run two git commands simultaneously across foreground + background bash tasks. All git operations MUST be foreground and sequential.

## Index Lock Recovery

If a git command fails with:

```
fatal: Unable to create '.git/index.lock': File exists.
```

A previous git invocation was killed mid-write (often a SIGTERM from a timeout or parent shell exit). Recovery:

1. Confirm no other bash task or background process is running git in this repo.
2. `rm .git/index.lock`
3. Retry the original command.

Do NOT investigate the lock file's contents or age — it's a marker, not data. Just remove it and retry.
