# Change-Feed Handler Idempotency

Applies to read-model handlers on the Cosmos change-feed path.

Change feed is at-least-once: lease-checkpoint gaps cause re-delivery. Handlers MUST be safe to re-run on the same document version.

- Use `WHERE NOT EXISTS` on INSERTs, or `MERGE` with a proper match clause. Never a naked INSERT that would violate a unique constraint on re-delivery.
- For missing aggregates, use `MaybeGetById<T>` + `Switch` — NOT `Get<T>` + null check. `Get<T>` returns non-nullable and throws on 404; the null check is dead code and the throw triggers a CF retry loop.
- If skipping missing aggregates is legitimate (e.g. deletion races), make it an explicit `IsNone` branch with a comment, not a null guard.
