/**
 * Contract for a single-responsibility reaction to an Order_Stage_Event__e. Each
 * subscriber decides for itself which stage(s) it cares about (appliesTo) and is
 * otherwise completely unaware of every other subscriber — new reactions are added by
 * registering a new class in OrderStageEventHandler, never by editing an existing one.
 */
public interface OrderStageEventSubscriber {
    Boolean appliesTo(String stage);
    void handle(Order_Stage_Event__e event);
}
