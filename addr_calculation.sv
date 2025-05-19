module addr_calculation
import rv32i_types::*;
(
    input   ld_st_data_pkt_t             input_packet,
    input   logic [31:0]                 rs1_data,
    input   logic [31:0]                 rs2_data,
    input   st_tag_pkt_t                 st_tag_pkt,
    input   cdb_pkt_t                    cdb_pkt2,

    output  mem_pkt_t                    output_packet

);

always_comb begin
    output_packet            = '0;
    output_packet.rvfi_pkt   = input_packet.rvfi_pkt;

    output_packet.rvfi_pkt.monitor_rs1_rdata = input_packet.i_use_rs1 ? rs1_data : '0;
    output_packet.rvfi_pkt.monitor_rs2_rdata = input_packet.i_use_rs2 ? rs2_data : '0;
 
    output_packet.mem_funct3  = input_packet.mem_funct3;
    output_packet.rob_idx     = input_packet.rob_idx;
    output_packet.rd_paddr    = input_packet.rd_paddr;
    output_packet.rd_aaddr    = input_packet.rd_addr;
    output_packet.i_use_store = input_packet.i_use_store;
    output_packet.store_tag   = input_packet.store_tag;
    output_packet.bmask       = input_packet.bmask;

    if (input_packet.valid) begin
        output_packet.valid     = '1;

        if(cdb_pkt2.cdb_broadcast && cdb_pkt2.br_mispred && input_packet.bmask[cdb_pkt2.br_bit]) output_packet.valid = '0;
        else if (cdb_pkt2.cdb_broadcast && ~cdb_pkt2.br_mispred) output_packet.bmask[cdb_pkt2.br_bit] = '0;

        output_packet.mem_addr  = input_packet.imm_data + rs1_data;
        output_packet.store_tag = input_packet.store_tag;

        output_packet.store_tag_done = (st_tag_pkt.st_tag_broadcast && (st_tag_pkt.store_tag == input_packet.store_tag)) ? '1 : input_packet.store_tag_done;

        unique case (input_packet.mem_funct3)
            store_f3_sb, load_f3_lbu: begin
                output_packet.dmem_mask = 4'b0001 << output_packet.mem_addr[1:0];
                output_packet.mem_wdata[8 *output_packet.mem_addr[1:0] +: 8 ] = rs2_data[7 :0];
            end
            store_f3_sh, load_f3_lhu: begin
                output_packet.dmem_mask = 4'b0011 << output_packet.mem_addr[1:0];
                output_packet.mem_wdata[16*output_packet.mem_addr[1]   +: 16] = rs2_data[15:0];
            end
            store_f3_sw: begin
                output_packet.dmem_mask = 4'b1111;
                output_packet.mem_wdata = rs2_data;
            end
            default    : begin
                output_packet.dmem_mask = '0;
                output_packet.mem_wdata = '0;
            end
        endcase
        // output_packet.mem_addr[1:0] = 2'd0;
    end
end


endmodule : addr_calculation