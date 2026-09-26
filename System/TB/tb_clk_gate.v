`timescale 1ns/1ps
module tb_clk_gate;

    reg CLK, CLK_EN;
    wire GATED_CLK;
    integer edge_count = 0;
    integer errors = 0;

    clk_gate DUT(.CLK(CLK), .CLK_EN(CLK_EN), .GATED_CLK(GATED_CLK));

    always #10 CLK = ~CLK;
    always @(posedge GATED_CLK) edge_count = edge_count + 1;

    initial begin
        $dumpfile("tb_clk_gate.vcd"); $dumpvars(0, tb_clk_gate);
        CLK = 0; CLK_EN = 0;
        #100; // 5 clk periods disabled
        if (edge_count != 0) begin errors=errors+1; $display("FAIL: edges seen while gated off"); end
        else $display("PASS: no toggling while CLK_EN=0");

        CLK_EN = 1;
        #100; // 5 periods enabled -> expect ~5 edges
        if (edge_count < 4) begin errors=errors+1; $display("FAIL: too few edges while enabled (%0d)", edge_count); end
        else $display("PASS: GATED_CLK toggling while enabled (%0d edges)", edge_count);

        CLK_EN = 0;
        edge_count = 0;
        #100;
        if (edge_count != 0) begin errors=errors+1; $display("FAIL: edges after disabling"); end
        else $display("PASS: stopped cleanly after disable");

        if (errors == 0) $display("*** TB_CLK_GATE: ALL TESTS PASSED ***");
        else $display("*** TB_CLK_GATE: %0d TEST(S) FAILED ***", errors);
        $finish;
    end
endmodule
