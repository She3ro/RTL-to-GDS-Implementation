// =====================================================================
// Module      : data_sync
// Description : Crosses a multi-bit "quasi-static" bus (e.g. a
//               configuration register) from a source domain into a
//               destination clock domain. bus_enable is captured with
//               the bus and re-generated as a single-cycle pulse
//               (enable_pulse_d) in the destination domain once the
//               new bus value has been safely synchronized.
//               Used for REG2 (UART config) / REG3 (Div Ratio) which
//               are written in the REF_CLK domain by SYS_CTRL/RegFile
//               but consumed in the UART_CLK domain.
// =====================================================================
module data_sync #(
    parameter DATA_WIDTH = 8,
    parameter [DATA_WIDTH-1:0] RESET_VAL = {DATA_WIDTH{1'b0}}
)(
    input  wire [DATA_WIDTH-1:0] unsync_bus,
    input  wire                  bus_enable,
    input  wire                  dest_clk,
    input  wire                  dest_rst,   // active-low async

    output reg  [DATA_WIDTH-1:0] sync_bus,
    output reg                   enable_pulse_d
);

    // Double-flop synchronizer for the enable/valid strobe
    reg en_meta, en_sync, en_sync_d;

    // Data is captured alongside the synchronized enable. Because the
    // source bus is assumed quasi-static (held stable for several
    // destination clocks while bus_enable is asserted), it is safe to
    // sample it directly once the enable has been synchronized.
    //   NOTE: sync_bus resets to RESET_VAL (rather than always 0) so
    //   that a downstream consumer sees a sensible power-on value
    //   immediately, without depending on winning a boot-time race
    //   against the very first change-detect pulse from the source
    //   domain (whose reset may deassert later than this domain's).
    always @(posedge dest_clk or negedge dest_rst) begin
        if (!dest_rst) begin
            en_meta   <= 1'b0;
            en_sync   <= 1'b0;
            en_sync_d <= 1'b0;
            sync_bus  <= RESET_VAL;
            enable_pulse_d <= 1'b0;
        end else begin
            en_meta   <= bus_enable;
            en_sync   <= en_meta;
            en_sync_d <= en_sync;

            enable_pulse_d <= en_sync & ~en_sync_d; // rising-edge detect -> 1 cycle pulse

            if (en_sync & ~en_sync_d)
                sync_bus <= unsync_bus;
        end
    end

endmodule
