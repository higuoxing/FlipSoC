`default_nettype none
`timescale 1 ns / 1 ps

// clk is the 27 MHz board crystal on pin 4 (see boards/tangnano20k/constraints.cst).
// Top names must match .cst: clk, reset, uart_txd
// Submodule uart_tx latches tx_data when tx_start is high in IDLE — load in LOAD, pulse in START.
module top (
   input logic  clk,
   input logic  s1,
   output logic uart_txd
);

  logic reset;

  assign reset = s1;

  localparam integer ClkFreq = 27_000_000;
  localparam integer BaudRate = 115_200;

  localparam integer BytesCount = 8;
  localparam [BytesCount*8-1:0] Msg = {
    8'h46,
    8'h6c,
    8'h69,
    8'h70,
    8'h52,
    8'h56,
    8'h0d,
    8'h0a
  };

  typedef enum logic [1:0] {
    INIT = 2'b00,
    LOAD = 2'b01,
    START = 2'b10,
    WAIT = 2'b11
  } state_t;

  state_t                         state;
  logic [3:0]                         byte_index;
  logic [7:0]                         tx_data;
  logic                               tx_start;
  logic [31:0]                        gap_counter;
  logic                               tx_busy;
  logic                               tx_done;

  uart_tx #(
    .CLK_FREQ (ClkFreq),
    .BAUD_RATE(BaudRate)
  ) u_tx (
    .clk     (clk),
    .reset   (reset),
    .tx_data (tx_data),
    .tx_start(tx_start),
    .tx_busy (tx_busy),
    .tx_done (tx_done),
    .uart_txd(uart_txd)
  );

  localparam integer GapClocks = ClkFreq / 2;

  logic              sending_line;

  always_ff @(posedge clk) begin
    if (reset) begin
      state        <= INIT;
      byte_index   <= 4'd0;
      tx_data      <= 8'b0;
      tx_start     <= 1'b0;
      gap_counter  <= 32'd0;
      sending_line <= 1'b1;
    end else begin
      tx_start <= 1'b0;

      if (sending_line) begin
        case (state)
          INIT: begin
            if (!tx_busy) begin
              state <= LOAD;
            end
          end

          LOAD: begin
            tx_data <= Msg[(BytesCount - 1 - byte_index)*8 +: 8];
            state   <= START;
          end

          START: begin
            tx_start <= 1'b1;
            state    <= WAIT;
          end

          WAIT: begin
            if (tx_done) begin
              if (byte_index == BytesCount - 1) begin
                sending_line <= 1'b0;
                gap_counter  <= 32'd0;
                state        <= INIT;
              end else begin
                byte_index <= byte_index + 4'd1;
                state      <= INIT;
              end
            end
          end

          default: state <= INIT;
        endcase
      end else begin
        if (gap_counter < GapClocks) begin
          gap_counter <= gap_counter + 32'd1;
        end else begin
          byte_index   <= 4'd0;
          sending_line <= 1'b1;
          state        <= INIT;
        end
      end
    end
  end

endmodule
