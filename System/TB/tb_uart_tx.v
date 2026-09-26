`timescale 1ns/1ps
module tb_uart_tx;

    reg        CLK, RST;
    reg        PAR_EN, PAR_TYP;
    reg  [7:0] P_DATA;
    reg        DATA_VALID;
    wire       S_DATA;
    wire       Busy;

    integer errors = 0;
    reg [7:0] captured;
    integer i;

    uart_tx DUT (
        .CLK(CLK), .RST(RST), .PAR_EN(PAR_EN), .PAR_TYP(PAR_TYP),
        .P_DATA(P_DATA), .DATA_VALID(DATA_VALID), .S_DATA(S_DATA), .Busy(Busy)
    );

    always #10 CLK = ~CLK; // baud-rate clock, 1 bit per CLK edge

    task send_byte(input [7:0] data);
        begin
            @(negedge CLK);
            P_DATA = data;
            DATA_VALID = 1;
            @(negedge CLK);
            DATA_VALID = 0;
        end
    endtask

    // sample S_DATA on each rising edge and reconstruct the frame
    task capture_frame(input par_en);
        integer nbits;
        begin
            captured = 8'h00;
            // wait for start bit (S_DATA=0)
            wait (S_DATA === 1'b0);
            @(negedge CLK); // start bit sampled mid-cycle here for simplicity
            for (i = 0; i < 8; i = i + 1) begin
                @(negedge CLK);
                captured[i] = S_DATA;
            end
            if (par_en) @(negedge CLK); // consume parity bit
            @(negedge CLK); // stop bit
        end
    endtask

    initial begin
        $dumpfile("tb_uart_tx.vcd"); $dumpvars(0, tb_uart_tx);
        CLK=0; RST=0; PAR_EN=0; PAR_TYP=0; P_DATA=0; DATA_VALID=0;
        #25 RST = 1;

        if (S_DATA !== 1'b1) begin errors=errors+1; $display("FAIL: line not idle-high after reset"); end
        else $display("PASS: TX line idles high");

        // Test 1: no parity
        fork
            send_byte(8'h5A);
            capture_frame(0);
        join
        if (captured !== 8'h5A) begin
            errors = errors+1; $display("FAIL: no-parity frame got %h expected 5A", captured);
        end else $display("PASS: no-parity frame correctly received 0x5A");

        @(negedge CLK);
        if (Busy !== 1'b0) begin errors=errors+1; $display("FAIL: Busy stuck high after frame"); end
        else $display("PASS: Busy deasserted after frame complete");

        // Test 2: with even parity
        PAR_EN = 1; PAR_TYP = 0;
        fork
            send_byte(8'hAA); // 4 ones -> even parity bit = 0
            capture_frame(1);
        join
        if (captured !== 8'hAA) begin
            errors = errors+1; $display("FAIL: parity frame data got %h expected AA", captured);
        end else $display("PASS: parity-enabled frame correctly received 0xAA");

        if (errors == 0) $display("*** TB_UART_TX: ALL TESTS PASSED ***");
        else $display("*** TB_UART_TX: %0d TEST(S) FAILED ***", errors);
        $finish;
    end
endmodule
