trigger OrderStageEventTrigger on Order_Stage_Event__e (after insert) {
    new OrderStageEventHandler().handle(Trigger.new);
}
