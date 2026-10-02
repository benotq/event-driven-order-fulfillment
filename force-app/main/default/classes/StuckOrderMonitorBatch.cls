/**
 * Catches sagas that stalled: an order sitting in a non-terminal status for longer
 * than the threshold almost certainly means a subscriber failed outside the normal
 * event flow, or an expected follow-up event (e.g. a delivery confirmation from a
 * carrier) never arrived. Reuses the same FAILED-stage path as any other failure, so
 * there's exactly one way an order becomes Failed, not two.
 */
public with sharing class StuckOrderMonitorBatch implements Database.Batchable<SObject> {

    public static final Integer STUCK_THRESHOLD_MINUTES = 60;

    public Database.QueryLocator start(Database.BatchableContext context) {
        DateTime cutoff = System.now().addMinutes(-STUCK_THRESHOLD_MINUTES);
        return Database.getQueryLocator([
            SELECT Id, Status__c, Last_Stage_Completed_At__c
            FROM Order__c
            WHERE Status__c NOT IN ('Delivered', 'Failed')
            AND Last_Stage_Completed_At__c < :cutoff
            WITH USER_MODE
        ]);
    }

    public void execute(Database.BatchableContext context, List<Order__c> scope) {
        for (Order__c order : scope) {
            OrderFulfillmentService.reportFailure(
                order.Id,
                'Timed out waiting to advance past "' + order.Status__c + '" (last progressed ' + order.Last_Stage_Completed_At__c + ').'
            );
        }
    }

    public void finish(Database.BatchableContext context) {
    }
}
