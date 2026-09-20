// AXI3 diagnostic registers, one outstanding transaction per direction and no
// write-data interleaving. Aligned 32-bit single-beat accesses are supported;
// other address/size/burst/lock combinations complete with SLVERR and no writes.
// Unsupported read bursts return LEN+1 errors; write bursts drain LEN+1 beats.
// Sources must honor AXI's VALID stability rules, WID and WLAST. Reset aborts
// pending work and clears scratch/counters; quiesce the master before resetting.
module zynq_ps_probe #(
    parameter [31:0] BASE_ADDR = 32'h40000000
)(
    input wire clock, input wire reset_n,
    input wire [11:0] awid, input wire [31:0] awaddr,
    input wire [3:0] awlen, input wire [2:0] awsize,
    input wire [1:0] awburst, input wire [1:0] awlock,
    input wire awvalid, output wire awready,
    input wire [11:0] wid, input wire [31:0] wdata,
    input wire [3:0] wstrb, input wire wlast, input wire wvalid, output wire wready,
    output reg [11:0] bid, output reg [1:0] bresp,
    output reg bvalid, input wire bready,
    input wire [11:0] arid, input wire [31:0] araddr,
    input wire [3:0] arlen, input wire [2:0] arsize,
    input wire [1:0] arburst, input wire [1:0] arlock,
    input wire arvalid, output wire arready,
    output reg [11:0] rid, output reg [31:0] rdata,
    output reg [1:0] rresp, output wire rlast,
    output reg rvalid, input wire rready
);
    localparam [1:0] OKAY = 2'b00, SLVERR = 2'b10;
    reg [31:0] scratch, cycles, writes;
    reg write_active, write_error;
    reg [3:0] write_left, read_left;
    wire write_bad = write_error || wid != bid || wlast != (write_left == 0);
    wire read_ok = arlen == 0 && arsize == 2 && arlock == 0 &&
                   (arburst == 0 || arburst == 1);
    integer byte_index;

    // Write data may be presented before its address; hold it until AW is accepted.
    assign awready = reset_n && !write_active && !bvalid;
    assign wready = reset_n && write_active;
    assign arready = reset_n && !rvalid;
    assign rlast = read_left == 0;

    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            scratch <= 0; cycles <= 0; writes <= 0;
            write_active <= 0; write_error <= 0; write_left <= 0;
            bid <= 0; bresp <= OKAY; bvalid <= 0;
            rid <= 0; rdata <= 0; rresp <= OKAY; rvalid <= 0; read_left <= 0;
        end else begin
            cycles <= cycles + 1'b1;
            if (bvalid && bready) bvalid <= 0;
            if (awvalid && awready) begin
                bid <= awid;
                write_active <= 1;
                write_left <= awlen;
                write_error <= awaddr != BASE_ADDR + 8 || awlen != 0 ||
                               awsize != 2 || awlock != 0 ||
                               (awburst != 0 && awburst != 1);
            end
            if (wvalid && wready) begin
                write_error <= write_bad;
                if (write_left == 0) begin
                    write_active <= 0;
                    bvalid <= 1;
                    bresp <= write_bad ? SLVERR : OKAY;
                    if (!write_bad) begin
                        for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                            if (wstrb[byte_index])
                                scratch[8*byte_index +: 8] <= wdata[8*byte_index +: 8];
                        writes <= writes + 1'b1;
                    end
                end else write_left <= write_left - 1'b1;
            end

            // Snapshot reads at AR acceptance, including when a write commits on
            // the same edge (the read sees the preceding value). Hold under stalls.
            if (arvalid && arready) begin
                rid <= arid;
                read_left <= arlen;
                rvalid <= 1;
                rresp <= read_ok ? OKAY : SLVERR;
                rdata <= 0;
                if (read_ok) begin
                    case (araddr)
                        BASE_ADDR:      rdata <= 32'h45524c48; // "ERLH"
                        BASE_ADDR + 4:  rdata <= 1;            // register ABI
                        BASE_ADDR + 8:  rdata <= scratch;
                        BASE_ADDR + 12: rdata <= cycles;
                        BASE_ADDR + 16: rdata <= writes;
                        default: rresp <= SLVERR;
                    endcase
                end
            end else if (rvalid && rready) begin
                if (read_left == 0) rvalid <= 0;
                else read_left <= read_left - 1'b1;
            end
        end
    end
endmodule

// Assert reset asynchronously, but release it after two destination-clock edges.
// Initial zeroes hold an unclocked/newly configured probe in reset.
module zynq_probe_reset(input wire clock, input wire reset_n_async, output wire reset_n);
    (* ASYNC_REG = "TRUE" *) reg [1:0] release_sync = 0;
    always @(posedge clock or negedge reset_n_async)
        if (!reset_n_async) release_sync <= 0;
        else release_sync <= {release_sync[0], 1'b1};
    assign reset_n = release_sync[1];
endmodule
