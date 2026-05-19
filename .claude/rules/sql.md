# SQL & Migrations

Applies to `*.sql` files and code that executes SQL.

## Queries

- **Parameterize all queries** — always use `@param` syntax with Dapper. Never concatenate user input into SQL strings.
- **LIKE wildcard escaping**: `.Replace("[", "[[]").Replace("%", "[%]").Replace("_", "[_]")` for search handlers.
- **Views**: name like tables (no `vw_` prefix).

## Migrations

- `IF NOT EXISTS` guard for CREATE TABLE.
- `IF EXISTS / DROP VIEW` then `CREATE VIEW` for views (idempotent).
- Index naming: `UQ_` for unique, `IX_` for non-clustered.
- Standard columns: `IsDeleted BIT NOT NULL DEFAULT 0`, `CreatedOn DATETIME2 NOT NULL`, `LastModifiedOn DATETIME2 NOT NULL`.
- GRANT permissions on new tables/views to: `FmfxDeveloper`, `FmfxSupportTeam`, `FmfxReleaseAPP`, plus module-specific roles.
- DbUp scripts are embedded resources — just add the `.sql` file to the Scripts folder.
- **Use `GO` batch separators** for multi-step migrations, especially anything toggling system versioning or altering schema before inserting data.
- **Steps that disable system versioning** cannot live in a DbUp transaction — make them independently idempotent so a re-run after failure succeeds.
