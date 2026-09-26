// =====================================================================
// Module      : uart_top
// Description : Clock Domain 2 (UART_CLK) top module. Instantiates
//               UART_RX, UART_TX, PULSE_GEN, ASYNC_FIFO and the two
//               programmable clock dividers (one for TX baud rate
//               using Div_Ratio, one for RX oversampling using
//               Prescale).
//
//   Data path for transmit: SYS_CTRL (REF_CLK domain) pushes result
//   bytes into ASYNC_FIFO on the write side; on the read side (this
//   domain), whenever UART_TX is not busy and the FIFO isn't empty a
//   byte is popped and handed to UART_TX. PULSE_GEN turns UART_TX's
//   Busy 1->0 transition into the FIFO's R_INC pulse. An extra
//   "kick" pulse is generated the first time data becomes available
//   while TX is idle, since PULSE_GEN alone cannot fire before the
//   first Busy transition has occurred.
// =====================================================================
module uart_top #(
    parameter DATA_WIDTH  = 8,
    parameter FIFO_AWIDTH = 4
)(
    input  wire                   UART_CLK,
    input  wire                   SYNC_RST,     // from RST_SYNC_2 (UART_CLK domain)
    input  wire                   REF_CLK,      // for FIFO write-side domain
    input  wire                   REF_SYNC_RST, // from RST_SYNC_1 (REF_CLK domain)

    // UART config, already synchronized into this domain
    input  wire [7:0]             UART_CFG,     // REG2: [0]=PAR_EN [1]=PAR_TYP [7:2]=Prescale
    input  wire [7:0]             DIV_RATIO,    // REG3

    // serial lines
    input  wire                   RX_IN,
    output wire                   TX_OUT,

    // frame error flags
    output wire                   PAR_ERR,
    output wire                   STP_ERR,

    // received parallel data toward Data_Sync -> SYS_CTRL
    output wire [DATA_WIDTH-1:0]  RX_P_DATA,
    output wire                   RX_D_VLD,

    // result bytes coming from SYS_CTRL (REF_CLK domain) to transmit
    input  wire [DATA_WIDTH-1:0]  TX_WR_DATA,
    input  wire                   TX_WR_INC,
    output wire                   TX_FIFO_FULL
);

    wire par_en   = UART_CFG[0];
    wire par_typ  = UART_CFG[1];
    wire [5:0] prescale = UART_CFG[7:2];

    // ---------------- clock dividers ----------------
    wire tx_clk, rx_clk;

    clk_div #(.RATIO_WIDTH(8)) u_txdiv (
        .i_ref_clk(UART_CLK), .i_rst_n(SYNC_RST), .i_clk_en(1'b1),
        .i_div_ratio(DIV_RATIO), .o_div_clk(tx_clk)
    );

    clk_div #(.RATIO_WIDTH(8)) u_rxdiv (
        .i_ref_clk(UART_CLK), .i_rst_n(SYNC_RST), .i_clk_en(1'b1),
        .i_div_ratio({2'b00, prescale}), .o_div_clk(rx_clk)
    );

    // ---------------- receiver ----------------
    uart_rx #(.DATA_WIDTH(DATA_WIDTH), .OVERSAMPLE(16)) u_uart_rx (
        .CLK(rx_clk), .RST(SYNC_RST), .Prescale(prescale),
        .PAR_EN(par_en), .PAR_TYP(par_typ), .RX_IN(RX_IN),
        .P_DATA(RX_P_DATA), .DATA_VLD(RX_D_VLD),
        .PAR_ERR(PAR_ERR), .STP_ERR(STP_ERR)
    );

    // ---------------- TX side: FIFO + pulse_gen + uart_tx ----------
    wire [DATA_WIDTH-1:0] fifo_rd_data;
    wire fifo_empty, r_inc;
    wire busy;

    async_fifo #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(FIFO_AWIDTH)) u_fifo (
        .W_CLK(REF_CLK), .W_RST(REF_SYNC_RST), .W_INC(TX_WR_INC),
        .WR_DATA(TX_WR_DATA), .FULL(TX_FIFO_FULL),
        .R_CLK(UART_CLK), .R_RST(SYNC_RST), .R_INC(r_inc),
        .RD_DATA(fifo_rd_data), .EMPTY(fifo_empty)
    );

    pulse_gen u_pulse_gen (
        .CLK(UART_CLK), .RST(SYNC_RST), .LVL_SIG(busy), .PULSE_SIG(r_inc_falling)
    );
    wire r_inc_falling;

    // Kick-start: pulse_gen (below) only fires when UART_TX transitions
    // Busy 1->0, which handles draining the FIFO one entry at a time
    // for the 2nd, 3rd, ... bytes of a burst. But the very FIRST byte
    // after an idle period has no prior Busy transition to key off of.
    //   To start that first read WITHOUT risking a repeated/erroneous
    //   pop (which would desynchronize the FIFO's read pointer past
    //   its write pointer - the FIFO trusts the caller not to read
    //   while EMPTY, and does not self-correct an over-read), the kick
    //   is generated as a genuine one-shot EDGE pulse: it fires only
    //   at the instant FIFO transitions from empty to non-empty while
    //   TX is idle, not on every cycle where "not empty and not busy"
    //   happens to be true.
    reg tx_dv_pending;
    reg fifo_empty_d1, fifo_empty_d2;
    always @(posedge UART_CLK or negedge SYNC_RST) begin
        if (!SYNC_RST) begin
            fifo_empty_d1 <= 1'b1;
            fifo_empty_d2 <= 1'b1;
        end else begin
            fifo_empty_d1 <= fifo_empty;   // last cycle's EMPTY (registered)
            fifo_empty_d2 <= fifo_empty_d1; // cycle before that
        end
    end
    // Both operands here are registered (never the live combinational
    // fifo_empty), so this cannot feed back into the same-cycle EMPTY
    // computation inside the FIFO - unlike a naive "fifo_empty_d & ~fifo_empty"
    // which would still create the same zero-delay loop this glue logic
    // is trying to avoid.
    wire fifo_became_nonempty = fifo_empty_d2 & ~fifo_empty_d1;
    wire kick = fifo_became_nonempty & ~busy & ~tx_dv_pending & ~tx_dv_reg;
    // r_inc_falling (from pulse_gen, fires whenever TX finishes a byte)
    // must also be gated against the FIFO genuinely being empty, or a
    // "request next byte" pulse fires even with nothing left to send.
    // Using the registered fifo_empty_d1 here (rather than the live
    // combinational EMPTY) avoids recreating the same-cycle loop this
    // glue logic works around elsewhere.
    assign r_inc = (r_inc_falling & ~fifo_empty_d1) | kick;

    // one-cycle-delayed "data valid" to UART_TX after a FIFO read.
    // Held at level (not a single pulse) until UART_TX asserts Busy,
    // since UART_TX runs on the slower divided tx_clk and a single
    // UART_CLK-wide pulse could be missed between tx_clk edges.
    reg [DATA_WIDTH-1:0] tx_pdata_reg;
    reg tx_dv_reg;

    always @(posedge UART_CLK or negedge SYNC_RST) begin
        if (!SYNC_RST) begin
            tx_dv_reg     <= 1'b0;
            tx_dv_pending <= 1'b0;
            tx_pdata_reg  <= {DATA_WIDTH{1'b0}};
        end else begin
            if (r_inc) begin
                tx_dv_pending <= 1'b1;
            end else if (tx_dv_pending) begin
                tx_pdata_reg  <= fifo_rd_data;
                tx_dv_reg     <= 1'b1;
                tx_dv_pending <= 1'b0;
            end
            if (busy) // UART_TX has accepted the byte
                tx_dv_reg <= 1'b0;
        end
    end

    uart_tx #(.DATA_WIDTH(DATA_WIDTH)) u_uart_tx (
        .CLK(tx_clk), .RST(SYNC_RST), .PAR_EN(par_en), .PAR_TYP(par_typ),
        .P_DATA(tx_pdata_reg), .DATA_VALID(tx_dv_reg),
        .S_DATA(TX_OUT), .Busy(busy)
    );

endmodule
