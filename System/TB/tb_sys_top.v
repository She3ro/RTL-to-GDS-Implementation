`timescale 1ns/1ps
// =====================================================================
// tb_sys_top : Full system-level integration testbench.
//
// Emulates the "Master" referred to in the specification: drives
// command frames into RX_IN and captures replies on TX_OUT, following
// the documented sequence of operation:
//   1) Configuration writes to RegFile addresses 0x2 / 0x3
//   2) Normal RegFile write/read commands
//   3) ALU operation commands (with and without operands)
//
// NOTE ON BAUD TIMING: UART_RX's effective bit period is governed by
// Prescale (REG2[7:2]) and UART_TX's by Div_Ratio (REG3), which are
// independent knobs per the block diagram. Reconfiguring Prescale
// changes the receiver's timing for ALL FRAMES AFTER the write takes
// effect - including, in principle, the very write command carrying
// the new value. To keep the boot sequence well-defined this testbench:
//   - writes REG3 (Div_Ratio) first, at the power-on-default bit rate
//     (safe: it only affects the TX side, not what the RX is currently
//     listening for)
//   - writes REG2 (Prescale/parity) LAST among the config commands,
//     still at the power-on-default bit rate, since that is the last
//     frame the receiver decodes using the OLD prescale value
//   - switches to the NEW bit rate for everything sent afterwards
// =====================================================================
module tb_sys_top;

    localparam DW = 8;
    localparam real T_UART = 270.0; // ns, ~matches 3.6864MHz

    reg REF_CLK, UART_CLK, RST;
    reg RX_IN;
    wire TX_OUT, PAR_ERR, STP_ERR;

    integer errors = 0;

    sys_top #(.ADDR_WIDTH(5), .DATA_WIDTH(DW), .FIFO_AWIDTH(4)) DUT (
        .REF_CLK(REF_CLK), .UART_CLK(UART_CLK), .RST(RST),
        .RX_IN(RX_IN), .TX_OUT(TX_OUT),
        .PAR_ERR(PAR_ERR), .STP_ERR(STP_ERR)
    );

    always #10   REF_CLK  = ~REF_CLK;  // 50 MHz
    always #135  UART_CLK = ~UART_CLK; // ~3.6864 MHz

    // ---- default (power-on) bit period: prescale=32, OVERSAMPLE=16 ----
    real DEFAULT_BIT_NS;
    // ---- reconfigured bit period: prescale=2 ----
    real NEW_RX_BIT_NS;
    // ---- TX reply bit period: div_ratio=16 (after reconfig) ----
    real NEW_TX_BIT_NS;

    initial begin
        DEFAULT_BIT_NS = 16.0 * 2.0 * 32.0 * T_UART; // 276,480 ns
        NEW_RX_BIT_NS  = 16.0 * 2.0 * 2.0  * T_UART; // 17,280 ns
        NEW_TX_BIT_NS  = 2.0  * 16.0 * T_UART;       // 8,640 ns
    end

    // ------------------------------------------------------------
    // Master-side serial send (to RX_IN), even parity always on
    // ------------------------------------------------------------
    task send_bit(input b, input real period);
        begin
            RX_IN = b;
            #period;
        end
    endtask

    task send_byte(input [7:0] data, input real period);
        reg parbit;
        integer i;
        begin
            parbit = ^data; // even parity
            send_bit(1'b0, period); // start
            for (i = 0; i < 8; i = i + 1)
                send_bit(data[i], period);
            send_bit(parbit, period); // parity (PAR_EN=1 by default & after reconfig)
            send_bit(1'b1, period);   // stop
        end
    endtask

    // ------------------------------------------------------------
    // Capture a reply frame on TX_OUT (parity enabled)
    // ------------------------------------------------------------
    task capture_reply(output [7:0] data, input real period);
        integer i;
        begin
            wait (TX_OUT === 1'b0);
            #(1.5*period); // reach mid of bit0
            for (i = 0; i < 8; i = i + 1) begin
                data[i] = TX_OUT;
                #period;
            end
            // consume parity bit (TX always has parity enabled in this
            // test's configuration) and the stop bit before returning,
            // so a later call's "wait(TX_OUT===0)" cannot falsely
            // trigger on a leftover bit of THIS frame.
            #period; // parity bit
            #period; // stop bit
        end
    endtask

    reg [7:0] result;

    initial begin
        $dumpfile("tb_sys_top.vcd"); $dumpvars(0, tb_sys_top);
        REF_CLK = 0; UART_CLK = 0; RST = 0; RX_IN = 1;
        #100 RST = 1;
        #1000;

        // ---------------- Step 1: configuration writes -------------
        // REG3 (0x03) = Div_Ratio = 16
        send_byte(8'hAA, DEFAULT_BIT_NS);
        send_byte(8'h03, DEFAULT_BIT_NS);
        send_byte(8'h10, DEFAULT_BIT_NS);

        // REG2 (0x02) = {prescale=2, par_typ=0, par_en=1} = 0x09
        send_byte(8'hAA, DEFAULT_BIT_NS);
        send_byte(8'h02, DEFAULT_BIT_NS);
        send_byte(8'h09, DEFAULT_BIT_NS);

        // allow the config CDC (data_sync stretch pulse) to settle
        #50000;

        if (DUT.reg2_cfg !== 8'h09) begin
            errors = errors + 1;
            $display("FAIL: REG2 config not applied, got %h", DUT.reg2_cfg);
        end else
            $display("PASS: REG2 (prescale/parity) configured to 0x09");

        if (DUT.reg3_cfg !== 8'h10) begin
            errors = errors + 1;
            $display("FAIL: REG3 config not applied, got %h", DUT.reg3_cfg);
        end else
            $display("PASS: REG3 (div ratio) configured to 0x10");

        // ---------------- Step 2: normal RegFile write/read --------
        send_byte(8'hAA, NEW_RX_BIT_NS); // RF_WR
        send_byte(8'h08, NEW_RX_BIT_NS); // addr 0x08
        send_byte(8'h3D, NEW_RX_BIT_NS); // data

        #(5*NEW_RX_BIT_NS);

        send_byte(8'hBB, NEW_RX_BIT_NS); // RF_RD
        send_byte(8'h08, NEW_RX_BIT_NS); // addr 0x08
        capture_reply(result, NEW_TX_BIT_NS);
        if (result !== 8'h3D) begin
            errors = errors + 1;
            $display("FAIL: RegFile RD reply got %h expected 3D", result);
        end else
            $display("PASS: RegFile write 0x08=0x3D then read-back over full system");

        #(5*NEW_RX_BIT_NS);

        // ---------------- Step 3: ALU op with operands --------------
        // 12 + 7 = 19, ALU_FUN = ADD (0000)
        send_byte(8'hCC, NEW_RX_BIT_NS);
        send_byte(8'd12, NEW_RX_BIT_NS);
        send_byte(8'd7,  NEW_RX_BIT_NS);
        send_byte(8'b0000_0000, NEW_RX_BIT_NS);
        capture_reply(result, NEW_TX_BIT_NS);
        if (result !== 8'd19) begin
            errors = errors + 1;
            $display("FAIL: ALU ADD reply got %0d expected 19", result);
        end else
            $display("PASS: ALU operation (12+7=19) over full system");

        #(5*NEW_RX_BIT_NS);

        // ---------------- Step 4: ALU op, no operand (reuse) --------
        // SUB: 12 - 7 = 5
        send_byte(8'hDD, NEW_RX_BIT_NS);
        send_byte(8'b0000_0001, NEW_RX_BIT_NS); // FUN = SUB
        capture_reply(result, NEW_TX_BIT_NS);
        if (result !== 8'd5) begin
            errors = errors + 1;
            $display("FAIL: ALU NOP SUB reply got %0d expected 5", result);
        end else
            $display("PASS: ALU no-operand operation (12-7=5) over full system");

        if (errors == 0) $display("*** TB_SYS_TOP: ALL TESTS PASSED ***");
        else $display("*** TB_SYS_TOP: %0d TEST(S) FAILED ***", errors);
        $finish;
    end

    // safety timeout (real-time bound on simulation, in ns)
    initial begin
        #50_000_000; // 50 ms simulated time ceiling
        $display("TIMEOUT - tb_sys_top did not complete");
        $finish;
    end

endmodule
