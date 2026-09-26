`timescale 1ns/1ps
module tb_rst_sync;

    reg RST, CLK;
    wire SYNC_RST;
    integer errors = 0;

    rst_sync DUT (.RST(RST), .CLK(CLK), .SYNC_RST(SYNC_RST));

    always #10 CLK = ~CLK; // 50MHz

    initial begin
        $dumpfile("tb_rst_sync.vcd");
        $dumpvars(0, tb_rst_sync);

        CLK = 0;
        RST = 0;                 // assert async reset
        #5;
        if (SYNC_RST !== 1'b0) begin errors = errors+1; $display("FAIL: SYNC_RST not low during reset"); end

        #35 RST = 1;              // deassert - should take 2 clks to propagate
        #1;
        if (SYNC_RST !== 1'b0) begin errors = errors+1; $display("FAIL: SYNC_RST rose too early"); end

        #40; // wait >2 clk edges
        if (SYNC_RST !== 1'b1) begin errors = errors+1; $display("FAIL: SYNC_RST did not deassert"); end
        else $display("PASS: SYNC_RST deasserted synchronously");

        // async assert mid-operation
        #20 RST = 0;
        #1;
        if (SYNC_RST !== 1'b0) begin errors = errors+1; $display("FAIL: async assert not immediate"); end
        else $display("PASS: async assert immediate");

        if (errors == 0) $display("*** TB_RST_SYNC: ALL TESTS PASSED ***");
        else $display("*** TB_RST_SYNC: %0d TEST(S) FAILED ***", errors);

        $finish;
    end
endmodule
