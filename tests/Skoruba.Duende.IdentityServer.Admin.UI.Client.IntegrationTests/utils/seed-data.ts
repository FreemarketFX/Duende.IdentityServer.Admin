import fs from "node:fs";
import path from "node:path";

export interface E2ESeedData {
  username: string;
  password: string;
  expectedClientId: string;
}

type JsonObject = Record<string, unknown>;

const DEFAULT_ADMIN_ROLE = "SkorubaIdentityAdminAdministrator";

function stripUtf8Bom(content: string): string {
  if (content.charCodeAt(0) === 0xfeff) {
    return content.slice(1);
  }

  return content;
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function asObject(value: unknown): JsonObject | undefined {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as JsonObject;
  }

  return undefined;
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function getValue(object: JsonObject | undefined, keys: string[]): unknown {
  if (!object) {
    return undefined;
  }

  for (const key of keys) {
    if (Object.prototype.hasOwnProperty.call(object, key)) {
      return object[key];
    }
  }

  return undefined;
}

function readJsonFile(filePath: string): JsonObject {
  try {
    const raw = fs.readFileSync(filePath, "utf8");
    return JSON.parse(stripUtf8Bom(raw)) as JsonObject;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`Unable to read JSON file '${filePath}': ${message}`);
  }
}

function findRepoRoot(startDirectory: string = process.cwd()): string {
  let currentDirectory = startDirectory;

  while (true) {
    if (
      fs.existsSync(
        path.join(currentDirectory, "Skoruba.Duende.IdentityServer.Admin.sln")
      )
    ) {
      return currentDirectory;
    }

    const parentDirectory = path.dirname(currentDirectory);
    if (parentDirectory === currentDirectory) {
      throw new Error(
        `Repository root not found from '${startDirectory}'. Expected to find 'Skoruba.Duende.IdentityServer.Admin.sln'.`
      );
    }

    currentDirectory = parentDirectory;
  }
}

function resolvePathFromEnvironment(pathFromEnvironment: string): string {
  return path.isAbsolute(pathFromEnvironment)
    ? pathFromEnvironment
    : path.resolve(process.cwd(), pathFromEnvironment);
}

function resolveFirstExistingPath(candidates: string[], fileLabel: string): string {
  const existing = candidates.find((candidate) => fs.existsSync(candidate));

  if (!existing) {
    throw new Error(
      `Unable to find ${fileLabel}. Checked: ${candidates.join(", ")}`
    );
  }

  return existing;
}

function resolveIdentityDataPath(repoRoot: string): string {
  if (isNonEmptyString(process.env.E2E_IDENTITY_JSON)) {
    return resolvePathFromEnvironment(process.env.E2E_IDENTITY_JSON);
  }

  return resolveFirstExistingPath(
    [
      path.join(repoRoot, "src/Skoruba.Duende.IdentityServer.Admin.Api/identity.json"),
      path.join(repoRoot, "src/Skoruba.Duende.IdentityServer.Admin.Api/identitydata.json"),
      path.join(repoRoot, "shared/identity.json"),
      path.join(repoRoot, "shared/identitydata.json"),
    ],
    "identity data JSON"
  );
}

function resolveIdentityServerDataPath(repoRoot: string): string {
  if (isNonEmptyString(process.env.E2E_IDENTITYSERVER_JSON)) {
    return resolvePathFromEnvironment(process.env.E2E_IDENTITYSERVER_JSON);
  }

  return resolveFirstExistingPath(
    [
      path.join(repoRoot, "src/Skoruba.Duende.IdentityServer.Admin.Api/identityserver.json"),
      path.join(repoRoot, "src/Skoruba.Duende.IdentityServer.Admin.Api/identityserverdata.json"),
      path.join(repoRoot, "shared/identityserver.json"),
      path.join(repoRoot, "shared/identityserverdata.json"),
    ],
    "IdentityServer data JSON"
  );
}

function extractUsers(identityDataDocument: JsonObject): Array<{
  username: string;
  password: string;
  roles: string[];
}> {
  const identityDataSection = asObject(
    getValue(identityDataDocument, ["IdentityData", "identityData"])
  );

  return asArray(getValue(identityDataSection, ["Users", "users"]))
    .map((userValue) => {
      const user = asObject(userValue);
      if (!user) {
        return undefined;
      }

      const username = getValue(user, [
        "Username",
        "username",
        "UserName",
        "userName",
      ]);
      const password = getValue(user, ["Password", "password"]);
      const roleValues = asArray(getValue(user, ["Roles", "roles"]));

      if (!isNonEmptyString(username) || !isNonEmptyString(password)) {
        return undefined;
      }

      const roles = roleValues.filter(isNonEmptyString);

      return {
        username,
        password,
        roles,
      };
    })
    .filter((user): user is { username: string; password: string; roles: string[] } =>
      Boolean(user)
    );
}

function extractRoleNames(identityDataDocument: JsonObject): string[] {
  const identityDataSection = asObject(
    getValue(identityDataDocument, ["IdentityData", "identityData"])
  );

  return asArray(getValue(identityDataSection, ["Roles", "roles"]))
    .map((roleValue) => {
      if (isNonEmptyString(roleValue)) {
        return roleValue;
      }

      const role = asObject(roleValue);
      if (!role) {
        return undefined;
      }

      const roleName = getValue(role, ["Name", "name"]);
      return isNonEmptyString(roleName) ? roleName : undefined;
    })
    .filter((roleName): roleName is string => Boolean(roleName));
}

function extractClientIds(identityServerDocument: JsonObject): string[] {
  const identityServerSection = asObject(
    getValue(identityServerDocument, ["IdentityServerData", "identityServerData"])
  );

  return asArray(getValue(identityServerSection, ["Clients", "clients"]))
    .map((clientValue) => {
      const client = asObject(clientValue);
      if (!client) {
        return undefined;
      }

      const clientId = getValue(client, ["ClientId", "clientId"]);
      return isNonEmptyString(clientId) ? clientId : undefined;
    })
    .filter((clientId): clientId is string => Boolean(clientId));
}

export function loadE2ESeedData(): E2ESeedData {
  const repoRoot = findRepoRoot();
  const identityDataPath = resolveIdentityDataPath(repoRoot);
  const identityServerDataPath = resolveIdentityServerDataPath(repoRoot);

  const identityDataDocument = readJsonFile(identityDataPath);
  const identityServerDataDocument = readJsonFile(identityServerDataPath);

  const users = extractUsers(identityDataDocument);
  const roleNames = extractRoleNames(identityDataDocument);
  const clientIds = extractClientIds(identityServerDataDocument);

  if (users.length === 0) {
    throw new Error(
      `No users with credentials found in '${identityDataPath}'.`
    );
  }

  if (clientIds.length === 0) {
    throw new Error(
      `No clients found in '${identityServerDataPath}'.`
    );
  }

  const configuredUsername = process.env.E2E_USERNAME;
  const configuredPassword = process.env.E2E_PASSWORD;
  const configuredClientId = process.env.E2E_EXPECTED_CLIENT_ID;

  let selectedUser = users[0];

  if (isNonEmptyString(configuredUsername) && isNonEmptyString(configuredPassword)) {
    selectedUser = {
      username: configuredUsername,
      password: configuredPassword,
      roles: [],
    };
  } else if (isNonEmptyString(configuredUsername)) {
    const matchingUser = users.find((user) => user.username === configuredUsername);
    if (!matchingUser) {
      throw new Error(
        `User '${configuredUsername}' was not found in '${identityDataPath}'.`
      );
    }

    selectedUser = matchingUser;
  } else {
    const configuredAdminRole = process.env.E2E_ADMIN_ROLE;
    const adminRoleFromIdentityData = roleNames.find((roleName) =>
      users.some((user) => user.roles.includes(roleName))
    );
    const adminRole = isNonEmptyString(configuredAdminRole)
      ? configuredAdminRole
      : adminRoleFromIdentityData ?? roleNames[0] ?? DEFAULT_ADMIN_ROLE;

    selectedUser =
      users.find((user) => user.roles.includes(adminRole)) ?? users[0];
  }

  const expectedClientId = isNonEmptyString(configuredClientId)
    ? configuredClientId
    : clientIds[0];

  if (
    isNonEmptyString(configuredClientId) &&
    !clientIds.includes(configuredClientId)
  ) {
    throw new Error(
      `Client '${expectedClientId}' was not found in '${identityServerDataPath}'.`
    );
  }

  return {
    username: selectedUser.username,
    password: selectedUser.password,
    expectedClientId,
  };
}
