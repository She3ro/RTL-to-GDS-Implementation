`timescale 1ns/1ps
module tb_clk_div;

    reg i_ref_clk, i_rst_n, i_clk_en;
    reg [7:0] i_div_ratio;
    wire o_div_clk;
    integer errors = 0;

    clk_div #(.RATIO_WIDTH(8)) DUT (
        .i_ref_clk(i_ref_clk), .i_rst_n(i_rst_n), .i_clk_en(i_clk_en),
        .i_div_ratio(i_div_ratio), .o_div_clk(o_div_clk)
    );

    always #10 i_ref_clk = ~i_ref_clk; // 50MHz -> 20ns period

    real t_rise1, t_rise2, period;

    initial begin
        $dumpfile("tb_clk_div.vcd"); $dumpvars(0, tb_clk_div);
        i_ref_clk = 0; i_rst_n = 0; i_clk_en = 0; i_div_ratio = 8'd4;
        #25 i_rst_n = 1;
        i_clk_en = 1;

        @(posedge o_div_clk); t_rise1 = $realtime;
        @(posedge o_div_clk); t_rise2 = $realtime;
        period = t_rise2 - t_rise1;
        // expect period = 2*ratio*20ns = 2*4*20 = 160ns
        if (period < 150 || period > 170) begin
            errors = errors + 1;
            $display("FAIL: measured period=%0f expected ~160ns", period);
        end else
            $display("PASS: divided clock period = %0f ns (expected ~160ns)", period);

        if (errors == 0) $display("*** TB_CLK_DIV: ALL TESTS PASSED ***");
        else $display("*** TB_CLK_DIV: %0d TEST(S) FAILED ***", errors);
        $finish;
    end
endmodule
