/**
 * Doesn't change Order__c.Status__c at all, so it can't use the status-based
 * idempotency guard in OrderFulfillmentService.advanceOrder. Instead it checks the
 * audit log itself for a prior NOTIFICATION_SENT entry — a second, independent
 * idempotency strategy for a subscriber whose job is a side effect, not a transition.
 */
public with sharing class CustomerNotificationSubscriber implements OrderStageEventSubscriber {

    private static final String NOTIFICATION_SENT = 'NOTIFICATION_SENT';

    public Boolean appliesTo(String stage) {
        return stage == OrderFulfillmentService.STAGE_SHIPPED;
    }

    public void handle(Order_Stage_Event__e event) {
        Id orderId = (Id) event.Order_Id__c;

        Integer alreadyNotified = [
            SELECT COUNT()
            FROM Order_Event_Log__c
            WHERE Order__c = :orderId AND Event_Type__c = :NOTIFICATION_SENT
            WITH USER_MODE
        ];
        if (alreadyNotified > 0) {
            return;
        }

        // Simulated notification side effect (email/SMS integration would go here).
        OrderFulfillmentService.logEvent(orderId, NOTIFICATION_SENT, 'Success', 'Shipment notification sent to customer.');
    }
}
