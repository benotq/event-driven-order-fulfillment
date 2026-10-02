public with sharing class ShipmentCreationSubscriber implements OrderStageEventSubscriber {

    public Boolean appliesTo(String stage) {
        return stage == OrderFulfillmentService.STAGE_INVENTORY_RESERVED;
    }

    public void handle(Order_Stage_Event__e event) {
        OrderFulfillmentService.advanceOrder(
            (Id) event.Order_Id__c,
            OrderFulfillmentService.STATUS_INVENTORY_RESERVED,
            OrderFulfillmentService.STATUS_SHIPPED,
            OrderFulfillmentService.STAGE_SHIPPED,
            'Shipment created.'
        );
    }
}
