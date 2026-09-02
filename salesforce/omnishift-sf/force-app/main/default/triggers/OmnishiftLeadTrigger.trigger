/**
 * Puts a new inbound lead on the board immediately, for the intake channels the
 * firm holds a five-minute SLA on. Everything else waits for the nightly run.
 */
trigger OmnishiftLeadTrigger on Lead (after insert) {
    OmnishiftInboundService.scoreNew(Trigger.new);
}
