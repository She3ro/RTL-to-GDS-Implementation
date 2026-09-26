`timescale 1ns/1ps
module tb_uart_rx;

    localparam OVERSAMPLE = 16;
    localparam TCLK = 10; // half period of oversample clock

    reg        CLK, RST;
    reg  [5:0] Prescale;
    reg        PAR_EN, PAR_TYP;
    reg        RX_IN;
    wire [7:0] P_DATA;
    wire       DATA_VLD, PAR_ERR, STP_ERR;

    integer errors = 0;

    uart_rx #(.DATA_WIDTH(8), .OVERSAMPLE(OVERSAMPLE)) DUT (
        .CLK(CLK), .RST(RST), .Prescale(Prescale), .PAR_EN(PAR_EN), .PAR_TYP(PAR_TYP),
        .RX_IN(RX_IN), .P_DATA(P_DATA), .DATA_VLD(DATA_VLD), .PAR_ERR(PAR_ERR), .STP_ERR(STP_ERR)
    );

    always #TCLK CLK = ~CLK;

    // send one UART bit = OVERSAMPLE CLK periods
    task send_bit(input b);
        begin
            RX_IN = b;
            repeat (OVERSAMPLE) @(posedge CLK);
        end
    endtask

    task send_frame(input [7:0] data, input par_en, input par_typ);
        integer i;
        reg parbit;
        begin
            parbit = par_typ ? ~(^data) : (^data);
            send_bit(1'b0); // start
            for (i = 0; i < 8; i = i + 1)
                send_bit(data[i]);
            if (par_en) send_bit(parbit);
            send_bit(1'b1); // stop
        end
    endtask

    initial begin
        $dumpfile("tb_uart_rx.vcd"); $dumpvars(0, tb_uart_rx);
        CLK=0; RST=0; Prescale=6'd16; PAR_EN=0; PAR_TYP=0; RX_IN=1;
        #25 RST = 1;
        repeat(4) @(posedge CLK);

        // Test 1: no parity, data 0x3C
        fork
            send_frame(8'h3C, 0, 0);
            begin
                @(posedge DATA_VLD);
                #1;
                if (P_DATA !== 8'h3C) begin errors=errors+1; $display("FAIL: got %h expected 3C", P_DATA); end
                else $display("PASS: no-parity frame received 0x3C");
                if (PAR_ERR !== 1'b0 || STP_ERR !== 1'b0) begin errors=errors+1; $display("FAIL: unexpected error flags"); end
            end
        join

        repeat(4) @(posedge CLK);

        // Test 2: even parity, correct
        PAR_EN = 1; PAR_TYP = 0;
        fork
            send_frame(8'hC3, 1, 0);
            begin
                @(posedge DATA_VLD);
                #1;
                if (P_DATA !== 8'hC3) begin errors=errors+1; $display("FAIL: got %h expected C3", P_DATA); end
                else $display("PASS: even-parity frame received 0xC3");
                if (PAR_ERR !== 1'b0) begin errors=errors+1; $display("FAIL: false parity error"); end
                else $display("PASS: no parity error on correct frame");
            end
        join

        repeat(4) @(posedge CLK);

        // Test 3: inject a parity error
        fork
            begin : bad_frame
                reg [7:0] d;
                reg parbit;
                d = 8'h0F;
                parbit = ^d; // even parity for 0x0F
                send_bit(1'b0);
                send_bit(d[0]); send_bit(d[1]); send_bit(d[2]); send_bit(d[3]);
                send_bit(d[4]); send_bit(d[5]); send_bit(d[6]); send_bit(d[7]);
                send_bit(~parbit); // wrong parity bit
                send_bit(1'b1);
            end
            begin
                @(posedge DATA_VLD);
                #1;
                if (PAR_ERR !== 1'b1) begin errors=errors+1; $display("FAIL: parity error not flagged"); end
                else $display("PASS: parity error correctly flagged");
            end
        join

        if (errors == 0) $display("*** TB_UART_RX: ALL TESTS PASSED ***");
        else $display("*** TB_UART_RX: %0d TEST(S) FAILED ***", errors);
        $finish;
    end
endmodule
