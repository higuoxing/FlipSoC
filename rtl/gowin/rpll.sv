// Ref: https://cdn.gowinsemi.com.cn/UG286E.pdf
// This wrapper instantiates the rPLL hard primitive.
// Default values target Tangnano20k board.

module rpll #(
  parameter FCLKIN = "27",            // Reference clock frequency in MHz, "3"~"500"

  parameter IDIV_SEL = 0,             // IDIV frequency division coefficient static setting, 0~63

  parameter DYN_IDIV_SEL = "false",   // IDIV frequency division coefficient static control parameter
                                      // or dynamic control signal selection
                                      // - "false": Static, that is, select the parameter IDIV_SEL
                                      // - "true": Dynamic, namely select signal IDSEL

  parameter FBDIV_SEL = 0,            // FBDIV frequency division coefficient static setting, 0~63

  parameter DYN_FBDIV_SEL = "false",  // FBDIV frequency division coefficient static control
                                      // parameter or dynamic control signal selection
                                      // - "false": Static, that is, select the parameter FBDIV_SEL
                                      // - "true": Dynamic, namely select signal FBDSEL

  parameter ODIV_SEL = 8,             // ODIV frequency division coefficient static setting,
                                      // 2, 4, 8, 16, ..., 128

  parameter DYN_ODIV_SEL = "false",   // ODIV frequency division coefficient static control parameter
                                      // or dynamic control signal selection
                                      // - "false": Static, that is, select the parameter ODIV_SEL
                                      // - "true": Dynamic, namely select signal ODSEL

  parameter PSDA_SEL = "0000",        // Phase static adjustment (controls the position of the rising
                                      // edge of the output clock), "0000"~"1111"

  parameter DUTYDA_SEL = "1000",      // Duty cycle static adjustment (controls the position of the
                                      // falling edge of the output clock), "0010"~"1110"

  parameter DYN_DA_EN = "false",      // The dynamic signal is selected as the control of phase and
                                      // duty cycle adjustment
                                      // - "false": Static control
                                      // - "true": Dynamic control

  parameter CLKOUT_FT_DIR = 1,        // CLKOUT trim direction setting, 1'b1: Decrease

  parameter CLKOUT_DLY_STEP = 0,      // CLKOUT trim coefficient setting, 0, 1, 2, 4
                                      // CLKOUT_DLY_STEP * delay (delay=50ps)

  parameter CLKOUTP_FT_DIR = 1,       // CLKOUTP trim direction setting, 1'b1: Decrease

  parameter CLKOUTP_DLY_STEP = 0,     // CLKOUTP trim coefficient setting, 0, 1, 2
                                      // CLKOUTP_DLY_STEP * delay (delay=50ps)

  parameter DYN_SDIV_SEL = 2,         // SDIV frequency division coefficient static setting,
                                      // 2~128 (even)

  parameter CLKFB_SEL = "internal",   // CLKFB source selection
                                      // - "internal": Feedback from internal CLKOUT
                                      // - "external": Feedback from external signal

  parameter CLKOUTD_SRC = "CLKOUT",   // CLKOUTD source selection,
                                      // "CLKOUT", "CLKOUTP"

  parameter CLKOUTD3_SRC = "CLKOUT",  // CLKOUTD3 source selection,
                                      // "CLKOUT", "CLKOUTP"

  parameter CLKOUT_BYPASS = "false",  // Bypasses rPLL, and CLKOUT comes directly from CLKIN
                                      // - "true": CLKIN bypasses rPLL and acts directly on CLKOUT
                                      // - "false": Normal

  parameter CLKOUTP_BYPASS = "false", // Bypasses rPLL, and CLKOUTP comes directly from CLKIN
                                      // - "true": CLKIN bypasses rPLL and acts directly on CLKOUTP
                                      // - "false": Normal

  parameter CLKOUTD_BYPASS = "false", // Bypasses rPLL, and CLKOUTD comes directly from CLKIN
                                      // - "true": CLKIN bypasses rPLL and acts directly on CLKOUTD
                                      // - "false": Normal

  parameter DEVICE = "GW2AR-18C"      // Devices selected
) (
  input wire       clkin,   // Reference clock input
  input wire       clkfb,   // Feedback clock input
  input wire       reset,   // PLL main reset (Active High)
  input wire       reset_p, // PLL power down (Active High)
  input wire [5:0] fbdsel,  // Dynamic FBDIV control (Used if DYN_FBDIV_SEL="true")
  input wire [5:0] idsel,   // Dynamic IDIV control (Used if DYN_IDIV_SEL="true")
  input wire [5:0] odsel,   // Dynamic ODIV control (Used if DYN_ODIV_SEL="true")
  input wire [3:0] dutyda,  // Dynamic Duty Cycle control
  input wire [3:0] psda,    // Dynamic Phase Shift control
  input wire [3:0] fdly,    // Fine Delay control
  output wire clkout,  // Main output
  output wire lock,    // PLL Lock indicator
  output wire clkoutp, // Phase-shifted output
  output wire clkoutd, // Divided output
  output wire clkoutd3 // Divide-by-3 output
);

  rPLL #(
    .FCLKIN(FCLKIN),
    .IDIV_SEL(IDIV_SEL),
    .DYN_IDIV_SEL(DYN_IDIV_SEL),
    .FBDIV_SEL(FBDIV_SEL),
    .DYN_FBDIV_SEL(DYN_FBDIV_SEL),
    .ODIV_SEL(ODIV_SEL),
    .DYN_ODIV_SEL(DYN_ODIV_SEL),
    .PSDA_SEL(PSDA_SEL),
    .DUTYDA_SEL(DUTYDA_SEL),
    .DYN_DA_EN(DYN_DA_EN),
    .CLKOUT_FT_DIR(CLKOUT_FT_DIR),
    .CLKOUT_DLY_STEP(CLKOUT_DLY_STEP),
    .CLKOUTP_FT_DIR(CLKOUTP_FT_DIR),
    .CLKOUTP_DLY_STEP(CLKOUTP_DLY_STEP),
    .DYN_SDIV_SEL(DYN_SDIV_SEL),
    .CLKFB_SEL(CLKFB_SEL),
    .CLKOUTD_SRC(CLKOUTD_SRC),
    .CLKOUTD3_SRC(CLKOUTD3_SRC),
    .CLKOUT_BYPASS(CLKOUT_BYPASS),
    .CLKOUTP_BYPASS(CLKOUTP_BYPASS),
    .CLKOUTD_BYPASS(CLKOUTD_BYPASS),
    .DEVICE(DEVICE)
  ) rpll_inst (
    .CLKIN(clkin),
    .CLKFB(clkfb),
    .RESET(reset),
    .RESET_P(reset_p),
    .FBDSEL(fbdsel),
    .IDSEL(idsel),
    .ODSEL(odsel),
    .DUTYDA(dutyda),
    .PSDA(psda),
    .FDLY(fdly),
    .CLKOUT(clkout),
    .LOCK(lock),
    .CLKOUTP(clkoutp),
    .CLKOUTD(clkoutd),
    .CLKOUTD3(clkoutd3)
  );

endmodule // rpll
