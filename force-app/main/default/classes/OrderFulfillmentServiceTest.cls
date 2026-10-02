@isTest
private class OrderFulfillmentServiceTest {

    @isTest
    static void testSubmitOrderInsertsAsSubmittedAndPublishesFirstStage() {
        Test.startTest();
        Id orderId = OrderFulfillmentService.submitOrder(new Order__c(Order_Total__c = 500));
        Test.getEventBus().deliver();

        // Asserted before stopTest(), which performs one implicit delivery of its own -
        // asserting after it would silently observe one extra hop of the saga.
        Order__c order = [SELECT Status__c FROM Order__c WHERE Id = :orderId];
        Assert.areEqual(
            OrderFulfillmentService.STATUS_INVENTORY_RESERVED,
            order.Status__c,
            'Submitting should publish SUBMITTED, which InventoryReservationSubscriber advances to Inventory Reserved.'
        );
        Test.stopTest();
    }

    @isTest
    static void testAdvanceOrderIsANoOpWhenStatusAlreadyMovedPast() {
        Order__c order = new Order__c(Status__c = OrderFulfillmentService.STATUS_INVENTORY_RESERVED);
        insert order;

        Test.startTest();
        Boolean advanced = OrderFulfillmentService.advanceOrder(
            order.Id,
            OrderFulfillmentService.STATUS_SUBMITTED,
            OrderFulfillmentService.STATUS_INVENTORY_RESERVED,
            null,
            null
        );
        Test.stopTest();

        Assert.isFalse(advanced, 'advanceOrder must refuse to transition when the order is not in the expected starting status.');
        Order__c unchanged = [SELECT Status__c FROM Order__c WHERE Id = :order.Id];
        Assert.areEqual(OrderFulfillmentService.STATUS_INVENTORY_RESERVED, unchanged.Status__c);
    }

    @isTest
    static void testMarkFailedOverridesAnyPriorStatus() {
        Order__c order = new Order__c(Status__c = OrderFulfillmentService.STATUS_SHIPPED);
        insert order;

        Test.startTest();
        OrderFulfillmentService.markFailed(order.Id, 'Carrier lost the package.');
        Test.stopTest();

        Order__c failed = [SELECT Status__c, Failure_Reason__c FROM Order__c WHERE Id = :order.Id];
        Assert.areEqual(OrderFulfillmentService.STATUS_FAILED, failed.Status__c);
        Assert.areEqual('Carrier lost the package.', failed.Failure_Reason__c);
    }
}
