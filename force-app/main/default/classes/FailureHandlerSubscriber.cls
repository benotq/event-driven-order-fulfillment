/**
 * Reacts to a FAILED stage event by marking the order Failed, regardless of whatever
 * status it was previously in — unlike the forward-progress subscribers, a failure is
 * an override, not a guarded transition from one specific expected status.
 */
public with sharing class FailureHandlerSubscriber implements OrderStageEventSubscriber {

    public Boolean appliesTo(String stage) {
        return stage == OrderFulfillmentService.STAGE_FAILED;
    }

    public void handle(Order_Stage_Event__e event) {
        OrderFulfillmentService.markFailed((Id) event.Order_Id__c, event.Detail__c);
    }
}
