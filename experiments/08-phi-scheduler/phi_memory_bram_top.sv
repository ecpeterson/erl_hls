`timescale 1ns/1ps

// ERTS-compatible boundary around one BRAM-backed sequential scheduler.
module phi_memory_bram_top (
    input  wire        aclk,
    input  wire        aresetn,

    input  wire [31:0] s_axis_tdata,
    input  wire [3:0]  s_axis_tkeep,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,

    output wire [31:0] m_axis_tdata,
    output wire [3:0]  m_axis_tkeep,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast
);
    wire [129:0] worker_command;
    wire worker_command_valid;
    wire worker_command_ready;
    wire [103:0] worker_event;
    wire worker_event_valid;
    wire worker_event_ready;

    wire [7:0] actor_state_addr;
    wire [31:0] actor_state_wr_data;
    wire actor_state_we;
    wire actor_state_re;
    reg [31:0] actor_state_rd_data;

    (* ram_style = "block" *) reg [31:0] actor_state [0:255];

    always @(posedge aclk) begin
        if (actor_state_we)
            actor_state[actor_state_addr] <= actor_state_wr_data;
        if (actor_state_re)
            actor_state_rd_data <= actor_state[actor_state_addr];
    end

    phi_memory_scheduler_boundary boundary (
        .clk(aclk),
        .resetn(aresetn),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .worker_command(worker_command),
        .worker_command_valid(worker_command_valid),
        .worker_command_ready(worker_command_ready),
        .worker_event(worker_event),
        .worker_event_valid(worker_event_valid),
        .worker_event_ready(worker_event_ready)
    );

    __phi_sequential_bram_core__SequentialBramCore_0_next worker (
        .clk(aclk),
        .reset(!aresetn),
        ._command_in(worker_command),
        ._command_in_vld(worker_command_valid),
        ._command_in_rdy(worker_command_ready),
        ._event_out(worker_event),
        ._event_out_vld(worker_event_valid),
        ._event_out_rdy(worker_event_ready),
        .actor_state_rd_data(actor_state_rd_data),
        .actor_state_addr(actor_state_addr),
        .actor_state_wr_data(actor_state_wr_data),
        .actor_state_we(actor_state_we),
        .actor_state_re(actor_state_re)
    );

    assign m_axis_tkeep = 4'hf;
    wire _unused_tkeep = &s_axis_tkeep;
endmodule
