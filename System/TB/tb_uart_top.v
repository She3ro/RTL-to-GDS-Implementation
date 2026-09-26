`timescale 1ns/1ps
module tb_uart_top;

    localparam DW = 8;

    reg UART_CLK, SYNC_RST, REF_CLK, REF_SYNC_RST;
    reg [7:0] UART_CFG;
    reg [7:0] DIV_RATIO;
    reg RX_IN;
    wire TX_OUT;
    wire PAR_ERR, STP_ERR;
    wire [DW-1:0] RX_P_DATA;
    wire RX_D_VLD;
    reg [DW-1:0] TX_WR_DATA;
    reg TX_WR_INC;
    wire TX_FIFO_FULL;

    integer errors = 0;

    // div_ratio=16 (TX bit period = 2*16=32 UART_CLK cycles)
    // prescale=1   (RX_CLK period = 2*1=2 UART_CLK cycles -> RX bit = 16*2=32 cycles)
    // -> matched baud rate between TX and RX for this testbench
    initial begin
        DIV_RATIO = 8'd16;
        UART_CFG  = {6'd1, 1'b0, 1'b1}; // prescale=1, par_typ=0(even), par_en=1
    end

    uart_top #(.DATA_WIDTH(DW), .FIFO_AWIDTH(4)) DUT (
        .UART_CLK(UART_CLK), .SYNC_RST(SYNC_RST),
        .REF_CLK(REF_CLK), .REF_SYNC_RST(REF_SYNC_RST),
        .UART_CFG(UART_CFG), .DIV_RATIO(DIV_RATIO),
        .RX_IN(RX_IN), .TX_OUT(TX_OUT),
        .PAR_ERR(PAR_ERR), .STP_ERR(STP_ERR),
        .RX_P_DATA(RX_P_DATA), .RX_D_VLD(RX_D_VLD),
        .TX_WR_DATA(TX_WR_DATA), .TX_WR_INC(TX_WR_INC), .TX_FIFO_FULL(TX_FIFO_FULL)
    );

    always #135 UART_CLK = ~UART_CLK; // ~3.6864MHz-ish
    always #10  REF_CLK  = ~REF_CLK;  // 50MHz

    // ---------------- TX check: capture serial frame on TX_OUT -------
    reg [7:0] captured;
    integer i;
    task capture_tx_frame(input par_en);
        begin
            wait (TX_OUT === 1'b0); // start bit begins
            // sample each subsequent bit at its center using edge counts;
            // since we control timing exactly, wait 1.5 bit periods to
            // land mid-way through the first DATA bit (0.5 to finish the
            // start bit + 1.0 to reach the middle of bit0).
            #(3*32*270/2);
            for (i = 0; i < 8; i = i + 1) begin
                captured[i] = TX_OUT;
                #(32*270);
            end
            if (par_en) #(32*270); // skip parity bit
            // now at stop bit
        end
    endtask

    initial begin
        $dumpfile("tb_uart_top.vcd"); $dumpvars(0, tb_uart_top);
        UART_CLK=0; REF_CLK=0; SYNC_RST=0; REF_SYNC_RST=0;
        RX_IN=1; TX_WR_DATA=0; TX_WR_INC=0;
        #50 SYNC_RST=1; REF_SYNC_RST=1;

        // ---------- TX path test ----------
        @(negedge REF_CLK);
        TX_WR_DATA = 8'h6A;
        TX_WR_INC  = 1;
        @(negedge REF_CLK);
        TX_WR_INC = 0;

        capture_tx_frame(1'b1); // parity enabled per UART_CFG
        if (captured !== 8'h6A) begin
            errors = errors + 1;
            $display("FAIL: uart_top TX frame got %h expected 6A", captured);
        end else
            $display("PASS: uart_top TX path delivered 0x6A onto TX_OUT");

        // ---------- RX path test ----------
        // send a frame on RX_IN at the matched bit rate (32 UART_CLK cycles/bit)
        fork
            begin : send_rx
                reg [7:0] d;
                reg parbit;
                integer j;
                d = 8'h5C;
                parbit = ^d; // even parity
                @(negedge UART_CLK);
                RX_IN = 0; #(32*270);          // start
                for (j = 0; j < 8; j = j + 1) begin
                    RX_IN = d[j]; #(32*270);
                end
                RX_IN = parbit; #(32*270);      // parity
                RX_IN = 1;      #(32*270);      // stop
            end
            begin : check_rx
                @(posedge RX_D_VLD);
                #1;
                if (RX_P_DATA !== 8'h5C) begin
                    errors = errors + 1;
                    $display("FAIL: uart_top RX got %h expected 5C", RX_P_DATA);
                end else
                    $display("PASS: uart_top RX path correctly decoded 0x5C");
                if (PAR_ERR !== 1'b0) begin
                    errors = errors + 1;
                    $display("FAIL: unexpected parity error on RX");
                end
            end
        join

        if (errors == 0) $display("*** TB_UART_TOP: ALL TESTS PASSED ***");
        else $display("*** TB_UART_TOP: %0d TEST(S) FAILED ***", errors);
        $finish;
    end

    // safety timeout
    initial begin
        #2_000_000;
        $display("TIMEOUT - simulation did not complete in time");
        $finish;
    end
endmodule
