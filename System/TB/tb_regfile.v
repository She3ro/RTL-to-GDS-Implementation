`timescale 1ns/1ps
module tb_regfile;

    localparam ADDR_WIDTH = 5;
    localparam DATA_WIDTH = 8;

    reg                     CLK, RST;
    reg  [ADDR_WIDTH-1:0]   Address;
    reg                     WrEn, RdEn;
    reg  [DATA_WIDTH-1:0]   WrData;
    wire [DATA_WIDTH-1:0]   RdData;
    wire                    RdData_Valid;
    wire [DATA_WIDTH-1:0]   REG0, REG1, REG2, REG3;

    integer errors = 0;

    regfile #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) DUT (
        .CLK(CLK), .RST(RST), .Address(Address), .WrEn(WrEn), .RdEn(RdEn),
        .WrData(WrData), .RdData(RdData), .RdData_Valid(RdData_Valid),
        .REG0(REG0), .REG1(REG1), .REG2(REG2), .REG3(REG3)
    );

    always #10 CLK = ~CLK;

    task do_write(input [ADDR_WIDTH-1:0] a, input [DATA_WIDTH-1:0] d);
        begin
            @(negedge CLK);
            Address = a; WrData = d; WrEn = 1;
            @(negedge CLK);
            WrEn = 0;
        end
    endtask

    task do_read(input [ADDR_WIDTH-1:0] a);
        begin
            @(negedge CLK);
            Address = a; RdEn = 1;
            @(negedge CLK);
            RdEn = 0;
        end
    endtask

    initial begin
        $dumpfile("tb_regfile.vcd"); $dumpvars(0, tb_regfile);
        CLK = 0; RST = 0; Address = 0; WrEn = 0; RdEn = 0; WrData = 0;
        #25 RST = 1;

        // check reset defaults
        if (REG2 !== 8'h81) begin errors=errors+1; $display("FAIL: REG2 default=%h expected 81", REG2); end
        else $display("PASS: REG2 default correct (0x81)");
        if (REG3 !== 8'd32) begin errors=errors+1; $display("FAIL: REG3 default=%d expected 32", REG3); end
        else $display("PASS: REG3 default correct (32)");

        // write/read REG0
        do_write(5'h00, 8'hA5);
        do_read(5'h00);
        #1;
        if (RdData !== 8'hA5 || RdData_Valid !== 1'b1) begin
            errors = errors+1; $display("FAIL: REG0 RW mismatch data=%h valid=%b", RdData, RdData_Valid);
        end else $display("PASS: REG0 write/read back 0xA5");
        if (REG0 !== 8'hA5) begin errors=errors+1; $display("FAIL: REG0 port mismatch"); end

        // write to normal range address 0x10
        do_write(5'h10, 8'h3C);
        do_read(5'h10);
        #1;
        if (RdData !== 8'h3C) begin errors=errors+1; $display("FAIL: addr 0x10 mismatch got %h", RdData); end
        else $display("PASS: normal range addr 0x10 write/read 0x3C");

        // check RdData_Valid deasserts next cycle
        @(negedge CLK);
        if (RdData_Valid !== 1'b0) begin errors=errors+1; $display("FAIL: RdData_Valid did not deassert"); end
        else $display("PASS: RdData_Valid pulses for one cycle");

        if (errors == 0) $display("*** TB_REGFILE: ALL TESTS PASSED ***");
        else $display("*** TB_REGFILE: %0d TEST(S) FAILED ***", errors);
        $finish;
    end
endmodule
