module rrat
import rv32i_types::*;
#(
    parameter               ROB_DEPTH = 32
)(

    input   logic           clk,
    input   logic           rst,

    // Commit I/O
    input logic             rrat_wen,
    input logic [4:0]       rrat_rd_s,
    input logic [$clog2(ROB_DEPTH + 32)-1:0] rrat_p_addr,

    // Free list I/O
    output logic            rrat_kick,
    output logic [$clog2(ROB_DEPTH + 32)-1:0] rrat_kick_p_addr,
    output logic [$clog2(ROB_DEPTH + 32)-1:0] rrat_next[32]

);

logic [$clog2(ROB_DEPTH + 32)-1:0] rrat_data[32];

    always_ff @ (posedge clk) begin
        if(rst) begin
            for (integer i = 0; i < 32; i++) begin
                rrat_data[i] <= '0;
            end
        end
        else if (rrat_wen) rrat_data <= rrat_next;
    end

    always_comb begin
        rrat_next        = rrat_data;
        rrat_kick        = '0;
        rrat_kick_p_addr = 'x;

        // insert committed p_addr and kick out other to free list
        if(rrat_wen) begin //&& |rrat_rd_s
            rrat_kick            = '1;
            rrat_kick_p_addr     = rrat_data[rrat_rd_s];
            rrat_next[rrat_rd_s] = rrat_p_addr;
        end
    end

endmodule : rrat