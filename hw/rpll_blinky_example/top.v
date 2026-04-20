`default_nettype none
`timescale 1 ns / 1 ps

module top (
  input wire        clk,   // Pin 4: 27 MHz Crystal
  input wire        reset, // Pin 88: S1 Button
  output wire [5:0] led    // Pins 15-20: 6 On-board LEDs
);

  // --- Clock Generation ---
  wire clk_sys;
  wire pll_lock;

  rpll #(
    .IDIV_SEL(1),
    .FBDIV_SEL(14),
    .ODIV_SEL(4)
  ) my_pll (
    .clk_in(clk),
    .reset(reset),
    .clk_out(clk_sys),
    .clk_out_p(),
    .lock(pll_lock)
  );

  // Global reset: Reset if button is pressed OR PLL is still warming up
  wire sys_reset = reset || !pll_lock;

  reg [26:0] counter;
  reg        led_state;

  always @(posedge clk_sys) begin
    if (sys_reset) begin
      counter   <= 26'd0;
      led_state <= 1'b0;
    end else begin
      // 101,250,000 cycles = exactly 1 second
      if (counter >= 27'd101_250_000 - 1) begin
        counter   <= 27'd0;
        led_state <= ~led_state;
      end else begin
        counter <= counter + 1;
      end
    end
  end

  // LED Output Logic:
  // led[0:4] show the blinky state.
  // led[5]   shows if the PLL is locked (ON if locked).
  // Note: LEDs are active-low (0 = ON).
  assign led[4:0] = {5{~led_state}};
  assign led[5]   = !pll_lock;

endmodule // top
