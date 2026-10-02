/**
 * Schedule with, for example:
 *   System.schedule('Stuck Order Monitor', '0 0 * * * ?', new StuckOrderMonitorScheduler());
 */
public with sharing class StuckOrderMonitorScheduler implements Schedulable {

    public void execute(SchedulableContext context) {
        Database.executeBatch(new StuckOrderMonitorBatch());
    }
}
