module writeback
import rv32i_types::*;
(
    input   wb_pkt_t       alu_wb_pkt,
    input   wb_pkt_t       mul_wb_pkt,
    input   wb_pkt_t       div_wb_pkt,
    input   wb_pkt_t       br_wb_pkt,
    input   wb_pkt_t       load_wb_pkt,

    output  stall_pkt_t    wb_unit_stalls,

    output  cdb_pkt_t      cdb_pkt,
    output  cdb_pkt_t      cdb_pkt2
);

always_comb begin
    cdb_pkt.br_en               = '0;
    cdb_pkt.cdb_broadcast       = '0;
    cdb_pkt.cdb_p_addr          = '0;
    cdb_pkt.cdb_aaddr           = '0;
    cdb_pkt.cdb_rd              = '0;
    cdb_pkt.cdb_rob_idx         = 'x;
    cdb_pkt.rvfi_pkt            = 'x;
    cdb_pkt.pc_next             = '0;
    cdb_pkt.br_mispred          = '0;
    cdb_pkt.br_bmask            = '0; // need to set
    cdb_pkt.br_bit              = '0;
    cdb_pkt.prediction          = '0;
    cdb_pkt.pht_index           = '0;
    cdb_pkt.is_branch           = '0;

    cdb_pkt2.br_en               = '0;
    cdb_pkt2.cdb_broadcast       = '0;
    cdb_pkt2.cdb_p_addr          = '0;
    cdb_pkt2.cdb_aaddr           = '0;
    cdb_pkt2.cdb_rd              = '0;
    cdb_pkt2.cdb_rob_idx         = 'x;
    cdb_pkt2.rvfi_pkt            = 'x;
    cdb_pkt2.pc_next             = '0;
    cdb_pkt2.br_mispred          = '0;
    cdb_pkt2.br_bmask            = '0; 
    cdb_pkt2.br_bit              = '0;
    cdb_pkt2.prediction          = '0;
    cdb_pkt2.pht_index           = '0;
    cdb_pkt2.is_branch           = '0;

    wb_unit_stalls.alu_stall                = '0;
    wb_unit_stalls.mul_stall                = '0;
    wb_unit_stalls.div_stall                = '0;
    wb_unit_stalls.br_stall                 = '0;

    if(br_wb_pkt.valid) begin
        cdb_pkt2.cdb_broadcast   = 1'b1;
        cdb_pkt2.cdb_p_addr      = br_wb_pkt.rd_paddr;
        cdb_pkt2.cdb_aaddr       = br_wb_pkt.rd_aaddr;
        cdb_pkt2.cdb_rd          = br_wb_pkt.rd_aaddr != '0 ? br_wb_pkt.rd_data : '0;
        cdb_pkt2.cdb_rob_idx     = br_wb_pkt.rob_idx;
        cdb_pkt2.rvfi_pkt        = br_wb_pkt.rvfi_pkt;
        cdb_pkt2.pc_next         = br_wb_pkt.pc_next;
        cdb_pkt2.br_en           = br_wb_pkt.br_en;
        cdb_pkt2.br_mispred      = br_wb_pkt.br_mispred;
        cdb_pkt2.prediction      = br_wb_pkt.prediction;
        cdb_pkt2.pht_index       = br_wb_pkt.pht_index;
        cdb_pkt2.br_bmask        = br_wb_pkt.br_bmask;
        cdb_pkt2.br_bit          = br_wb_pkt.br_bit;
        cdb_pkt2.is_branch       = br_wb_pkt.is_branch;
    end

    if(load_wb_pkt.valid) begin
        cdb_pkt.cdb_broadcast             = 1'b1;
        cdb_pkt.cdb_p_addr                = load_wb_pkt.rd_paddr;
        cdb_pkt.cdb_aaddr                 = load_wb_pkt.rd_aaddr;
        cdb_pkt.cdb_rd                    = load_wb_pkt.rd_aaddr != '0 ? load_wb_pkt.rd_data : '0;
        cdb_pkt.cdb_rob_idx               = load_wb_pkt.rob_idx;
        cdb_pkt.rvfi_pkt                  = load_wb_pkt.rvfi_pkt;
        cdb_pkt.pc_next                   = load_wb_pkt.pc_next;
        cdb_pkt.br_en                     = load_wb_pkt.br_en;
        cdb_pkt.rvfi_pkt.monitor_rd_wdata = load_wb_pkt.rd_aaddr != '0 ? load_wb_pkt.rd_data : '0;
        cdb_pkt.br_bmask                  = load_wb_pkt.br_bmask;

        wb_unit_stalls.alu_stall = alu_wb_pkt.valid;
        wb_unit_stalls.mul_stall = mul_wb_pkt.valid;
        wb_unit_stalls.div_stall = div_wb_pkt.valid;
    end
    else if(div_wb_pkt.valid) begin
        cdb_pkt.cdb_broadcast   = 1'b1;
        cdb_pkt.cdb_p_addr      = div_wb_pkt.rd_paddr;
        cdb_pkt.cdb_aaddr       = div_wb_pkt.rd_aaddr;
        cdb_pkt.cdb_rd          = div_wb_pkt.rd_aaddr != '0 ? div_wb_pkt.rd_data : '0;
        cdb_pkt.cdb_rob_idx     = div_wb_pkt.rob_idx;
        cdb_pkt.rvfi_pkt        = div_wb_pkt.rvfi_pkt;
        cdb_pkt.br_bmask        = div_wb_pkt.br_bmask;

        wb_unit_stalls.alu_stall = alu_wb_pkt.valid;
        wb_unit_stalls.mul_stall = mul_wb_pkt.valid;
    end
    else if(mul_wb_pkt.valid) begin
        cdb_pkt.cdb_broadcast   = 1'b1;
        cdb_pkt.cdb_p_addr      = mul_wb_pkt.rd_paddr;
        cdb_pkt.cdb_aaddr       = mul_wb_pkt.rd_aaddr;
        cdb_pkt.cdb_rd          = mul_wb_pkt.rd_aaddr != '0 ? mul_wb_pkt.rd_data : '0;
        cdb_pkt.cdb_rob_idx     = mul_wb_pkt.rob_idx;
        cdb_pkt.rvfi_pkt        = mul_wb_pkt.rvfi_pkt;
        cdb_pkt.br_bmask        = mul_wb_pkt.br_bmask;

        wb_unit_stalls.alu_stall = alu_wb_pkt.valid;
    end
    else if(alu_wb_pkt.valid) begin
        cdb_pkt.cdb_broadcast   = 1'b1;
        cdb_pkt.cdb_p_addr      = alu_wb_pkt.rd_paddr;
        cdb_pkt.cdb_aaddr       = alu_wb_pkt.rd_aaddr;
        cdb_pkt.cdb_rd          = alu_wb_pkt.rd_aaddr != '0 ? alu_wb_pkt.rd_data : '0;
        cdb_pkt.cdb_rob_idx     = alu_wb_pkt.rob_idx;
        cdb_pkt.rvfi_pkt        = alu_wb_pkt.rvfi_pkt;
        cdb_pkt.br_bmask        = alu_wb_pkt.br_bmask;
    end
end


endmodule




