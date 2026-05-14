module tn20k_sdram_ctrl # (
  parameter [31:0] CLK_FREQ = 27_000_000
) (
  // Clock and Reset
  input logic         clk,       // Internal Logic Clock (e.g., 27MHz)
  input logic         iclk,      // 180° shifted clock for SDRAM chip
  input logic         reset,     // Active High reset (or as per your design)

  // User/Internal Logic Interface
  input logic [23:0]  addr,      // {Bank[1:0], Row[12:0], Column[8:0]}
  input logic         wr_en,
  input logic         rd_en,
  input logic [15:0]  din,
  output logic [15:0] dout,
  output logic        busy,

  // Physical SDRAM Interface
  output logic        sdram_clk, // Connects directly to iclk
  output logic        sdram_cke,
  output logic        sdram_cs_n,
  output logic        sdram_ras_n,
  output logic        sdram_cas_n,
  output logic        sdram_we_n,
  output logic [1:0]  sdram_ba,
  output logic [12:0] sdram_addr,
  inout wire [15:0]   sdram_dq,  // Changed to wire for best compatibility
  output logic [1:0]  sdram_dqm
);

  // Timing constants
  // 200us initialization delay.
  localparam WAIT_200us = (CLK_FREQ / 1_000_000) * 200;
  // Refresh interval: 64ms / 4096rows = 15.6us (we'll use 15us for safety).
  localparam REF_INTERVAL = (CLK_FREQ / 1_000_000) * 15;
  localparam CLK_NS = 1_000_000_000 / CLK_FREQ;
  localparam TRCD_CYCLES = (20 + CLK_NS - 1) / CLK_NS; // 20ns TRCD delay

  typedef enum logic [3:0] {
    INIT_WAIT, INIT_PRE, INIT_REF, INIT_LMR,
    IDLE, ACTIVATE, WRITE, READ, PRECHARGE, REFRESH
  } state_t;

  state_t state;
  logic [31:0] timer;
  logic [3:0]  ref_count;
  logic [15:0] refresh_timer;
  logic        refresh_req;

  // SDRAM commands
  localparam   CMD_LMR = 4'b0000;
  localparam   CMD_REFRESH = 4'b0001;
  localparam   CMD_PRECHARGE = 4'b0010;
  localparam   CMD_ACTIVATE = 4'b0011;
  localparam   CMD_WRITE = 4'b0100;
  localparam   CMD_READ = 4'b0101;
  localparam   CMD_NOP = 4'b0111;

  assign sdram_clk = iclk;
  assign sdram_cke = 1'b1;
  assign sdram_dqm = 2'b00;
  assign sdram_dq = (state == WRITE) ? din : 16'hzzzz;

  // Refresh request logic
  always_ff @ (posedge clk) begin
    if (reset) begin
      refresh_timer <= 0;
      refresh_req <= 0;
    end else begin
      if (refresh_timer >= REF_INTERVAL) begin
        refresh_timer <= 0;
        refresh_req <= 1;
      end else begin
        refresh_timer <= refresh_timer + 1;
      end
      if (state == REFRESH) refresh_req <= 0;
    end
  end // always_ff @ (posedge clk)

  // Main FSM
  always_ff @ (posedge clk) begin
    if (reset) begin
      state <= INIT_WAIT;
      timer <= 0;
      busy <= 1;
      ref_count <= 0;
      {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} <= CMD_NOP;
    end else begin
      case (state)
        // Initialization: Power-up wait
        INIT_WAIT: begin
          if (timer >= WAIT_200us) begin
            state <= INIT_PRE;
            timer <= 0;
          end else timer <= timer + 1;
        end

        // Initialization: Precharge all
        INIT_PRE: begin
          {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} <= CMD_PRECHARGE;
          sdram_addr[10] <= 1'b1; // All banks
          state <= INIT_REF;
          ref_count <= 0;
        end

        // Initialization: 8 refresh cycles
        INIT_REF: begin
          {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} <= CMD_REFRESH;
          if (ref_count >= 8) begin
            state <= INIT_LMR;
          end else begin
            ref_count <= ref_count + 1;
            state <= INIT_REF;
          end
        end

        // Initialization: Load mode register
        // Config: Burst=1, Seq, CAS Latency=2 (010)
        INIT_LMR: begin
          {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} <= CMD_LMR;
          sdram_ba <= 2'b00;
          sdram_addr <= 13'b000_0_00_010_0_000;
          state <= IDLE;
          busy <= 0;
        end

        IDLE: begin
          {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} <= CMD_NOP;
          busy <= 0;
          if (refresh_req) begin
            state <= REFRESH;
            busy <= 1;
          end else if (wr_en || rd_en) begin
            state <= ACTIVATE;
            busy <= 1;
          end
        end // case: IDLE

        ACTIVATE: begin
          {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} <= CMD_ACTIVATE;
          sdram_ba <= addr[23:22];
          sdram_addr <= addr[21:9];

          // At high speeds, stay here for TRCD_CYCLES before moving
          if (timer >= TRCD_CYCLES - 1) begin
            timer <= 0;
            state <= (wr_en) ? WRITE : READ;
          end else begin
            timer <= timer + 1;
            {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} <= CMD_NOP;
          end
        end

        WRITE: begin
          {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} <= CMD_WRITE;
          sdram_ba <= addr[23:22];
          sdram_addr <= {4'b0100, addr[8:0]}; // A10=1 for Auto-precharge.
          state <= IDLE;
        end

        READ: begin
          {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} <= CMD_READ;
          sdram_ba <= addr[23:22];
          sdram_addr <= {4'b0100, addr[8:0]}; // A10=1 for Auto-precharge.
          state <= IDLE;
        end

        REFRESH: begin
          {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} <= CMD_REFRESH;
          state <= IDLE;
        end

        default: state <= IDLE;
      endcase // case (state)
    end
  end // always_ff @ (posedge clk)

  // Data capture (CAS latency = 2)
  logic [1:0] read_pipe;
  always_ff @ (posedge clk) begin
    if (reset) begin
      read_pipe <= 2'b00;
      dout <= 16'h0000;
    end else begin
      read_pipe <= {read_pipe[0], (state == READ)};

      if (read_pipe[1])
        dout <= sdram_dq;
    end
  end
endmodule
