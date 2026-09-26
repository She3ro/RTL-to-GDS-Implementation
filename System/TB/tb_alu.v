`timescale 1ns/1ps
module tb_alu;

    reg CLK, RST, Enable;
    reg [7:0] A, B;
    reg [3:0] ALU_FUN;
    wire [7:0] ALU_OUT;
    wire OUT_VALID;
    integer errors = 0;

    alu DUT(.CLK(CLK), .RST(RST), .A(A), .B(B), .ALU_FUN(ALU_FUN),
             .Enable(Enable), .ALU_OUT(ALU_OUT), .OUT_VALID(OUT_VALID));

    always #10 CLK = ~CLK;

    task run_op(input [3:0] fun, input [7:0] a, input [7:0] b, input [7:0] exp, input [127:0] name);
        begin
            @(negedge CLK);
            A = a; B = b; ALU_FUN = fun; Enable = 1;
            @(negedge CLK);
            Enable = 0;
            #1;
            if (ALU_OUT !== exp || OUT_VALID !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL: %0s  A=%0d B=%0d got=%0d(valid=%b) exp=%0d", name, a, b, ALU_OUT, OUT_VALID, exp);
            end else
                $display("PASS: %0s  A=%0d B=%0d -> %0d", name, a, b, ALU_OUT);
            @(negedge CLK);
        end
    endtask

    initial begin
        $dumpfile("tb_alu.vcd"); $dumpvars(0, tb_alu);
        CLK=0; RST=0; Enable=0; A=0; B=0; ALU_FUN=0;
        #25 RST = 1;

        run_op(4'b0000, 8'd10, 8'd20, 8'd30, "ADD");
        run_op(4'b0001, 8'd30, 8'd12, 8'd18, "SUB");
        run_op(4'b0010, 8'd12, 8'd12, 8'd144, "MUL");
        run_op(4'b0011, 8'd99, 8'd9,  8'd11, "DIV");
        run_op(4'b0011, 8'd10, 8'd0,  8'd0,  "DIV_by_zero");
        run_op(4'b0100, 8'hF0, 8'h3C, 8'h30, "AND");
        run_op(4'b0101, 8'hF0, 8'h0C, 8'hFC, "OR");
        run_op(4'b0110, 8'hFF, 8'hFF, 8'h00, "NAND");
        run_op(4'b0111, 8'h00, 8'h00, 8'hFF, "NOR");
        run_op(4'b1000, 8'hAA, 8'h55, 8'hFF, "XOR");
        run_op(4'b1001, 8'hAA, 8'h55, 8'h00, "XNOR");
        run_op(4'b1010, 8'd5,  8'd5,  8'd1,  "CMP_EQ_true");
        run_op(4'b1010, 8'd5,  8'd6,  8'd0,  "CMP_EQ_false");
        run_op(4'b1011, 8'd8,  8'd3,  8'd1,  "CMP_GT_true");
        run_op(4'b1100, 8'b0001_0000, 8'd0, 8'b0000_1000, "SHR");
        run_op(4'b1101, 8'b0001_0000, 8'd0, 8'b0010_0000, "SHL");

        if (errors == 0) $display("*** TB_ALU: ALL TESTS PASSED ***");
        else $display("*** TB_ALU: %0d TEST(S) FAILED ***", errors);
        $finish;
    end
endmodule
