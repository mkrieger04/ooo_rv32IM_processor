module dispatch_rename
import rv32i_types::*;
#(
    parameter               ROB_DEPTH = 32, 
    parameter               LSQ_DEPTH = 4,
    parameter               TAG_DEPTH = 16,
    parameter               BMASK_DEPTH = 3,
    parameter               PRE_ST_DEPTH = 4,
    parameter               RAS_DEPTH   = 4

)
(
    // Decode I/O
    input    logic           fifo_empty_decode_queue,
    input    instr_pkt_t     instruction_data,
    input    rvfi_pkt_t      rvfi_pkt,

    output   logic           read_decode_queue,

    // RAT I/O
    input    ratatouille_t   rs1_rat, rs2_rat,

    output   logic   [4:0]   rd_s,
    output   logic           rd_rename_we,
    output   logic   [$clog2(ROB_DEPTH + 32)-1:0] rd_p_addr_rename_val,

    // ROB I/O
    input    logic           rob_full,
    input    logic [$clog2(ROB_DEPTH):0] rob_enque_idx,

    output   rob_pkt_t       rob_enque_pkt,
    output   logic           rob_enque_wen,

    // CDB I/O
    input   cdb_pkt_t       cdb_pkt,
    input   cdb_pkt_t       cdb_pkt2,

    // free_list I/O
    input   logic   [$clog2(ROB_DEPTH + 32)-1:0] free_p_addr,

    output    logic   dispatch_ren,

    // store tag list I/O
    input   logic   [$clog2(TAG_DEPTH)-1:0] curr_store_tag,
    input   logic   [$clog2(TAG_DEPTH)-1:0] free_store_tag,

    input   st_tag_pkt_t               st_tag_wb_pkt,
    input   logic                      no_pending_stores,
    input   logic                      all_pending_stores,

    output  logic              store_tag_ren,

    // ISSUE I/O
    input    rs_full_pkt_t     rs_full_pkt,

    output   rs_data_pkt_t     alu_rs_instr_pkt_out,
    output   rs_data_pkt_t     mul_rs_instr_pkt_out,
    output   rs_data_pkt_t     div_rs_instr_pkt_out,
    output   rs_data_pkt_t     br_rs_instr_pkt_out,
    output   ld_st_data_pkt_t  ld_rs_instr_pkt_out,
    output   ld_st_data_pkt_t  st_rs_instr_pkt_out,


    // ebr I/O
    input    logic   [$clog2(ROB_DEPTH + 32)-1:0] rrat_kick_p_addr,
    input    logic   rrat_kick,

    output ratatouille_t  br_rat[32],
    output logic [ROB_DEPTH + 31:0]  br_free_list,
    output logic [$clog2(ROB_DEPTH):0] br_rob_tail,

    input  logic clk,
    input  logic rst,

    input ratatouille_t  rat[32],
    input logic [ROB_DEPTH + 31:0]  free_list,


    input logic [$clog2(PRE_ST_DEPTH):0]    pre_st_r_tail_idx,
    input logic [$clog2(PRE_ST_DEPTH):0]    pre_st_r_head_idx,

    output  logic              pre_st_flush,
    output  logic [$clog2(PRE_ST_DEPTH):0]    pre_st_w_tail_idx,

    input  logic               post_st_wen,
    input  logic [$clog2(LSQ_DEPTH):0]         post_st_r_tail_idx,

    output logic [$clog2(LSQ_DEPTH):0]         post_st_w_tail_idx,
    input mem_pkt_t            post_st_bmask,

    input logic [TAG_DEPTH - 1:0] store_tag_list_real,

    output logic [TAG_DEPTH - 1:0] br_store_tag_list,
    output logic [$clog2(TAG_DEPTH)-1:0] br_curr_store_tag,

    input logic pre_st_ren,


    output ras_t br_ras_top,
    output logic [$clog2(RAS_DEPTH)-1:0] br_stack_ptr_val
);


    logic bmask_ren;
    logic [$clog2(BMASK_DEPTH)-1:0] free_bmask_bit;
    logic bmask_stall;
    logic [BMASK_DEPTH-1:0]  bmask_list_val;

    branch_stack_t branch_stack [BMASK_DEPTH-1:0];
    branch_stack_t branch_stack_next [BMASK_DEPTH-1:0];

    // update branch_stack
    always_ff @(posedge clk) begin
        if(rst) begin
            for (integer unsigned i = 0; i < unsigned'(BMASK_DEPTH); i++) begin
                branch_stack[i] <= '0;
            end
        end
        else begin
            branch_stack <= branch_stack_next;
        end
    end

    // Update checkpoints in branch stack
    always_comb begin
        branch_stack_next = branch_stack;

        if(bmask_ren) begin
            for (integer i = 0; i < 32; i++) begin
                branch_stack_next[free_bmask_bit].rat[i] = rat[i];
            end

            if((rd_rename_we)) begin
                if((cdb_pkt.cdb_broadcast && (rd_s != cdb_pkt.cdb_aaddr) && (rat[cdb_pkt.cdb_aaddr].p_addr == cdb_pkt.cdb_p_addr)) && (cdb_pkt2.cdb_broadcast && (rd_s != cdb_pkt2.cdb_aaddr) && (rat[cdb_pkt2.cdb_aaddr].p_addr == cdb_pkt2.cdb_p_addr))) begin
                    branch_stack_next[free_bmask_bit].rat[rd_s].valid  = '0;
                    branch_stack_next[free_bmask_bit].rat[rd_s].p_addr = rd_p_addr_rename_val;
                    branch_stack_next[free_bmask_bit].rat[cdb_pkt.cdb_aaddr].valid = '1;
                    branch_stack_next[free_bmask_bit].rat[cdb_pkt2.cdb_aaddr].valid = '1;
                end
                else if ((cdb_pkt.cdb_broadcast && (rd_s != cdb_pkt.cdb_aaddr) && (rat[cdb_pkt.cdb_aaddr].p_addr == cdb_pkt.cdb_p_addr))) begin
                    branch_stack_next[free_bmask_bit].rat[rd_s].valid  = '0;
                    branch_stack_next[free_bmask_bit].rat[rd_s].p_addr = rd_p_addr_rename_val;
                    branch_stack_next[free_bmask_bit].rat[cdb_pkt.cdb_aaddr].valid = '1;
                end
                else if((cdb_pkt2.cdb_broadcast && (rd_s != cdb_pkt2.cdb_aaddr) && (rat[cdb_pkt2.cdb_aaddr].p_addr == cdb_pkt2.cdb_p_addr))) begin
                    branch_stack_next[free_bmask_bit].rat[rd_s].valid  = '0;
                    branch_stack_next[free_bmask_bit].rat[rd_s].p_addr = rd_p_addr_rename_val;
                    branch_stack_next[free_bmask_bit].rat[cdb_pkt2.cdb_aaddr].valid = '1;
                end
                else begin
                    branch_stack_next[free_bmask_bit].rat[rd_s].valid  = '0;
                    branch_stack_next[free_bmask_bit].rat[rd_s].p_addr = rd_p_addr_rename_val;
                end
            end
            else begin
                if((cdb_pkt.cdb_broadcast  && (rat[cdb_pkt.cdb_aaddr].p_addr == cdb_pkt.cdb_p_addr)))begin
                    branch_stack_next[free_bmask_bit].rat[cdb_pkt.cdb_aaddr].valid = '1;
                end

                if((cdb_pkt2.cdb_broadcast && (rat[cdb_pkt2.cdb_aaddr].p_addr == cdb_pkt2.cdb_p_addr)))begin
                    branch_stack_next[free_bmask_bit].rat[cdb_pkt2.cdb_aaddr].valid = '1;
                end
            end

            branch_stack_next[free_bmask_bit].free_list = free_list;
            if(dispatch_ren) branch_stack_next[free_bmask_bit].free_list[free_p_addr] = '1;

            branch_stack_next[free_bmask_bit].rob_tail = rob_enque_idx;

            // save tail of pre load_store_fifo
            branch_stack_next[free_bmask_bit].pre_addrcalc_store_tail =  pre_st_r_tail_idx;
            branch_stack_next[free_bmask_bit].pre_calc_fifo_empty     =  pre_st_ren ? pre_st_r_head_idx + 1'b1 == pre_st_r_tail_idx : pre_st_r_head_idx == pre_st_r_tail_idx;

            // post store fifo
            branch_stack_next[free_bmask_bit].post_addrcalc_store_tail = post_st_wen ? post_st_r_tail_idx  + 1'b1 : post_st_r_tail_idx;

            branch_stack_next[free_bmask_bit].store_tag_list = store_tag_list_real;
            // if(st_tag_wb_pkt.st_tag_broadcast) branch_stack_next[free_bmask_bit].store_tag_list[st_tag_wb_pkt.store_tag] = '0;
            branch_stack_next[free_bmask_bit].curr_store_tag = curr_store_tag; 


            branch_stack_next[free_bmask_bit].ras_top = instruction_data.ras_top;
            branch_stack_next[free_bmask_bit].stack_ptr_val = instruction_data.stack_ptr_val;

        end

        for(integer unsigned i = 0; i < unsigned'(BMASK_DEPTH); i++) begin
            if (rrat_kick && |rrat_kick_p_addr)  begin
                branch_stack_next[i].free_list[rrat_kick_p_addr] = '0;
            end
            if (st_tag_wb_pkt.st_tag_broadcast) begin
                 branch_stack_next[i].store_tag_list[st_tag_wb_pkt.store_tag] = '0;
            end

            // if initializing stack entry and at that entry skip
            if (~(bmask_ren && ($clog2(BMASK_DEPTH)'(i) == (free_bmask_bit)))) begin
                if(~cdb_pkt.br_bmask[i]) begin
                    if (cdb_pkt.cdb_broadcast && (branch_stack[i].rat[cdb_pkt.cdb_aaddr].p_addr == cdb_pkt.cdb_p_addr)) begin
                        branch_stack_next[i].rat[cdb_pkt.cdb_aaddr].valid = '1;
                    end
                end
                if(~cdb_pkt2.br_bmask[i]) begin
                    if (cdb_pkt2.cdb_broadcast && (branch_stack[i].rat[cdb_pkt2.cdb_aaddr].p_addr == cdb_pkt2.cdb_p_addr)) begin
                        branch_stack_next[i].rat[cdb_pkt2.cdb_aaddr].valid = '1;
                    end
                end

                // for pre store fifo
                if(pre_st_ren && (pre_st_r_head_idx + 1'b1 == branch_stack[i].pre_addrcalc_store_tail)) begin
                    branch_stack_next[i].pre_calc_fifo_empty = '1;
                end
                // branch_stack_next[free_bmask_bit].pre_calc_fifo_empty     =  pre_st_ren ? pre_st_r_head_idx + 1'b1 == pre_st_r_tail_idx : pre_st_r_head_idx == pre_st_r_tail_idx;
                // if( pre_st_r_head_idx == branch_stack[i].pre_addrcalc_store_tail)  branch_stack_next[i].pre_calc_fifo_empty = '1;

                // for post store fifo
                if (post_st_wen && ~post_st_bmask.bmask[i]) begin
                     branch_stack_next[i].post_addrcalc_store_tail =  branch_stack[i].post_addrcalc_store_tail + 1'b1;
                end
             end
        end
    end

    // received misprediciton, restore rat, rob, and free list
    always_comb begin
        // br_rat = '0;
        // br_rob_tail = '0;
        // br_free_list = '0;

        // if(cdb_pkt2.br_mispred & .cdb_pkt2.cdb_broadcast) begin
        //     // propogate output values to reset rob, rat, and free_list
        //     br_rat = branch_stack[cdb_pkt2.br_bit].rat

        //     if(~cdb_pkt.brmask[cdb_pkt2.br_bit] && (cdb_pkt.cdb_broadcast  && (branch_stack.rat[cdb_pkt.cdb_aaddr].p_addr == cdb_pkt.cdb_p_addr)))begin
        //         br_rat[cdb_pkt.cdb_aaddr].valid = '1;
        //     end

        //     if((branch_stack.rat[cdb_pkt2.cdb_aaddr].p_addr == cdb_pkt2.cdb_p_addr))begin
        //         br_rat[cdb_pkt2.cdb_aaddr].valid = '1;
        //     end

        //     br_free_list = branch_stack[cdb_pkt2.br_bit].free_list;
        //     if (rrat_kick && |rrat_kick_p_addr) br_free_list[rrat_kick_p_addr] = '0;

        //     br_rob_tail = branch_stack[cdb_pkt2.br_bit].br_rob_tail + 1'b1;
        // end

        // propogate output values to reset rob, rat, and free_list


            for (integer i = 0; i < 32; i++) begin
                br_rat[i] = branch_stack[cdb_pkt2.br_bit].rat[i];
            end

            if(~cdb_pkt.br_bmask[cdb_pkt2.br_bit] && (cdb_pkt.cdb_broadcast  && (br_rat[cdb_pkt.cdb_aaddr].p_addr == cdb_pkt.cdb_p_addr)))begin
                br_rat[cdb_pkt.cdb_aaddr].valid = '1;
            end

            if((br_rat[cdb_pkt2.cdb_aaddr].p_addr == cdb_pkt2.cdb_p_addr))begin
                br_rat[cdb_pkt2.cdb_aaddr].valid = '1;
            end

            br_free_list = branch_stack[cdb_pkt2.br_bit].free_list;
            if (rrat_kick && |rrat_kick_p_addr) br_free_list[rrat_kick_p_addr] = '0;

            br_rob_tail = branch_stack[cdb_pkt2.br_bit].rob_tail + 1'b1;

            // pre buffer
            pre_st_w_tail_idx = branch_stack[cdb_pkt2.br_bit].pre_addrcalc_store_tail;
            if(pre_st_ren && (pre_st_r_head_idx + 1'b1 == branch_stack[cdb_pkt2.br_bit].pre_addrcalc_store_tail)) pre_st_flush= '1;
            else pre_st_flush = branch_stack[cdb_pkt2.br_bit].pre_calc_fifo_empty;

            // post buffer
            if (post_st_wen && ~post_st_bmask.bmask[cdb_pkt2.br_bit])  post_st_w_tail_idx =  branch_stack[cdb_pkt2.br_bit].post_addrcalc_store_tail + 1'b1;
            else post_st_w_tail_idx = branch_stack[cdb_pkt2.br_bit].post_addrcalc_store_tail;

            // tag_list and curr-store tag
            br_store_tag_list = branch_stack[cdb_pkt2.br_bit].store_tag_list;
            if(st_tag_wb_pkt.st_tag_broadcast) br_store_tag_list[st_tag_wb_pkt.store_tag] = '0;
            br_curr_store_tag = branch_stack[cdb_pkt2.br_bit].curr_store_tag;

            br_ras_top = branch_stack[cdb_pkt2.br_bit].ras_top;
            br_stack_ptr_val = branch_stack[cdb_pkt2.br_bit].stack_ptr_val;

    end

bmask #(.BMASK_DEPTH(BMASK_DEPTH)) bmask(
    .clk(clk),
    .rst(rst),

    .br_mispred(cdb_pkt2.br_mispred & cdb_pkt2.cdb_broadcast),
    .br_corpred((~cdb_pkt2.br_mispred) & cdb_pkt2.cdb_broadcast),
    .br_bmask(cdb_pkt2.br_bmask),
    .br_bit(cdb_pkt2.br_bit),

    .bmask_ren(bmask_ren),
    .free_bmask_bit(free_bmask_bit),
    .bmask_stall(bmask_stall),
    .bmask_list_val(bmask_list_val)
);


always_comb begin
    // Output to decode
    read_decode_queue       = '0;

    // Output to rat
    rd_s                    = instruction_data.rd_addr;
    rd_rename_we            = '0;
    rd_p_addr_rename_val    = '0;

    // free_list i/o
    dispatch_ren            = '0;

    // Output to Issue
    alu_rs_instr_pkt_out    = '0;
    mul_rs_instr_pkt_out    = '0;
    div_rs_instr_pkt_out    = '0;
    br_rs_instr_pkt_out     = '0;
    ld_rs_instr_pkt_out     = '0;
    st_rs_instr_pkt_out     = '0;

    // Output to Store Tag List
    store_tag_ren = '0;

    // Output to Rob
    rob_enque_wen           = '0;


    rob_enque_pkt             = '0;
    // rob_enque_pkt.prediction  = instruction_data.prediction;
    // rob_enque_pkt.is_branch  = instruction_data.is_branch;
    // rob_enque_pkt.pht_index   = instruction_data.pht_index;
    rob_enque_pkt.rd_s        = instruction_data.rd_addr;
    rob_enque_pkt.p_addr      = '0;
    rob_enque_pkt.rvfi_pkt    = rvfi_pkt;


    br_rs_instr_pkt_out.prediction  = instruction_data.prediction;
    // br_rs_instr_pkt_out.is_branch  = instruction_data.is_branch;
    br_rs_instr_pkt_out.pht_index   = instruction_data.pht_index;

    alu_rs_instr_pkt_out.bmask    = bmask_list_val;
    mul_rs_instr_pkt_out.bmask    = bmask_list_val;
    div_rs_instr_pkt_out.bmask    = bmask_list_val;
    br_rs_instr_pkt_out.bmask     = bmask_list_val;
    ld_rs_instr_pkt_out.bmask     = bmask_list_val;
    st_rs_instr_pkt_out.bmask     = bmask_list_val;

    br_rs_instr_pkt_out.pc_pred     = instruction_data.pc_pred;

    if(cdb_pkt2.cdb_broadcast && ~cdb_pkt2.br_mispred) begin
        alu_rs_instr_pkt_out.bmask[cdb_pkt2.br_bit]    = '0;
        mul_rs_instr_pkt_out.bmask[cdb_pkt2.br_bit]    = '0;
        div_rs_instr_pkt_out.bmask[cdb_pkt2.br_bit]    = '0;
        br_rs_instr_pkt_out.bmask[cdb_pkt2.br_bit]     = '0;
        ld_rs_instr_pkt_out.bmask[cdb_pkt2.br_bit]     = '0;
        st_rs_instr_pkt_out.bmask[cdb_pkt2.br_bit]     = '0;
    end

    bmask_ren = '0;


    // check for rob stall and decode stall
    if(~rob_full && ~fifo_empty_decode_queue && instruction_data.i_valid &&  ~(cdb_pkt2.cdb_broadcast && cdb_pkt2.br_mispred)) begin
        // mul instr
        if((instruction_data.op_bits == op_bits_t'(i_use_mul)) && |free_p_addr) begin
            if (~rs_full_pkt.mul_rs_full) begin
                rob_enque_wen     = '1;
                read_decode_queue = '1;

                if(|instruction_data.rd_addr) begin
                    dispatch_ren      = '1;
                    rd_rename_we      = '1;

                    rob_enque_pkt.p_addr    = free_p_addr;
                    rd_p_addr_rename_val    = free_p_addr;
                end
            end
            if((rs1_rat.p_addr == cdb_pkt.cdb_p_addr) && cdb_pkt.cdb_broadcast) mul_rs_instr_pkt_out.rs1_rdy = '1;
            else if ((rs1_rat.p_addr == cdb_pkt2.cdb_p_addr) && cdb_pkt2.cdb_broadcast) mul_rs_instr_pkt_out.rs1_rdy = '1;
            else mul_rs_instr_pkt_out.rs1_rdy = rs1_rat.valid | ~instruction_data.i_use_rs1;

            if((rs2_rat.p_addr == cdb_pkt.cdb_p_addr) && cdb_pkt.cdb_broadcast) mul_rs_instr_pkt_out.rs2_rdy = '1;
            else if((rs2_rat.p_addr == cdb_pkt2.cdb_p_addr) && cdb_pkt2.cdb_broadcast) mul_rs_instr_pkt_out.rs2_rdy = '1;
            else mul_rs_instr_pkt_out.rs2_rdy = rs2_rat.valid | ~instruction_data.i_use_rs2;
            
            mul_rs_instr_pkt_out.ready           =  mul_rs_instr_pkt_out.rs2_rdy & mul_rs_instr_pkt_out.rs1_rdy;


            mul_rs_instr_pkt_out.valid           = instruction_data.i_valid;
            mul_rs_instr_pkt_out.i_use_rs1       = instruction_data.i_use_rs1;
            mul_rs_instr_pkt_out.rs1_aaddr       = instruction_data.rs1_addr;
            mul_rs_instr_pkt_out.rs1_paddr       = rs1_rat.p_addr;
            mul_rs_instr_pkt_out.i_use_rs2       = instruction_data.i_use_rs2;
            mul_rs_instr_pkt_out.rs2_aaddr       = instruction_data.rs2_addr;
            mul_rs_instr_pkt_out.rs2_paddr       = rs2_rat.p_addr;
            mul_rs_instr_pkt_out.rob_idx         = rob_enque_idx[$clog2(ROB_DEPTH)-1:0];

            mul_rs_instr_pkt_out.rd_addr         = instruction_data.rd_addr;

            mul_rs_instr_pkt_out.rd_paddr        = rob_enque_pkt.p_addr;

            mul_rs_instr_pkt_out.rvfi_pkt        = rvfi_pkt;

            mul_rs_instr_pkt_out.signed_mul      = instruction_data.signed_mul;
            mul_rs_instr_pkt_out.high_bits       = instruction_data.high_bits;

        end
        // div instr
        else if((instruction_data.op_bits == op_bits_t'(i_use_div)) && |free_p_addr) begin
            if (~rs_full_pkt.div_rs_full) begin
                rob_enque_wen     = '1;
                read_decode_queue = '1;
                if(|instruction_data.rd_addr) begin
                    dispatch_ren      = '1;
                    rd_rename_we      = '1;

                    rob_enque_pkt.p_addr    = free_p_addr;
                    rd_p_addr_rename_val    = free_p_addr;
                end
            end

         
            if((rs1_rat.p_addr == cdb_pkt.cdb_p_addr) && cdb_pkt.cdb_broadcast) div_rs_instr_pkt_out.rs1_rdy = '1;
            else if((rs1_rat.p_addr == cdb_pkt2.cdb_p_addr) && cdb_pkt2.cdb_broadcast) div_rs_instr_pkt_out.rs1_rdy = '1;
            else div_rs_instr_pkt_out.rs1_rdy = rs1_rat.valid | ~instruction_data.i_use_rs1;

            if((rs2_rat.p_addr == cdb_pkt.cdb_p_addr) && cdb_pkt.cdb_broadcast) div_rs_instr_pkt_out.rs2_rdy = '1;
            else if((rs2_rat.p_addr == cdb_pkt2.cdb_p_addr) && cdb_pkt2.cdb_broadcast) div_rs_instr_pkt_out.rs2_rdy = '1;
            else div_rs_instr_pkt_out.rs2_rdy = rs2_rat.valid | ~instruction_data.i_use_rs2;

            
            div_rs_instr_pkt_out.ready           =  div_rs_instr_pkt_out.rs2_rdy & div_rs_instr_pkt_out.rs1_rdy;



            div_rs_instr_pkt_out.valid           = instruction_data.i_valid;
            div_rs_instr_pkt_out.i_use_rs1       = instruction_data.i_use_rs1;
            div_rs_instr_pkt_out.rs1_aaddr       = instruction_data.rs1_addr;
            div_rs_instr_pkt_out.rs1_paddr       = rs1_rat.p_addr;
            div_rs_instr_pkt_out.i_use_rs2       = instruction_data.i_use_rs2;
            div_rs_instr_pkt_out.rs2_aaddr       = instruction_data.rs2_addr;
            div_rs_instr_pkt_out.rs2_paddr       = rs2_rat.p_addr;
            div_rs_instr_pkt_out.rob_idx         = rob_enque_idx[$clog2(ROB_DEPTH)-1:0];

            div_rs_instr_pkt_out.rd_addr         = instruction_data.rd_addr;

            div_rs_instr_pkt_out.rd_paddr        = rob_enque_pkt.p_addr;

            div_rs_instr_pkt_out.rvfi_pkt        = rvfi_pkt;
            
            div_rs_instr_pkt_out.signed_div      = instruction_data.signed_div;
            div_rs_instr_pkt_out.use_remainder   = instruction_data.use_remainder;
        end
        // alu instr
        else if(((instruction_data.op_bits == op_bits_t'(i_use_alu)) || (instruction_data.op_bits == op_bits_t'(i_use_cmpop))) && |free_p_addr) begin
            if (~rs_full_pkt.alu_rs_full) begin
                rob_enque_wen     = '1;
                read_decode_queue = '1;
                if(|instruction_data.rd_addr) begin
                    dispatch_ren      = '1;
                    rd_rename_we      = '1;

                    rob_enque_pkt.p_addr    = free_p_addr;
                    rd_p_addr_rename_val    = free_p_addr;
                end
            end

            //rs1/rs2 ready logic
            if((rs1_rat.p_addr == cdb_pkt.cdb_p_addr) && cdb_pkt.cdb_broadcast) alu_rs_instr_pkt_out.rs1_rdy = '1;
            else if((rs1_rat.p_addr == cdb_pkt2.cdb_p_addr) && cdb_pkt2.cdb_broadcast) alu_rs_instr_pkt_out.rs1_rdy = '1;
            else alu_rs_instr_pkt_out.rs1_rdy = rs1_rat.valid | ~instruction_data.i_use_rs1;

            if((rs2_rat.p_addr == cdb_pkt.cdb_p_addr) && cdb_pkt.cdb_broadcast) alu_rs_instr_pkt_out.rs2_rdy = '1;
            else if((rs2_rat.p_addr == cdb_pkt2.cdb_p_addr) && cdb_pkt2.cdb_broadcast) alu_rs_instr_pkt_out.rs2_rdy = '1;
            else alu_rs_instr_pkt_out.rs2_rdy = rs2_rat.valid | ~instruction_data.i_use_rs2;

            
            alu_rs_instr_pkt_out.ready           =  alu_rs_instr_pkt_out.rs2_rdy & alu_rs_instr_pkt_out.rs1_rdy;

            alu_rs_instr_pkt_out.valid           = instruction_data.i_valid;
            alu_rs_instr_pkt_out.i_use_rs1       = instruction_data.i_use_rs1;
            alu_rs_instr_pkt_out.rs1_aaddr       = instruction_data.rs1_addr;
            alu_rs_instr_pkt_out.rs1_paddr       = rs1_rat.p_addr;
            alu_rs_instr_pkt_out.i_use_rs2       = instruction_data.i_use_rs2;
            alu_rs_instr_pkt_out.rs2_aaddr       = instruction_data.rs2_addr;
            alu_rs_instr_pkt_out.rs2_paddr       = rs2_rat.p_addr;
            alu_rs_instr_pkt_out.rob_idx         = rob_enque_idx[$clog2(ROB_DEPTH)-1:0];

            alu_rs_instr_pkt_out.rd_addr         = instruction_data.rd_addr;

            alu_rs_instr_pkt_out.rd_paddr        = rob_enque_pkt.p_addr;
            alu_rs_instr_pkt_out.pc              = instruction_data.pc;
            alu_rs_instr_pkt_out.imm_data        = instruction_data.imm_data;

            alu_rs_instr_pkt_out.aluop           = instruction_data.aluop;
            alu_rs_instr_pkt_out.cmpop           = instruction_data.cmpop;

            alu_rs_instr_pkt_out.alu_op_sel      = instruction_data.alu_op_sel;
            alu_rs_instr_pkt_out.i_use_alu_cmpop = instruction_data.op_bits == op_bits_t'(i_use_cmpop);
            alu_rs_instr_pkt_out.rvfi_pkt        = rvfi_pkt;
        end
        // branches
        else if(instruction_data.op_bits == op_bits_t'(i_use_br) && ~bmask_stall) begin
            if (~rs_full_pkt.br_rs_full) begin
                rob_enque_wen     = '1;
                read_decode_queue = '1;
                bmask_ren = '1;
                br_rs_instr_pkt_out.free_bmask_bit = free_bmask_bit;
            end


            //rs1/rs2 ready logic
            if((rs1_rat.p_addr == cdb_pkt.cdb_p_addr) && cdb_pkt.cdb_broadcast) br_rs_instr_pkt_out.rs1_rdy = '1;
            else if((rs1_rat.p_addr == cdb_pkt2.cdb_p_addr) && cdb_pkt2.cdb_broadcast) br_rs_instr_pkt_out.rs1_rdy = '1;
            else br_rs_instr_pkt_out.rs1_rdy = rs1_rat.valid;

            if((rs2_rat.p_addr == cdb_pkt.cdb_p_addr) && cdb_pkt.cdb_broadcast) br_rs_instr_pkt_out.rs2_rdy = '1;
            else if((rs2_rat.p_addr == cdb_pkt2.cdb_p_addr) && cdb_pkt2.cdb_broadcast) br_rs_instr_pkt_out.rs2_rdy = '1;
            else br_rs_instr_pkt_out.rs2_rdy = rs2_rat.valid;

            
            br_rs_instr_pkt_out.ready           =  br_rs_instr_pkt_out.rs2_rdy & br_rs_instr_pkt_out.rs1_rdy;
            br_rs_instr_pkt_out.is_branch       = '1;

            br_rs_instr_pkt_out.valid           = instruction_data.i_valid;
            br_rs_instr_pkt_out.i_use_rs1       = instruction_data.i_use_rs1;
            br_rs_instr_pkt_out.rs1_aaddr       = instruction_data.rs1_addr;
            br_rs_instr_pkt_out.rs1_paddr       = rs1_rat.p_addr;
            br_rs_instr_pkt_out.i_use_rs2       = instruction_data.i_use_rs2;
            br_rs_instr_pkt_out.rs2_aaddr       = instruction_data.rs2_addr;
            br_rs_instr_pkt_out.rs2_paddr       = rs2_rat.p_addr;
            br_rs_instr_pkt_out.rob_idx         = rob_enque_idx[$clog2(ROB_DEPTH)-1:0];

            br_rs_instr_pkt_out.pc              = instruction_data.pc;
            br_rs_instr_pkt_out.pc_next         = instruction_data.pc_next;
            br_rs_instr_pkt_out.imm_data        = instruction_data.imm_data;


            br_rs_instr_pkt_out.aluop           = instruction_data.aluop;
            br_rs_instr_pkt_out.cmpop           = instruction_data.cmpop;

            br_rs_instr_pkt_out.alu_op_sel      = instruction_data.alu_op_sel;
            br_rs_instr_pkt_out.i_use_alu_cmpop = '1;

  

            br_rs_instr_pkt_out.rvfi_pkt        = rvfi_pkt;
        end
        // jal/jalr instructions
        else if(instruction_data.op_bits == op_bits_t'(i_use_jal) && |free_p_addr && ~bmask_stall) begin
            if (~rs_full_pkt.br_rs_full) begin
                rob_enque_wen     = '1;
                read_decode_queue = '1;
                bmask_ren = '1;
                br_rs_instr_pkt_out.free_bmask_bit = free_bmask_bit;
                if(|instruction_data.rd_addr) begin
                    dispatch_ren      = '1;
                    rd_rename_we      = '1;

                    rob_enque_pkt.p_addr    = free_p_addr;
                    rd_p_addr_rename_val    = free_p_addr;
                end
            end

            br_rs_instr_pkt_out.valid           = instruction_data.i_valid;

            //rs1/rs2 ready logic
            if((rs1_rat.p_addr == cdb_pkt.cdb_p_addr) && cdb_pkt.cdb_broadcast) br_rs_instr_pkt_out.rs1_rdy = '1;
            else if((rs1_rat.p_addr == cdb_pkt2.cdb_p_addr) && cdb_pkt2.cdb_broadcast) br_rs_instr_pkt_out.rs1_rdy = '1;
            else br_rs_instr_pkt_out.rs1_rdy = rs1_rat.valid | ~instruction_data.i_use_rs1;

            br_rs_instr_pkt_out.rs2_rdy         = '1;
            
            br_rs_instr_pkt_out.ready           =  br_rs_instr_pkt_out.rs1_rdy;


            br_rs_instr_pkt_out.i_use_rs1       = instruction_data.i_use_rs1;
            br_rs_instr_pkt_out.rs1_aaddr       = instruction_data.rs1_addr;
            br_rs_instr_pkt_out.rs1_paddr       = rs1_rat.p_addr;
            br_rs_instr_pkt_out.rob_idx         = rob_enque_idx[$clog2(ROB_DEPTH)-1:0];

            br_rs_instr_pkt_out.rd_addr         = instruction_data.rd_addr;

            br_rs_instr_pkt_out.rd_paddr        = rob_enque_pkt.p_addr;
            br_rs_instr_pkt_out.pc              = instruction_data.pc;
            br_rs_instr_pkt_out.imm_data        = instruction_data.imm_data;

            br_rs_instr_pkt_out.aluop           = instruction_data.aluop;
            br_rs_instr_pkt_out.cmpop           = instruction_data.cmpop;

            br_rs_instr_pkt_out.alu_op_sel      = instruction_data.alu_op_sel;
            br_rs_instr_pkt_out.i_use_alu_cmpop = '0;


            br_rs_instr_pkt_out.rvfi_pkt        = rvfi_pkt;
        end

        else if(instruction_data.op_bits == op_bits_t'(i_use_load) && |free_p_addr)begin
            if (~rs_full_pkt.ld_rs_full) begin
                rob_enque_wen     = '1;
                read_decode_queue = '1;

                if(|instruction_data.rd_addr) begin
                    dispatch_ren      = '1;
                    rd_rename_we      = '1;

                    rob_enque_pkt.p_addr            = free_p_addr;
                    rd_p_addr_rename_val            = free_p_addr;
                end
            end

            ld_rs_instr_pkt_out.rd_paddr = rob_enque_pkt.p_addr;
            ld_rs_instr_pkt_out.valid = '1;

            ld_rs_instr_pkt_out.i_use_store  = '0; 
            ld_rs_instr_pkt_out.i_use_rs1    = '1;
            ld_rs_instr_pkt_out.rs1_aaddr    = instruction_data.rs1_addr;
            ld_rs_instr_pkt_out.rs1_paddr    = rs1_rat.p_addr;

            if((rs1_rat.p_addr == cdb_pkt.cdb_p_addr) && cdb_pkt.cdb_broadcast) ld_rs_instr_pkt_out.rs1_rdy = '1;
            else if((rs1_rat.p_addr == cdb_pkt2.cdb_p_addr) && cdb_pkt2.cdb_broadcast) ld_rs_instr_pkt_out.rs1_rdy = '1;
            else ld_rs_instr_pkt_out.rs1_rdy = rs1_rat.valid;


            ld_rs_instr_pkt_out.store_tag_done = ((curr_store_tag == st_tag_wb_pkt.store_tag) && st_tag_wb_pkt.st_tag_broadcast) || no_pending_stores ? '1 : '0;

            ld_rs_instr_pkt_out.rs2_rdy         = '1;

            ld_rs_instr_pkt_out.ready           =  ld_rs_instr_pkt_out.rs1_rdy;

            ld_rs_instr_pkt_out.rd_addr         = instruction_data.rd_addr;
            ld_rs_instr_pkt_out.rob_idx         = rob_enque_idx[$clog2(ROB_DEPTH)-1:0];

            ld_rs_instr_pkt_out.imm_data        = instruction_data.imm_data;
            ld_rs_instr_pkt_out.mem_funct3      = instruction_data.mem_funct3;

            ld_rs_instr_pkt_out.store_tag       = curr_store_tag;

            ld_rs_instr_pkt_out.rvfi_pkt        = rvfi_pkt;
        end
        else if(instruction_data.op_bits == op_bits_t'(i_use_store) && !all_pending_stores) begin
            st_rs_instr_pkt_out.i_use_store  = '1;
            if(~rs_full_pkt.st_rs_full) begin
                rob_enque_wen     = '1;
                read_decode_queue = '1;
                store_tag_ren     = '1;
            end

            st_rs_instr_pkt_out.valid = '1;

            st_rs_instr_pkt_out.i_use_rs1    = '1;
            st_rs_instr_pkt_out.rs1_aaddr    = instruction_data.rs1_addr;
            st_rs_instr_pkt_out.rs1_paddr    = rs1_rat.p_addr;

            st_rs_instr_pkt_out.i_use_rs2    = '1;
            st_rs_instr_pkt_out.rs2_aaddr    = instruction_data.rs2_addr;
            st_rs_instr_pkt_out.rs2_paddr    = rs2_rat.p_addr;

            if((rs1_rat.p_addr == cdb_pkt.cdb_p_addr) && cdb_pkt.cdb_broadcast) st_rs_instr_pkt_out.rs1_rdy = '1;
            else if((rs1_rat.p_addr == cdb_pkt2.cdb_p_addr) && cdb_pkt2.cdb_broadcast) st_rs_instr_pkt_out.rs1_rdy = '1;
            else st_rs_instr_pkt_out.rs1_rdy = rs1_rat.valid;

            if((rs2_rat.p_addr == cdb_pkt.cdb_p_addr) && cdb_pkt.cdb_broadcast) st_rs_instr_pkt_out.rs2_rdy = '1;
            else if((rs2_rat.p_addr == cdb_pkt2.cdb_p_addr) && cdb_pkt2.cdb_broadcast) st_rs_instr_pkt_out.rs2_rdy = '1;
            else st_rs_instr_pkt_out.rs2_rdy = rs2_rat.valid;

            
            st_rs_instr_pkt_out.ready           =  st_rs_instr_pkt_out.rs2_rdy & st_rs_instr_pkt_out.rs1_rdy;

            st_rs_instr_pkt_out.rob_idx         = rob_enque_idx[$clog2(ROB_DEPTH)-1:0];

            st_rs_instr_pkt_out.imm_data        = instruction_data.imm_data;
            st_rs_instr_pkt_out.mem_funct3      = instruction_data.mem_funct3;

            st_rs_instr_pkt_out.store_tag       = free_store_tag;

            st_rs_instr_pkt_out.rvfi_pkt        = rvfi_pkt;
        end
    end
end

endmodule : dispatch_rename