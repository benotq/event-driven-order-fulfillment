/**
 * The trigger's only job is to hand events to this dispatcher. Each applicable
 * subscriber runs in its own try/catch, so one subscriber throwing (a bug, a bad
 * payload, a transient query failure) never prevents the other subscribers — notably
 * AuditTrailSubscriber — from still processing that same event. Failures are
 * themselves logged, so a broken subscriber is observable rather than silently eaten.
 */
public with sharing class OrderStageEventHandler {

    @TestVisible
    private static List<OrderStageEventSubscriber> subscribers = new List<OrderStageEventSubscriber>{
        new InventoryReservationSubscriber(),
        new ShipmentCreationSubscriber(),
        new CustomerNotificationSubscriber(),
        new DeliveryCompletionSubscriber(),
        new FailureHandlerSubscriber(),
        new AuditTrailSubscriber()
    };

    public void handle(List<Order_Stage_Event__e> events) {
        for (Order_Stage_Event__e event : events) {
            for (OrderStageEventSubscriber subscriber : subscribers) {
                if (!subscriber.appliesTo(event.Stage__c)) {
                    continue;
                }
                try {
                    subscriber.handle(event);
                } catch (Exception ex) {
                    logSubscriberFailure(event, subscriber, ex);
                }
            }
        }
    }

    private void logSubscriberFailure(Order_Stage_Event__e event, OrderStageEventSubscriber subscriber, Exception ex) {
        try {
            OrderFulfillmentService.logEvent(
                (Id) event.Order_Id__c,
                'SUBSCRIBER_ERROR',
                'Failed',
                String.valueOf(subscriber).split(':')[0] + ' failed on stage ' + event.Stage__c + ': ' + ex.getMessage()
            );
        } catch (Exception loggingException) {
            // Logging itself failed (e.g. an invalid Order_Id__c) - swallow rather than
            // let a logging problem take down processing of the other events/subscribers.
        }
    }
}
