// =====================================================================
// Module      : sys_ctrl
// Description : Command processor. Parses frames received over UART_RX
//               (via RX_P_DATA/RX_D_VLD, already crossed into this
//               REF_CLK domain) and drives the RegFile / ALU / clock
//               gate, then sends results back over UART_TX
//               (TX_P_DATA/TX_D_VLD).
//
//   Protocol (design assumption - see project README for rationale):
//   the command/opcode byte is always the FIRST frame of a command,
//   identifying how many further frames follow:
//     0xAA RF_WR   : CMD, ADDR, DATA                (3 frames)
//     0xBB RF_RD   : CMD, ADDR                       (2 frames)
//     0xCC ALU_OP  : CMD, OPERAND_A, OPERAND_B, FUN  (4 frames)
//     0xDD ALU_NOP : CMD, FUN                        (2 frames, reuses
//                                                      previously
//                                                      loaded operands)
//
//   RF_WR command results in no reply. RF_RD replies with the read
//   data. Both ALU commands write their operands into RegFile
//   REG0/REG1 (addresses 0x0/0x1) before triggering the ALU (per the
//   RegFile map: REG0 = ALU Operand A, REG1 = ALU Operand B), then
//   reply with the ALU result once available.
// =====================================================================
module sys_ctrl #(
    parameter ADDR_WIDTH = 5,
    parameter DATA_WIDTH = 8
)(
    input  wire                     CLK,
    input  wire                     RST,           // active-low sync

    // ALU interface
    input  wire [DATA_WIDTH-1:0]    ALU_OUT,
    input  wire                     OUT_Valid,
    output reg  [3:0]               ALU_FUN,
    output reg                      EN,

    // Clock gate
    output reg                      CLK_EN,

    // RegFile interface
    output reg  [ADDR_WIDTH-1:0]    Address,
    output reg                      WrEn,
    output reg                      RdEn,
    output reg  [DATA_WIDTH-1:0]    WrData,
    input  wire [DATA_WIDTH-1:0]    RdData,
    input  wire                     RdData_Valid,

    // UART (already CDC'd into this domain)
    input  wire [DATA_WIDTH-1:0]    RX_P_DATA,
    input  wire                     RX_D_VLD,
    output reg  [DATA_WIDTH-1:0]    TX_P_DATA,
    output reg                      TX_D_VLD,

    // Clock divider enable (always on per spec)
    output wire                     clk_div_en
);

    localparam CMD_RF_WR    = 8'hAA,
               CMD_RF_RD    = 8'hBB,
               CMD_ALU_OP   = 8'hCC,
               CMD_ALU_NOP  = 8'hDD;

    localparam ADDR_OPA = {ADDR_WIDTH{1'b0}};              // 0x0
    localparam ADDR_OPB = {{(ADDR_WIDTH-1){1'b0}}, 1'b1};  // 0x1

    localparam S_IDLE      = 4'd0,
               S_GET_ADDR   = 4'd1,
               S_GET_WDATA  = 4'd2,
               S_RF_WRITE   = 4'd3,
               S_RF_READ    = 4'd4,
               S_RF_WAIT_RD = 4'd5,
               S_RF_SEND    = 4'd6,
               S_GET_OPA    = 4'd7,
               S_GET_OPB    = 4'd8,
               S_GET_FUN    = 4'd9,
               S_WR_OPA     = 4'd10,
               S_WR_OPB     = 4'd11,
               S_ALU_TRIG   = 4'd12,
               S_ALU_WAIT   = 4'd13,
               S_ALU_SEND   = 4'd14;

    reg [3:0]            state;
    reg [7:0]             cmd_reg;
    reg [ADDR_WIDTH-1:0]  addr_reg;
    reg [DATA_WIDTH-1:0]  wdata_reg;
    reg [DATA_WIDTH-1:0]  opa_reg, opb_reg;
    reg [3:0]             fun_reg;

    assign clk_div_en = 1'b1; // clock divider always on per spec

    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            state     <= S_IDLE;
            Address   <= {ADDR_WIDTH{1'b0}};
            WrEn      <= 1'b0;
            RdEn      <= 1'b0;
            WrData    <= {DATA_WIDTH{1'b0}};
            ALU_FUN   <= 4'b0;
            EN        <= 1'b0;
            CLK_EN    <= 1'b1;
            TX_P_DATA <= {DATA_WIDTH{1'b0}};
            TX_D_VLD  <= 1'b0;
            cmd_reg   <= 8'h00;
            addr_reg  <= {ADDR_WIDTH{1'b0}};
            wdata_reg <= {DATA_WIDTH{1'b0}};
            opa_reg   <= {DATA_WIDTH{1'b0}};
            opb_reg   <= {DATA_WIDTH{1'b0}};
            fun_reg   <= 4'b0;
        end else begin
            // defaults (pulsed signals)
            WrEn     <= 1'b0;
            RdEn     <= 1'b0;
            EN       <= 1'b0;
            TX_D_VLD <= 1'b0;

            case (state)
                // -------------------------------------------------
                S_IDLE: begin
                    if (RX_D_VLD) begin
                        cmd_reg <= RX_P_DATA;
                        case (RX_P_DATA)
                            CMD_RF_WR   : state <= S_GET_ADDR;
                            CMD_RF_RD   : state <= S_GET_ADDR;
                            CMD_ALU_OP  : state <= S_GET_OPA;
                            CMD_ALU_NOP : state <= S_GET_FUN;
                            default     : state <= S_IDLE; // unknown cmd, ignore
                        endcase
                    end
                end

                // ------------------- RegFile write/read -----------
                S_GET_ADDR: begin
                    if (RX_D_VLD) begin
                        addr_reg <= RX_P_DATA[ADDR_WIDTH-1:0];
                        state    <= (cmd_reg == CMD_RF_WR) ? S_GET_WDATA : S_RF_READ;
                    end
                end

                S_GET_WDATA: begin
                    if (RX_D_VLD) begin
                        wdata_reg <= RX_P_DATA;
                        state     <= S_RF_WRITE;
                    end
                end

                S_RF_WRITE: begin
                    Address <= addr_reg;
                    WrData  <= wdata_reg;
                    WrEn    <= 1'b1;
                    state   <= S_IDLE; // write commands do not reply
                end

                S_RF_READ: begin
                    Address <= addr_reg;
                    RdEn    <= 1'b1;
                    state   <= S_RF_WAIT_RD;
                end

                S_RF_WAIT_RD: begin
                    if (RdData_Valid) begin
                        TX_P_DATA <= RdData;
                        TX_D_VLD  <= 1'b1;
                        state     <= S_IDLE;
                    end
                end

                // ------------------- ALU with operands -------------
                S_GET_OPA: begin
                    if (RX_D_VLD) begin
                        opa_reg <= RX_P_DATA;
                        state   <= S_GET_OPB;
                    end
                end

                S_GET_OPB: begin
                    if (RX_D_VLD) begin
                        opb_reg <= RX_P_DATA;
                        state   <= S_GET_FUN;
                    end
                end

                S_GET_FUN: begin
                    if (RX_D_VLD) begin
                        fun_reg <= RX_P_DATA[3:0];
                        // ALU_NOP command jumps straight to trigger,
                        // reusing whatever is already loaded in REG0/REG1
                        state <= (cmd_reg == CMD_ALU_NOP) ? S_ALU_TRIG : S_WR_OPA;
                    end
                end

                S_WR_OPA: begin
                    Address <= ADDR_OPA;
                    WrData  <= opa_reg;
                    WrEn    <= 1'b1;
                    state   <= S_WR_OPB;
                end

                S_WR_OPB: begin
                    Address <= ADDR_OPB;
                    WrData  <= opb_reg;
                    WrEn    <= 1'b1;
                    state   <= S_ALU_TRIG;
                end

                S_ALU_TRIG: begin
                    ALU_FUN <= fun_reg;
                    EN      <= 1'b1;
                    state   <= S_ALU_WAIT;
                end

                S_ALU_WAIT: begin
                    if (OUT_Valid) begin
                        TX_P_DATA <= ALU_OUT;
                        TX_D_VLD  <= 1'b1;
                        state     <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
