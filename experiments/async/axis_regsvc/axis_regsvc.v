module axis_regsvc (
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME ACLK, ASSOCIATED_BUSIF S_AXIS:M_AXIS, ASSOCIATED_RESET ARESETN" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
    input  wire        aclk,

    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME ARESETN, POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 ARESETN RST" *)
    input  wire        aresetn,

    // Slave AXI Stream
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TDATA" *)
    input  wire [31:0] s_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TKEEP" *)
    input  wire [3:0]  s_axis_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TVALID" *)
    input  wire        s_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TREADY" *)
    output wire        s_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TLAST" *)
    input  wire        s_axis_tlast,

    // Master AXI Stream
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *)
    output wire [31:0] m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TKEEP" *)
    output wire [3:0]  m_axis_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
    output wire        m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
    input  wire        m_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
    output wire        m_axis_tlast
);

    localparam [7:0] OP_GET      = 8'h01;
    localparam [7:0] OP_SET      = 8'h02;
    localparam [7:0] OP_BULK_GET = 8'h03;
    localparam [7:0] OP_PING     = 8'h04;

    localparam [7:0] OP_ACK      = 8'h81;
    localparam [7:0] OP_READ_RSP = 8'h82;
    localparam [7:0] OP_BULK_RSP = 8'h83;
    localparam [7:0] OP_ERROR    = 8'hE0;
    localparam [7:0] OP_EVENT    = 8'hF0;

    localparam [7:0] ERR_BAD_OPCODE   = 8'd1;
    localparam [7:0] ERR_BAD_LENGTH   = 8'd2;
    localparam [7:0] ERR_BAD_REGISTER = 8'd3;

    localparam integer NUM_REGS = 16;
    localparam [31:0] EVENT_PERIOD = 32'd25000000; // adjust as desired

    // Request FSM
    localparam [1:0] RX_IDLE    = 2'd0;
    localparam [1:0] RX_PAYLOAD = 2'd1;
    localparam [1:0] RX_EXEC    = 2'd2;

    reg [1:0] rx_state;

    // Response FSM
    localparam [2:0] TX_IDLE      = 3'd0;
    localparam [2:0] TX_SEND_HDR  = 3'd1;
    localparam [2:0] TX_SEND_W1   = 3'd2;
    localparam [2:0] TX_SEND_W2   = 3'd3;
    localparam [2:0] TX_SEND_BULK = 3'd4;

    reg [2:0] tx_state;

    // Register file
    reg [31:0] regs [0:NUM_REGS-1];
    reg [31:0] reply_mask [0:NUM_REGS-1];

    // Parsed request fields
    reg [7:0] req_opcode;
    reg [7:0] req_flags;
    reg [7:0] req_txid;
    reg [7:0] req_payload_words;
    reg [7:0] req_payload_seen;

    reg [31:0] req_w0;
    reg [31:0] req_w1;
    reg [31:0] req_w2;

    reg req_parse_error;
    reg [7:0] req_error_code;

    // Current response fields
    reg [7:0] rsp_opcode;
    reg [7:0] rsp_flags;
    reg [7:0] rsp_txid;
    reg [7:0] rsp_payload_words;
    reg [31:0] rsp_w1;
    reg [31:0] rsp_w2;

    // BULK_GET response state
    reg [7:0] bulk_start;
    reg [7:0] bulk_count;
    reg [7:0] bulk_index;

    // Simple event generation
    reg [31:0] event_counter;
    reg [7:0]  event_seq;
    reg        event_pending;
    reg [7:0]  event_id;
    reg [31:0] event_value;

    // Visibility/debug
    reg [31:0] malformed_count;
    reg [31:0] event_drop_count;

    // AXIS output holding registers
    reg [31:0] tx_data_reg;
    reg [3:0]  tx_keep_reg;
    reg        tx_last_reg;
    reg        tx_valid_reg;

    wire s_fire;
    wire m_fire;

    assign s_fire = s_axis_tvalid && s_axis_tready;
    assign m_fire = m_axis_tvalid && m_axis_tready;

    // Only accept inbound traffic when not busy sending a response.
    assign s_axis_tready = (rx_state != RX_EXEC) && (tx_state == TX_IDLE) && !tx_valid_reg;

    assign m_axis_tdata  = tx_data_reg;
    assign m_axis_tkeep  = tx_keep_reg;
    assign m_axis_tlast  = tx_last_reg;
    assign m_axis_tvalid = tx_valid_reg;

    integer i;

    task tx_load_word;
        input [31:0] data_in;
        input [3:0]  keep_in;
        input        last_in;
        begin
            tx_data_reg  <= data_in;
            tx_keep_reg  <= keep_in;
            tx_last_reg  <= last_in;
            tx_valid_reg <= 1'b1;
        end
    endtask

    task prepare_error_response;
        input [7:0] txid_in;
        input [7:0] err_in;
        begin
            rsp_opcode        <= OP_ERROR;
            rsp_flags         <= 8'h00;
            rsp_txid          <= txid_in;
            rsp_payload_words <= 8'd1;
            rsp_w1            <= {24'd0, err_in};
            rsp_w2            <= 32'd0;
        end
    endtask

    task prepare_read_response;
        input [7:0] txid_in;
        input [7:0] reg_in;
        input [31:0] value_in;
        begin
            rsp_opcode        <= OP_READ_RSP;
            rsp_flags         <= 8'h00;
            rsp_txid          <= txid_in;
            rsp_payload_words <= 8'd2;
            rsp_w1            <= {24'd0, reg_in};
            rsp_w2            <= value_in;
        end
    endtask

    task prepare_ping_response;
        input [7:0] txid_in;
        input [31:0] cookie_in;
        begin
            rsp_opcode        <= OP_ACK;
            rsp_flags         <= 8'h01;
            rsp_txid          <= txid_in;
            rsp_payload_words <= 8'd1;
            rsp_w1            <= cookie_in;
            rsp_w2            <= 32'd0;
        end
    endtask

    task prepare_bulk_response;
        input [7:0] txid_in;
        input [7:0] start_in;
        input [7:0] count_in;
        begin
            rsp_opcode        <= OP_BULK_RSP;
            rsp_flags         <= 8'h00;
            rsp_txid          <= txid_in;
            rsp_payload_words <= count_in + 8'd1;   // metadata word + count values
            rsp_w1            <= {16'd0, start_in, count_in};
            rsp_w2            <= 32'd0;
            bulk_start        <= start_in;
            bulk_count        <= count_in;
            bulk_index        <= 8'd0;
        end
    endtask

    always @(posedge aclk) begin
        if (!aresetn) begin
            rx_state <= RX_IDLE;
            tx_state <= TX_IDLE;

            req_opcode <= 8'd0;
            req_flags <= 8'd0;
            req_txid <= 8'd0;
            req_payload_words <= 8'd0;
            req_payload_seen <= 8'd0;
            req_w0 <= 32'd0;
            req_w1 <= 32'd0;
            req_w2 <= 32'd0;
            req_parse_error <= 1'b0;
            req_error_code <= 8'd0;

            rsp_opcode <= 8'd0;
            rsp_flags <= 8'd0;
            rsp_txid <= 8'd0;
            rsp_payload_words <= 8'd0;
            rsp_w1 <= 32'd0;
            rsp_w2 <= 32'd0;

            bulk_start <= 8'd0;
            bulk_count <= 8'd0;
            bulk_index <= 8'd0;

            event_counter <= 32'd0;
            event_seq <= 8'd0;
            event_pending <= 1'b0;
            event_id <= 8'd0;
            event_value <= 32'd0;

            malformed_count <= 32'd0;
            event_drop_count <= 32'd0;

            tx_data_reg <= 32'd0;
            tx_keep_reg <= 4'h0;
            tx_last_reg <= 1'b0;
            tx_valid_reg <= 1'b0;

            for (i = 0; i < NUM_REGS; i = i + 1) begin
                regs[i] <= 32'd0;
                reply_mask[i] <= (i[0] == 1'b0) ? 32'h0000_0001 : 32'h0000_0000;
            end
        end else begin
            // Consume AXIS output beat
            if (m_fire)
                tx_valid_reg <= 1'b0;

            // Generate an example async event if reg0 bit0 is set
            if (regs[0][0]) begin
                if (event_counter == EVENT_PERIOD - 1) begin
                    event_counter <= 32'd0;
                    if (!event_pending && tx_state == TX_IDLE && !tx_valid_reg) begin
                        event_pending <= 1'b1;
                        event_id <= 8'hEE;
                        event_value <= regs[1];
                    end else begin
                        event_drop_count <= event_drop_count + 1'b1;
                    end
                end else begin
                    event_counter <= event_counter + 1'b1;
                end
            end else begin
                event_counter <= 32'd0;
            end

            // If completely idle, prefer emitting an async event before accepting a new request
            if ((tx_state == TX_IDLE) && !tx_valid_reg && event_pending) begin
                rsp_opcode        <= OP_EVENT;
                rsp_flags         <= 8'h00;
                rsp_txid          <= event_seq;
                rsp_payload_words <= 8'd2;
                rsp_w1            <= {24'd0, event_id};
                rsp_w2            <= event_value;
                event_seq         <= event_seq + 1'b1;
                event_pending     <= 1'b0;
                tx_state          <= TX_SEND_HDR;
            end else begin
                // RX parser
                case (rx_state)
                    RX_IDLE: begin
                        req_parse_error <= 1'b0;
                        req_error_code  <= 8'd0;
                        req_payload_seen <= 8'd0;

                        if (s_fire) begin
                            req_opcode        <= s_axis_tdata[31:24];
                            req_flags         <= s_axis_tdata[23:16];
                            req_txid          <= s_axis_tdata[15:8];
                            req_payload_words <= s_axis_tdata[7:0];
                            req_w0            <= 32'd0;
                            req_w1            <= 32'd0;
                            req_w2            <= 32'd0;
                            req_payload_seen  <= 8'd0;

                            if (s_axis_tlast) begin
                                // Header-only packet. Valid only for payload_words == 0.
                                if (s_axis_tdata[7:0] != 8'd0) begin
                                    req_parse_error <= 1'b1;
                                    req_error_code  <= ERR_BAD_LENGTH;
                                end
                                rx_state <= RX_EXEC;
                            end else begin
                                rx_state <= RX_PAYLOAD;
                            end
                        end
                    end

                    RX_PAYLOAD: begin
                        if (s_fire) begin
                            if (req_payload_seen == 8'd0)
                                req_w0 <= s_axis_tdata;
                            else if (req_payload_seen == 8'd1)
                                req_w1 <= s_axis_tdata;
                            else if (req_payload_seen == 8'd2)
                                req_w2 <= s_axis_tdata;

                            req_payload_seen <= req_payload_seen + 1'b1;

                            if (s_axis_tlast)
                                rx_state <= RX_EXEC;
                        end
                    end

                    RX_EXEC: begin
                        // Validate actual vs declared payload count
                        if (req_payload_seen != req_payload_words) begin
                            prepare_error_response(req_txid, ERR_BAD_LENGTH);
                            malformed_count <= malformed_count + 1'b1;
                            tx_state <= TX_SEND_HDR;
                        end else begin
                            case (req_opcode)
                                OP_GET: begin
                                    if (req_payload_words != 8'd1) begin
                                        prepare_error_response(req_txid, ERR_BAD_LENGTH);
                                        malformed_count <= malformed_count + 1'b1;
                                    end else if (req_w0[7:0] >= NUM_REGS) begin
                                        prepare_error_response(req_txid, ERR_BAD_REGISTER);
                                        malformed_count <= malformed_count + 1'b1;
                                    end else begin
                                        prepare_read_response(req_txid, req_w0[7:0], regs[req_w0[7:0]]);
                                    end
                                    tx_state <= TX_SEND_HDR;
                                end

                                OP_SET: begin
                                    if (req_payload_words != 8'd3) begin
                                        prepare_error_response(req_txid, ERR_BAD_LENGTH);
                                        malformed_count <= malformed_count + 1'b1;
                                        tx_state <= TX_SEND_HDR;
                                    end else if (req_w0[7:0] >= NUM_REGS) begin
                                        prepare_error_response(req_txid, ERR_BAD_REGISTER);
                                        malformed_count <= malformed_count + 1'b1;
                                        tx_state <= TX_SEND_HDR;
                                    end else begin
                                        regs[req_w0[7:0]] <= (regs[req_w0[7:0]] & ~req_w2) | (req_w1 & req_w2);
                                    end
                                end

                                OP_BULK_GET: begin
                                    if (req_payload_words != 8'd2) begin
                                        prepare_error_response(req_txid, ERR_BAD_LENGTH);
                                        malformed_count <= malformed_count + 1'b1;
                                        tx_state <= TX_SEND_HDR;
                                    end else if ((req_w1[7:0] == 8'd0) ||
                                                 (req_w0[7:0] >= NUM_REGS) ||
                                                 ((req_w0[7:0] + req_w1[7:0]) > NUM_REGS)) begin
                                        prepare_error_response(req_txid, ERR_BAD_REGISTER);
                                        malformed_count <= malformed_count + 1'b1;
                                        tx_state <= TX_SEND_HDR;
                                    end else begin
                                        prepare_bulk_response(req_txid, req_w0[7:0], req_w1[7:0]);
                                        tx_state <= TX_SEND_HDR;
                                    end
                                end

                                OP_PING: begin
                                    if (req_payload_words != 8'd1) begin
                                        prepare_error_response(req_txid, ERR_BAD_LENGTH);
                                        malformed_count <= malformed_count + 1'b1;
                                    end else begin
                                        prepare_ping_response(req_txid, req_w0);
                                    end
                                    tx_state <= TX_SEND_HDR;
                                end

                                default: begin
                                    prepare_error_response(req_txid, ERR_BAD_OPCODE);
                                    malformed_count <= malformed_count + 1'b1;
                                    tx_state <= TX_SEND_HDR;
                                end
                            endcase
                        end

                        rx_state <= RX_IDLE;
                    end

                    default: rx_state <= RX_IDLE;
                endcase

                // TX serializer
                case (tx_state)
                    TX_IDLE: begin
                        // nothing
                    end

                    TX_SEND_HDR: begin
                        if (!tx_valid_reg) begin
                            tx_load_word({rsp_opcode, rsp_flags, rsp_txid, rsp_payload_words},
                                         4'hF,
                                         (rsp_payload_words == 8'd0));
                            if (rsp_payload_words == 8'd0)
                                tx_state <= TX_IDLE;
                            else
                                tx_state <= TX_SEND_W1;
                        end
                    end

                    TX_SEND_W1: begin
                        if (!tx_valid_reg) begin
                            tx_load_word(rsp_w1,
                                         4'hF,
                                         (rsp_payload_words == 8'd1));
                            if (rsp_payload_words == 8'd1) begin
                                tx_state <= TX_IDLE;
                            end else if (rsp_opcode == OP_BULK_RSP) begin
                                bulk_index <= 8'd0;
                                tx_state <= TX_SEND_BULK;
                            end else begin
                                tx_state <= TX_SEND_W2;
                            end
                        end
                    end

                    TX_SEND_W2: begin
                        if (!tx_valid_reg) begin
                            tx_load_word(rsp_w2, 4'hF, 1'b1);
                            tx_state <= TX_IDLE;
                        end
                    end

                    TX_SEND_BULK: begin
                        if (!tx_valid_reg) begin
                            tx_load_word(regs[bulk_start + bulk_index],
                                         4'hF,
                                         (bulk_index == bulk_count - 1));
                            if (bulk_index == bulk_count - 1)
                                tx_state <= TX_IDLE;
                            else
                                bulk_index <= bulk_index + 1'b1;
                        end
                    end

                    default: tx_state <= TX_IDLE;
                endcase
            end
        end
    end

endmodule
