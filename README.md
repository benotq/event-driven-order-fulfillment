# Event-Driven Order Fulfillment

A Salesforce backend project demonstrating a Platform Event-driven saga: an order
moves through a multi-stage fulfillment pipeline (Submitted → Inventory Reserved →
Shipped → Delivered) where each stage transition is a published event, and
independent, decoupled subscribers react to it — not one big trigger doing
everything synchronously.

This is the kind of architecture that shows up in real integration/platform teams:
publish/subscribe instead of direct calls, idempotent handlers (events are
at-least-once, never exactly-once), per-subscriber fault isolation, and a
scheduled job to catch sagas that stall.

## Architecture

```
OrderFulfillmentService.submitOrder()
  → publishes Order_Stage_Event__e{Stage=SUBMITTED}
      → InventoryReservationSubscriber: Submitted → Inventory Reserved, publishes INVENTORY_RESERVED
          → ShipmentCreationSubscriber: Inventory Reserved → Shipped, publishes SHIPPED
              → CustomerNotificationSubscriber: logs a notification (no further publish)
              → (nothing auto-advances past Shipped — delivery is an external event)
OrderFulfillmentService.confirmDelivery()                [e.g. a carrier webhook]
  → publishes Order_Stage_Event__e{Stage=DELIVERED}
      → DeliveryCompletionSubscriber: Shipped → Delivered (terminal)

Every event, regardless of stage: → AuditTrailSubscriber logs it to Order_Event_Log__c
Any stage marked FAILED:          → FailureHandlerSubscriber marks the order Failed
```

A single trigger (`OrderStageEventTrigger`) fires on `Order_Stage_Event__e` and hands
off entirely to `OrderStageEventHandler`, which dispatches each event to every
subscriber whose `appliesTo(stage)` returns true. Adding a new reaction to a stage
means registering a new subscriber class — never editing an existing one.

### Idempotency

Platform Events are delivered **at-least-once**: a subscriber must tolerate seeing
the same event twice. Two different strategies are used here, because not every
subscriber does the same kind of work:

- **State-based** (`OrderFulfillmentService.advanceOrder`) — the row is locked
  (`FOR UPDATE`) and the transition only applies if the order is still in the
  *expected* prior status. A redelivered `SUBMITTED` event, for example, is a
  guaranteed no-op once the order has already moved to Inventory Reserved.
- **Log-based** (`CustomerNotificationSubscriber`) — a subscriber whose job is a side
  effect, not a state transition, has nothing to check its state against. It checks
  `Order_Event_Log__c` for a prior `NOTIFICATION_SENT` entry instead.

### Fault isolation

`OrderStageEventHandler` wraps each subscriber's `handle()` call in its own
try/catch. One subscriber throwing (a bug, a bad payload, a transient query failure)
never prevents the others — notably the audit trail — from still processing that
event, and the failure itself is logged as a `SUBSCRIBER_ERROR` entry rather than
silently swallowed or allowed to fail the whole trigger for every event in the batch.

### Stuck-saga detection

`StuckOrderMonitorBatch` (scheduled hourly via `StuckOrderMonitorScheduler`) finds
orders that have sat in a non-terminal status longer than
`StuckOrderMonitorBatch.STUCK_THRESHOLD_MINUTES` — meaning either a subscriber failed
outside the normal flow, or an expected follow-up event (like a delivery
confirmation) never arrived — and routes them through the exact same `FAILED` stage
path as any other failure, so there's one way an order becomes Failed, not two.

## Data model

| Object | Purpose |
|---|---|
| `Order__c` | The order and its current saga status (`Status__c`), plus `Last_Stage_Completed_At__c` for stall detection |
| `Order_Event_Log__c` | Append-only audit trail: one row per event *received* (not per state change — a skipped duplicate is still logged) |
| `Order_Stage_Event__e` | The Platform Event: `Order_Id__c`, `Stage__c`, `Detail__c` |

## Testing

All of this is tested with `Test.getEventBus().deliver()` to drive the saga one hop
at a time — including a subtlety worth knowing if you write similar tests:
**`Test.stopTest()` itself performs one implicit event delivery**, so assertions
about an intermediate stage must run *before* `stopTest()`, not after.

- **`OrderFulfillmentServiceTest`** — `submitOrder`, the `advanceOrder` idempotency
  guard, `markFailed`.
- **`OrderFulfillmentSagaIntegrationTest`** — the full saga end-to-end hop by hop,
  a duplicate `SUBMITTED` event being ignored by the state-changing subscriber but
  still fully audited, a duplicate `SHIPPED` event not double-sending a
  notification, one failing subscriber not blocking the audit trail (plus its own
  logged `SUBSCRIBER_ERROR`), and the stuck-order monitor correctly flagging a
  stalled order while leaving a fresh or already-terminal one alone.

96–100% coverage on every class in the feature. Run with:

```bash
sf apex run test --target-org <alias> --class-names OrderFulfillmentServiceTest --class-names OrderFulfillmentSagaIntegrationTest --code-coverage --wait 10
```

## Deploying

```bash
sf project deploy start --target-org <alias> --source-dir force-app
sf org assign permset --target-org <alias> --name Order_Fulfillment_Access
```

Try it live:

```bash
# Kick off a saga - watch Order__c.Status__c and Order_Event_Log__c progress
# through Submitted -> Inventory Reserved -> Shipped within about a second.
sf apex run --target-org <alias> --file - <<< "OrderFulfillmentService.submitOrder(new Order__c(Order_Total__c = 500));"

# Simulate the external delivery confirmation that completes the saga.
sf apex run --target-org <alias> --file - <<< "OrderFulfillmentService.confirmDelivery('<orderId>', 'Delivered.');"

# Schedule the stuck-order monitor to run hourly.
sf apex run --target-org <alias> --file - <<< "System.schedule('Stuck Order Monitor', '0 0 * * * ?', new StuckOrderMonitorScheduler());"
```
