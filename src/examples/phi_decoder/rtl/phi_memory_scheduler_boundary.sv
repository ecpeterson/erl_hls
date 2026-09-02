`timescale 1ns/1ps

// Routed phi-memory wire protocol around a scheduler-local command/event pair.
//
// The worker interface intentionally contains no transport endpoints. Multiple
// workers may later sit behind this boundary, with commands distributed and
// events merged without changing the ERTS-visible stream.
module phi_memory_scheduler_boundary (
    input  wire         clk,
    input  wire         resetn,

    input  wire [31:0]  s_axis_tdata,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    input  wire         s_axis_tlast,

    output reg  [31:0]  m_axis_tdata,
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready,
    output wire         m_axis_tlast,

    output reg  [129:0] worker_command,
    output reg          worker_command_valid,
    input  wire         worker_command_ready,

    input  wire [103:0] worker_event,
    input  wire         worker_event_valid,
    output wire         worker_event_ready
);
    localparam [31:0] INPUT_ROUTE = 32'h00000001;
    localparam [31:0] CUTOFF_HEADER = 32'h0f010003;
    localparam [31:0] UPDATE_HEADER = 32'h10010003;
    localparam [31:0] QUERY_HEADER = 32'h0d010004;

    localparam [1:0] COMMAND_CUTOFF = 2'd0;
    localparam [1:0] COMMAND_UPDATE = 2'd1;
    localparam [1:0] COMMAND_QUERY = 2'd2;

    localparam [1:0] EVENT_ANNOUNCEMENT = 2'd0;
    localparam [1:0] EVENT_CORRECTION = 2'd1;
    localparam [1:0] EVENT_STATUS = 2'd2;
    localparam [1:0] EVENT_REPLY = 2'd3;

    localparam [15:0] DATA_ENDPOINT = 16'd2;
    localparam [15:0] X_ANNOUNCEMENTS_ENDPOINT = 16'd3;
    localparam [15:0] X_DECODER_EVENTS_ENDPOINT = 16'd4;
    localparam [15:0] Z_ANNOUNCEMENTS_ENDPOINT = 16'd5;
    localparam [15:0] Z_DECODER_EVENTS_ENDPOINT = 16'd6;

    localparam [7:0] OP_ANNOUNCEMENT = 8'd10;
    localparam [7:0] OP_CORRECTION = 8'd11;
    localparam [7:0] OP_PAULI_REPLY = 8'd14;
    localparam [7:0] OP_STATUS = 8'd17;

    localparam [2:0] IN_ROUTE = 3'd0;
    localparam [2:0] IN_HEADER = 3'd1;
    localparam [2:0] IN_RECT0 = 3'd2;
    localparam [2:0] IN_RECT1 = 3'd3;
    localparam [2:0] IN_PAYLOAD0 = 3'd4;
    localparam [2:0] IN_PAYLOAD1 = 3'd5;
    localparam [2:0] IN_DROP = 3'd6;

    reg [2:0] in_state;
    reg [31:0] in_header;
    reg [15:0] in_x0;
    reg [15:0] in_y0;
    reg [15:0] in_x1;
    reg [15:0] in_y1;
    reg [31:0] in_payload0;

    reg out_busy;
    reg [2:0] out_word;
    reg [15:0] out_source;
    reg [7:0] out_op;
    reg [31:0] out_payload0;
    reg [31:0] out_payload1;
    reg [31:0] out_payload2;

    wire [1:0] event_kind = worker_event[103:102];
    wire event_plane = worker_event[101];
    wire [4:0] event_index = worker_event[100:96];
    wire [31:0] event_step = worker_event[95:64];
    wire [31:0] event_request_id = worker_event[63:32];
    wire [31:0] event_value = worker_event[31:0];
    function automatic [31:0] phi_coordinate(input [4:0] index);
        begin
            case (index)
                0: phi_coordinate = 32'h00000000;
                1: phi_coordinate = 32'h00010000;
                2: phi_coordinate = 32'h00020000;
                3: phi_coordinate = 32'h00000001;
                4: phi_coordinate = 32'h00010001;
                5: phi_coordinate = 32'h00020001;
                6: phi_coordinate = 32'h00000002;
                7: phi_coordinate = 32'h00010002;
                default: phi_coordinate = 32'h00020002;
            endcase
        end
    endfunction

    function automatic [31:0] data_coordinate(input [4:0] index);
        begin
            case (index)
                0: data_coordinate = 32'h00000000;
                1: data_coordinate = 32'h00010000;
                2: data_coordinate = 32'h00020000;
                3: data_coordinate = 32'h00030000;
                4: data_coordinate = 32'h00040000;
                5: data_coordinate = 32'h00050000;
                6: data_coordinate = 32'h00000001;
                7: data_coordinate = 32'h00010001;
                8: data_coordinate = 32'h00020001;
                9: data_coordinate = 32'h00030001;
                10: data_coordinate = 32'h00040001;
                11: data_coordinate = 32'h00050001;
                12: data_coordinate = 32'h00000002;
                13: data_coordinate = 32'h00010002;
                14: data_coordinate = 32'h00020002;
                15: data_coordinate = 32'h00030002;
                16: data_coordinate = 32'h00040002;
                default: data_coordinate = 32'h00050002;
            endcase
        end
    endfunction

    wire rectangle_valid = in_x0 <= in_x1 && in_x1 < 16'd3 &&
        in_y0 <= in_y1 && in_y1 < 16'd6;
    wire command_slot_available =
        !worker_command_valid || worker_command_ready;

    assign s_axis_tready = command_slot_available;
    assign worker_event_ready = !out_busy;
    assign m_axis_tvalid = out_busy;
    assign m_axis_tlast = out_busy && out_word == 3'd4;

    always @* begin
        case (out_word)
            3'd0: m_axis_tdata = {out_source, 16'd0};
            3'd1: m_axis_tdata = {out_op, 8'd1, 8'd0, 8'd3};
            3'd2: m_axis_tdata = out_payload0;
            3'd3: m_axis_tdata = out_payload1;
            default: m_axis_tdata = out_payload2;
        endcase
    end

    task automatic accept_command(
        input [1:0] kind,
        input [31:0] request_id,
        input [31:0] value
    );
        begin
            worker_command <= {
                kind,
                in_x0,
                in_y0,
                in_x1,
                in_y1,
                request_id,
                value
            };
            worker_command_valid <= 1'b1;
        end
    endtask

    always @(posedge clk) begin
        if (!resetn) begin
            in_state <= IN_ROUTE;
            in_header <= 32'd0;
            in_x0 <= 16'd0;
            in_y0 <= 16'd0;
            in_x1 <= 16'd0;
            in_y1 <= 16'd0;
            in_payload0 <= 32'd0;
            worker_command <= 130'd0;
            worker_command_valid <= 1'b0;
            out_busy <= 1'b0;
            out_word <= 3'd0;
            out_source <= 16'd0;
            out_op <= 8'd0;
            out_payload0 <= 32'd0;
            out_payload1 <= 32'd0;
            out_payload2 <= 32'd0;
        end else begin
            if (worker_command_valid && worker_command_ready)
                worker_command_valid <= 1'b0;

            if (s_axis_tvalid && s_axis_tready) begin
                case (in_state)
                    IN_ROUTE: begin
                        if (s_axis_tlast)
                            in_state <= IN_ROUTE;
                        else if (s_axis_tdata == INPUT_ROUTE)
                            in_state <= IN_HEADER;
                        else
                            in_state <= IN_DROP;
                    end
                    IN_HEADER: begin
                        in_header <= s_axis_tdata;
                        if (s_axis_tlast)
                            in_state <= IN_ROUTE;
                        else if (s_axis_tdata == CUTOFF_HEADER ||
                                 s_axis_tdata == UPDATE_HEADER ||
                                 s_axis_tdata == QUERY_HEADER)
                            in_state <= IN_RECT0;
                        else
                            in_state <= IN_DROP;
                    end
                    IN_RECT0: begin
                        if (s_axis_tlast) begin
                            in_state <= IN_ROUTE;
                        end else begin
                            in_x0 <= s_axis_tdata[15:0];
                            in_y0 <= s_axis_tdata[31:16];
                            in_state <= IN_RECT1;
                        end
                    end
                    IN_RECT1: begin
                        if (s_axis_tlast) begin
                            in_state <= IN_ROUTE;
                        end else begin
                            in_x1 <= s_axis_tdata[15:0];
                            in_y1 <= s_axis_tdata[31:16];
                            in_state <= IN_PAYLOAD0;
                        end
                    end
                    IN_PAYLOAD0: begin
                        if (in_header == QUERY_HEADER) begin
                            if (s_axis_tlast)
                                in_state <= IN_ROUTE;
                            else begin
                                in_payload0 <= s_axis_tdata;
                                in_state <= IN_PAYLOAD1;
                            end
                        end else begin
                            if (s_axis_tlast && rectangle_valid) begin
                                if (in_header == CUTOFF_HEADER)
                                    accept_command(
                                        COMMAND_CUTOFF, 32'd0, s_axis_tdata);
                                else if (s_axis_tdata <= 32'd3)
                                    accept_command(
                                        COMMAND_UPDATE, 32'd0, s_axis_tdata);
                            end
                            in_state <= s_axis_tlast ? IN_ROUTE : IN_DROP;
                        end
                    end
                    IN_PAYLOAD1: begin
                        if (s_axis_tlast && rectangle_valid &&
                            s_axis_tdata <= 32'd3)
                            accept_command(
                                COMMAND_QUERY, in_payload0, s_axis_tdata);
                        in_state <= s_axis_tlast ? IN_ROUTE : IN_DROP;
                    end
                    default: begin
                        if (s_axis_tlast)
                            in_state <= IN_ROUTE;
                    end
                endcase
            end

            if (out_busy && m_axis_tready) begin
                if (out_word == 3'd4)
                    out_busy <= 1'b0;
                else
                    out_word <= out_word + 1'b1;
            end

            if (worker_event_valid && worker_event_ready) begin
                out_busy <= 1'b1;
                out_word <= 3'd0;
                case (event_kind)
                    EVENT_ANNOUNCEMENT: begin
                        out_source <= event_plane ?
                            Z_ANNOUNCEMENTS_ENDPOINT :
                            X_ANNOUNCEMENTS_ENDPOINT;
                        out_op <= OP_ANNOUNCEMENT;
                        out_payload0 <= event_step;
                        out_payload1 <= event_value;
                        out_payload2 <= phi_coordinate(event_index);
                    end
                    EVENT_CORRECTION: begin
                        out_source <= event_plane ?
                            Z_DECODER_EVENTS_ENDPOINT :
                            X_DECODER_EVENTS_ENDPOINT;
                        out_op <= OP_CORRECTION;
                        out_payload0 <= event_step;
                        out_payload1 <= phi_coordinate(event_index);
                        out_payload2 <= event_value;
                    end
                    EVENT_STATUS: begin
                        out_source <= event_plane ?
                            Z_DECODER_EVENTS_ENDPOINT :
                            X_DECODER_EVENTS_ENDPOINT;
                        out_op <= OP_STATUS;
                        out_payload0 <= event_step;
                        out_payload1 <= phi_coordinate(event_index);
                        out_payload2 <= event_value;
                    end
                    default: begin
                        out_source <= DATA_ENDPOINT;
                        out_op <= OP_PAULI_REPLY;
                        out_payload0 <= event_request_id;
                        out_payload1 <= data_coordinate(event_index);
                        out_payload2 <= event_value;
                    end
                endcase
            end
        end
    end
endmodule
