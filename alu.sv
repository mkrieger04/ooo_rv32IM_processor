module alu
import rv32i_types::*;
(
    input rs_data_pkt_t          rs_input_pkt,
    input logic [31:0]           rs1_data,
    input logic [31:0]           rs2_data,

    output  logic [31:0]         rd_data
);

logic   [31:0]  a, b;
logic   [31:0]  aluout;
logic   [31:0]  comp_out;
logic   [31:0]  rd_v;

logic signed   [31:0] as;
logic signed   [31:0] bs;
logic unsigned [31:0] au;
logic unsigned [31:0] bu;

logic br_en;

always_comb begin
    case (rs_input_pkt.alu_op_sel.alu_m1_sel)
    rs1_out:
        a = rs1_data;
    pc_out:
        a = rs_input_pkt.pc;
    default:
        a = 'x;
    endcase
end

always_comb begin
    case (rs_input_pkt.alu_op_sel.alu_m2_sel)
    rs2_out:
        b = rs2_data;
    imm_out:
        b = rs_input_pkt.imm_data;
    default:
        b = 'x;
    endcase
end

assign as =   signed'(a);
assign bs =   signed'(b);
assign au = unsigned'(a);
assign bu = unsigned'(b);

always_comb begin
    unique case (rs_input_pkt.aluop)
        alu_op_add: aluout = au +   bu;
        alu_op_sll: aluout = au <<  bu[4:0];
        alu_op_sra: aluout = unsigned'(as >>> bu[4:0]);
        alu_op_sub: aluout = au -   bu;
        alu_op_xor: aluout = au ^   bu;
        alu_op_srl: aluout = au >>  bu[4:0];
        alu_op_or : aluout = au |   bu;
        alu_op_and: aluout = au &   bu;
        default   : aluout = 'x;
    endcase
end


always_comb begin
    unique case (rs_input_pkt.cmpop)
        branch_f3_beq : br_en = (au == bu);
        branch_f3_bne : br_en = (au != bu);
        branch_f3_blt : br_en = (as <  bs);
        branch_f3_bge : br_en = (as >=  bs); // CHANGED
        branch_f3_bltu: br_en = (au <  bu);
        branch_f3_bgeu: br_en = (au >=  bu); // CHANGED
        default       : br_en = 1'bx;
    endcase
end

assign comp_out = {31'd0, br_en};

always_comb begin
    if(rs_input_pkt.i_use_alu_cmpop) begin
        rd_data = comp_out;
    end
    else begin
        rd_data = aluout;
    end
end

endmodule