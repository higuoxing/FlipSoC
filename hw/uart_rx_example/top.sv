`default_nettype none
`timescale 1 ns / 1 ps

module top (
   input logic  clk,   // 27 MHz
   input logic  s1, // Active high reset
   input logic  uart_rxd,
   output logic uart_txd
);

  localparam [31:0] CLK_FREQ  = 27_000_000;
  localparam [31:0] BAUD_RATE = 115_200;
  localparam [31:0] BUF_SIZE  = 256;

  logic             reset;

  assign reset = s1;

  // UART Interconnects
  logic [7:0]         rx_data;
  logic               rx_ready, rx_busy, rx_err;
  logic [7:0]          tx_data;
  logic                tx_start;
  logic               tx_busy, tx_done;

  // Buffer and Pointers
  logic [7:0]          buffer [0: BUF_SIZE-1];
  logic [7:0]          wr_ptr;   // Index for receiving bytes
  logic [7:0]          rd_ptr;   // Index for transmitting bytes
  logic [7:0]          line_len; // Stores length of line to echo

  // FSM States
  typedef enum logic [1:0]  {
    StateRx = 2'b00,
    StateTxInit = 2'b01,
    StateTxWait = 2'b10
  } state_t;
  state_t            state;

  always_ff @(posedge clk) begin
    if (reset) begin
      state    <= StateRx;
      wr_ptr   <= 0;
      rd_ptr   <= 0;
      line_len <= 0;
      tx_start <= 1'b0;
    end else begin
      case (state)
        // --- Phase 1: Fill the buffer ---
        StateRx: begin
          tx_start <= 1'b0;
          if (rx_ready) begin
            // Store character in buffer
            buffer[wr_ptr] <= rx_data;

            // Check for line ending (\r or \n) or buffer full
            if (rx_data == 8'h0a || rx_data == 8'h0d || wr_ptr == BUF_SIZE - 1) begin
              // Count '\r\n' in
              buffer[wr_ptr+1] <= 8'h0a;
              buffer[wr_ptr+2] <= 8'h0d;
              line_len <= wr_ptr + 2;
              rd_ptr   <= 0;
              state    <= StateTxInit;
            end else begin
              wr_ptr <= wr_ptr + 1;
            end
          end
        end

        // --- Phase 2: Start Transmission of one byte ---
        StateTxInit: begin
          if (!tx_busy) begin
            tx_data  <= buffer[rd_ptr];
            tx_start <= 1'b1;
            state    <= StateTxWait;
          end
        end

        // --- Phase 3: Wait for byte to clear, then loop ---
        StateTxWait: begin
          tx_start <= 1'b0;
          if (tx_done) begin
            if (rd_ptr == line_len) begin
              wr_ptr <= 0; // Reset write pointer for next line
              state  <= StateRx;
            end else begin
              rd_ptr <= rd_ptr + 1;
              state  <= StateTxInit;
            end
          end
        end

        default: state <= StateRx;
      endcase
    end
  end

  uart_rx #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
  ) u_rx (
    .clk(clk), .reset(reset), .uart_rxd(uart_rxd),
    .rx_data(rx_data), .rx_ready(rx_ready), .rx_busy(rx_busy), .rx_err(rx_err)
  );

  uart_tx #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
  ) u_tx (
    .clk(clk), .reset(reset), .tx_data(tx_data),
    .tx_start(tx_start), .tx_busy(tx_busy), .tx_done(tx_done), .uart_txd(uart_txd)
  );

endmodule
