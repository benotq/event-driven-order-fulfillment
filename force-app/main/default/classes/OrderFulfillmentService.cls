/**
 * Public entry points into the fulfillment saga (submitOrder, confirmDelivery) plus
 * the shared, idempotent stage-transition helper every state-changing subscriber
 * calls. Keeping the transition logic here — rather than duplicated in each
 * subscriber — means the idempotency guard and row locking only have to be gotten
 * right once.
 *
 * Apex only allows static fields on a top-level type, so the stage/status constants
 * live directly on this class (STAGE_* for Order_Stage_Event__e.Stage__c values,
 * STATUS_* for Order__c.Status__c picklist values) rather than in nested marker
 * classes.
 */
public with sharing class OrderFulfillmentService {

    public static final String STAGE_SUBMITTED = 'SUBMITTED';
    public static final String STAGE_INVENTORY_RESERVED = 'INVENTORY_RESERVED';
    public static final String STAGE_SHIPPED = 'SHIPPED';
    public static final String STAGE_DELIVERED = 'DELIVERED';
    public static final String STAGE_FAILED = 'FAILED';

    public static final String STATUS_SUBMITTED = 'Submitted';
    public static final String STATUS_INVENTORY_RESERVED = 'Inventory Reserved';
    public static final String STATUS_SHIPPED = 'Shipped';
    public static final String STATUS_DELIVERED = 'Delivered';
    public static final String STATUS_FAILED = 'Failed';

    /** Creates the order and kicks off the saga by publishing the first stage event. */
    public static Id submitOrder(Order__c order) {
        order.Status__c = STATUS_SUBMITTED;
        order.Last_Stage_Completed_At__c = System.now();
        insert order;

        publishStage(order.Id, STAGE_SUBMITTED, 'Order submitted.');
        return order.Id;
    }

    /** Represents an external confirmation (e.g. a carrier webhook) that an order arrived. */
    public static void confirmDelivery(Id orderId, String detail) {
        publishStage(orderId, STAGE_DELIVERED, detail);
    }

    public static void reportFailure(Id orderId, String reason) {
        publishStage(orderId, STAGE_FAILED, reason);
    }

    /**
     * Idempotently advances an order from expectedCurrentStatus to newStatus, then
     * publishes the next stage event. Returns false (a safe no-op) if the order has
     * already moved past expectedCurrentStatus — the guard against at-least-once
     * event redelivery re-running a stage transition twice.
     */
    public static Boolean advanceOrder(Id orderId, String expectedCurrentStatus, String newStatus, String nextStage, String detail) {
        List<Order__c> locked = [
            SELECT Id, Status__c
            FROM Order__c
            WHERE Id = :orderId
            WITH USER_MODE
            FOR UPDATE
        ];
        if (locked.isEmpty() || locked[0].Status__c != expectedCurrentStatus) {
            return false;
        }

        Order__c order = locked[0];
        order.Status__c = newStatus;
        order.Last_Stage_Completed_At__c = System.now();
        update order;

        if (nextStage != null) {
            publishStage(orderId, nextStage, detail);
        }
        return true;
    }

    public static void markFailed(Id orderId, String reason) {
        update new Order__c(Id = orderId, Status__c = STATUS_FAILED, Failure_Reason__c = reason);
    }

    public static void publishStage(Id orderId, String stage, String detail) {
        EventBus.publish(new Order_Stage_Event__e(
            Order_Id__c = orderId,
            Stage__c = stage,
            Detail__c = detail
        ));
    }

    public static void logEvent(Id orderId, String eventType, String status, String detail) {
        insert new Order_Event_Log__c(
            Order__c = orderId,
            Event_Type__c = eventType,
            Status__c = status,
            Detail__c = detail
        );
    }
}
