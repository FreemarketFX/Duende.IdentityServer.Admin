import { expect, type Page } from "@playwright/test";

export type WizardClientInput = {
  clientId: string;
  clientName: string;
  description: string;
  redirectUri: string;
  logoutUri: string;
  secretValue: string;
  secretDescription: string;
};

export async function createConfidentialClientViaWizard(
  page: Page,
  data: WizardClientInput,
): Promise<void> {
  await page.getByRole("button", { name: "Add New Client" }).click();

  const clientTypeDialog = page.getByRole("dialog", { name: "New Client" });
  await expect(clientTypeDialog).toBeVisible();
  await clientTypeDialog.getByRole("button", { name: "Create" }).first().click();

  await expect(page.locator('input[name="clientId"]')).toBeVisible({
    timeout: 60_000,
  });
  await page.locator('input[name="clientId"]').fill(data.clientId);
  await page.locator('input[name="clientName"]').fill(data.clientName);
  await page.locator('textarea[name="description"]').fill(data.description);
  await page.getByRole("button", { name: "Next" }).click();

  const wizardItemInput = page.getByPlaceholder("Enter item").first();
  await wizardItemInput.fill(data.redirectUri);
  await page.getByRole("button", { name: "Add Item" }).click();
  await page.locator('input[name="logoutUri"]').fill(data.logoutUri);
  await page.getByRole("button", { name: "Next" }).click();

  await expect(
    page.getByRole("button", { name: "Select All", exact: true }),
  ).toBeVisible({
    timeout: 30_000,
  });
  await page.getByRole("button", { name: "Select All", exact: true }).click();
  await page.getByRole("button", { name: "Next" }).click();

  await expect(page.locator('input[name="secretValue"]')).toBeVisible({
    timeout: 30_000,
  });
  await page.locator('input[name="secretValue"]').fill(data.secretValue);
  await page
    .locator('textarea[name="secretDescription"]')
    .fill(data.secretDescription);
  await page.getByRole("button", { name: "Next" }).click();

  await expect(
    page.getByRole("heading", { name: "Review and Submit" }),
  ).toBeVisible({
    timeout: 30_000,
  });
  await page.getByRole("button", { name: "Save" }).click();

  await expect(page).toHaveURL(/\/client\/\d+(?:[/?#]|$)/i, {
    timeout: 60_000,
  });
}
