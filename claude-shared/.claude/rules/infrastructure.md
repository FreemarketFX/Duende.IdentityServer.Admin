# Infrastructure & JSON

Applies to bootstrap / bicep / Cosmos container setup, and to any `.json` file edits.

## Cosmos Containers

- **Partition key** — domain containers using durable domain events MUST use `partitionKey` (not `id`) to support transactional batches. Only non-domain containers (e.g. `http-request-audit`) may use `id`.

## JSON Files

After modifying any `.json` file, validate it is still valid JSON. Common mistakes: trailing commas, missing commas, unquoted keys.
