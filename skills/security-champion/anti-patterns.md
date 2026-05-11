# Security Anti-Patterns Reference

Commonly missed patterns that scanners overlook and developers don't catch. Each example shows the vulnerable code and working fix.

## C# / .NET

```csharp
// BinaryFormatter — deserialization gadget chain (CWE-502)
// Often hidden in legacy serialization helpers
new BinaryFormatter().Deserialize(stream);
// Fix: System.Text.Json with concrete types only, never polymorphic deserialization

// ECB cipher mode — deterministic encryption leaks patterns (CWE-327)
new AesManaged { Mode = CipherMode.ECB }
// Fix: AES-GCM (preferred) or AES-CBC with random IV per operation

// Mass assignment — domain model bound directly from request (CWE-915)
public async Task<IActionResult> Update([FromBody] UserModel user)
// Fix: Bind a scoped DTO/command that omits IsAdmin, Role, etc.

// JWT alg:none / validation disabled (CWE-347)
new TokenValidationParameters { ValidateIssuerSigningKey = false }
// Fix: All Validate* properties must be true. See JWT checklist below.

// Unvalidated open redirect (CWE-601)
return Redirect(Request.Query["returnUrl"]);
// Fix: LocalRedirect(returnUrl) — validates it's a local path

// Developer exception page leaking to production (CWE-209)
app.UseDeveloperExceptionPage(); // outside IsDevelopment() guard
// Fix: if (app.Environment.IsDevelopment()) app.UseDeveloperExceptionPage();

// Middleware ordering — auth bypassed silently
app.UseAuthorization();    // BAD: runs before authentication is set up
app.UseAuthentication();
// Fix: Authentication MUST come before Authorization
app.UseAuthentication();
app.UseAuthorization();

// FromSqlRaw with string concatenation (CWE-89)
var users = _db.Users.FromSqlRaw("SELECT * FROM Users WHERE Name = '" + name + "'");
// Fix: Use FromSqlInterpolated (auto-parameterizes) or FromSqlRaw with params
var users = _db.Users.FromSqlInterpolated($"SELECT * FROM Users WHERE Name = {name}");

// SignalR hub missing authorization
public class AdminHub : Hub { /* no [Authorize] */ }
// Fix: [Authorize(Roles = "Admin")] on the hub class

// Minimal API endpoint missing auth (easy to miss — no [Authorize] attribute to scan for)
app.MapGet("/admin/users", (IUserService svc) => svc.GetAll());
// Fix: Chain .RequireAuthorization()
app.MapGet("/admin/users", (IUserService svc) => svc.GetAll())
   .RequireAuthorization("AdminPolicy");

// XXE — XmlDocument with external entities enabled (CWE-611)
var doc = new XmlDocument();
doc.LoadXml(userInput);  // default allows external entities in .NET Framework
// Fix: Disable external entities explicitly
var doc = new XmlDocument { XmlResolver = null };
doc.LoadXml(userInput);

// Path traversal — Path.Combine does NOT prevent ../../ escapes (CWE-22)
var filePath = Path.Combine(uploadsDir, userFileName);
return PhysicalFile(filePath, "application/octet-stream");
// Fix: Resolve full path and verify it stays within the allowed directory
var fullPath = Path.GetFullPath(Path.Combine(uploadsDir, userFileName));
if (!fullPath.StartsWith(Path.GetFullPath(uploadsDir) + Path.DirectorySeparatorChar))
    return BadRequest("Invalid path");

// ReDoS — catastrophic backtracking in user-facing regex (CWE-1333)
var emailRegex = new Regex(@"^([a-zA-Z0-9]+\.)+[a-zA-Z]{2,}$");
emailRegex.IsMatch(maliciousInput);  // can hang for seconds
// Fix (.NET 7+): Use NonBacktracking mode or set a timeout
var emailRegex = new Regex(@"^([a-zA-Z0-9]+\.)+[a-zA-Z]{2,}$",
    RegexOptions.NonBacktracking);
// Fix (older .NET): Set matchTimeout
var emailRegex = new Regex(pattern, RegexOptions.None, TimeSpan.FromSeconds(1));

// Log injection — unsanitized user input in structured logs (CWE-117)
_logger.LogInformation("User login: " + username);  // attacker injects newlines/fake entries
// Fix: Use structured logging parameters — never concatenate user input
_logger.LogInformation("User login: {Username}", username);

// SSRF — user-controlled URL passed to HttpClient (CWE-918)
var response = await _httpClient.GetAsync(userProvidedUrl);
// Fix: Validate against an allowlist; block internal ranges including Azure IMDS (169.254.169.254)
var uri = new Uri(userProvidedUrl);
if (!_allowedHosts.Contains(uri.Host))
    return BadRequest("URL not allowed");
// Better: Use IHttpClientFactory with a DelegatingHandler that enforces the allowlist centrally

// TLS certificate validation disabled (CWE-295)
var handler = new HttpClientHandler {
    ServerCertificateCustomValidationCallback = (_, _, _, _) => true  // accepts ANY cert
};
// Fix: Remove entirely, or pin to a specific certificate thumbprint for internal services
// If self-signed certs are required, validate the specific certificate rather than bypassing

// Dangerous CORS configuration (CWE-942)
builder.Services.AddCors(o => o.AddPolicy("open", p =>
    p.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader()));
// Fix: Restrict to specific origins; never combine AllowAnyOrigin with AllowCredentials
builder.Services.AddCors(o => o.AddPolicy("strict", p =>
    p.WithOrigins("https://app.example.com").AllowCredentials().AllowAnyMethod()));
```

## Azure Bicep

```bicep
// Secret exposed in output — readable by anyone with deployment access
output storageKey string = storageAccount.listKeys().keys[0].value
// Fix: Never output secrets. Store in Key Vault and reference via secret URI.

// Broad RBAC at subscription scope
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: subscription()   // too broad
  properties: { roleDefinitionId: contributorRoleId }
}
// Fix: Scope to specific resource group or resource; use minimal built-in role
```

## Kubernetes

```yaml
# Security context missing entirely (defaults to root, privileged)
containers:
  - name: app
    image: myapp:latest  # also: unpinned tag
# Fix: Always set securityContext explicitly
securityContext:
  privileged: false
  runAsNonRoot: true
  runAsUser: 1000
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
```

## Terraform

```hcl
# Overly permissive IAM — wildcard actions and resources (CWE-250)
resource "aws_iam_policy" "too_broad" {
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = "*"
      Resource = "*"
    }]
  })
}
# Fix: Scope to specific actions and resources
resource "aws_iam_policy" "scoped" {
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = "arn:aws:s3:::my-bucket/*"
    }]
  })
}

# Public S3 bucket — ACL allows world read
resource "aws_s3_bucket_acl" "public" {
  bucket = aws_s3_bucket.data.id
  acl    = "public-read"
}
# Fix: Use private ACL + S3 bucket policy for specific access
resource "aws_s3_bucket_acl" "private" {
  bucket = aws_s3_bucket.data.id
  acl    = "private"
}
resource "aws_s3_bucket_public_access_block" "block" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Security group open to the world
resource "aws_security_group_rule" "open" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]  # SSH from anywhere
}
# Fix: Restrict to known CIDR ranges or use SSM Session Manager instead
```

## JWT Security Checklist (C# / .NET)

```csharp
new TokenValidationParameters
{
    ValidateIssuerSigningKey = true,              // never false
    IssuerSigningKey = new SymmetricSecurityKey(key), // min 256-bit (32 bytes)
    ValidateIssuer   = true,
    ValidIssuer      = "https://login.microsoftonline.com/{tenantId}/v2.0",
    ValidateAudience = true,
    ValidAudience    = "api://my-app-id",
    ValidateLifetime = true,                      // checks exp claim
    ClockSkew        = TimeSpan.FromMinutes(1)    // tighten from default 5 min
};
```

Red flags — flag as findings immediately:

- `ValidateIssuerSigningKey = false`
- `ValidateLifetime = false`
- Algorithm accepted from token header (alg: none attack)
- Symmetric signing secret shorter than 32 bytes
- Refresh tokens stored in localStorage (use httpOnly cookie instead)
- Token validation result cached across requests

## Secrets Detection — Flag These Patterns

**Severity by context — not all secrets are equal:**
- **Critical:** Real production credentials, live API keys, actual SAS tokens, PEM private keys — regardless of which file they appear in
- **Medium:** Placeholder or template passwords in dev config files (`appsettings.Development.json`, `docker-compose.yml`, `bootstrap.ps1`) — the pattern is wrong even if the value isn't sensitive
- **Low:** Well-known local-only credentials (Cosmos DB emulator key, default SQL container passwords) — flag the pattern, note it's local-only, move on

Flag any of the following appearing in source code, config, or IaC files:

- Passwords in `appsettings.json` (non-placeholder values)
- `connectionStrings` containing `Password=` or `pwd=` in plaintext
- Azure SAS tokens (`sv=`, `sig=`, `se=` query parameters)
- Azure Storage account keys (base64, ~88 chars ending in `==`)
- JWT signing secrets shorter than 32 characters
- Bearer tokens or API keys inline (`api_key=`, `apiKey:`, `Bearer <token>`)
- PEM private keys (`-----BEGIN RSA PRIVATE KEY-----`)
- AWS/GCP credentials (`AKIA...`, `"private_key_id"`)
- GitHub tokens (`ghp_`, `gho_`, `ghs_`, `github_pat_`)
- Slack tokens (`xoxb-`, `xoxp-`, `xoxs-`)
- Common SaaS API keys (SendGrid `SG.`, Stripe `sk_live_`, Twilio)

**Also check git history.** `.gitignore` only prevents future commits. If a secret is in the current codebase, recommend checking whether it was ever committed to history with `gitleaks` or `trufflehog`. Previously committed secrets must be rotated — removing them from HEAD does not remove them from history.

**Also check `.gitignore` coverage.** Missing entries for these files is itself a finding:

- `launchSettings.json` (commonly contains real env vars and gets committed — if present, scan its `environmentVariables` for secrets)
- `appsettings.Development.json`, `appsettings.Local.json`
- `.env`, `.env.local`
- `*.pfx`, `*.pem`, `*.key`
- `nuget.config` with credentials
