---
name: domain-event
description: "Create a domain event and handler. Use for intra-aggregate events within the domain layer. Triggers on: create domain event, add domain event, new domain event."
license: MIT
---

# Domain Event Scaffolder

Create a domain event and its handler in the Domain layer.

---

## The Job

1. Get event name and details from user
2. Find existing examples in the codebase
3. Create event and handler files
4. Ensure build passes

**Important:** Domain events are for intra-aggregate communication. For cross-service messaging, use Brighter events instead.

---

## Domain Events vs Brighter Events

| | Domain Events | Brighter Events |
|--|---------------|-----------------|
| Base | `DomainEvent` | `StorableEvent` |
| Handler | `DomainEventHandler<T>` | `BaseServiceRequestHandlerAsync<T>` |
| Mapper | **NO** | **Required** (`MessageMapper<T>`) |
| Markers | None | `IAmPublished`, `IAmSubscribedTo` |
| Location | `Domain/` | `Application/Features/` |

---

## Step 1: Gather Information

Ask the user:
- Event name (e.g., "OrderCreated", "CustomerUpdated")
- Module name (which bounded context)
- What aggregate raises this event
- What should happen when the event is raised

---

## Step 2: Find Examples

Search for existing domain events:

```bash
# Find existing domain events
find src -name "*.cs" -path "*/Domain/*" | xargs grep -l "DomainEvent" | head -5

# Find existing domain event handlers
grep -l "DomainEventHandler" src -r --include="*.cs" | head -5
```

Read examples to understand the exact patterns used.

---

## Step 3: Create Files

### 1. Domain/{EventName}.cs

Create in `src/{Module}/Domain/`:

```csharp
namespace {Module}.Domain;

public class {EventName}(Guid aggregateId, string name) : DomainEvent
{
    public Guid AggregateId { get; } = aggregateId;
    public string Name { get; } = name;
}
```

### 2. Domain/{EventName}Handler.cs

Create in `src/{Module}/Domain/`:

```csharp
namespace {Module}.Domain;

public class {EventName}Handler(
    ILogger<{EventName}Handler> logger)
    : DomainEventHandler<{EventName}>
{
    public override Task Handle({EventName} domainEvent, CancellationToken ct = default)
    {
        logger.LogInformation("{EventName} raised for {AggregateId}",
            nameof({EventName}), domainEvent.AggregateId);

        // Handle the event
        // If you need to publish a Brighter event:
        // await commandProcessor.DepositPostAsync(new SomeBrighterEvent(...), ct);

        return Task.CompletedTask;
    }
}
```

---

## Step 4: Raise from Aggregate

In the aggregate that raises this event:

```csharp
public class {Aggregate} : AggregateRoot
{
    public void DoSomething(string name)
    {
        // Business logic here
        Name = name;

        // Enqueue the domain event
        Events.Enqueue(new {EventName}(Id, Name));
    }
}
```

---

## Step 5: Verify

```bash
dotnet build --configuration Release /p:NetCoreBuild=true
```

Fix any build errors before completing.

---

## When to Use Domain Events

**Use domain events for:**
- Side effects within the same bounded context
- Updating read models
- Triggering workflows within the domain
- Audit logging

**Use Brighter events instead for:**
- Cross-service communication
- Events that need to be persisted to a message bus
- Events consumed by external systems

---

## Checklist

- [ ] Event class extends `DomainEvent`
- [ ] Handler extends `DomainEventHandler<T>`
- [ ] No mapper needed (domain events don't have mappers)
- [ ] Event is enqueued from aggregate via `Events.Enqueue()`
- [ ] Build passes
