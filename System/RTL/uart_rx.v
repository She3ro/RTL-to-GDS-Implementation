// =====================================================================
// Module      : uart_rx
// Description : UART receiver. CLK is an oversampled clock (produced
//               by a CLKDiv instance whose divide ratio is the
//               "Prescale" configuration value), running at
//               OVERSAMPLE ticks per bit period. The receiver detects
//               the start bit, samples every bit at mid-period, and
//               checks parity/stop framing.
// =====================================================================
module uart_rx #(
    parameter DATA_WIDTH = 8,
    parameter OVERSAMPLE = 16   // CLK ticks per bit period
)(
    input  wire                   CLK,       // oversampled clock (from CLKDiv)
    input  wire                   RST,       // active-low sync reset
    input  wire [5:0]             Prescale,  // present for interface completeness (unused internally)
    input  wire                   PAR_EN,
    input  wire                   PAR_TYP,   // 0 = even, 1 = odd
    input  wire                   RX_IN,
    output reg  [DATA_WIDTH-1:0]  P_DATA,
    output reg                    DATA_VLD,
    output reg                    PAR_ERR,
    output reg                    STP_ERR
);

    localparam S_IDLE  = 3'd0,
               S_START = 3'd1,
               S_DATA  = 3'd2,
               S_PARITY= 3'd3,
               S_STOP  = 3'd4;

    // double-flop synchronize the async serial input
    reg rx_meta, rx_sync;
    always @(posedge CLK or negedge RST) begin
        if (!RST) begin rx_meta <= 1'b1; rx_sync <= 1'b1; end
        else begin rx_meta <= RX_IN; rx_sync <= rx_meta; end
    end

    reg [2:0]              state;
    reg [$clog2(OVERSAMPLE)-1:0] tick_cnt;
    reg [3:0]               bit_idx;
    reg [DATA_WIDTH-1:0]    shift_reg;
    reg                     parity_calc;
    reg                     par_err_latched;

    localparam HALF = OVERSAMPLE/2;

    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            state       <= S_IDLE;
            tick_cnt    <= 0;
            bit_idx     <= 0;
            shift_reg   <= {DATA_WIDTH{1'b0}};
            P_DATA      <= {DATA_WIDTH{1'b0}};
            DATA_VLD    <= 1'b0;
            PAR_ERR     <= 1'b0;
            STP_ERR     <= 1'b0;
            parity_calc <= 1'b0;
            par_err_latched <= 1'b0;
        end else begin
            DATA_VLD <= 1'b0;
            PAR_ERR  <= 1'b0;
            STP_ERR  <= 1'b0;

            case (state)
                S_IDLE: begin
                    tick_cnt <= 0;
                    if (rx_sync == 1'b0) begin // possible start bit
                        state <= S_START;
                        tick_cnt <= 0;
                    end
                end

                S_START: begin
                    // sample at mid-bit to confirm valid start bit
                    if (tick_cnt == HALF-1) begin
                        if (rx_sync == 1'b0) begin
                            tick_cnt  <= 0;
                            bit_idx   <= 0;
                            parity_calc <= 1'b0;
                            state     <= S_DATA;
                        end else begin
                            state <= S_IDLE; // false start
                        end
                    end else begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end

                S_DATA: begin
                    if (tick_cnt == OVERSAMPLE-1) begin
                        tick_cnt <= 0;
                        shift_reg[bit_idx] <= rx_sync;
                        parity_calc        <= parity_calc ^ rx_sync;
                        if (bit_idx == DATA_WIDTH-1)
                            state <= PAR_EN ? S_PARITY : S_STOP;
                        bit_idx <= bit_idx + 1'b1;
                    end else begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end

                S_PARITY: begin
                    if (tick_cnt == OVERSAMPLE-1) begin
                        tick_cnt <= 0;
                        // expected parity bit: even -> XOR(data,parbit)=0 ; odd -> =1
                        par_err_latched <= ((parity_calc ^ rx_sync) != (PAR_TYP));
                        state <= S_STOP;
                    end else begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end

                S_STOP: begin
                    if (tick_cnt == OVERSAMPLE-1) begin
                        tick_cnt <= 0;
                        if (rx_sync != 1'b1)
                            STP_ERR <= 1'b1;
                        PAR_ERR  <= par_err_latched;
                        P_DATA   <= shift_reg;
                        DATA_VLD <= 1'b1;
                        state    <= S_IDLE;
                    end else begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
