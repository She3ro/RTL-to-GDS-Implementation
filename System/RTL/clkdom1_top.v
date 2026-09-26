// =====================================================================
// Module      : clkdom1_top
// Description : Clock Domain 1 (REF_CLK) top module. Instantiates and
//               wires together RegFile, ALU, Clock Gating and SYS_CTRL.
//
//   REG0/REG1 are wired to the ALU operand inputs; SYS_CTRL owns the
//   RegFile/ALU control ports; SYS_CTRL also drives clk_div_en for the
//   domain-2 clock dividers, and the UART configuration bytes (REG2,
//   REG3) are exposed so the top-level system can cross them into the
//   UART_CLK domain via data_sync.
// =====================================================================
module clkdom1_top #(
    parameter ADDR_WIDTH = 5,
    parameter DATA_WIDTH = 8
)(
    input  wire                     REF_CLK,
    input  wire                     SYNC_RST,     // from RST_SYNC_1

    // UART RX/TX interface (already CDC'd into this domain)
    input  wire [DATA_WIDTH-1:0]    RX_P_DATA,
    input  wire                     RX_D_VLD,
    output wire [DATA_WIDTH-1:0]    TX_P_DATA,
    output wire                     TX_D_VLD,

    // Config bytes exposed for cross-domain sync toward UART_CLK domain
    output wire [DATA_WIDTH-1:0]    REG2_CFG,   // parity/prescale
    output wire [DATA_WIDTH-1:0]    REG3_CFG,   // div ratio

    output wire                     clk_div_en
);

    wire [3:0]            alu_fun;
    wire                   alu_en, alu_out_valid, clk_en_w, gated_clk;
    wire [ADDR_WIDTH-1:0]  rf_addr;
    wire                   rf_wren, rf_rden, rf_rddata_valid;
    wire [DATA_WIDTH-1:0]  rf_wdata, rf_rddata;
    wire [DATA_WIDTH-1:0]  reg0, reg1;
    wire [DATA_WIDTH-1:0]  alu_out;

    regfile #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_regfile (
        .CLK(REF_CLK), .RST(SYNC_RST),
        .Address(rf_addr), .WrEn(rf_wren), .RdEn(rf_rden),
        .WrData(rf_wdata), .RdData(rf_rddata), .RdData_Valid(rf_rddata_valid),
        .REG0(reg0), .REG1(reg1), .REG2(REG2_CFG), .REG3(REG3_CFG)
    );

    clk_gate u_clk_gate (
        .CLK(REF_CLK), .CLK_EN(clk_en_w), .GATED_CLK(gated_clk)
    );

    alu #(.DATA_WIDTH(DATA_WIDTH)) u_alu (
        .CLK(gated_clk), .RST(SYNC_RST),
        .A(reg0), .B(reg1), .ALU_FUN(alu_fun), .Enable(alu_en),
        .ALU_OUT(alu_out), .OUT_VALID(alu_out_valid)
    );

    sys_ctrl #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_sys_ctrl (
        .CLK(REF_CLK), .RST(SYNC_RST),
        .ALU_OUT(alu_out), .OUT_Valid(alu_out_valid), .ALU_FUN(alu_fun), .EN(alu_en),
        .CLK_EN(clk_en_w),
        .Address(rf_addr), .WrEn(rf_wren), .RdEn(rf_rden), .WrData(rf_wdata),
        .RdData(rf_rddata), .RdData_Valid(rf_rddata_valid),
        .RX_P_DATA(RX_P_DATA), .RX_D_VLD(RX_D_VLD),
        .TX_P_DATA(TX_P_DATA), .TX_D_VLD(TX_D_VLD),
        .clk_div_en(clk_div_en)
    );

endmodule
