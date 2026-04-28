module axis_add1 (
	(* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME ACLK, ASSOCIATED_BUSIF S_AXIS:M_AXIS, ASSOCIATED_RESET ARESETN" *)
	(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
	input  wire        aclk,

	(* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME ARESETN, POLARITY ACTIVE_LOW" *)
	(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 ARESETN RST" *)
	input  wire        aresetn,

	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TDATA" *)
	input  wire [31:0] s_axis_tdata,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TVALID" *)
	input  wire        s_axis_tvalid,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TREADY" *)
	output wire        s_axis_tready,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TLAST" *)
	input  wire        s_axis_tlast,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TKEEP" *)
	input  wire  [3:0] s_axis_tkeep,

	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *)
	output wire [31:0] m_axis_tdata,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
	output wire        m_axis_tvalid,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
	input  wire        m_axis_tready,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
	output wire        m_axis_tlast,
	(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TKEEP" *)
	output wire  [3:0] m_axis_tkeep
);

	reg [31:0] data_reg;
	reg        last_reg;
	reg        valid_reg;
	reg  [3:0] keep_reg;

	wire input_fire;
	wire output_fire;

	assign input_fire  = s_axis_tvalid && s_axis_tready;
	assign output_fire = m_axis_tvalid && m_axis_tready;

	assign s_axis_tready = (~valid_reg) || m_axis_tready;

	assign m_axis_tdata  = data_reg;
	assign m_axis_tlast  = last_reg;
	assign m_axis_tvalid = valid_reg;
	assign m_axis_tkeep  = keep_reg;

	always @(posedge aclk) begin
		if (!aresetn) begin
			data_reg  <= 32'd0;
			last_reg  <= 1'b0;
			keep_reg  <= 1'b0;
			valid_reg <= 1'b0;
		end else begin
			if (input_fire) begin
				data_reg  <= s_axis_tdata + 32'd1;
				last_reg  <= s_axis_tlast;
				keep_reg  <= s_axis_tkeep;
				valid_reg <= 1'b1;
			end else if (output_fire) begin
				valid_reg <= 1'b0;
			end
		end
	end

endmodule

