// =====================================================================
// Module      : clk_gate
// Description : Glitch-free integrated clock gating cell (latch based).
// =====================================================================
module clk_gate (
    input  wire CLK,
    input  wire CLK_EN,
    output wire GATED_CLK
);

    reg en_latch;

    // Transparent latch on the low phase of CLK avoids glitches when
    // CLK_EN toggles while CLK is high.
    always @(*) begin
        if (!CLK)
            en_latch = CLK_EN;
    end

    assign GATED_CLK = CLK & en_latch;

endmodule
