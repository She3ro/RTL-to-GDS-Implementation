`timescale 1ns/1ps
module tb_data_sync;

    reg  [7:0] unsync_bus;
    reg        bus_enable;
    reg        dest_clk, dest_rst;
    wire [7:0] sync_bus;
    wire       enable_pulse_d;

    integer errors = 0;

    data_sync #(.DATA_WIDTH(8)) DUT (
        .unsync_bus(unsync_bus), .bus_enable(bus_enable),
        .dest_clk(dest_clk), .dest_rst(dest_rst),
        .sync_bus(sync_bus), .enable_pulse_d(enable_pulse_d)
    );

    always #135 dest_clk = ~dest_clk; // slower UART-ish clock

    initial begin
        $dumpfile("tb_data_sync.vcd"); $dumpvars(0, tb_data_sync);
        dest_clk = 0; dest_rst = 0; unsync_bus = 0; bus_enable = 0;
        #50 dest_rst = 1;

        // drive a new value with a pulse on bus_enable (async to dest_clk)
        #37; // arbitrary async offset
        unsync_bus = 8'hA5;
        bus_enable = 1;
        #50 bus_enable = 0;

        // wait for pulse to appear
        fork
            begin : wait_pulse
                @(posedge enable_pulse_d);
                if (sync_bus !== 8'hA5) begin
                    errors = errors + 1;
                    $display("FAIL: sync_bus=%h expected A5", sync_bus);
                end else
                    $display("PASS: sync_bus correctly captured 0xA5 with pulse");
            end
            begin : timeout_g
                #2000;
                $display("FAIL: enable_pulse_d never asserted (timeout)");
                errors = errors + 1;
            end
        join_any
        disable timeout_g;

        // pulse should only be 1 cycle
        @(posedge dest_clk);
        #1;
        if (enable_pulse_d !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL: enable_pulse_d did not deassert");
        end else
            $display("PASS: enable_pulse_d is a single-cycle pulse");

        if (errors == 0) $display("*** TB_DATA_SYNC: ALL TESTS PASSED ***");
        else $display("*** TB_DATA_SYNC: %0d TEST(S) FAILED ***", errors);
        $finish;
    end
endmodule
