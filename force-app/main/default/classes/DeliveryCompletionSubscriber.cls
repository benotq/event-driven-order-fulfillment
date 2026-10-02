public with sharing class DeliveryCompletionSubscriber implements OrderStageEventSubscriber {

    public Boolean appliesTo(String stage) {
        return stage == OrderFulfillmentService.STAGE_DELIVERED;
    }

    public void handle(Order_Stage_Event__e event) {
        OrderFulfillmentService.advanceOrder(
            (Id) event.Order_Id__c,
            OrderFulfillmentService.STATUS_SHIPPED,
            OrderFulfillmentService.STATUS_DELIVERED,
            null,
            event.Detail__c
        );
    }
}
