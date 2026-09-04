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
    __phi_decoder_profile_topology__Top_0_next application (
        .clk(aclk),
        .reset(!aresetn),
        ._x_decoder_events_out(x_decoder_event),
        ._x_decoder_events_out_vld(x_decoder_event_valid),
        ._x_decoder_events_out_rdy(x_decoder_event_ready),
        ._z_decoder_events_out(z_decoder_event),
        ._z_decoder_events_out_vld(z_decoder_event_valid),
        ._z_decoder_events_out_rdy(z_decoder_event_ready)@APPLICATION_RAM_PORTS@
    );

@SCHEDULER_RAMS@
endmodule
