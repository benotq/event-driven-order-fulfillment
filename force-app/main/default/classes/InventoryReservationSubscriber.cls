public with sharing class InventoryReservationSubscriber implements OrderStageEventSubscriber {

    public Boolean appliesTo(String stage) {
        return stage == OrderFulfillmentService.STAGE_SUBMITTED;
    }

    public void handle(Order_Stage_Event__e event) {
        OrderFulfillmentService.advanceOrder(
            (Id) event.Order_Id__c,
            OrderFulfillmentService.STATUS_SUBMITTED,
            OrderFulfillmentService.STATUS_INVENTORY_RESERVED,
            OrderFulfillmentService.STAGE_INVENTORY_RESERVED,
            'Inventory reserved for order.'
        );
    }
}
