import { expect, type Locator, type Page } from "@playwright/test";
import {
  ensureLoggedInAndOpenClients,
  type LoginCredentials,
} from "./auth";

export async function findClientRow(
  page: Page,
  clientId: string,
): Promise<Locator> {
  const searchInput = page.locator("input[type='text']").first();
  const searchButton = page.getByRole("button", { name: "Search" });
  const targetRow = page.locator("table tbody tr", {
    has: page.locator("code", { hasText: clientId }),
  });
  const timeoutAt = Date.now() + 90_000;

  while (Date.now() < timeoutAt) {
    await searchInput.fill(clientId);
    await searchButton.click();

    if ((await targetRow.count()) === 1) {
      return targetRow;
    }

    await page.waitForTimeout(500);
  }

  throw new Error(`Client '${clientId}' was not found in Clients list.`);
}

export async function openClientDetailFromClients(
  page: Page,
  clientId: string,
  credentials: LoginCredentials,
): Promise<void> {
  await ensureLoggedInAndOpenClients(page, credentials);
  const targetRow = await findClientRow(page, clientId);
  await targetRow.getByRole("link").first().click();
  await expect(page).toHaveURL(/\/client\/\d+(?:[/?#]|$)/i);
}
