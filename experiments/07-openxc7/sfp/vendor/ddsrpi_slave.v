module ddsrpi_slave
  (input  RX_CLK,
   input  RX_DATA,
   output TX_DATA,
   output user_clk,
   output [31:0] gpio_out,
   input  [31:0] gpio_in,
   input  resetn,
   output ready);
  wire [31:0] rx_sr;
  wire [31:0] tx_sr;
  wire [31:0] gpio_out_s;
  wire clk;
  wire sync;
  wire [30:0] n7;
  wire [31:0] n8;
  wire n13;
  wire [30:0] n17;
  wire [31:0] n19;
  wire [31:0] n20;
  localparam n24 = 1'bZ;
  reg [31:0] n25;
  reg [31:0] n26;
  wire [31:0] n27;
  reg [31:0] n28;
  reg n29;
  assign TX_DATA = n13; //(module output)
  assign user_clk = n24; //(module output)
  assign gpio_out = gpio_out_s; //(module output)
  assign ready = sync; //(module output)
  /* experiments/07-openxc7/sfp/vendor/ddsrpi_slave.vhd:47:8  */
  assign rx_sr = n25; // (signal)
  /* experiments/07-openxc7/sfp/vendor/ddsrpi_slave.vhd:48:8  */
  assign tx_sr = n26; // (signal)
  /* experiments/07-openxc7/sfp/vendor/ddsrpi_slave.vhd:49:8  */
  assign gpio_out_s = n28; // (signal)
  /* experiments/07-openxc7/sfp/vendor/ddsrpi_slave.vhd:51:8  */
  assign clk = RX_CLK; // (signal)
  /* experiments/07-openxc7/sfp/vendor/ddsrpi_slave.vhd:52:8  */
  assign sync = n29; // (signal)
  /* experiments/07-openxc7/sfp/vendor/ddsrpi_slave.vhd:63:23  */
  assign n7 = rx_sr[30:0]; // extract
  /* experiments/07-openxc7/sfp/vendor/ddsrpi_slave.vhd:63:37  */
  assign n8 = {n7, RX_DATA};
  /* experiments/07-openxc7/sfp/vendor/ddsrpi_slave.vhd:70:17  */
  assign n13 = tx_sr[31]; // extract
  /* experiments/07-openxc7/sfp/vendor/ddsrpi_slave.vhd:81:27  */
  assign n17 = tx_sr[30:0]; // extract
  /* experiments/07-openxc7/sfp/vendor/ddsrpi_slave.vhd:81:41  */
  assign n19 = {n17, 1'b0};
  /* experiments/07-openxc7/sfp/vendor/ddsrpi_slave.vhd:78:9  */
  assign n20 = sync ? gpio_in : n19;
  /* experiments/07-openxc7/sfp/vendor/ddsrpi_slave.vhd:62:4  */
  always @(posedge clk)
    n25 <= n8;
  /* experiments/07-openxc7/sfp/vendor/ddsrpi_slave.vhd:74:4  */
  always @(negedge clk)
    n26 <= n20;
  /* experiments/07-openxc7/sfp/vendor/ddsrpi_slave.vhd:62:4  */
  assign n27 = sync ? rx_sr : gpio_out_s;
  /* experiments/07-openxc7/sfp/vendor/ddsrpi_slave.vhd:62:4  */
  always @(posedge clk)
    n28 <= n27;
  /* experiments/07-openxc7/sfp/vendor/ddsrpi_slave.vhd:74:4  */
  always @(negedge clk)
    n29 <= RX_DATA;
endmodule

