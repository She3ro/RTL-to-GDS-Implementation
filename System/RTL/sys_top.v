// =====================================================================
// Module      : sys_top
// Description : Final system-level integration. Ties together:
//                 - RST_SYNC_1 (REF_CLK domain) / RST_SYNC_2 (UART_CLK domain)
//                 - clkdom1_top   (RegFile, ALU, Clock Gating, SYS_CTRL)
//                 - uart_top      (UART_RX, UART_TX, PULSE_GEN, ASYNC_FIFO,
//                                   two clock dividers)
//                 - two Data_Sync instances that cross the UART
//                   configuration bytes (REG2 = parity/prescale,
//                   REG3 = clock-divider ratio) from the REF_CLK
//                   domain into the UART_CLK domain, and a third
//                   Data_Sync that crosses received UART bytes back
//                   from the UART_CLK domain into the REF_CLK domain
//                   for SYS_CTRL to consume.
//
//   The write side of ASYNC_FIFO (results going out over UART_TX) is
//   handled internally by uart_top's own CDC FIFO, so no extra
//   Data_Sync is needed there.
// =====================================================================
module sys_top #(
    parameter ADDR_WIDTH  = 5,
    parameter DATA_WIDTH  = 8,
    parameter FIFO_AWIDTH = 4
)(
    input  wire REF_CLK,     // 50 MHz
    input  wire UART_CLK,    // 3.6864 MHz
    input  wire RST,         // async active-low, raw

    input  wire RX_IN,
    output wire TX_OUT,

    output wire PAR_ERR,
    output wire STP_ERR
);

    // ---------------- reset synchronizers ----------------
    wire sync_rst_1, sync_rst_2;

    rst_sync u_rst_sync_1 (.RST(RST), .CLK(REF_CLK),  .SYNC_RST(sync_rst_1));
    rst_sync u_rst_sync_2 (.RST(RST), .CLK(UART_CLK), .SYNC_RST(sync_rst_2));

    // ---------------- clock domain 1 (REF_CLK) ----------------
    wire [DATA_WIDTH-1:0] rx_p_data_d1;   // RX byte synced into REF_CLK domain
    wire                   rx_d_vld_d1;
    wire [DATA_WIDTH-1:0] tx_p_data_d1;   // byte to transmit, from SYS_CTRL
    wire                   tx_d_vld_d1;
    wire [DATA_WIDTH-1:0] reg2_cfg, reg3_cfg;
    wire                   clk_div_en;

    clkdom1_top #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_clkdom1 (
        .REF_CLK(REF_CLK), .SYNC_RST(sync_rst_1),
        .RX_P_DATA(rx_p_data_d1), .RX_D_VLD(rx_d_vld_d1),
        .TX_P_DATA(tx_p_data_d1), .TX_D_VLD(tx_d_vld_d1),
        .REG2_CFG(reg2_cfg), .REG3_CFG(reg3_cfg),
        .clk_div_en(clk_div_en)
    );

    // ---------------- config change detectors (REF_CLK domain) -----
    // The resulting strobe must be held long enough for the much
    // slower UART_CLK domain to reliably sample it (REF_CLK = 50MHz,
    // UART_CLK ~= 3.6864MHz), otherwise a single 20ns-wide REF_CLK
    // pulse could be missed entirely by the destination flip-flops.
    // A simple stretcher holds the strobe high for STRETCH REF_CLK
    // cycles, comfortably longer than one UART_CLK period.
    localparam STRETCH = 24;

    reg [DATA_WIDTH-1:0] reg2_prev, reg3_prev;
    reg                   reg2_chg_raw, reg3_chg_raw;
    reg [4:0]             reg2_stretch_cnt, reg3_stretch_cnt;
    wire                   reg2_chg = (reg2_stretch_cnt != 0);
    wire                   reg3_chg = (reg3_stretch_cnt != 0);

    always @(posedge REF_CLK or negedge sync_rst_1) begin
        if (!sync_rst_1) begin
            reg2_prev        <= {DATA_WIDTH{1'b0}};
            reg3_prev        <= {DATA_WIDTH{1'b0}};
            reg2_chg_raw      <= 1'b1; // force an initial sync after reset
            reg3_chg_raw      <= 1'b1;
            reg2_stretch_cnt  <= STRETCH[4:0];
            reg3_stretch_cnt  <= STRETCH[4:0];
        end else begin
            reg2_chg_raw <= (reg2_cfg != reg2_prev);
            reg3_chg_raw <= (reg3_cfg != reg3_prev);
            reg2_prev    <= reg2_cfg;
            reg3_prev    <= reg3_cfg;

            if (reg2_chg_raw)
                reg2_stretch_cnt <= STRETCH[4:0];
            else if (reg2_stretch_cnt != 0)
                reg2_stretch_cnt <= reg2_stretch_cnt - 1'b1;

            if (reg3_chg_raw)
                reg3_stretch_cnt <= STRETCH[4:0];
            else if (reg3_stretch_cnt != 0)
                reg3_stretch_cnt <= reg3_stretch_cnt - 1'b1;
        end
    end

    // ---------------- config CDC: REF_CLK -> UART_CLK --------------
    wire [DATA_WIDTH-1:0] uart_cfg_synced, div_ratio_synced;
    wire                   uart_cfg_pulse, div_ratio_pulse; // unused, informational

    data_sync #(.DATA_WIDTH(DATA_WIDTH), .RESET_VAL(8'h81)) u_datasync_cfg (
        .unsync_bus(reg2_cfg), .bus_enable(reg2_chg),
        .dest_clk(UART_CLK), .dest_rst(sync_rst_2),
        .sync_bus(uart_cfg_synced), .enable_pulse_d(uart_cfg_pulse)
    );

    data_sync #(.DATA_WIDTH(DATA_WIDTH), .RESET_VAL(8'd32)) u_datasync_divratio (
        .unsync_bus(reg3_cfg), .bus_enable(reg3_chg),
        .dest_clk(UART_CLK), .dest_rst(sync_rst_2),
        .sync_bus(div_ratio_synced), .enable_pulse_d(div_ratio_pulse)
    );

    // ---------------- clock domain 2 (UART_CLK) ---------------------
    wire [DATA_WIDTH-1:0] rx_p_data_d2;   // RX byte, still in UART_CLK domain
    wire                   rx_d_vld_d2;
    wire                   tx_fifo_full;

    uart_top #(.DATA_WIDTH(DATA_WIDTH), .FIFO_AWIDTH(FIFO_AWIDTH)) u_uart_top (
        .UART_CLK(UART_CLK), .SYNC_RST(sync_rst_2),
        .REF_CLK(REF_CLK), .REF_SYNC_RST(sync_rst_1),
        .UART_CFG(uart_cfg_synced), .DIV_RATIO(div_ratio_synced),
        .RX_IN(RX_IN), .TX_OUT(TX_OUT),
        .PAR_ERR(PAR_ERR), .STP_ERR(STP_ERR),
        .RX_P_DATA(rx_p_data_d2), .RX_D_VLD(rx_d_vld_d2),
        .TX_WR_DATA(tx_p_data_d1), .TX_WR_INC(tx_d_vld_d1), .TX_FIFO_FULL(tx_fifo_full)
    );

    // ---------------- received-byte CDC: UART_CLK -> REF_CLK --------
    // RX_D_VLD from uart_rx is already a clean single-cycle strobe in
    // its own domain and P_DATA is held stable alongside it, so we
    // can drive Data_Sync's bus_enable directly from it.
    data_sync #(.DATA_WIDTH(DATA_WIDTH)) u_datasync_rx (
        .unsync_bus(rx_p_data_d2), .bus_enable(rx_d_vld_d2),
        .dest_clk(REF_CLK), .dest_rst(sync_rst_1),
        .sync_bus(rx_p_data_d1), .enable_pulse_d(rx_d_vld_d1)
    );

endmodule
