// =====================================================================
// Module      : pulse_gen
// Description : Detects the falling edge of a level signal (UART_TX's
//               Busy output) and produces a single CLK-cycle pulse.
//               Used to generate ASYNC_FIFO's R_INC: once a TX frame
//               finishes (Busy: 1->0) a pulse requests the next byte
//               from the FIFO.
// =====================================================================
module pulse_gen (
    input  wire CLK,
    input  wire RST,      // active-low sync reset
    input  wire LVL_SIG,
    output reg  PULSE_SIG
);

    reg lvl_d;

    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            lvl_d     <= 1'b0;
            PULSE_SIG <= 1'b0;
        end else begin
            lvl_d     <= LVL_SIG;
            PULSE_SIG <= lvl_d & ~LVL_SIG; // falling edge detect
        end
    end

endmodule
