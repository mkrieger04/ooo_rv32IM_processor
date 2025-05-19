module prf
import rv32i_types::*;
#(
    parameter       PRF_DEPTH = 96
)(
    input   logic           clk,
    input   logic           rst,

    input   cdb_pkt_t       cdb_pkt,
    input   cdb_pkt_t       cdb_pkt2,

    input  reg_addr_pkt_t   alu_prf_reg_addr,
    input  reg_addr_pkt_t   mul_prf_reg_addr,
    input  reg_addr_pkt_t   div_prf_reg_addr,
    input  reg_addr_pkt_t   br_prf_reg_addr,
    input  reg_addr_pkt_t   ld_prf_reg_addr,
    input  reg_addr_pkt_t   st_prf_reg_addr,

    input  reg_ren_pkt_t    alu_prf_reg_ren_pkt,
    input  reg_ren_pkt_t    mul_prf_reg_ren_pkt,
    input  reg_ren_pkt_t    div_prf_reg_ren_pkt,
    input  reg_ren_pkt_t    br_prf_reg_ren_pkt,
    input  reg_ren_pkt_t    ld_prf_reg_ren_pkt,
    input  reg_ren_pkt_t    st_prf_reg_ren_pkt,


    output reg_data_pkt_t   alu_prf_reg_data,
    output reg_data_pkt_t   mul_prf_reg_data,
    output reg_data_pkt_t   div_prf_reg_data,
    output reg_data_pkt_t   br_prf_reg_data,
    output reg_data_pkt_t   ld_prf_reg_data,
    output reg_data_pkt_t   st_prf_reg_data
);

    logic   [31:0]  prf_data [PRF_DEPTH];

    always_ff @(posedge clk) begin
        if (rst) begin
            for (integer i = 0; i < PRF_DEPTH; i++) begin
                prf_data[i] <= '0;
            end
        end else begin
            if (cdb_pkt.cdb_broadcast && (cdb_pkt.cdb_aaddr != '0)) begin
                prf_data[cdb_pkt.cdb_p_addr] <= cdb_pkt.cdb_rd;
            end
            if (cdb_pkt2.cdb_broadcast && (cdb_pkt2.cdb_aaddr != '0)) begin
                prf_data[cdb_pkt2.cdb_p_addr] <= cdb_pkt2.cdb_rd;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            alu_prf_reg_data <= '0;
            mul_prf_reg_data <= '0;
            div_prf_reg_data <= '0;
            br_prf_reg_data <= '0;
            ld_prf_reg_data <= '0;
        end else begin
            if (alu_prf_reg_ren_pkt.prf_ren_rs1)
                alu_prf_reg_data.rs1_data <= (alu_prf_reg_addr.rs1_paddr != '0) ? prf_data[alu_prf_reg_addr.rs1_paddr] : '0;
            if (alu_prf_reg_ren_pkt.prf_ren_rs2)
                alu_prf_reg_data.rs2_data <= (alu_prf_reg_addr.rs2_paddr != '0) ? prf_data[alu_prf_reg_addr.rs2_paddr] : '0;

            if (mul_prf_reg_ren_pkt.prf_ren_rs1)
                mul_prf_reg_data.rs1_data <= (mul_prf_reg_addr.rs1_paddr != '0) ? prf_data[mul_prf_reg_addr.rs1_paddr] : '0;
            if (mul_prf_reg_ren_pkt.prf_ren_rs2)
                mul_prf_reg_data.rs2_data <= (mul_prf_reg_addr.rs2_paddr != '0) ? prf_data[mul_prf_reg_addr.rs2_paddr] : '0;

            if (div_prf_reg_ren_pkt.prf_ren_rs1)
                div_prf_reg_data.rs1_data <= (div_prf_reg_addr.rs1_paddr != '0) ? prf_data[div_prf_reg_addr.rs1_paddr] : '0;
            if (div_prf_reg_ren_pkt.prf_ren_rs2)
                div_prf_reg_data.rs2_data <= (div_prf_reg_addr.rs2_paddr != '0) ? prf_data[div_prf_reg_addr.rs2_paddr] : '0;

            if (br_prf_reg_ren_pkt.prf_ren_rs1)
                br_prf_reg_data.rs1_data <= (br_prf_reg_addr.rs1_paddr != '0)   ? prf_data[br_prf_reg_addr.rs1_paddr] : '0;
            if (br_prf_reg_ren_pkt.prf_ren_rs2)
                br_prf_reg_data.rs2_data <= (br_prf_reg_addr.rs2_paddr != '0)   ? prf_data[br_prf_reg_addr.rs2_paddr] : '0;

            if (ld_prf_reg_ren_pkt.prf_ren_rs1)
                ld_prf_reg_data.rs1_data <= (ld_prf_reg_addr.rs1_paddr != '0)   ? prf_data[ld_prf_reg_addr.rs1_paddr] : '0;
            if (ld_prf_reg_ren_pkt.prf_ren_rs2)
                ld_prf_reg_data.rs2_data <= (ld_prf_reg_addr.rs2_paddr != '0)   ? prf_data[ld_prf_reg_addr.rs2_paddr] : '0;
                
            if (st_prf_reg_ren_pkt.prf_ren_rs1)
                st_prf_reg_data.rs1_data <= (st_prf_reg_addr.rs1_paddr != '0)   ? prf_data[st_prf_reg_addr.rs1_paddr] : '0;
            if (st_prf_reg_ren_pkt.prf_ren_rs2)
                st_prf_reg_data.rs2_data <= (st_prf_reg_addr.rs2_paddr != '0)   ? prf_data[st_prf_reg_addr.rs2_paddr] : '0;
        end
    end

endmodule : prf


