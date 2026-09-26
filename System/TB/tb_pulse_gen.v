`timescale 1ns/1ps
module tb_pulse_gen;

    reg CLK, RST, LVL_SIG;
    wire PULSE_SIG;
    integer errors = 0;

    pulse_gen DUT(.CLK(CLK), .RST(RST), .LVL_SIG(LVL_SIG), .PULSE_SIG(PULSE_SIG));

    always #10 CLK = ~CLK;

    initial begin
        $dumpfile("tb_pulse_gen.vcd"); $dumpvars(0, tb_pulse_gen);
        CLK=0; RST=0; LVL_SIG=0;
        #25 RST = 1;

        // rising edge of LVL_SIG should NOT generate a pulse
        @(negedge CLK); LVL_SIG = 1;
        @(negedge CLK);
        if (PULSE_SIG !== 1'b0) begin errors=errors+1; $display("FAIL: pulse on rising edge"); end
        else $display("PASS: no pulse on rising edge");

        // hold busy for a few cycles
        repeat (3) @(negedge CLK);

        // falling edge should generate exactly one pulse
        @(negedge CLK); LVL_SIG = 0;
        @(posedge CLK); #1;
        if (PULSE_SIG !== 1'b1) begin errors=errors+1; $display("FAIL: no pulse on falling edge"); end
        else $display("PASS: pulse generated on falling edge");

        @(posedge CLK); #1;
        if (PULSE_SIG !== 1'b0) begin errors=errors+1; $display("FAIL: pulse lasted >1 cycle"); end
        else $display("PASS: pulse is single-cycle");

        if (errors == 0) $display("*** TB_PULSE_GEN: ALL TESTS PASSED ***");
        else $display("*** TB_PULSE_GEN: %0d TEST(S) FAILED ***", errors);
        $finish;
    end
endmodule
