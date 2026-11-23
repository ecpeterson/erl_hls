// Decoder-only phi topology with scheduler-owned 1R1W RAMs. This shell is
// rendered by phi_decoder_profile_top_v from the selected physical profile.
module phi_decoder_profile_top (
    input  wire         aclk,
    input  wire         aresetn,

    output wire [127:0] x_decoder_event,
    output wire         x_decoder_event_valid,
    input  wire         x_decoder_event_ready,

    output wire [127:0] z_decoder_event,
    output wire         z_decoder_event_valid,
    input  wire         z_decoder_event_ready
);
@SCHEDULER_WIRES@
@PROFILE_READS@
@INACTIVE_PLANES@
    __phi_decoder_profile_topology__Top_0_next application (
        .clk(aclk),
        .reset(!aresetn)@EVENT_PORTS@@APPLICATION_RAM_PORTS@
    );

@SCHEDULER_RAMS@
endmodule
