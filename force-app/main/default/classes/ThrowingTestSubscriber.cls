/**
 * Test double that always applies and always throws, used to verify that
 * OrderStageEventHandler isolates one failing subscriber from the others rather than
 * letting it abort processing of the whole event.
 */
@isTest
public class ThrowingTestSubscriber implements OrderStageEventSubscriber {

    public Boolean appliesTo(String stage) {
        return true;
    }

    public void handle(Order_Stage_Event__e event) {
        throw new TestException('Simulated subscriber failure for ' + event.Stage__c);
    }

    public class TestException extends Exception {}
}
