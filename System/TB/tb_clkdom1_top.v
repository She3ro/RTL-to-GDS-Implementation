`timescale 1ns/1ps
module tb_clkdom1_top;

    localparam AW = 5, DW = 8;

    reg REF_CLK, SYNC_RST;
    reg [DW-1:0] RX_P_DATA;
    reg RX_D_VLD;
    wire [DW-1:0] TX_P_DATA;
    wire TX_D_VLD;
    wire [DW-1:0] REG2_CFG, REG3_CFG;
    wire clk_div_en;

    integer errors = 0;

    clkdom1_top #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW)) DUT (
        .REF_CLK(REF_CLK), .SYNC_RST(SYNC_RST),
        .RX_P_DATA(RX_P_DATA), .RX_D_VLD(RX_D_VLD),
        .TX_P_DATA(TX_P_DATA), .TX_D_VLD(TX_D_VLD),
        .REG2_CFG(REG2_CFG), .REG3_CFG(REG3_CFG),
        .clk_div_en(clk_div_en)
    );

    always #10 REF_CLK = ~REF_CLK;

    task send_byte(input [7:0] b);
        begin
            @(negedge REF_CLK);
            RX_P_DATA = b;
            RX_D_VLD  = 1;
            @(negedge REF_CLK);
            RX_D_VLD = 0;
        end
    endtask

    task wait_tx(output [7:0] result);
        begin
            @(posedge TX_D_VLD);
            result = TX_P_DATA;
            @(negedge REF_CLK);
        end
    endtask

    reg [7:0] result;

    initial begin
        $dumpfile("tb_clkdom1_top.vcd"); $dumpvars(0, tb_clkdom1_top);
        REF_CLK=0; SYNC_RST=0; RX_P_DATA=0; RX_D_VLD=0;
        #25 SYNC_RST = 1;
        @(negedge REF_CLK);

        // reset defaults for config registers
        if (REG2_CFG !== 8'h81) begin errors=errors+1; $display("FAIL: REG2_CFG default wrong: %h", REG2_CFG); end
        else $display("PASS: REG2_CFG default 0x81 visible at domain-1 top");
        if (REG3_CFG !== 8'd32) begin errors=errors+1; $display("FAIL: REG3_CFG default wrong: %0d", REG3_CFG); end
        else $display("PASS: REG3_CFG default 32 visible at domain-1 top");
        if (clk_div_en !== 1'b1) begin errors=errors+1; $display("FAIL: clk_div_en not asserted"); end
        else $display("PASS: clk_div_en always-on as specified");

        // configuration write: set REG2 (0x2) prescale=16,type=0,en=1 -> 8'b0100_0001=0x41
        send_byte(8'hAA); send_byte(8'h02); send_byte(8'h41);
        repeat(3) @(negedge REF_CLK);
        if (REG2_CFG !== 8'h41) begin errors=errors+1; $display("FAIL: REG2 config write failed: %h", REG2_CFG); end
        else $display("PASS: REG2 configuration write updates REG2_CFG");

        // RF normal write/read at 0x08
        send_byte(8'hAA); send_byte(8'h08); send_byte(8'h5A);
        repeat(3) @(negedge REF_CLK);
        send_byte(8'hBB); send_byte(8'h08);
        wait_tx(result);
        if (result !== 8'h5A) begin errors=errors+1; $display("FAIL: RF RW got %h expected 5A", result); end
        else $display("PASS: RegFile write/read through domain-1 top");

        // ALU op: 100 * 2 (mul low byte) = 200
        send_byte(8'hCC); send_byte(8'd100); send_byte(8'd2); send_byte(8'b0010);
        wait_tx(result);
        if (result !== 8'd200) begin errors=errors+1; $display("FAIL: ALU MUL got %0d expected 200", result); end
        else $display("PASS: ALU op end-to-end through domain-1 top (100*2=200)");

        if (errors == 0) $display("*** TB_CLKDOM1_TOP: ALL TESTS PASSED ***");
        else $display("*** TB_CLKDOM1_TOP: %0d TEST(S) FAILED ***", errors);
        $finish;
    end
endmodule
