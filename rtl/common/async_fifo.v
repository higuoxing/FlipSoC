`default_nettype none `timescale 1 ns / 1 ps

module async_fifo #(
  parameter DATA_WIDTH = 8,
  parameter ADDR_WIDTH = 4
) (
  // Write domain
  input wire                   w_clk,
  input wire                   w_reset,
  input wire                   w_en,
  input wire [DATA_WIDTH-1: 0] w_data,
  output wire                  w_full,

  // Read domain
  input wire                   r_clk,
  input wire                   r_reset,
  input wire                   r_en,
  output wire [DATA_WIDTH-1:0] r_data,
  output wire r_empty
);

  localparam integer DEPTH = 1 << ADDR_WIDTH;

  reg [DATA_WIDTH-1:0] mem[DEPTH];

  // Pointers use ADDR_WIDTH + 1 bits to handle Full/Empty
  reg [ADDR_WIDTH:0]   w_ptr_bin, r_ptr_bin;
  wire [ADDR_WIDTH:0]  w_ptr_gray, r_ptr_gray;
  assign w_ptr_gray = w_ptr_bin ^ (w_ptr_bin >> 1);
  assign r_ptr_gray = r_ptr_bin ^ (r_ptr_bin >> 1);

  // Write domain
  always @ (posedge w_clk) begin
    if (w_reset) begin
      w_ptr_bin <= 0;
    end else if (w_en && !w_full) begin
      mem[w_ptr_bin[ADDR_WIDTH-1:0]] <= w_data;
      w_ptr_bin <= w_ptr_bin + 1'b1;
    end
  end

  // Read domain
  always @ (posedge r_clk) begin
    if (r_reset) begin
      r_ptr_bin <= 0;
    end else if (r_en && !r_empty) begin
      r_ptr_bin <= r_ptr_bin + 1'b1;
    end
  end

  assign r_data = mem[r_ptr_bin[ADDR_WIDTH-1:0]];

  reg [ADDR_WIDTH:0] w_ptr_gray_sync1, w_ptr_gray_sync2;
  reg [ADDR_WIDTH:0] r_ptr_gray_sync1, r_ptr_gray_sync2;

  // Cross write pointer into read domain
  always @ (posedge r_clk) begin
    if (r_reset) begin
      w_ptr_gray_sync1 <= 0;
      w_ptr_gray_sync2 <= 0;
    end else begin
      w_ptr_gray_sync1 <= w_ptr_gray;
      w_ptr_gray_sync2 <= w_ptr_gray_sync1;
    end
  end

  // Cross read pointer into write domain
  always @ (posedge w_clk) begin
    if (w_reset) begin
      r_ptr_gray_sync1 <= 0;
      r_ptr_gray_sync2 <= 0;
    end else begin
      r_ptr_gray_sync1 <= r_ptr_gray;
      r_ptr_gray_sync2 <= r_ptr_gray_sync1;
    end
  end

  // Empty: Read pointer catches up to synchronized write pointer
  assign r_empty = (r_ptr_gray == w_ptr_gray_sync2);

  // Full: MSB and 2nd MSB are inverted, rest is same
  // Standard gray code check for a 2^N buffer
  assign w_full = (w_ptr_gray ==
    {~r_ptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1], r_ptr_gray_sync2[ADDR_WIDTH-2:0]});

`ifdef FORMAL

  (* gclk *) reg f_clk;

  always @ (posedge f_clk)
    assume(w_clk == !$past(w_clk));

  always @ (posedge f_clk)
    assume(r_clk == !$past(r_clk, 2));

  // Initial with valid state
  // {{
  reg f_w_past_valid, f_r_past_valid;
  initial begin
    assume(w_reset);
    assume(r_reset);
    assume(!f_w_past_valid);
    assume(!f_r_past_valid);
  end

  always @ (posedge w_clk) f_w_past_valid <= 1'b1;
  always @ (posedge r_clk) f_r_past_valid <= 1'b1;

  always @ (posedge w_clk) if (f_w_past_valid) w_reset <= 1'b0; else w_reset <= 1'b1;
  always @ (posedge r_clk) if (f_r_past_valid) r_reset <= 1'b0; else r_reset <= 1'b1;
  // }}

  // Check gray codes
  // {{
  always @ (*) if (!w_reset) assert(w_ptr_gray == bin2gray(w_ptr_bin));
  always @ (*) if (!r_reset) assert(r_ptr_gray == bin2gray(r_ptr_bin));
  // Always change 1 bit
  always @ (posedge w_clk) begin
    if (!w_reset && !$past(w_reset))
      assert($countones(w_ptr_gray ^ $past(w_ptr_gray)) <= 1);
  end
  always @ (posedge r_clk) begin
    if (!r_reset && !$past(r_reset))
      assert($countones(r_ptr_gray ^ $past(r_ptr_gray)) <= 1);
  end
  // }}

  // Domain safety
  // {{
  always @ (posedge w_clk) begin
    if (f_w_past_valid && !w_reset && $past(w_full && w_en))
      assert($stable(w_ptr_bin));
  end
  always @ (posedge r_clk) begin
    if (f_w_past_valid && !r_reset && $past(r_empty && r_en))
      assert($stable(r_ptr_bin));
  end
  // }}

  // Cover checks
  // {{
  always @ (posedge w_clk) begin
    if (f_w_past_valid && !w_reset) begin
      // Check we actually fill the FIFO.
      cover(w_full);

      // Write while the FIFO is partially full
      cover(w_en && !w_full && !r_empty);
    end
  end

  always @ (posedge r_clk) begin
    if (f_r_past_valid && !r_reset) begin
      if (f_r_past_valid && !r_reset) begin
        cover(r_empty);
        cover(r_en && !w_full && !r_empty);
      end
    end
  end
  // }}

  function [ADDR_WIDTH:0] bin2gray(input [ADDR_WIDTH:0] bin);
    bin2gray = (bin >> 1) ^ bin;
  endfunction // bin2gray
`endif

endmodule // async_fifo
