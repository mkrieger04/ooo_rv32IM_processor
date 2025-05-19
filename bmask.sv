module bmask
import rv32i_types::*;
#(
    parameter               BMASK_DEPTH = 4
)(
    input   logic           clk,
    input   logic           rst,

    // input off of cdb
    input   logic                           br_mispred,
    input   logic                           br_corpred,
    input   logic [BMASK_DEPTH-1:0]         br_bmask,
    input   logic [$clog2(BMASK_DEPTH)-1:0] br_bit,


    // Dispatch/Rename I/O
    input    logic   bmask_ren,

    output   logic   [$clog2(BMASK_DEPTH)-1:0] free_bmask_bit,
    output   logic   bmask_stall,

    output   logic [BMASK_DEPTH-1:0]  bmask_list_val
);

    logic   [BMASK_DEPTH-1:0]  bmask_list;
    logic   [BMASK_DEPTH-1:0]  bmask_list_next;    

    assign bmask_list_val = bmask_list;
    assign bmask_stall = &bmask_list;

    always_ff @(posedge clk) begin
        if (rst) begin
            bmask_list[BMASK_DEPTH-1:0] <= '0;
        end 
        else bmask_list <= bmask_list_next;
    end

    logic [$clog2(BMASK_DEPTH)-1:0] next_open_bit;


    always_comb begin
        next_open_bit = '0;
        for(integer unsigned i = 0; i < unsigned'(BMASK_DEPTH); i++) begin //signed to unsigne
            if(bmask_list[i] == '0) begin
                next_open_bit = ($clog2(BMASK_DEPTH))'(i); 
                break;
            end 
        end
        free_bmask_bit = next_open_bit;
    end
    
    always_comb begin
        bmask_list_next = bmask_list;
        if (br_mispred) begin
            bmask_list_next = br_bmask;
        end
        else if(br_corpred) begin
            bmask_list_next[br_bit] = '0;
            if(bmask_ren) bmask_list_next[next_open_bit] = '1;
        end
        else if (bmask_ren) bmask_list_next[next_open_bit] = '1;
    end


endmodule