// Generate/check a fixed 64-byte broadcast frame with experimental EtherType
// 0x88b5. Payload integrity and frame counts only: no delivery/sequence protocol.
// Streams and counters use their directional clocks; reset abandons prefixes.
// enable is asynchronous and pauses TX (including an unfinished producer frame).
// GAP_CYCLES is the gap after queue admission, not an on-wire inter-frame gap.
module ethernet_probe_traffic #(parameter GAP_CYCLES=125000)(
    input wire tx_clock, tx_reset_n, rx_clock, rx_reset_n, enable,
    output wire tx_valid, tx_last,
    output wire [7:0] tx_data,
    input wire tx_ready, rx_valid, rx_last,
    input wire [7:0] rx_data,
    output wire rx_ready,
    output reg [31:0] sent, received, bad_frames
);
    // Stable broadcast/local source header, followed by an index-dependent body.
    function [7:0] pattern(input [5:0] index);
        begin
            case(index)
                0,1,2,3,4,5: pattern=8'hff;
                6: pattern=8'h02;
                7,8,9,10: pattern=0;
                11: pattern=1;
                12: pattern=8'h88;
                13: pattern=8'hb5;
                default: pattern={2'b0,index} ^ 8'ha5;
            endcase
        end
    endfunction
    (* ASYNC_REG="TRUE" *) reg [1:0] enable_sync;
    reg [5:0] tx_index;
    reg [31:0] delay;
    reg [6:0] rx_index;
    reg bad;
    // Count registered events so wide diagnostic counters do not extend the
    // frame-admission/checking path. Observations lag completion by one cycle.
    reg sent_event, received_event, bad_event;
    assign tx_valid=tx_reset_n && enable_sync[1] && delay==0;
    assign tx_last=tx_index==63;
    assign tx_data=pattern(tx_index);
    assign rx_ready=rx_reset_n;
    always @(posedge tx_clock or negedge tx_reset_n) begin
        if(!tx_reset_n) begin enable_sync<=0; tx_index<=0; delay<=0; sent<=0; sent_event<=0; end
        else begin
            enable_sync<={enable_sync[0],enable};
            sent_event<=tx_valid && tx_ready && tx_last;
            if(sent_event) sent<=sent+1'b1;
            if(delay!=0) delay<=delay-1'b1;
            if(tx_valid && tx_ready) begin
                tx_index<=tx_index+1'b1;
                if(tx_last) delay<=GAP_CYCLES;
            end
        end
    end
    always @(posedge rx_clock or negedge rx_reset_n) begin
        if(!rx_reset_n) begin
            rx_index<=0; bad<=0; received<=0; bad_frames<=0; received_event<=0; bad_event<=0;
        end else begin
            received_event<=rx_valid && rx_ready && rx_last;
            bad_event<=rx_valid && rx_ready && rx_last &&
                       (bad || rx_index!=63 || rx_data!=pattern(rx_index[5:0]));
            if(received_event) received<=received+1'b1;
            if(bad_event) bad_frames<=bad_frames+1'b1;
            if(rx_valid && rx_ready) begin
                if(rx_last) begin rx_index<=0; bad<=0; end
                else begin
                    if(rx_index<64) rx_index<=rx_index+1'b1;
                    bad<=bad || rx_index>=63 || rx_data!=pattern(rx_index[5:0]);
                end
            end
        end
    end
endmodule
