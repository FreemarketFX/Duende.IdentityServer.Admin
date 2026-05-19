# Domain & Brighter Events

Applies when creating or modifying events / event handlers.

| | Domain Events | Brighter Events |
|--|---------------|-----------------|
| Base | `DomainEvent` | `StorableEvent` |
| Handler | `DomainEventHandler<T>` | `BaseServiceRequestHandlerAsync<T>` |
| Mapper | **NO** | **Required** (`MessageMapper<T>`) |
| Markers | None | `IAmPublished`, `IAmSubscribedTo` |
| Location | `Domain/` | `Application/Features/` |

Domain events: `aggregate.Events.Enqueue(new MyDomainEvent(...))`. The handler can call `commandProcessor.DepositPostAsync()` to publish a Brighter event.

- Domain event handlers are auto-discovered by reflection — no manual registration.
- **Brighter subscriptions** MUST be registered in `BrighterConfiguration.CreateSubscriptions()` or messages are silently dropped.
- Domain events are dequeued during `repository.Save()` — assert via `aggregate.Events.Dequeue()` + `OfType<T>()` **before** saving.

## Cross-Store Deposit (publish from where?)

A command handler that does both `repository.Save(...)` (Cosmos) AND `commandProcessor.DepositPostAsync(...)` (Brighter outbox, Cosmos-backed) in the same body is writing to two stores in one logical operation. Cosmos and the outbox are independent containers — there is no transaction across them.

**Default:** publish from a `ModuleDomainEventHandler<T>` instead of inline:

1. Enqueue the domain event on the aggregate (`aggregate.Events.Enqueue(new XCreatedDomainEvent(...))`).
2. Add a Brighter handler `XCreatedDomainEventMessageBusHandler : ModuleDomainEventHandler<XCreatedDomainEvent>` that calls `await PublishEvent(new XCreatedEvent(...), enrichers)`.
3. The change-feed delivery on the durable domain event is at-least-once and survives crashes.

**When inline deposit is acceptable:** the Cosmos SDK retries on transient failure, so a single re-delivery on the read side is often tolerable. Cases where inline deposit is fine:

- Idempotent consumer with an explicit dedupe key.
- Best-effort notifications where missing one event is recoverable.
- Latency-critical flows where the change-feed hop is too slow.

If you choose inline, document the reason at the call site and verify the consumer is idempotent. Don't enforce this at hook level — it's a judgment call, not a hard rule. (Originally drafted as a `PreToolUse` hook; reverted to a rule because the hook flagged legitimate cases.)
