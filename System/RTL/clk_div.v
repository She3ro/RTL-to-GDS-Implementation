// =====================================================================
// Module      : clk_div
// Description : Programmable clock divider. Produces O_div_clk which
//               toggles once every i_div_ratio input-clock cycles
//               (i.e. output period = 2 * i_div_ratio input periods).
//               i_div_ratio = 0 or 1 is treated as divide-by-2 minimum
//               to avoid a div-by-zero lockup.
// =====================================================================
module clk_div #(
    parameter RATIO_WIDTH = 8
)(
    input  wire                     i_ref_clk,
    input  wire                     i_rst_n,     // active-low async reset
    input  wire                     i_clk_en,
    input  wire [RATIO_WIDTH-1:0]   i_div_ratio,
    output reg                      o_div_clk
);

    reg [RATIO_WIDTH-1:0] count;
    wire [RATIO_WIDTH-1:0] ratio_safe = (i_div_ratio < 2) ? {{(RATIO_WIDTH-1){1'b0}},1'b1} : i_div_ratio;

    initial o_div_clk = 1'b0;

    always @(posedge i_ref_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            count     <= {RATIO_WIDTH{1'b0}};
            o_div_clk <= 1'b0;
        end else if (i_clk_en) begin
            if (count >= ratio_safe - 1'b1) begin
                count     <= {RATIO_WIDTH{1'b0}};
                o_div_clk <= ~o_div_clk;
            end else begin
                count <= count + 1'b1;
            end
        end
    end

endmodule
