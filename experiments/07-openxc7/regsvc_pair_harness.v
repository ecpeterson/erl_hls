`default_nettype none

// Compile-only shell around the routed pair. Independent packet generators
// issue valid application and debug requests to both endpoints. Boundary
// registers capture every response before a rotating digest reduces them to
// one observable pin, retaining translated-process state without treating the
// four logical AXIS interfaces as board I/O or lengthening DUT timing paths.
module regsvc_pair_openxc7_harness (
    input  wire clock,
    output wire activity
);
    localparam [1:0] APP_ROUTE = 2'd0;
    localparam [1:0] APP_HEADER = 2'd1;
    localparam [1:0] APP_PAYLOAD = 2'd2;

    localparam DEBUG_ROUTE = 1'b0;
    localparam DEBUG_HEADER = 1'b1;

    reg [3:0]  reset_pipe = 4'b0;
    reg [31:0] app_lfsr = 32'h0000_0001;
    reg [1:0]  app_phase = APP_ROUTE;
    reg [2:0]  app_operation = 3'b0;
    reg [1:0]  app_payload_index = 2'b0;
    reg        app_destination = 1'b0;
    reg [31:0] debug_lfsr = 32'h1357_9bdf;
    reg        debug_phase = DEBUG_ROUTE;
    reg [1:0]  debug_operation = 2'b0;
    reg        debug_destination = 1'b0;
    reg [31:0] flow_lfsr = 32'h2468_ace1;

    reg [31:0] app_response_capture = 32'b0;
    reg [31:0] debug_response_capture = 32'b0;
    reg [31:0] response_control_capture = 32'b0;
    reg [31:0] response_digest = 32'b0;

    wire resetn = reset_pipe[3];

    wire        app_request_ready;
    wire [31:0] app_response_data;
    wire [3:0]  app_response_keep;
    wire        app_response_valid;
    wire        app_response_last;

    wire        debug_request_ready;
    wire [31:0] debug_response_data;
    wire [3:0]  debug_response_keep;
    wire        debug_response_valid;
    wire        debug_response_last;

    function [31:0] next_lfsr;
        input [31:0] value;
        begin
            next_lfsr = {
                value[30:0],
                value[31] ^ value[21] ^ value[1] ^ value[0]
            };
        end
    endfunction

    wire [15:0] app_endpoint = app_destination ? 16'd2 : 16'd1;
    wire [7:0] app_tag = 8'd3 + {5'b0, app_operation};
    wire [7:0] app_payload_words = app_operation == 3'd0 ? 8'd3 :
        app_operation == 3'd1 || app_operation == 3'd2 ? 8'd1 :
        app_operation == 3'd3 ? 8'd2 : 8'd0;
    wire app_payload_last =
        (app_operation == 3'd0 && app_payload_index == 2'd2) ||
        ((app_operation == 3'd1 || app_operation == 3'd2) &&
            app_payload_index == 2'd0) ||
        (app_operation == 3'd3 && app_payload_index == 2'd1);
    wire [31:0] app_payload_data = app_operation == 3'd0 ?
        (app_payload_index == 2'd0 ? {31'b0, app_lfsr[8]} :
         app_payload_index == 2'd1 ? app_lfsr : 32'hffff_ffff) :
        app_operation == 3'd1 ?
            (app_lfsr[9] ? app_lfsr : {31'b0, app_lfsr[8]}) :
        app_operation == 3'd2 ? app_lfsr :
        app_payload_index == 2'd0 ? 32'd0 : 32'd3;
    wire [31:0] app_request_data = app_phase == APP_ROUTE ?
        {16'd0, app_endpoint} :
        app_phase == APP_HEADER ?
            {app_tag, 8'd0, app_lfsr[7:0], app_payload_words} :
            app_payload_data;
    wire app_request_last =
        (app_phase == APP_HEADER && app_payload_words == 8'd0) ||
        (app_phase == APP_PAYLOAD && app_payload_last);

    wire [15:0] debug_endpoint = debug_destination ? 16'd2 : 16'd1;
    wire [7:0] debug_tag = 8'd1 + {6'b0, debug_operation};
    wire [31:0] debug_request_data = debug_phase == DEBUG_ROUTE ?
        {16'd0, debug_endpoint} :
        {debug_tag, 8'd0, debug_lfsr[7:0], 8'd0};
    wire debug_request_last = debug_phase == DEBUG_HEADER;

    always @(posedge clock) begin
        reset_pipe <= {reset_pipe[2:0], 1'b1};
        if (!resetn) begin
            app_lfsr <= 32'h0000_0001;
            app_phase <= APP_ROUTE;
            app_operation <= 3'b0;
            app_payload_index <= 2'b0;
            app_destination <= 1'b0;
            debug_lfsr <= 32'h1357_9bdf;
            debug_phase <= DEBUG_ROUTE;
            debug_operation <= 2'b0;
            debug_destination <= 1'b0;
            flow_lfsr <= 32'h2468_ace1;
        end else begin
            flow_lfsr <= next_lfsr(flow_lfsr);

            if (app_request_ready) begin
                case (app_phase)
                    APP_ROUTE: app_phase <= APP_HEADER;
                    APP_HEADER: begin
                        if (app_payload_words == 8'd0) begin
                            app_phase <= APP_ROUTE;
                            if (app_destination)
                                app_operation <= app_operation + 1'b1;
                            app_destination <= !app_destination;
                            app_lfsr <= next_lfsr(app_lfsr);
                        end else begin
                            app_phase <= APP_PAYLOAD;
                            app_payload_index <= 2'b0;
                        end
                    end
                    default: begin
                        if (app_payload_last) begin
                            app_phase <= APP_ROUTE;
                            if (app_destination)
                                app_operation <= app_operation + 1'b1;
                            app_destination <= !app_destination;
                            app_lfsr <= next_lfsr(app_lfsr);
                            app_payload_index <= 2'b0;
                        end else begin
                            app_payload_index <= app_payload_index + 1'b1;
                        end
                    end
                endcase
            end

            if (debug_request_ready) begin
                if (debug_phase == DEBUG_ROUTE) begin
                    debug_phase <= DEBUG_HEADER;
                end else begin
                    debug_phase <= DEBUG_ROUTE;
                    if (debug_destination)
                        debug_operation <= debug_operation + 1'b1;
                    debug_destination <= !debug_destination;
                    debug_lfsr <= next_lfsr(debug_lfsr);
                end
            end
        end
    end

    // Keep the DUT boundary itself registered. The digest consumes the prior
    // cycle's captures, so its XOR tree is not part of a DUT timing path.
    always @(posedge clock) begin
        if (!resetn) begin
            app_response_capture <= 32'b0;
            debug_response_capture <= 32'b0;
            response_control_capture <= 32'b0;
            response_digest <= 32'b0;
        end else begin
            app_response_capture <= app_response_data;
            debug_response_capture <= debug_response_data;
            response_control_capture <= {
                18'b0,
                app_request_ready,
                app_response_keep,
                app_response_valid,
                app_response_last,
                debug_request_ready,
                debug_response_keep,
                debug_response_valid,
                debug_response_last
            };
            response_digest <=
                {response_digest[30:0], response_digest[31]} ^
                app_response_capture ^
                debug_response_capture ^
                response_control_capture;
        end
    end

    regsvc_pair_fixture routed_pair (
        .aclk(clock),
        .aresetn(resetn),

        .s_axis_tdata(app_request_data),
        .s_axis_tkeep(4'hf),
        .s_axis_tvalid(resetn),
        .s_axis_tready(app_request_ready),
        .s_axis_tlast(app_request_last),

        .m_axis_tdata(app_response_data),
        .m_axis_tkeep(app_response_keep),
        .m_axis_tvalid(app_response_valid),
        .m_axis_tready(flow_lfsr[0] || flow_lfsr[3]),
        .m_axis_tlast(app_response_last),

        .s_dbg_tdata(debug_request_data),
        .s_dbg_tkeep(4'hf),
        .s_dbg_tvalid(resetn),
        .s_dbg_tready(debug_request_ready),
        .s_dbg_tlast(debug_request_last),

        .m_dbg_tdata(debug_response_data),
        .m_dbg_tkeep(debug_response_keep),
        .m_dbg_tvalid(debug_response_valid),
        .m_dbg_tready(flow_lfsr[1] || flow_lfsr[4]),
        .m_dbg_tlast(debug_response_last)
    );

    assign activity = response_digest[31];
endmodule

`default_nettype wire
