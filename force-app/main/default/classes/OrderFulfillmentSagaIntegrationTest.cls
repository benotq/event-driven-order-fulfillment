@isTest
private class OrderFulfillmentSagaIntegrationTest {

    @isTest
    static void testFullSagaAdvancesThroughEveryStageOneHopAtATime() {
        Test.startTest();
        Id orderId = OrderFulfillmentService.submitOrder(new Order__c(Order_Total__c = 1200));

        // Hop 1: SUBMITTED -> Inventory Reserved (publishes INVENTORY_RESERVED, not yet delivered).
        Test.getEventBus().deliver();
        Assert.areEqual(OrderFulfillmentService.STATUS_INVENTORY_RESERVED, statusOf(orderId));

        // Hop 2: INVENTORY_RESERVED -> Shipped (publishes SHIPPED, not yet delivered).
        Test.getEventBus().deliver();
        Assert.areEqual(OrderFulfillmentService.STATUS_SHIPPED, statusOf(orderId));

        // Hop 3: SHIPPED notifies the customer but does not itself advance the order -
        // delivery only happens on an explicit external confirmation.
        Test.getEventBus().deliver();
        Assert.areEqual(OrderFulfillmentService.STATUS_SHIPPED, statusOf(orderId));
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Order_Event_Log__c WHERE Order__c = :orderId AND Event_Type__c = 'NOTIFICATION_SENT']
        );

        // External confirmation (e.g. a carrier webhook) drives the final hop.
        OrderFulfillmentService.confirmDelivery(orderId, 'Delivered and signed for.');
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.areEqual(OrderFulfillmentService.STATUS_DELIVERED, statusOf(orderId));

        List<Order_Event_Log__c> auditTrail = [
            SELECT Event_Type__c, Status__c
            FROM Order_Event_Log__c
            WHERE Order__c = :orderId AND Event_Type__c IN ('SUBMITTED', 'INVENTORY_RESERVED', 'SHIPPED', 'DELIVERED')
            ORDER BY CreatedDate ASC
        ];
        Assert.areEqual(4, auditTrail.size(), 'Every stage of the saga should leave exactly one audit entry.');
        Assert.areEqual('SUBMITTED', auditTrail[0].Event_Type__c);
        Assert.areEqual('DELIVERED', auditTrail[3].Event_Type__c);
    }

    @isTest
    static void testDuplicateStageEventIsIgnoredByTheStateChangingSubscriberButStillAudited() {
        Order__c order = new Order__c(Status__c = OrderFulfillmentService.STATUS_SUBMITTED);
        insert order;

        Test.startTest();
        OrderFulfillmentService.publishStage(order.Id, OrderFulfillmentService.STAGE_SUBMITTED, 'Original delivery.');
        OrderFulfillmentService.publishStage(order.Id, OrderFulfillmentService.STAGE_SUBMITTED, 'Duplicate redelivery.');
        Test.getEventBus().deliver();

        // Asserted before stopTest(), which performs one implicit delivery of its own -
        // asserting after it would silently observe one extra hop of the saga.
        Assert.areEqual(
            OrderFulfillmentService.STATUS_INVENTORY_RESERVED,
            statusOf(order.Id),
            'The order should advance exactly one step even though SUBMITTED was delivered twice.'
        );
        Assert.areEqual(
            2,
            [SELECT COUNT() FROM Order_Event_Log__c WHERE Order__c = :order.Id AND Event_Type__c = 'SUBMITTED'],
            'The audit trail records every delivery attempt, including the duplicate.'
        );
        Test.stopTest();
    }

    @isTest
    static void testDuplicateShippedEventDoesNotSendASecondNotification() {
        Order__c order = new Order__c(Status__c = OrderFulfillmentService.STATUS_SHIPPED);
        insert order;

        Test.startTest();
        OrderFulfillmentService.publishStage(order.Id, OrderFulfillmentService.STAGE_SHIPPED, 'First delivery.');
        OrderFulfillmentService.publishStage(order.Id, OrderFulfillmentService.STAGE_SHIPPED, 'Duplicate redelivery.');

        Test.getEventBus().deliver();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Order_Event_Log__c WHERE Order__c = :order.Id AND Event_Type__c = 'NOTIFICATION_SENT'],
            'A duplicate SHIPPED delivery must not send a second notification.'
        );
        Test.stopTest();
    }

    @isTest
    static void testOneFailingSubscriberDoesNotPreventOthersFromRunning() {
        Order__c order = new Order__c(Status__c = OrderFulfillmentService.STATUS_SUBMITTED);
        insert order;

        List<OrderStageEventSubscriber> original = OrderStageEventHandler.subscribers;
        OrderStageEventHandler.subscribers = new List<OrderStageEventSubscriber>{
            new ThrowingTestSubscriber(),
            new AuditTrailSubscriber()
        };

        try {
            Test.startTest();
            OrderFulfillmentService.publishStage(order.Id, OrderFulfillmentService.STAGE_SUBMITTED, 'Trigger a failing subscriber.');
            Test.getEventBus().deliver();
            Test.stopTest();
        } finally {
            OrderStageEventHandler.subscribers = original;
        }

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Order_Event_Log__c WHERE Order__c = :order.Id AND Event_Type__c = 'SUBMITTED'],
            'AuditTrailSubscriber must still log the event even though the subscriber before it threw.'
        );
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Order_Event_Log__c WHERE Order__c = :order.Id AND Event_Type__c = 'SUBSCRIBER_ERROR'],
            'The dispatcher should log the failing subscriber as its own observable error entry.'
        );
    }

    @isTest
    static void testStuckOrderMonitorMarksAStalledOrderFailedViaTheNormalFailurePath() {
        Order__c stuckOrder = new Order__c(
            Status__c = OrderFulfillmentService.STATUS_SHIPPED,
            Last_Stage_Completed_At__c = System.now().addMinutes(-StuckOrderMonitorBatch.STUCK_THRESHOLD_MINUTES - 5)
        );
        Order__c freshOrder = new Order__c(
            Status__c = OrderFulfillmentService.STATUS_SHIPPED,
            Last_Stage_Completed_At__c = System.now()
        );
        Order__c deliveredOrder = new Order__c(
            Status__c = OrderFulfillmentService.STATUS_DELIVERED,
            Last_Stage_Completed_At__c = System.now().addMinutes(-StuckOrderMonitorBatch.STUCK_THRESHOLD_MINUTES - 5)
        );
        insert new List<Order__c>{ stuckOrder, freshOrder, deliveredOrder };

        Test.startTest();
        Database.executeBatch(new StuckOrderMonitorBatch());
        Test.stopTest();
        // The batch only actually runs at stopTest(); flush its resulting
        // Order_Stage_Event__e publications explicitly rather than relying on
        // stopTest() having already delivered them in the same pass.
        Test.getEventBus().deliver();

        Assert.areEqual(OrderFulfillmentService.STATUS_FAILED, statusOf(stuckOrder.Id), 'A stalled non-terminal order should be marked Failed.');
        Assert.areEqual(OrderFulfillmentService.STATUS_SHIPPED, statusOf(freshOrder.Id), 'A recently-progressed order must not be flagged.');
        Assert.areEqual(OrderFulfillmentService.STATUS_DELIVERED, statusOf(deliveredOrder.Id), 'A terminal order must never be flagged, no matter how old.');
    }

    @isTest
    static void testStuckOrderMonitorCanBeScheduled() {
        Test.startTest();
        String jobId = System.schedule('Stuck Order Monitor Test', '0 0 3 * * ?', new StuckOrderMonitorScheduler());
        Test.stopTest();

        CronTrigger job = [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId];
        Assert.areEqual('0 0 3 * * ?', job.CronExpression);
    }

    private static String statusOf(Id orderId) {
        return [SELECT Status__c FROM Order__c WHERE Id = :orderId].Status__c;
    }
}
