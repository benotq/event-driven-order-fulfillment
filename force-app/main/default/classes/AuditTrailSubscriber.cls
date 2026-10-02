/**
 * Listens to every stage, unconditionally. This is intentionally decoupled from
 * whether a forward-progress subscriber actually advanced the order (it may have been
 * a no-op duplicate) — the audit trail records what was *received*, not what changed,
 * which is what you want when diagnosing redelivery or ordering issues later.
 */
public with sharing class AuditTrailSubscriber implements OrderStageEventSubscriber {

    public Boolean appliesTo(String stage) {
        return true;
    }

    public void handle(Order_Stage_Event__e event) {
        String status = event.Stage__c == OrderFulfillmentService.STAGE_FAILED ? 'Failed' : 'Success';
        OrderFulfillmentService.logEvent((Id) event.Order_Id__c, event.Stage__c, status, event.Detail__c);
    }
}
