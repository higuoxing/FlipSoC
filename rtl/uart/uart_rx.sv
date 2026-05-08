`default_nettype none `timescale 1 ns / 1 ps

module uart_rx #(
  parameter [31:0] CLK_FREQ = 50_000_000,
  parameter [31:0] BAUD_RATE = 115_200
) (
  input logic        clk,
  input logic        reset,
  input logic        uart_rxd,
  output logic [7:0] rx_data,
  output logic rx_ready,
  output logic rx_busy,
  output logic rx_err // High if stop bit is invalid
);

  // Synchronizer & glitch filter (majority voting)
  logic [1:0]          rxd_sync;
  logic [2:0]          filter_reg;
  logic                rxd_voted;
  logic                rxd_stable;

  assign rxd_stable = rxd_voted;
  always_ff @ (posedge clk) begin
    if (reset) begin
      rxd_sync <= 2'b11;
      filter_reg <= 3'b111;
      rxd_voted <= 1'b1;
    end else begin
      rxd_sync <= {rxd_sync[0], uart_rxd};
      filter_reg <= {filter_reg[1:0], rxd_sync[1]};

      // 3-sample Majority vote:
      // If at least two bits are '1', the output is '1'.
      rxd_voted <= (filter_reg[0] & filter_reg[1]) |
                   (filter_reg[1] & filter_reg[2]) |
                   (filter_reg[2] & filter_reg[0]);
    end
  end

  // Precise fractional baud generator
  logic [31:0] baud_acc;
  logic        tick_16x;
  logic        sync_reset_tick;

  localparam [31:0] INC = BAUD_RATE * 16;

  always_ff @ (posedge clk) begin
    if (reset || sync_reset_tick) begin
      baud_acc <= 32'd0;
      tick_16x <= 1'b0;
    end else if (baud_acc >= CLK_FREQ) begin
      // Overflow, generate a tick and keep the fractional remainder
      baud_acc <= baud_acc - CLK_FREQ + INC;
      tick_16x <= 1'b1;
    end else begin
      baud_acc <= baud_acc + INC;
      tick_16x <= 1'b0;
    end
  end

  typedef enum logic [1:0] {
    IDLE, START, DATA, STOP
  } state_t;

  state_t state;
  logic [3:0]            s_count; // Counts 0-15 (oversamples)
  logic [2:0]            b_count; // Counts 0-7 (data bits)
  logic [7:0]            shift_reg;

  always @ (posedge clk) begin
    if (reset) begin
      state <= IDLE;
      rx_ready <= 1'b0;
      rx_busy <= 1'b0;
      rx_err <= 1'b0;
      rx_data <= 8'b0;
      s_count <= 4'd0;
      b_count <= 3'd0;
      shift_reg <= 8'b0;
      sync_reset_tick <= 1'b0;
    end else begin
      // Default: don't reset the tick counter
      sync_reset_tick <= 1'b0;

      if (state == IDLE) begin
        rx_ready <= 0;
        if (rxd_stable == 1'b0) begin // Potential start bit
          rx_err <= 1'b0;
          state <= START;
          s_count <= 0;
          sync_reset_tick <= 1'b1; // Force the next tick of tick_16x to align with this edge
          rx_busy <= 1'b1;
        end else begin
          rx_busy <= 1'b0;
        end
      end else begin
        if (!tick_16x) begin
          rx_ready <= 1'b0;
        end else begin
          case (state)
            IDLE: begin
              // IDLE state has already been handled.
            end

            START: begin
              if (s_count == 7) begin // Center of start bit
                if (rxd_stable == 1'b0) begin
                  s_count <= 0;
                  b_count <= 0;
                  state <= DATA;
                end else begin
                  state <= IDLE; // False start (noise)
                end
              end else begin
                s_count <= s_count + 1;
              end
            end // case: START

            DATA: begin
              if (s_count == 15) begin
                s_count <= 0;
                shift_reg[b_count] <= rxd_stable; // Sample in the middle

                if (b_count == 7) begin
                  state <= STOP;
                end else begin
                  b_count <= b_count + 1;
                end
              end else begin
                s_count <= s_count + 1;
              end
            end


            STOP: begin
              if (s_count == 15) begin
                // Check for valid stop bit (should be 1'b1)
                if (rxd_stable == 1'b1) begin
                  rx_data <= shift_reg;
                  rx_ready <= 1'b1;
                  rx_err <= 1'b0;
                end else begin
                  rx_err <= 1'b1; // Framing error
                  rx_ready <= 1'b0;
                end

                state <= IDLE;
                rx_busy <= 1'b0;
              end else begin
                s_count <= s_count + 1;
              end
            end // case: STOP

            default:
              state <= IDLE;
          endcase // case (state)
        end
      end
    end
  end // always @ (posedge clk)

`ifdef FORMAL
  // Helper to ensure we don't check past values on the first clock cycle
  logic f_past_valid;
  initial f_past_valid = 0;
  always_ff @ (posedge clk) f_past_valid <= 1;

  // Ensure the solver starts in a reset state
  always_comb begin
    if (!f_past_valid)
      assume(reset);
  end

  // Check the initial state after the first clock edge (which processed the reset)
  always_ff @ (posedge clk) begin
    if (f_past_valid && $past(reset)) begin
      assert(state == IDLE);
      assert(!rx_ready);
      assert(!rx_busy);
    end
  end

  // FSM Safety Properties
  always_ff @ (posedge clk) begin
    if (f_past_valid && !reset) begin
      // If rx_ready was high, it MUST be low the next cycle (Single-cycle strobe)
      if ($past(rx_ready))
        assert(!rx_ready);

      // rx_busy must be active if we aren't in IDLE
      if (state != IDLE)
        assert(rx_busy);

      // If in IDLE, we shouldn't have data ready unless it just finished
      if (state == IDLE && !$past(state == STOP && tick_16x && s_count == 15))
        assert(!rx_ready);
    end
  end

  // Baud Counter Invariants
  // These help the tool "Induce" that the counter is working correctly
  always_ff @ (posedge clk) begin
    if (state != IDLE) begin
      // The 16x ticks should only happen at predictable intervals
      // Formal will try to "break" the math; these keep it honest
      assert(s_count <= 15);
    end
  end

  // Start Bit Validation
  // Proves that if we detect a "False Start", we return to IDLE
  always_ff @ (posedge clk) begin
    if (f_past_valid && $past(state == START && s_count == 7 && tick_16x)) begin
      if ($past(rxd_voted == 1'b1)) // Line went high (noise/false start)
        assert(state == IDLE);
    end
  end

  // Liveness (Cover)
  // This proves that a successful reception is MATHEMATICALLY POSSIBLE.
  // If the tool says "Unreachable," your FSM logic is disconnected.
  always_ff @ (posedge clk) begin
    cover(rx_ready == 1'b1);
    cover(rx_err == 1'b1); // Can we actually reach an error state?
  end

  // State Constraints
  always_ff @ (posedge clk) begin
    if (f_past_valid) begin
      if (state == DATA) assert(b_count <= 7);
      if (state != IDLE) assert(rx_busy);
    end
  end

  // Logic to capture the bits as the solver manipulates uart_rxd
  always_ff @ (posedge clk) begin
    if (f_past_valid && !reset && !$past(reset)) begin
      if ($past(state == DATA && tick_16x && s_count == 15)) begin
        assert(shift_reg[$past(b_count)] == $past(rxd_stable));
      end
    end
  end

`endif // `ifdef FORMAL

endmodule // uart_rx
