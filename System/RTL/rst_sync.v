// =====================================================================
// Module      : rst_sync
// Description : Two flip-flop asynchronous-assert / synchronous-deassert
//               active-low reset synchronizer.
// =====================================================================
module rst_sync (
    input  wire RST,       // async active-low reset (raw)
    input  wire CLK,       // destination clock
    output wire SYNC_RST   // synchronized active-low reset
);

    reg meta_ff, sync_ff;

    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            meta_ff <= 1'b0;
            sync_ff <= 1'b0;
        end else begin
            meta_ff <= 1'b1;
            sync_ff <= meta_ff;
        end
    end

    assign SYNC_RST = sync_ff;

endmodule
