---
name: brighter-event
description: "Brighter event generator — produces mapper and handler for cross-service message bus communication. Activated by: brighter event setup, message event wiring, storable event publishing."
license: MIT
---

# Brighter Event Scaffolder

Create a Brighter event with mapper and handler for cross-service messaging.

---

## The Job

1. Get event name and details from user
2. Find existing examples in the codebase
3. Create event, mapper, and handler files
4. Ensure build passes

**Important:** Brighter events require a mapper. Domain events do not.

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
- Event name (e.g., "OrderCreatedEvent", "CustomerUpdatedEvent")
- Module name (which bounded context)
- Is this published, subscribed, or both?
- What data should the event carry?

---

## Step 2: Find Examples

Search for existing Brighter events:

```bash
# Find existing storable events
grep -l "StorableEvent" src -r --include="*.cs" | head -5

# Find existing message mappers
grep -l "MessageMapper" src -r --include="*.cs" | head -5

# Find IAmPublished/IAmSubscribedTo markers
grep -l "IAmPublished\|IAmSubscribedTo" src -r --include="*.cs" | head -5
```

Read examples to understand the exact patterns used.

---

## Step 3: Create Files

Create in `src/{Module}/Application/Features/{EventName}/`:

### 1. {EventName}.Event.cs

```csharp
namespace {Module}.Application.Features;

public class {EventName} : StorableEvent, IAmPublished  // or IAmSubscribedTo, or both
{
    public Guid AggregateId { get; init; }
    public string Name { get; init; } = string.Empty;

    public {EventName}() : base(Guid.NewGuid(), DateTime.UtcNow) { }

    public {EventName}(Guid id, Guid aggregateId, string name)
        : base(id, DateTime.UtcNow)
    {
        AggregateId = aggregateId;
        Name = name;
    }
}
```

### 2. {EventName}.Mapper.cs

```csharp
using System.Text.Json;
using Paramore.Brighter;

namespace {Module}.Application.Features;

public class {EventName}Mapper : MessageMapper<{EventName}>
{
    public override Message MapToMessage({EventName} request, Publication publication)
    {
        MessageHeader header = new(
            request.Id,
            publication.Topic,
            MessageType.MT_EVENT,
            DateTime.UtcNow);

        MessageBody body = new(JsonSerializer.Serialize(request));

        return new Message(header, body);
    }

    public override {EventName} MapToRequest(Message message)
    {
        return JsonSerializer.Deserialize<{EventName}>(message.Body.Value)
            ?? throw new InvalidOperationException("Failed to deserialize {EventName}");
    }
}
```

### 3. {EventName}.Handler.cs (if subscribing)

```csharp
namespace {Module}.Application.Features;

public class {EventName}Handler(
    IRepository repository,
    ILogger<{EventName}Handler> logger)
    : BaseServiceRequestHandlerAsync<{EventName}>
{
    public override async Task<{EventName}> HandleAsync(
        {EventName} @event,
        CancellationToken ct = default)
    {
        logger.LogInformation("Handling {EventName} for {AggregateId}",
            nameof({EventName}), @event.AggregateId);

        // Handle the event
        // e.g., update a read model, trigger a workflow

        return @event;
    }
}
```

---

## Step 4: Publishing the Event

To publish from a domain event handler or command handler:

```csharp
// In a domain event handler
public class SomeDomainEventHandler(
    IAmACommandProcessor commandProcessor,
    ILogger<SomeDomainEventHandler> logger)
    : DomainEventHandler<SomeDomainEvent>
{
    public override async Task Handle(SomeDomainEvent domainEvent, CancellationToken ct)
    {
        {EventName} brighterEvent = new(
            Guid.NewGuid(),
            domainEvent.AggregateId,
            domainEvent.Name);

        await commandProcessor.DepositPostAsync(brighterEvent, ct);
    }
}
```

---

## Step 5: Register in Configuration

Register the event in the module's `BrighterExtensions.cs` (typical location: `src/{Module}/Application/BrighterExtensions.cs`).

1. Find the file: `Glob("src/{Module}/**/BrighterExtensions.cs")`. If not found, fall back to `Glob("src/**/BrighterExtensions.cs")` and pick the one in the target module.
2. Read it to see the existing `CreatePublications` / `CreateSubscriptions` methods.
3. Add to `CreatePublications` if the event has `IAmPublished`.
4. Add to `CreateSubscriptions` if the event has `IAmSubscribedTo`.
5. If the module has no `BrighterExtensions.cs`, ask the user — this likely means a new module is being set up and needs wiring in HostApp too (see `infrastructure-update` skill).

---

## Step 6: Verify

```bash
dotnet build --configuration Release /p:NetCoreBuild=true
```

Fix any build errors before completing.

---

## Markers

- `IAmPublished` - This service publishes this event
- `IAmSubscribedTo` - This service handles this event
- Both - This service both publishes and handles the event

---

## Checklist

- [ ] Event class extends `StorableEvent`
- [ ] Event has appropriate marker interface (`IAmPublished`, `IAmSubscribedTo`)
- [ ] Mapper extends `MessageMapper<T>`
- [ ] Handler extends `BaseServiceRequestHandlerAsync<T>` (if subscribing)
- [ ] Event registered in Brighter configuration
- [ ] Build passes
