`timescale 1ns/1ps
module tb_sys_ctrl;

    localparam AW = 5, DW = 8;

    reg CLK, RST;
    reg [DW-1:0] RX_P_DATA;
    reg RX_D_VLD;
    wire [DW-1:0] TX_P_DATA;
    wire TX_D_VLD;

    wire [3:0] ALU_FUN;
    wire EN, CLK_EN;
    wire [AW-1:0] Address;
    wire WrEn, RdEn;
    wire [DW-1:0] WrData, RdData;
    wire RdData_Valid;
    wire [DW-1:0] ALU_OUT;
    wire OUT_Valid;
    wire [DW-1:0] REG0, REG1, REG2, REG3;
    wire clk_div_en;

    integer errors = 0;

    sys_ctrl #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW)) DUT (
        .CLK(CLK), .RST(RST),
        .ALU_OUT(ALU_OUT), .OUT_Valid(OUT_Valid), .ALU_FUN(ALU_FUN), .EN(EN),
        .CLK_EN(CLK_EN),
        .Address(Address), .WrEn(WrEn), .RdEn(RdEn), .WrData(WrData),
        .RdData(RdData), .RdData_Valid(RdData_Valid),
        .RX_P_DATA(RX_P_DATA), .RX_D_VLD(RX_D_VLD),
        .TX_P_DATA(TX_P_DATA), .TX_D_VLD(TX_D_VLD),
        .clk_div_en(clk_div_en)
    );

    regfile #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW)) RF (
        .CLK(CLK), .RST(RST), .Address(Address), .WrEn(WrEn), .RdEn(RdEn),
        .WrData(WrData), .RdData(RdData), .RdData_Valid(RdData_Valid),
        .REG0(REG0), .REG1(REG1), .REG2(REG2), .REG3(REG3)
    );

    alu #(.DATA_WIDTH(DW)) ALU_U (
        .CLK(CLK), .RST(RST), .A(REG0), .B(REG1), .ALU_FUN(ALU_FUN),
        .Enable(EN), .ALU_OUT(ALU_OUT), .OUT_VALID(OUT_Valid)
    );

    always #10 CLK = ~CLK;

    task send_byte(input [7:0] b);
        begin
            @(negedge CLK);
            RX_P_DATA = b;
            RX_D_VLD  = 1;
            @(negedge CLK);
            RX_D_VLD = 0;
        end
    endtask

    task wait_tx(output [7:0] result);
        begin
            @(posedge TX_D_VLD);
            result = TX_P_DATA;
            @(negedge CLK);
        end
    endtask

    reg [7:0] result;

    initial begin
        $dumpfile("tb_sys_ctrl.vcd"); $dumpvars(0, tb_sys_ctrl);
        CLK=0; RST=0; RX_P_DATA=0; RX_D_VLD=0;
        #25 RST = 1;
        @(negedge CLK);

        // Test 1: RF write to normal address 0x10 then read back
        send_byte(8'hAA); // RF_WR
        send_byte(8'h10); // addr
        send_byte(8'h77); // data
        repeat(3) @(negedge CLK);

        send_byte(8'hBB); // RF_RD
        send_byte(8'h10); // addr
        wait_tx(result);
        if (result !== 8'h77) begin errors=errors+1; $display("FAIL: RF RD got %h expected 77", result); end
        else $display("PASS: RF write 0x10=0x77 then read back correctly");

        // Test 2: ALU op with operands: 12 + 30 = 42, ALU_FUN=ADD(0000)
        send_byte(8'hCC); // ALU_OP
        send_byte(8'd12); // operand A
        send_byte(8'd30); // operand B
        send_byte(8'b0000_0000); // FUN = ADD
        wait_tx(result);
        if (result !== 8'd42) begin errors=errors+1; $display("FAIL: ALU ADD got %0d expected 42", result); end
        else $display("PASS: ALU op with operands 12+30=42");

        // Test 3: ALU no-operand reusing REG0/REG1 (still 12,30), FUN=SUB
        send_byte(8'hDD); // ALU_NOP
        send_byte(8'b0000_0001); // FUN = SUB
        wait_tx(result);
        if (result !== ((12-30) & 8'hFF)) begin
            errors=errors+1; $display("FAIL: ALU NOP SUB got %0d expected %0d", result, (12-30)&8'hFF);
        end else $display("PASS: ALU no-operand op reused REG0/REG1 correctly");

        if (errors == 0) $display("*** TB_SYS_CTRL: ALL TESTS PASSED ***");
        else $display("*** TB_SYS_CTRL: %0d TEST(S) FAILED ***", errors);
        $finish;
    end
endmodule
