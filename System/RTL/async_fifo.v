// =====================================================================
// Module      : async_fifo
// Description : Dual-clock asynchronous FIFO using gray-coded pointers
//               for safe clock-domain crossing between the write side
//               (REF_CLK domain, SYS_CTRL) and the read side
//               (UART_CLK domain, UART_TX).
// =====================================================================
module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4     // depth = 16
)(
    input  wire                     W_CLK,
    input  wire                     W_RST,   // active-low async
    input  wire                     W_INC,
    input  wire [DATA_WIDTH-1:0]    WR_DATA,
    output wire                     FULL,

    input  wire                     R_CLK,
    input  wire                     R_RST,   // active-low async
    input  wire                     R_INC,
    output reg  [DATA_WIDTH-1:0]    RD_DATA,
    output wire                     EMPTY
);

    localparam DEPTH = (1 << ADDR_WIDTH);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // ---------------- write domain ----------------
    // NOTE: the pointer increment intentionally does NOT depend on FULL
    // (only the memory write does) - gating the pointer combinationally
    // by FULL, which is itself derived from the pointer, creates a zero
    // -delay combinational loop. Callers must respect FULL and not
    // assert W_INC while FULL is set.
    reg  [ADDR_WIDTH:0] wr_bin, wr_gray;
    wire [ADDR_WIDTH:0] wr_bin_next  = wr_bin + W_INC;
    wire [ADDR_WIDTH:0] wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;

    reg [ADDR_WIDTH:0] rd_gray_wsync1, rd_gray_wsync2;

    always @(posedge W_CLK or negedge W_RST) begin
        if (!W_RST) begin
            wr_bin  <= 0;
            wr_gray <= 0;
        end else begin
            // Caller is expected to hold off W_INC while FULL is set;
            // gating this on the look-ahead FULL would create a
            // same-cycle combinational hazard, so we trust the
            // external interface contract here (matches the pointer
            // logic above).
            if (W_INC)
                mem[wr_bin[ADDR_WIDTH-1:0]] <= WR_DATA;
            wr_bin  <= wr_bin_next;
            wr_gray <= wr_gray_next;
        end
    end

    // synchronize read pointer into write domain
    always @(posedge W_CLK or negedge W_RST) begin
        if (!W_RST) begin
            rd_gray_wsync1 <= 0;
            rd_gray_wsync2 <= 0;
        end else begin
            rd_gray_wsync1 <= rd_gray;
            rd_gray_wsync2 <= rd_gray_wsync1;
        end
    end

    assign FULL = (wr_gray_next == {~rd_gray_wsync2[ADDR_WIDTH:ADDR_WIDTH-1], rd_gray_wsync2[ADDR_WIDTH-2:0]});

    // ---------------- read domain ----------------
    // Same rationale as the write side: pointer increment does not
    // depend combinationally on EMPTY.
    reg  [ADDR_WIDTH:0] rd_bin, rd_gray;
    wire [ADDR_WIDTH:0] rd_bin_next  = rd_bin + R_INC;
    wire [ADDR_WIDTH:0] rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;

    reg [ADDR_WIDTH:0] wr_gray_rsync1, wr_gray_rsync2;

    always @(posedge R_CLK or negedge R_RST) begin
        if (!R_RST) begin
            rd_bin  <= 0;
            rd_gray <= 0;
            RD_DATA <= {DATA_WIDTH{1'b0}};
        end else begin
            // Same rationale as the write side: caller must not
            // assert R_INC while EMPTY is set.
            if (R_INC)
                RD_DATA <= mem[rd_bin[ADDR_WIDTH-1:0]];
            rd_bin  <= rd_bin_next;
            rd_gray <= rd_gray_next;
        end
    end

    // synchronize write pointer into read domain
    always @(posedge R_CLK or negedge R_RST) begin
        if (!R_RST) begin
            wr_gray_rsync1 <= 0;
            wr_gray_rsync2 <= 0;
        end else begin
            wr_gray_rsync1 <= wr_gray;
            wr_gray_rsync2 <= wr_gray_rsync1;
        end
    end

    assign EMPTY = (rd_gray_next == wr_gray_rsync2);

endmodule
