// =====================================================================
// Module      : uart_tx
// Description : UART transmitter. CLK is the already-divided baud-rate
//               clock (from clk_div, one bit shifted per CLK edge).
//               Frame = 1 start bit (0) + 8 data bits (LSB first) +
//               optional parity bit + 1 stop bit (1).
// =====================================================================
module uart_tx #(
    parameter DATA_WIDTH = 8
)(
    input  wire                   CLK,      // baud-rate clock (from CLKDiv)
    input  wire                   RST,      // active-low sync reset
    input  wire                   PAR_EN,
    input  wire                   PAR_TYP,  // 0 = even, 1 = odd
    input  wire [DATA_WIDTH-1:0]  P_DATA,
    input  wire                   DATA_VALID,
    output reg                    S_DATA,   // -> TOP Output Port (TX_OUT)
    output reg                    Busy
);

    localparam S_IDLE   = 3'd0,
               S_START  = 3'd1,
               S_DATA_ST= 3'd2,
               S_PARITY = 3'd3,
               S_STOP   = 3'd4;

    reg [2:0]            state;
    reg [DATA_WIDTH-1:0] shift_reg;
    reg [3:0]            bit_cnt;
    reg                  parity_bit;

    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            state      <= S_IDLE;
            S_DATA     <= 1'b1;   // idle line = high
            Busy       <= 1'b0;
            shift_reg  <= {DATA_WIDTH{1'b0}};
            bit_cnt    <= 4'd0;
            parity_bit <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    S_DATA <= 1'b1;
                    if (DATA_VALID) begin
                        shift_reg  <= P_DATA;
                        parity_bit <= PAR_TYP ? ~(^P_DATA) : (^P_DATA); // odd/even
                        Busy       <= 1'b1;
                        state      <= S_START;
                    end else begin
                        Busy <= 1'b0;
                    end
                end

                S_START: begin
                    S_DATA  <= 1'b0;
                    bit_cnt <= 4'd0;
                    state   <= S_DATA_ST;
                end

                S_DATA_ST: begin
                    S_DATA    <= shift_reg[0];
                    shift_reg <= shift_reg >> 1;
                    bit_cnt   <= bit_cnt + 1'b1;
                    if (bit_cnt == DATA_WIDTH-1)
                        state <= PAR_EN ? S_PARITY : S_STOP;
                end

                S_PARITY: begin
                    S_DATA <= parity_bit;
                    state  <= S_STOP;
                end

                S_STOP: begin
                    S_DATA <= 1'b1;
                    Busy   <= 1'b0;
                    state  <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
