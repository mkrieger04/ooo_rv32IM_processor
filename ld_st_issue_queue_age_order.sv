module ld_st_issue_queue_age_order
import rv32i_types::*;
#(
    parameter       QUEUE_DEPTH = 4
)(
    input   logic                             clk,
    input   logic                             rst,
    input   logic                             rs_station_wen,
    input   logic                             rs_station_complete,
    input   logic  [$clog2(QUEUE_DEPTH)-1:0]  rs_station_waddr,
    input   logic  [$clog2(QUEUE_DEPTH)-1:0]  rs_station_raddr,
    input   ld_st_data_pkt_t                  dispatch_rename_pkt_in,

    input   cdb_pkt_t                         cdb_pkt,
    input   cdb_pkt_t                         cdb_pkt2,
    input   st_tag_pkt_t                      st_tag_pkt,

    output  reg_addr_pkt_t                    rs_prf_reg_addr,
    output  reg_ren_pkt_t                     rs_prf_reg_ren_pkt,
    output  logic   [QUEUE_DEPTH-1:0]         rs_queue_valid_bits,
    output  logic   [QUEUE_DEPTH-1:0]         incoming_valid_bits,
    output  logic   [QUEUE_DEPTH-1:0]         rs_ready_bits,
    output  ld_st_data_pkt_t                  rs_pkt_out
);

localparam i_depth = $clog2(QUEUE_DEPTH);

ld_st_data_pkt_t entry_list[QUEUE_DEPTH];
ld_st_data_pkt_t entry_list_next[QUEUE_DEPTH];
logic bmask_misspred;

always_ff @(posedge clk) begin
    if (rst) for (integer i = 0; i < QUEUE_DEPTH; i++) entry_list[i] <= '0;
    else entry_list <= entry_list_next;
end

assign rs_pkt_out = entry_list[rs_station_raddr];

always_comb begin
    rs_ready_bits = '0;
    for(integer unsigned i = 0; i < QUEUE_DEPTH; i++) begin
        bmask_misspred = '0;

        if(cdb_pkt2.cdb_broadcast && entry_list[$clog2(QUEUE_DEPTH)'(i)].valid) begin
            if(cdb_pkt2.br_mispred && entry_list[$clog2(QUEUE_DEPTH)'(i)].bmask[cdb_pkt2.br_bit]) bmask_misspred = '1;
        end

        rs_ready_bits[$clog2(QUEUE_DEPTH)'(i)] = entry_list[$clog2(QUEUE_DEPTH)'(i)].valid && ~bmask_misspred &&
        (entry_list[$clog2(QUEUE_DEPTH)'(i)].rs1_rdy || (((cdb_pkt.cdb_p_addr == entry_list[$clog2(QUEUE_DEPTH)'(i)].rs1_paddr) 
        && entry_list[$clog2(QUEUE_DEPTH)'(i)].i_use_rs1) ||
        ((cdb_pkt2.cdb_p_addr == entry_list[$clog2(QUEUE_DEPTH)'(i)].rs1_paddr) 
        && entry_list[$clog2(QUEUE_DEPTH)'(i)].i_use_rs1)));
    end
end

always_comb begin
    entry_list_next = entry_list;
    rs_prf_reg_addr = '0;
    rs_prf_reg_ren_pkt = '0;

    if(rs_station_complete) begin
        entry_list_next[rs_station_raddr].valid = '0;
        if(entry_list[rs_station_raddr].i_use_rs1) begin
            rs_prf_reg_addr.rs1_paddr = entry_list[rs_station_raddr].rs1_paddr;
            rs_prf_reg_ren_pkt.prf_ren_rs1 = 1'b1;
        end
    end
    if(rs_station_wen) entry_list_next[rs_station_waddr] = dispatch_rename_pkt_in;
    for(integer unsigned i = 0; i < QUEUE_DEPTH; i++) begin
        if(cdb_pkt.cdb_broadcast && entry_list[$clog2(QUEUE_DEPTH)'(i)].valid) begin
            if((cdb_pkt.cdb_p_addr == entry_list[$clog2(QUEUE_DEPTH)'(i)].rs1_paddr) && entry_list[$clog2(QUEUE_DEPTH)'(i)].i_use_rs1) entry_list_next[$clog2(QUEUE_DEPTH)'(i)].rs1_rdy = '1;
        end
        if(cdb_pkt2.cdb_broadcast && entry_list[$clog2(QUEUE_DEPTH)'(i)].valid) begin
            if((cdb_pkt2.cdb_p_addr == entry_list[$clog2(QUEUE_DEPTH)'(i)].rs1_paddr) && entry_list[$clog2(QUEUE_DEPTH)'(i)].i_use_rs1) entry_list_next[$clog2(QUEUE_DEPTH)'(i)].rs1_rdy = '1;

            if(cdb_pkt2.br_mispred && entry_list[$clog2(QUEUE_DEPTH)'(i)].bmask[cdb_pkt2.br_bit]) begin
                entry_list_next[$clog2(QUEUE_DEPTH)'(i)].valid = '0;
            end
            else if (~cdb_pkt2.br_mispred) begin
                entry_list_next[$clog2(QUEUE_DEPTH)'(i)].bmask[cdb_pkt2.br_bit] = '0;
            end

        end
        if(st_tag_pkt.st_tag_broadcast && entry_list[$clog2(QUEUE_DEPTH)'(i)].valid && (st_tag_pkt.store_tag == entry_list[$clog2(QUEUE_DEPTH)'(i)].store_tag)) begin
            entry_list_next[$clog2(QUEUE_DEPTH)'(i)].store_tag_done = '1;
        end

        rs_queue_valid_bits[$clog2(QUEUE_DEPTH)'(i)] = entry_list[$clog2(QUEUE_DEPTH)'(i)].valid;
        incoming_valid_bits[$clog2(QUEUE_DEPTH)'(i)] = entry_list_next[$clog2(QUEUE_DEPTH)'(i)].valid;
    end
end

endmodule
