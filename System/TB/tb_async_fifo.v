`timescale 1ns/1ps
module tb_async_fifo;

    localparam DW = 8, AW = 4;

    reg  W_CLK, W_RST, W_INC;
    reg  [DW-1:0] WR_DATA;
    wire FULL;

    reg  R_CLK, R_RST, R_INC;
    wire [DW-1:0] RD_DATA;
    wire EMPTY;

    integer errors = 0;
    integer i;

    async_fifo #(.DATA_WIDTH(DW), .ADDR_WIDTH(AW)) DUT (
        .W_CLK(W_CLK), .W_RST(W_RST), .W_INC(W_INC), .WR_DATA(WR_DATA), .FULL(FULL),
        .R_CLK(R_CLK), .R_RST(R_RST), .R_INC(R_INC), .RD_DATA(RD_DATA), .EMPTY(EMPTY)
    );

    always #10 W_CLK = ~W_CLK;   // 50MHz write clock
    always #135 R_CLK = ~R_CLK;  // ~3.7MHz read clock (different domain)

    initial begin
        $dumpfile("tb_async_fifo.vcd"); $dumpvars(0, tb_async_fifo);
        W_CLK=0; R_CLK=0; W_RST=0; R_RST=0; W_INC=0; R_INC=0; WR_DATA=0;
        #30 W_RST = 1; R_RST = 1;

        if (EMPTY !== 1'b1) begin errors=errors+1; $display("FAIL: FIFO not empty after reset"); end
        else $display("PASS: FIFO empty after reset");

        // write 5 bytes
        for (i = 0; i < 5; i = i + 1) begin
            @(negedge W_CLK);
            WR_DATA = 8'h10 + i;
            W_INC = 1;
            @(negedge W_CLK);
            W_INC = 0;
        end

        // wait for empty flag to deassert across CDC
        #500;
        if (EMPTY !== 1'b0) begin errors=errors+1; $display("FAIL: EMPTY did not clear after writes"); end
        else $display("PASS: EMPTY cleared after writes propagated");

        // read back 5 bytes and check values
        for (i = 0; i < 5; i = i + 1) begin
            @(negedge R_CLK);
            if (EMPTY) begin
                errors = errors + 1;
                $display("FAIL: unexpected EMPTY during read %0d", i);
            end
            R_INC = 1;
            @(negedge R_CLK);
            R_INC = 0;
            #1;
            if (RD_DATA !== (8'h10 + i)) begin
                errors = errors + 1;
                $display("FAIL: read %0d got %h expected %h", i, RD_DATA, 8'h10+i);
            end else
                $display("PASS: read %0d got %h", i, RD_DATA);
        end

        #300;
        if (EMPTY !== 1'b1) begin errors=errors+1; $display("FAIL: FIFO not empty after draining"); end
        else $display("PASS: FIFO empty after draining");

        if (errors == 0) $display("*** TB_ASYNC_FIFO: ALL TESTS PASSED ***");
        else $display("*** TB_ASYNC_FIFO: %0d TEST(S) FAILED ***", errors);
        $finish;
    end
endmodule
