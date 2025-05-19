module decode
import rv32i_types::*;
(
    input   fetch_pkt_t  instruction_queue_pkt_in,
    input   logic        fifo_empty_instruction_queue,     

    output  decode_pkt_t decode_pkt_out
);
    logic   [31:0]  inst;
    logic           fetch_stage_valid;
    logic   [2:0]   funct3;
    logic   [6:0]   funct7;
    logic   [6:0]   opcode;
    logic   [31:0]  i_imm;
    logic   [4:0]   rd_s, rs1_s, rs2_s;
    logic   [31:0]  s_imm;
    logic   [31:0]  b_imm;
    logic   [31:0]  u_imm;
    logic   [31:0]  j_imm;

    logic   [2:0]   cmpop;

    assign inst   = instruction_queue_pkt_in.inst;
    assign fetch_stage_valid =  instruction_queue_pkt_in.valid && !fifo_empty_instruction_queue;
    assign funct3 = inst[14:12];
    assign funct7 = inst[31:25];
    assign opcode = inst[6:0];
    assign i_imm  = {{21{inst[31]}}, inst[30:20]};
    assign s_imm  = {{21{inst[31]}}, inst[30:25], inst[11:7]};
    assign b_imm  = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
    assign u_imm  = {inst[31:12], 12'h000};
    assign j_imm  = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
    assign rs1_s  = inst[19:15];
    assign rs2_s  = inst[24:20];
    assign rd_s   = inst[11:7];

always_comb begin
    decode_pkt_out.instr_pkt = '0;
    decode_pkt_out.rvfi_pkt  = '0; 
    decode_pkt_out.instr_pkt.prediction = instruction_queue_pkt_in.prediction;
    decode_pkt_out.instr_pkt.pht_index  = instruction_queue_pkt_in.pht_index;

    // Propagating signals
    decode_pkt_out.instr_pkt.pc              = instruction_queue_pkt_in.pc;
    decode_pkt_out.instr_pkt.pc_next         = instruction_queue_pkt_in.pc_next; 
    decode_pkt_out.rvfi_pkt.monitor_order    = instruction_queue_pkt_in.order;
    decode_pkt_out.instr_pkt.i_valid         = fetch_stage_valid;

    decode_pkt_out.rvfi_pkt.monitor_valid    = fetch_stage_valid;
    decode_pkt_out.rvfi_pkt.monitor_inst     = inst;
    decode_pkt_out.rvfi_pkt.monitor_pc_rdata = instruction_queue_pkt_in.pc;
    decode_pkt_out.rvfi_pkt.monitor_pc_wdata = instruction_queue_pkt_in.pc + 4;

    decode_pkt_out.instr_pkt.mem_funct3      = funct3;
    decode_pkt_out.instr_pkt.pc_pred         = instruction_queue_pkt_in.pc_pred;
    decode_pkt_out.instr_pkt.ras_top         = instruction_queue_pkt_in.ras_top;
    decode_pkt_out.instr_pkt.stack_ptr_val   = instruction_queue_pkt_in.stack_ptr_val;

    // decode_pkt_out.instr_pkt.rs1_addr        = fetch_stage_valid ? rs1_s : '0;
    // decode_pkt_out.instr_pkt.rs2_addr        = fetch_stage_valid ? rs2_s : '0;
    // decode_pkt_out.instr_pkt.rd_addr         = rd_s;

    unique case (opcode)
        op_b_lui  : begin
            decode_pkt_out.instr_pkt.op_bits                =  op_bits_t'(i_use_alu);
            decode_pkt_out.instr_pkt.alu_op_sel.alu_m1_sel  =  alu_m1_sel_t'(rs1_out);                //rd_v = pc + u_imm;
            decode_pkt_out.instr_pkt.alu_op_sel.alu_m2_sel  =  alu_m2_sel_t'(imm_out);
            decode_pkt_out.instr_pkt.aluop                  =  alu_ops'(alu_op_add);
            decode_pkt_out.instr_pkt.i_use_rs1              =  '1;
            decode_pkt_out.instr_pkt.imm_data               =  u_imm;
            decode_pkt_out.instr_pkt.rs1_addr               =  '0;
            decode_pkt_out.instr_pkt.rd_addr                =  rd_s;

            decode_pkt_out.rvfi_pkt.monitor_rd_addr  = rd_s;
        end
        op_b_auipc : begin
            decode_pkt_out.instr_pkt.op_bits                =  op_bits_t'(i_use_alu);
            decode_pkt_out.instr_pkt.alu_op_sel.alu_m1_sel  =  alu_m1_sel_t'(pc_out);                //rd_v = pc + u_imm;
            decode_pkt_out.instr_pkt.alu_op_sel.alu_m2_sel  =  alu_m2_sel_t'(imm_out);
            decode_pkt_out.instr_pkt.aluop                  =  alu_ops'(alu_op_add);
            decode_pkt_out.instr_pkt.imm_data               =  u_imm;
            decode_pkt_out.instr_pkt.rd_addr                =  rd_s;
            
            decode_pkt_out.rvfi_pkt.monitor_rd_addr  = rd_s;
        end
        op_b_imm  : begin        
            decode_pkt_out.instr_pkt.i_use_rs1                                  = 1'b1;
            decode_pkt_out.instr_pkt.imm_data                                   = i_imm;

            decode_pkt_out.instr_pkt.rs1_addr        = rs1_s;
            decode_pkt_out.instr_pkt.rd_addr         = rd_s;

            decode_pkt_out.rvfi_pkt.monitor_rs1_addr = rs1_s;
            decode_pkt_out.rvfi_pkt.monitor_rd_addr  = rd_s;
                unique case (funct3)
                    arith_f3_slt: begin
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m1_sel      = alu_m1_sel_t'(rs1_out);
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m2_sel      = alu_m2_sel_t'(imm_out);
                        decode_pkt_out.instr_pkt.op_bits                    = op_bits_t'(i_use_cmpop);
                        decode_pkt_out.instr_pkt.cmpop                      = branch_f3_blt;
                    end
                    arith_f3_sltu: begin
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m1_sel         = alu_m1_sel_t'(rs1_out);
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m2_sel         = alu_m2_sel_t'(imm_out);
                        decode_pkt_out.instr_pkt.op_bits                        = op_bits_t'(i_use_cmpop);
                        decode_pkt_out.instr_pkt.cmpop                          = branch_f3_bltu;
                    end
                    arith_f3_sr: begin
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m1_sel          = alu_m1_sel_t'(rs1_out);
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m2_sel          = alu_m2_sel_t'(imm_out);
                        if (funct7[5]) begin
                            decode_pkt_out.instr_pkt.op_bits                    = op_bits_t'(i_use_alu);
                            decode_pkt_out.instr_pkt.aluop                      = alu_op_sra;
                        end 
                        else begin
                            decode_pkt_out.instr_pkt.op_bits                    = op_bits_t'(i_use_alu);
                            decode_pkt_out.instr_pkt.aluop                      = alu_op_srl;
                        end
                    end
                    default: begin
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m1_sel          = alu_m1_sel_t'(rs1_out);
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m2_sel          = alu_m2_sel_t'(imm_out);
                        decode_pkt_out.instr_pkt.op_bits                        = op_bits_t'(i_use_alu);
                        decode_pkt_out.instr_pkt.aluop                          = funct3;
                    end
                endcase
        end
        op_b_reg  : begin //s_rr
            decode_pkt_out.instr_pkt.i_valid    = fetch_stage_valid;
            decode_pkt_out.instr_pkt.i_use_rs1  = 1'b1;
            decode_pkt_out.instr_pkt.i_use_rs2  = 1'b1;

            decode_pkt_out.instr_pkt.rs1_addr        = rs1_s;
            decode_pkt_out.instr_pkt.rs2_addr        = rs2_s;
            decode_pkt_out.instr_pkt.rd_addr         = rd_s;

            decode_pkt_out.rvfi_pkt.monitor_rs1_addr = rs1_s;
            decode_pkt_out.rvfi_pkt.monitor_rs2_addr = rs2_s;
            decode_pkt_out.rvfi_pkt.monitor_rd_addr  = rd_s;
            unique case (funct3)
                arith_f3_slt: begin
                    if (funct7[0]) begin    //Mulhsu
                        decode_pkt_out.instr_pkt.op_bits                        = op_bits_t'(i_use_mul);
                        decode_pkt_out.instr_pkt.signed_mul = 2'b10;
                        decode_pkt_out.instr_pkt.high_bits = 1'b1;
                    end
                    else begin
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m1_sel         = alu_m1_sel_t'(rs1_out);
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m2_sel         = alu_m2_sel_t'(rs2_out);
                        decode_pkt_out.instr_pkt.op_bits                        = op_bits_t'(i_use_cmpop);
                        decode_pkt_out.instr_pkt.cmpop                          = branch_f3_blt;
                    end
                end
                arith_f3_sltu: begin
                    if (funct7[0]) begin    //Mulhu
                        decode_pkt_out.instr_pkt.op_bits                        = op_bits_t'(i_use_mul);
                        decode_pkt_out.instr_pkt.signed_mul = 2'b00;
                        decode_pkt_out.instr_pkt.high_bits = 1'b1;
                    end
                    else begin
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m1_sel         = alu_m1_sel_t'(rs1_out);
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m2_sel         = alu_m2_sel_t'(rs2_out);
                        decode_pkt_out.instr_pkt.op_bits                        = op_bits_t'(i_use_cmpop);
                        decode_pkt_out.instr_pkt.cmpop                          = branch_f3_bltu;
                    end
                end
                arith_f3_sll: begin
                    if (funct7[0]) begin    //Mulh
                        decode_pkt_out.instr_pkt.op_bits                        = op_bits_t'(i_use_mul);
                        decode_pkt_out.instr_pkt.signed_mul = 2'b11;
                        decode_pkt_out.instr_pkt.high_bits = 1'b1;
                    end
                    else begin
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m1_sel          = alu_m1_sel_t'(rs1_out);
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m2_sel          = alu_m2_sel_t'(rs2_out);
                        decode_pkt_out.instr_pkt.op_bits                        = op_bits_t'(i_use_alu);
                        decode_pkt_out.instr_pkt.aluop                          = funct3;
                    end
                end
                arith_f3_sr: begin
                    if (funct7[5]) begin
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m1_sel          = alu_m1_sel_t'(rs1_out);
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m2_sel          = alu_m2_sel_t'(rs2_out);
                        decode_pkt_out.instr_pkt.op_bits                        = op_bits_t'(i_use_alu);
                        decode_pkt_out.instr_pkt.aluop                          = alu_op_sra;
                    end
                     else if (funct7[0]) begin  //Divu
                        decode_pkt_out.instr_pkt.op_bits                        = op_bits_t'(i_use_div);
                        decode_pkt_out.instr_pkt.use_remainder = '0; 
                        decode_pkt_out.instr_pkt.signed_div = '0;
                    end
                    else begin
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m1_sel          = alu_m1_sel_t'(rs1_out);
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m2_sel          = alu_m2_sel_t'(rs2_out);
                        decode_pkt_out.instr_pkt.op_bits                        = op_bits_t'(i_use_alu);
                        decode_pkt_out.instr_pkt.aluop                          = alu_op_srl;
                    end
                end
                arith_f3_add: begin
                    if (funct7[0]) begin    //Mul
                        decode_pkt_out.instr_pkt.op_bits                        = op_bits_t'(i_use_mul);
                        decode_pkt_out.instr_pkt.signed_mul                     = 2'b11;
                        decode_pkt_out.instr_pkt.high_bits                      = 1'b0;
                    end
                    else if (funct7[5]) begin
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m1_sel          = alu_m1_sel_t'(rs1_out);
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m2_sel          = alu_m2_sel_t'(rs2_out);
                        decode_pkt_out.instr_pkt.op_bits                        = op_bits_t'(i_use_alu);
                        decode_pkt_out.instr_pkt.aluop                          = alu_op_sub;
                    end else begin
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m1_sel          = alu_m1_sel_t'(rs1_out);
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m2_sel          = alu_m2_sel_t'(rs2_out);
                        decode_pkt_out.instr_pkt.op_bits                        = op_bits_t'(i_use_alu);
                        decode_pkt_out.instr_pkt.aluop                          = alu_op_add;
                    end
                end
                arith_f3_or: begin
                    if (funct7[0]) begin    //Rem
                        decode_pkt_out.instr_pkt.op_bits                        = op_bits_t'(i_use_div);
                        decode_pkt_out.instr_pkt.use_remainder = '1; 
                        decode_pkt_out.instr_pkt.signed_div = '1;
                    end
                    else begin
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m1_sel          = alu_m1_sel_t'(rs1_out);
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m2_sel          = alu_m2_sel_t'(rs2_out);
                        decode_pkt_out.instr_pkt.op_bits                        = op_bits_t'(i_use_alu);
                        decode_pkt_out.instr_pkt.aluop                          = funct3;
                    end
                end
                arith_f3_and: begin
                    if (funct7[0]) begin    //Remu
                        decode_pkt_out.instr_pkt.op_bits                        = op_bits_t'(i_use_div);
                        decode_pkt_out.instr_pkt.use_remainder                  = '1; 
                        decode_pkt_out.instr_pkt.signed_div                     = '0;
                    end
                    else begin
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m1_sel          = alu_m1_sel_t'(rs1_out);
                        decode_pkt_out.instr_pkt.alu_op_sel.alu_m2_sel          = alu_m2_sel_t'(rs2_out);
                        decode_pkt_out.instr_pkt.op_bits                        = op_bits_t'(i_use_alu);
                        decode_pkt_out.instr_pkt.aluop                          = funct3;
                    end
                end
                arith_f3_xor: begin
                        if (funct7[0]) begin    //Div
                            decode_pkt_out.instr_pkt.op_bits                    = op_bits_t'(i_use_div);
                            decode_pkt_out.instr_pkt.use_remainder              = '0; 
                            decode_pkt_out.instr_pkt.signed_div                 = '1;
                        end
                        else begin
                            decode_pkt_out.instr_pkt.alu_op_sel.alu_m1_sel      = alu_m1_sel_t'(rs1_out);
                            decode_pkt_out.instr_pkt.alu_op_sel.alu_m2_sel      = alu_m2_sel_t'(rs2_out);
                            decode_pkt_out.instr_pkt.op_bits                    = op_bits_t'(i_use_alu);
                            decode_pkt_out.instr_pkt.aluop                      = funct3;
                        end
                end
                default: begin
                    decode_pkt_out.instr_pkt.alu_op_sel.alu_m1_sel              = alu_m1_sel_t'(rs1_out);
                    decode_pkt_out.instr_pkt.alu_op_sel.alu_m2_sel              = alu_m2_sel_t'(rs2_out);
                    decode_pkt_out.instr_pkt.op_bits                            = op_bits_t'(i_use_alu);
                    decode_pkt_out.instr_pkt.aluop                              = funct3;
                end
            endcase
        end
        op_b_br   : begin 
            // decode_pkt_out.instr_pkt.is_branch              = '1;
            decode_pkt_out.instr_pkt.i_use_rs1              =  1'b1;
            decode_pkt_out.instr_pkt.i_use_rs2              =  1'b1;
            decode_pkt_out.instr_pkt.imm_data               =  b_imm;
            decode_pkt_out.instr_pkt.alu_op_sel.alu_m1_sel  =  alu_m1_sel_t'(rs1_out);
            decode_pkt_out.instr_pkt.alu_op_sel.alu_m2_sel  =  alu_m2_sel_t'(rs2_out);

            decode_pkt_out.instr_pkt.op_bits                =  op_bits_t'(i_use_br);
            decode_pkt_out.instr_pkt.cmpop                  =  branch_f3_t'(funct3);

            decode_pkt_out.instr_pkt.rd_addr                =  '0;

            decode_pkt_out.instr_pkt.i_valid                =  fetch_stage_valid;

            decode_pkt_out.instr_pkt.rs1_addr               = rs1_s;
            decode_pkt_out.instr_pkt.rs2_addr               = rs2_s;

            decode_pkt_out.rvfi_pkt.monitor_rs1_addr        = rs1_s;
            decode_pkt_out.rvfi_pkt.monitor_rs2_addr        = rs2_s;
        end
        op_b_jal  : begin
            // decode_pkt_out.instr_pkt.is_branch              = '1;
            decode_pkt_out.instr_pkt.op_bits                =  op_bits_t'(i_use_jal);

            decode_pkt_out.instr_pkt.i_use_rs1              =  1'b0;
            decode_pkt_out.instr_pkt.imm_data               =  j_imm;
            decode_pkt_out.instr_pkt.aluop                  =  alu_ops'(alu_op_add);
            decode_pkt_out.instr_pkt.alu_op_sel.alu_m1_sel  =  alu_m1_sel_t'(pc_out);
            decode_pkt_out.instr_pkt.alu_op_sel.alu_m2_sel  =  alu_m2_sel_t'(imm_out);

            decode_pkt_out.instr_pkt.i_valid                =  fetch_stage_valid;

            decode_pkt_out.instr_pkt.rd_addr                =  rd_s;

            decode_pkt_out.rvfi_pkt.monitor_rd_addr         =  rd_s;
        end

        op_b_jalr : begin
            // decode_pkt_out.instr_pkt.is_branch              = '1;
            decode_pkt_out.instr_pkt.op_bits                =  op_bits_t'(i_use_jal);

            decode_pkt_out.instr_pkt.i_use_rs1              =  1'b1;
            decode_pkt_out.instr_pkt.imm_data               =  i_imm;
            decode_pkt_out.instr_pkt.aluop                  =  alu_ops'(alu_op_add);
            decode_pkt_out.instr_pkt.alu_op_sel.alu_m1_sel  =  alu_m1_sel_t'(rs1_out);
            decode_pkt_out.instr_pkt.alu_op_sel.alu_m2_sel  =  alu_m2_sel_t'(imm_out);
            decode_pkt_out.instr_pkt.i_valid                =  fetch_stage_valid;

            decode_pkt_out.instr_pkt.rs1_addr               = rs1_s;
            decode_pkt_out.instr_pkt.rd_addr                = rd_s;

            decode_pkt_out.rvfi_pkt.monitor_rs1_addr        = rs1_s;
            decode_pkt_out.rvfi_pkt.monitor_rd_addr         = rd_s;
        end

        op_b_load : begin
            decode_pkt_out.instr_pkt.i_valid                = fetch_stage_valid;
            decode_pkt_out.instr_pkt.op_bits                = op_bits_t'(i_use_load);

            decode_pkt_out.instr_pkt.i_use_rs1              = 1'b1;
            decode_pkt_out.instr_pkt.rs1_addr               = rs1_s;

            decode_pkt_out.instr_pkt.rd_addr                = rd_s;
            
            decode_pkt_out.instr_pkt.mem_funct3             = funct3;

            decode_pkt_out.instr_pkt.imm_data               = i_imm;

            decode_pkt_out.rvfi_pkt.monitor_rs1_addr        = rs1_s;
            decode_pkt_out.rvfi_pkt.monitor_rd_addr         = rd_s;
        end
        op_b_store: begin
            decode_pkt_out.instr_pkt.i_valid            = fetch_stage_valid;
            decode_pkt_out.instr_pkt.op_bits            = op_bits_t'(i_use_store);
            decode_pkt_out.instr_pkt.i_use_rs1          = 1'b1;
            decode_pkt_out.instr_pkt.i_use_rs2          = 1'b1;
            decode_pkt_out.instr_pkt.imm_data           = s_imm;
            decode_pkt_out.instr_pkt.rs1_addr           = rs1_s;
            decode_pkt_out.instr_pkt.rs2_addr           = rs2_s;
            decode_pkt_out.instr_pkt.mem_funct3         = funct3;

            decode_pkt_out.rvfi_pkt.monitor_rs1_addr = rs1_s;
            decode_pkt_out.rvfi_pkt.monitor_rs2_addr = rs2_s;
            decode_pkt_out.rvfi_pkt.monitor_rd_addr  = '0;
            decode_pkt_out.instr_pkt.rd_addr         =  '0;

        end

        default: begin
            decode_pkt_out.rvfi_pkt.monitor_valid                               = 1'b0;
            decode_pkt_out.instr_pkt.i_valid                                    = 1'b0;
        end
    endcase
end


endmodule : decode