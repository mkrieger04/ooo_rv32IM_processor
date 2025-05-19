module store_tag_list
import rv32i_types::*;
#(
    parameter               TAG_DEPTH = 16
)(
    input   logic           clk,
    input   logic           rst,

    // WB
    input    logic   [$clog2(TAG_DEPTH)-1:0] wb_store_tag,
    input    logic   wb_store_tag_kick,

    // Dispatch/Rename I/O
    input    logic   stq_ren,

    output   logic   no_pending_stores,
    output   logic   all_pending_stores,
    output   logic   [$clog2(TAG_DEPTH)-1:0] free_store_tag,
    
    // ebr
    output   logic   [TAG_DEPTH - 1:0] store_tag_list_real,

    input    cdb_pkt_t cdb_pkt2,
    input   logic   [TAG_DEPTH - 1:0] br_store_tag_list
);

    logic   [TAG_DEPTH - 1:0]  store_tag_list;
    logic   [TAG_DEPTH - 1:0]  store_tag_list_next;

    // store_tag_list code
    assign store_tag_list_real = store_tag_list;

    always_ff @(posedge clk) begin
        if (rst) begin
            store_tag_list[TAG_DEPTH-1:0] <= '0;
        end 
        else if (cdb_pkt2.cdb_broadcast & cdb_pkt2.br_mispred) begin
            store_tag_list <= br_store_tag_list;
        end
        else begin
            store_tag_list <= store_tag_list_next;
        end
    end

    logic [$clog2(TAG_DEPTH)-1:0] next_open_store_tag;

    assign no_pending_stores = &(~store_tag_list);
    assign all_pending_stores = &store_tag_list;

    always_comb begin
        next_open_store_tag = '0;
        for(integer unsigned i = 0; i < unsigned'(TAG_DEPTH); i++) begin //signed to unsigne
            if(store_tag_list[i] == '0) begin
                next_open_store_tag = ($clog2(TAG_DEPTH))'(i); 
                break;
            end 
        end
        free_store_tag = next_open_store_tag;
    end
    
    always_comb begin
        store_tag_list_next = store_tag_list;
        if (wb_store_tag_kick) store_tag_list_next[wb_store_tag] = '0;
        if (stq_ren) store_tag_list_next[next_open_store_tag] = '1;
    end


endmodule : store_tag_list