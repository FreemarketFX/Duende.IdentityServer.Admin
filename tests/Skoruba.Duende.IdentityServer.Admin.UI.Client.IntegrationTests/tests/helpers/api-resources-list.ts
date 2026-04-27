import { expect, type Locator, type Page } from "@playwright/test";
import {
  ensureLoggedInAndOpenClients,
  type LoginCredentials,
} from "./auth";

export async function ensureLoggedInAndOpenApiResources(
  page: Page,
  credentials: LoginCredentials,
): Promise<void> {
  await ensureLoggedInAndOpenClients(page, credentials);
  await page.goto("/api-resources");
  await expect(page).toHaveURL(/\/api-resources(?:[/?#]|$)/i);
}

export async function findApiResourceRow(
  page: Page,
  resourceName: string,
): Promise<Locator> {
  const searchInput = page.locator("input[type='text']").first();
  const searchButton = page.getByRole("button", { name: "Search" });
  const targetRow = page.locator("table tbody tr", {
    has: page.getByRole("link", { name: resourceName, exact: true }),
  });
  const timeoutAt = Date.now() + 90_000;

  while (Date.now() < timeoutAt) {
    await searchInput.fill(resourceName);
    await searchButton.click();

    if ((await targetRow.count()) === 1) {
      return targetRow;
    }

    await page.waitForTimeout(500);
  }

  throw new Error(`API resource '${resourceName}' was not found in list.`);
}

export async function openApiResourceDetailFromList(
  page: Page,
  resourceName: string,
  credentials: LoginCredentials,
): Promise<void> {
  await ensureLoggedInAndOpenApiResources(page, credentials);
  const targetRow = await findApiResourceRow(page, resourceName);
  await targetRow.getByRole("link", { name: resourceName, exact: true }).click();
  await expect(page).toHaveURL(/\/api-resource\/\d+(?:[/?#]|$)/i);
}
