// Exclusive field ownership for the numerical experiment, independent of actor RAM.
// Commands: 0 acquire, 1 advance, 2 release. An accepted command reserves its
// slot until the response transfers. Release transfers ownership with its response.
// Errors (response kind 3): 1 bad command, 2 ownership, 3 epoch mismatch.
// Error responses preserve state. Slots outside SLOTS are never accepted.
// Reset flushes commands/results and invalidates every slot; it is not recovery.
module phi_numerical_bank #(
  parameter integer SLOTS = 4,
  parameter integer LATENCY = 5,
  parameter integer SLOT_BITS = SLOTS > 1 ? $clog2(SLOTS) : 1
)(
  input wire clk, reset,
  input wire cmd_valid, output wire cmd_ready,
  input wire [1:0] cmd_kind,
  input wire [SLOT_BITS-1:0] cmd_slot,
  input wire [31:0] cmd_epoch, cmd_field0, cmd_field1, cmd_anyon,
  input wire [33:0] cmd_sum0, cmd_sum1,
  output wire rsp_valid, input wire rsp_ready,
  output wire [1:0] rsp_kind, rsp_error,
  output wire [SLOT_BITS-1:0] rsp_slot,
  output wire [31:0] rsp_epoch, rsp_field0, rsp_field1
);
reg [31:0] field0[0:SLOTS-1], field1[0:SLOTS-1];
reg [31:0] epoch[0:SLOTS-1], anyon[0:SLOTS-1];
reg [SLOTS-1:0] owned, busy, pending;
reg [1:0] response_kind[0:SLOTS-1], response_error[0:SLOTS-1];
reg [SLOT_BITS-1:0] tags[0:LATENCY-1];
reg locked;
reg [SLOT_BITS-1:0] cursor, held_slot;
reg found;
reg [SLOT_BITS-1:0] selected;
integer rank, candidate;

// Selection can rotate only after acceptance; a blocked response remains stable
// even when another actor finishes. No output-ready path enters the arithmetic.
always @* begin
  found = 0;
  selected = held_slot;
  candidate = 0;
  if (locked) found = 1;
  else for (rank=0; rank<SLOTS; rank=rank+1) begin
    candidate = cursor + rank;
    if (candidate >= SLOTS) candidate = candidate - SLOTS;
    if (!found && pending[candidate]) begin
      found = 1;
      selected = candidate;
    end
  end
end
assign rsp_valid = found && !reset;
assign rsp_slot = selected;
assign rsp_kind = response_kind[selected];
assign rsp_error = response_error[selected];
assign rsp_epoch = epoch[selected];
assign rsp_field0 = field0[selected];
assign rsp_field1 = field1[selected];
assign cmd_ready = !reset && cmd_slot < SLOTS && !busy[cmd_slot] && !pending[cmd_slot];
wire accepted = cmd_valid && cmd_ready;
wire ownership_ok = cmd_kind == 0 ? !owned[cmd_slot] : owned[cmd_slot];
wire epoch_ok = cmd_kind == 0 || cmd_epoch == epoch[cmd_slot];
wire issue = accepted && cmd_kind == 1 && ownership_ok && epoch_ok;
wire result_valid;
wire [63:0] result;
kernel arithmetic(.clk(clk), .reset(reset), .enable(1'b1), .in_valid(issue),
  .field0(field0[cmd_slot]), .field1(field1[cmd_slot]),
  .sum0(cmd_sum0), .sum1(cmd_sum1), .anyon(anyon[cmd_slot]),
  .out(result), .out_valid(result_valid));

// The accepted slot itself is the reserved completion storage. It cannot be
// reused while arithmetic runs or while its publication is blocked.
integer i;
always @(posedge clk) begin
  if (reset) begin
    owned <= 0; busy <= 0; pending <= 0;
    cursor <= 0; held_slot <= 0; locked <= 0;
    for (i=0; i<SLOTS; i=i+1) begin
      field0[i] <= 0; field1[i] <= 0; epoch[i] <= 0; anyon[i] <= 0;
      response_kind[i] <= 0; response_error[i] <= 0;
    end
  end else begin
    tags[0] <= cmd_slot;
    for (i=1; i<LATENCY; i=i+1) tags[i] <= tags[i-1];
    if (rsp_valid) begin
      if (rsp_ready) begin
        pending[selected] <= 0;
        if (response_kind[selected] == 2) owned[selected] <= 0;
        cursor <= selected == SLOTS-1 ? 0 : selected + 1'b1;
        locked <= 0;
      end else begin
        held_slot <= selected;
        locked <= 1;
      end
    end
    if (accepted) begin
      response_error[cmd_slot] <= 0;
      response_kind[cmd_slot] <= cmd_kind;
      if (cmd_kind == 3 || !ownership_ok || !epoch_ok) begin
        response_kind[cmd_slot] <= 3;
        response_error[cmd_slot] <= cmd_kind == 3 ? 1 : !ownership_ok ? 2 : 3;
        pending[cmd_slot] <= 1;
      end else if (cmd_kind == 0) begin
        field0[cmd_slot] <= cmd_field0; field1[cmd_slot] <= cmd_field1;
        epoch[cmd_slot] <= cmd_epoch; anyon[cmd_slot] <= cmd_anyon;
        owned[cmd_slot] <= 1;
        pending[cmd_slot] <= 1;
      end else if (cmd_kind == 2) pending[cmd_slot] <= 1;
      else busy[cmd_slot] <= 1;
    end
    if (result_valid) begin
      field0[tags[LATENCY-1]] <= result[31:0];
      field1[tags[LATENCY-1]] <= result[63:32];
      epoch[tags[LATENCY-1]] <= epoch[tags[LATENCY-1]] + 1'b1;
      busy[tags[LATENCY-1]] <= 0;
      pending[tags[LATENCY-1]] <= 1;
    end
  end
end
endmodule
