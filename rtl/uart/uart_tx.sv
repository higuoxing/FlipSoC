`default_nettype none `timescale 1 ns / 1 ps

module uart_tx #(
  parameter [31:0] CLK_FREQ = 50_000_000,
  parameter [31:0] BAUD_RATE = 115_200
) (
  input logic       clk,
  input logic       reset,
  input logic [7:0] tx_data,  // Byte to be transmitted
  input logic       tx_start, // Trigger signal to start transmission
  output logic      tx_busy,  // High when UART is currently sending data
  output logic      tx_done,  // High for one clock cycle when finished
  output logic      uart_txd  // The actual serial output pin
);

  localparam [31:0] ClocksPerBit = CLK_FREQ / BAUD_RATE;

  typedef enum logic [1:0] {
    IDLE, START, DATA, STOP
  } state_t;

  state_t            state;
  logic [31:0]           clk_count;
  logic [2:0]            bit_index;
  logic [7:0]            data_latch;

  always_ff @ (posedge clk) begin
    if (reset) begin
      state <= IDLE;
      uart_txd <= 1'b1; // Idle state is high
      tx_busy <= 1'b0;
      tx_done <= 1'b0;
    end else begin
      case (state)
        IDLE: begin
          uart_txd <= 1'b1;
          tx_done <= 1'b0;
          clk_count <= 32'd0;
          bit_index <= 3'd0;

          if (tx_start) begin
            data_latch <= tx_data;
            tx_busy    <= 1'b1;
            uart_txd   <= 1'b0;   // Start bit
            state      <= START;
          end else begin
            tx_busy    <= 1'b0;
          end
        end

        START: begin
          if (clk_count < ClocksPerBit - 1) begin
            clk_count <= clk_count + 1;
          end else begin
            clk_count <= 0;
            state     <= DATA;
            uart_txd  <= data_latch[0]; // Load first bit
            bit_index <= 0;
          end
        end

        DATA: begin
          if (clk_count < ClocksPerBit - 1) begin
            clk_count <= clk_count + 1;
          end else begin
            clk_count <= 0;
            if (bit_index < 7) begin
              bit_index <= bit_index + 1;
              // Use the INCREMENTED index to load the next bit
              uart_txd  <= data_latch[bit_index + 1];
            end else begin
              state     <= STOP;
              uart_txd  <= 1'b1; // Stop bit
            end
          end
        end
        STOP: begin
          uart_txd <= 1'b1; // Stop bit (high)
          if (clk_count < ClocksPerBit - 2) begin
            clk_count <= clk_count + 1;
          end else begin
            tx_done <= 1'b1;
            tx_busy <= 1'b0;
            state <= IDLE;
          end
        end

        default: state <= IDLE;
      endcase // case (state)
    end
  end // always_ff @ (posedge clk)

`ifdef FORMAL
  // Reset handling
  logic f_past_valid;
  initial begin
    assume(!f_past_valid);
    assume(reset);
  end

  always_ff @ (posedge clk) f_past_valid <= 1'b1;

  always_ff @ (posedge clk) begin
    if (!f_past_valid) assume(reset);
  end

  // Busy signal must be high if not in IDLE
  always_ff @ (posedge clk) begin
    if (!reset && f_past_valid) begin
      if (state != IDLE) begin
        assert(tx_busy == 1'b1);
      end else if (!tx_done) begin
        // Ensures no ghosting. tx_busy doesn't stay "stuck" high when no data
        // is being sent.
        assert(tx_busy == 1'b0);
      end
    end
  end

  // Check the start bit
  always_ff @(posedge clk) begin
    if (f_past_valid) begin
      // If we just entered the START state, the line MUST be 0
      if (state == START) begin
        assert(uart_txd == 1'b0);
      end
    end
  end

  // Capture data bits
  logic [7:0] f_expected_data;
  always_ff @ (posedge clk) begin
    if (reset) begin
      f_expected_data <= 8'h00;
    end else if (state == IDLE && tx_start) begin
      f_expected_data <= tx_data;
    end
  end

  always_ff @ (posedge clk) begin
    if (!reset && f_past_valid && state != IDLE) begin
      // This "links" your formal tracker to your actual hardware latch
      // so the induction engine can't imagine them being different.
      assert(data_latch == f_expected_data);
      // Also, help the solver understand the counter limits
      assert(clk_count < ClocksPerBit);
      assert(bit_index <= 7);
    end
  end

  // Verify the data bits
  always_ff @ (posedge clk) begin
    // Only check data if we are in the DATA state AND not in reset
    if (!reset && f_past_valid && state == DATA) begin
      if (clk_count == ClocksPerBit - 1) begin
        assert(uart_txd == f_expected_data[bit_index]);
      end
    end
  end

  // Ensure uart_txd doesn't flicker during a bit transmission
  always_ff @(posedge clk) begin
    if (!reset && f_past_valid && state != IDLE) begin
      if (clk_count > 0) begin
        assert(uart_txd == $past(uart_txd));
      end
    end
  end

  // tx_done should only be high for one cycle
  always_ff @(posedge clk) begin
    if (f_past_valid && $past(tx_done)) begin
      assert(!tx_done);
    end
  end
`endif

endmodule // uart_tx
