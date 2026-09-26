// =====================================================================
// Module      : regfile
// Description : General purpose register file.
//   NOTE (design assumption): the spec calls out normal R/W addresses
//   from 0x4 to 0x15 which needs 5 address bits, so ADDR_WIDTH default
//   is set to 5 (32 locations) rather than the 4 bits mentioned in the
//   interface table.
//
//   Reserved locations:
//     0x0 REG0 -> ALU Operand A
//     0x1 REG1 -> ALU Operand B
//     0x2 REG2 -> UART config : [0]=PAR_EN(default 1) [1]=PAR_TYP(default 0)
//                                [7:2]=Prescale (default 32)
//     0x3 REG3 -> Clock divider ratio (default 32)
// =====================================================================
module regfile #(
    parameter ADDR_WIDTH = 5,
    parameter DATA_WIDTH = 8
)(
    input  wire                     CLK,
    input  wire                     RST,          // active-low, synchronized
    input  wire [ADDR_WIDTH-1:0]    Address,
    input  wire                     WrEn,
    input  wire                     RdEn,
    input  wire [DATA_WIDTH-1:0]    WrData,
    output reg  [DATA_WIDTH-1:0]    RdData,
    output reg                      RdData_Valid,
    output wire [DATA_WIDTH-1:0]    REG0,
    output wire [DATA_WIDTH-1:0]    REG1,
    output wire [DATA_WIDTH-1:0]    REG2,
    output wire [DATA_WIDTH-1:0]    REG3
);

    localparam DEPTH = (1 << ADDR_WIDTH);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    integer i;

    localparam [DATA_WIDTH-1:0] REG2_DEFAULT = {6'd32, 1'b0, 1'b1}; // prescale=32,type=0,en=1
    localparam [DATA_WIDTH-1:0] REG3_DEFAULT = 8'd32;               // div ratio = 32

    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            for (i = 0; i < DEPTH; i = i + 1)
                mem[i] <= {DATA_WIDTH{1'b0}};
            mem[2]       <= REG2_DEFAULT;
            mem[3]       <= REG3_DEFAULT;
            RdData       <= {DATA_WIDTH{1'b0}};
            RdData_Valid <= 1'b0;
        end else begin
            RdData_Valid <= 1'b0;
            if (WrEn)
                mem[Address] <= WrData;
            if (RdEn) begin
                RdData       <= mem[Address];
                RdData_Valid <= 1'b1;
            end
        end
    end

    assign REG0 = mem[0];
    assign REG1 = mem[1];
    assign REG2 = mem[2];
    assign REG3 = mem[3];

endmodule
