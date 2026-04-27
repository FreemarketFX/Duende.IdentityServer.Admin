import { expect, type Page } from "@playwright/test";

export type LoginCredentials = {
  username: string;
  password: string;
};

function escapeForRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function getStsLoginUrlPattern(): RegExp {
  const stsUrl = process.env.E2E_STS_URL ?? "https://localhost:44310";
  return new RegExp(
    `${escapeForRegex(stsUrl)}/Account/Login(?:[/?#]|$)`,
    "i",
  );
}

async function waitForInitialState(
  clientsHeading: ReturnType<Page["getByRole"]>,
  usernameInput: ReturnType<Page["locator"]>,
  page: Page,
): Promise<"clients" | "login"> {
  const timeoutAt = Date.now() + 60_000;

  while (Date.now() < timeoutAt) {
    if (await clientsHeading.isVisible().catch(() => false)) {
      return "clients";
    }

    if (await usernameInput.isVisible().catch(() => false)) {
      return "login";
    }

    await page.waitForTimeout(250);
  }

  throw new Error(
    `Neither Clients screen nor STS login form became visible within timeout. Last URL: ${page.url()}`,
  );
}

async function waitForPostLoginResult(
  page: Page,
  clientsHeading: ReturnType<Page["getByRole"]>,
): Promise<"success" | "invalid_credentials" | "timeout"> {
  const invalidCredentials = page.getByText("Invalid username or password", {
    exact: false,
  });
  const consentAllowButton = page.getByRole("button", { name: "Yes, Allow" });
  const timeoutAt = Date.now() + 60_000;
  let consentHandled = false;

  while (Date.now() < timeoutAt) {
    if (await clientsHeading.isVisible().catch(() => false)) {
      return "success";
    }

    if (await invalidCredentials.isVisible().catch(() => false)) {
      return "invalid_credentials";
    }

    if (
      !consentHandled &&
      (await consentAllowButton.isVisible().catch(() => false))
    ) {
      await consentAllowButton.click();
      consentHandled = true;
      continue;
    }

    await page.waitForTimeout(250);
  }

  return "timeout";
}

export async function ensureLoggedInAndOpenClients(
  page: Page,
  credentials: LoginCredentials,
): Promise<void> {
  await page.goto("/clients");

  const clientsHeading = page.getByRole("heading", { name: "Clients" });
  const usernameInput = page.locator("#Username");
  const passwordInput = page.locator("#Password");
  const initialState = await waitForInitialState(
    clientsHeading,
    usernameInput,
    page,
  );

  if (initialState === "login") {
    await expect(page).toHaveURL(getStsLoginUrlPattern(), { timeout: 30_000 });

    await usernameInput.fill(credentials.username);
    await passwordInput.fill(credentials.password);
    await page.locator("button[name='button'][value='login']").click();

    const loginResult = await waitForPostLoginResult(page, clientsHeading);
    if (loginResult === "invalid_credentials") {
      throw new Error(
        `Login failed for user '${credentials.username}'. Provide valid credentials using E2E_USERNAME and E2E_PASSWORD.`,
      );
    }

    expect(loginResult).toBe("success");
  }

  await expect(clientsHeading).toBeVisible({ timeout: 60_000 });
}
