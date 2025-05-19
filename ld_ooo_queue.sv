module ld_ooo_queue
import rv32i_types::*;
#(
    parameter       QUEUE_DEPTH = 4
)(
    input   logic                             clk,
    input   logic                             rst,
    input   logic                             ld_ooo_queue_wen,
    input   logic                             ld_ooo_queue_complete,
    input   logic  [$clog2(QUEUE_DEPTH)-1:0]  ld_ooo_queue_waddr,
    input   logic  [$clog2(QUEUE_DEPTH)-1:0]  ld_ooo_queue_raddr,
    input   mem_pkt_t                         ld_ooo_queue_pkt_in,
    input   st_tag_pkt_t                      st_tag_pkt,
    input   cdb_pkt_t                         cdb_pkt2,


    output  logic   [QUEUE_DEPTH-1:0]         ld_ooo_queue_valid_bits,
    output  logic   [QUEUE_DEPTH-1:0]         ld_ooo_queue_ready_bits,
    output  mem_pkt_t                         ld_pkt_rdy_for_op
);

localparam i_depth = $clog2(QUEUE_DEPTH);

mem_pkt_t entry_list[QUEUE_DEPTH];
mem_pkt_t entry_list_next[QUEUE_DEPTH];
logic bmask_misspred;

always_ff @(posedge clk) begin
    if (rst) for (integer i = 0; i < QUEUE_DEPTH; i++) entry_list[i] <= '0;
    else entry_list <= entry_list_next;
end

// assign ld_pkt_rdy_for_op = entry_list[ld_ooo_queue_raddr];
always_comb begin
    ld_pkt_rdy_for_op = entry_list[ld_ooo_queue_raddr];

    // if(st_tag_pkt.st_tag_broadcast && ld_pkt_rdy_for_op.valid && (st_tag_pkt.store_tag == ld_pkt_rdy_for_op.store_tag)) begin
    //     ld_pkt_rdy_for_op.store_tag_done = '1;
    // end

    if(cdb_pkt2.cdb_broadcast && cdb_pkt2.br_mispred && entry_list[ld_ooo_queue_raddr].bmask[cdb_pkt2.br_bit]) ld_pkt_rdy_for_op.valid = '0;
    else if (cdb_pkt2.cdb_broadcast && ~cdb_pkt2.br_mispred) ld_pkt_rdy_for_op.bmask[cdb_pkt2.br_bit] = '0;
end

always_comb begin
    ld_ooo_queue_ready_bits = '0;

    for(integer unsigned i = 0; i < QUEUE_DEPTH; i++) begin
        bmask_misspred = '0;
        if(cdb_pkt2.cdb_broadcast && entry_list[$clog2(QUEUE_DEPTH)'(i)].valid) begin
            if(cdb_pkt2.br_mispred && entry_list[$clog2(QUEUE_DEPTH)'(i)].bmask[cdb_pkt2.br_bit]) bmask_misspred = '1;
        end

        ld_ooo_queue_ready_bits[$clog2(QUEUE_DEPTH)'(i)] = 
        entry_list[$clog2(QUEUE_DEPTH)'(i)].valid && ~bmask_misspred && entry_list[$clog2(QUEUE_DEPTH)'(i)].store_tag_done;
    end
end

always_comb begin
    entry_list_next = entry_list;

    if(ld_ooo_queue_complete) entry_list_next[ld_ooo_queue_raddr].valid = '0;

    if(ld_ooo_queue_wen) entry_list_next[ld_ooo_queue_waddr] = ld_ooo_queue_pkt_in;
    for(integer unsigned i = 0; i < QUEUE_DEPTH; i++) begin
        if(st_tag_pkt.st_tag_broadcast && entry_list[$clog2(QUEUE_DEPTH)'(i)].valid && (st_tag_pkt.store_tag == entry_list[$clog2(QUEUE_DEPTH)'(i)].store_tag)) begin
            entry_list_next[$clog2(QUEUE_DEPTH)'(i)].store_tag_done = '1;
        end
        if(cdb_pkt2.cdb_broadcast && entry_list[$clog2(QUEUE_DEPTH)'(i)].valid) begin
            if(cdb_pkt2.br_mispred && entry_list[$clog2(QUEUE_DEPTH)'(i)].bmask[cdb_pkt2.br_bit]) begin
                entry_list_next[$clog2(QUEUE_DEPTH)'(i)].valid = '0;
            end
            else if (~cdb_pkt2.br_mispred) begin
                entry_list_next[$clog2(QUEUE_DEPTH)'(i)].bmask[cdb_pkt2.br_bit] = '0;
            end
        end

        ld_ooo_queue_valid_bits[$clog2(QUEUE_DEPTH)'(i)] = entry_list[$clog2(QUEUE_DEPTH)'(i)].valid;
    end
end

endmodule
