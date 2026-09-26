// =====================================================================
// Module      : alu
// Description : 8-bit ALU supporting the 14 required operations.
// ALU_FUN encoding:
//   0000 ADD   0001 SUB   0010 MUL(low byte)  0011 DIV
//   0100 AND   0101 OR    0110 NAND           0111 NOR
//   1000 XOR   1001 XNOR  1010 CMP A==B       1011 CMP A>B
//   1100 SHR (A>>1)       1101 SHL (A<<1)
// =====================================================================
module alu #(
    parameter DATA_WIDTH = 8
)(
    input  wire                    CLK,
    input  wire                    RST,     // active-low sync reset
    input  wire [DATA_WIDTH-1:0]   A,
    input  wire [DATA_WIDTH-1:0]   B,
    input  wire [3:0]              ALU_FUN,
    input  wire                    Enable,
    output reg  [DATA_WIDTH-1:0]   ALU_OUT,
    output reg                     OUT_VALID
);

    localparam ADD  = 4'b0000, SUB  = 4'b0001, MUL  = 4'b0010, DIVOP = 4'b0011,
               ANDOP= 4'b0100, OROP = 4'b0101, NAND = 4'b0110, NOR  = 4'b0111,
               XOROP= 4'b1000, XNOR = 4'b1001, CMPEQ= 4'b1010, CMPGT= 4'b1011,
               SHR  = 4'b1100, SHL  = 4'b1101;

    reg [2*DATA_WIDTH-1:0] mul_full;

    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            ALU_OUT   <= {DATA_WIDTH{1'b0}};
            OUT_VALID <= 1'b0;
        end else begin
            OUT_VALID <= 1'b0;
            if (Enable) begin
                OUT_VALID <= 1'b1;
                case (ALU_FUN)
                    ADD  : ALU_OUT <= A + B;
                    SUB  : ALU_OUT <= A - B;
                    MUL  : begin
                                mul_full = A * B;
                                ALU_OUT <= mul_full[DATA_WIDTH-1:0]; // low byte
                           end
                    DIVOP: ALU_OUT <= (B == 0) ? {DATA_WIDTH{1'b0}} : A / B;
                    ANDOP: ALU_OUT <= A & B;
                    OROP : ALU_OUT <= A | B;
                    NAND : ALU_OUT <= ~(A & B);
                    NOR  : ALU_OUT <= ~(A | B);
                    XOROP: ALU_OUT <= A ^ B;
                    XNOR : ALU_OUT <= ~(A ^ B);
                    CMPEQ: ALU_OUT <= (A == B) ? {{(DATA_WIDTH-1){1'b0}},1'b1} : {DATA_WIDTH{1'b0}};
                    CMPGT: ALU_OUT <= (A > B)  ? {{(DATA_WIDTH-1){1'b0}},1'b1} : {DATA_WIDTH{1'b0}};
                    SHR  : ALU_OUT <= A >> 1;
                    SHL  : ALU_OUT <= A << 1;
                    default: ALU_OUT <= {DATA_WIDTH{1'b0}};
                endcase
            end
        end
    end

endmodule
