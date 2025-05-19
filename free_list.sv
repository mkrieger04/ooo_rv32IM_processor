module free_list
import rv32i_types::*;
#(
    parameter               ROB_DEPTH = 32
)(
    input   logic           clk,
    input   logic           rst,

    // RRAT I/O
    input    logic   [$clog2(ROB_DEPTH + 32)-1:0] rrat_kick_p_addr,
    input    logic   rrat_kick,

    // Dispatch/Rename I/O
    input    logic   dispatch_ren,

    output   logic   [$clog2(ROB_DEPTH + 32)-1:0] free_p_addr,

    // Commit I/O
    // input logic rrat_wen,
    // input logic br_en,
    // input logic [$clog2(ROB_DEPTH+32)-1:0] rrat_p_addr,

    // ebr
    input logic [ROB_DEPTH + 31:0]  br_free_list, 
    input  cdb_pkt_t                  cdb_pkt2,
    output logic [ROB_DEPTH + 31:0] free_listdata 
);

    logic   [ROB_DEPTH + 31:0]  free_list;
    logic   [ROB_DEPTH + 31:0]  free_list_next;
    assign free_listdata = free_list;

    // logic   [ROB_DEPTH + 31:0]  retired_free_list;
    // logic   [ROB_DEPTH + 31:0]  retired_free_list_next;    

    // // retired free_list
    // always_ff @(posedge clk) begin
    //     if (rst) begin
    //         retired_free_list[ROB_DEPTH + 31:1] <= '0;
    //         retired_free_list[0] <= '1;
    //     end 
    //     else retired_free_list <= retired_free_list_next;
    // end

    // always_comb begin
    //     retired_free_list_next = retired_free_list;
    //     if (rrat_kick && |rrat_kick_p_addr) retired_free_list_next[rrat_kick_p_addr] = '0; //&& |rrat_kick_p_addr
    //     if (rrat_wen) retired_free_list_next[rrat_p_addr] = '1;
    // end


    // free_list code

    always_ff @(posedge clk) begin
        if (rst) begin
            free_list[ROB_DEPTH + 31:1] <= '0;
            free_list[0] <= '1;
        end 
        else if (cdb_pkt2.br_mispred & cdb_pkt2.cdb_broadcast) begin
            free_list <= br_free_list;
        end
        else begin
            free_list <= free_list_next;
        end
    end

    logic [$clog2(ROB_DEPTH + 32)-1:0] next_open_p_addr;
    // assign free_p_addr = next_open_p_addr;

    always_comb begin
        next_open_p_addr = '0;
        for(integer unsigned i = 1; i < unsigned'(ROB_DEPTH + 32); i++) begin //signed to unsigne
            if(free_list[i] == '0) begin
                next_open_p_addr = ($clog2(ROB_DEPTH + 32))'(i); 
                break;
            end 
        end
        free_p_addr = next_open_p_addr;
    end
    
    always_comb begin
        free_list_next = free_list;
        if (rrat_kick && |rrat_kick_p_addr) free_list_next[rrat_kick_p_addr] = '0;   //can maybe remove && |rrat_kick_p_addr
        if (dispatch_ren) free_list_next[next_open_p_addr] = '1;
    end


endmodule : free_list