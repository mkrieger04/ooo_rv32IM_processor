module cpu
import rv32i_types::*;
(
    input   logic               clk,
    input   logic               rst,

    output  logic   [31:0]      bmem_addr,
    output  logic               bmem_read,
    output  logic               bmem_write,
    output  logic   [63:0]      bmem_wdata,
    input   logic               bmem_ready,

    input   logic   [31:0]      bmem_raddr,
    input   logic   [63:0]      bmem_rdata,
    input   logic               bmem_rvalid
);

    localparam ROB_DEPTH = 32; 
    localparam PHT_SIZE = 128;
    localparam TAG_DEPTH = 16;
    localparam BMASK_DEPTH = 3;
    localparam PRE_ST_DEPTH = 16;
    localparam LSQ_DEPTH    = 16;
    localparam RAS_DEPTH    = 4;
    
    logic [31:0] imem_addr, imem_rdata, dmem_rdata, buffer_rdata;
    logic [3:0]  imem_rmask, imem_wmask;
    logic imem_resp, dmem_resp, linebuffer_valid;
    logic fifo_full_instruction_queue, fifo_empty_instruction_queue, fifo_full_decode_queue, fifo_empty_decode_queue;
    logic read_decode_queue, rob_full, rat_rename_rd_we;

    logic   [31:0]       icache_addr, dcache_addr, linebuffer_addr;
    logic                icache_read, dcache_read;
    logic                icache_write, dcache_write;
    logic   [255:0]      icache_rdata, dcache_rdata;
    logic   [255:0]      icache_wdata, dcache_wdata;
    logic   [255:0]      linebuffer_line;
    logic                icache_resp, dcache_resp;

    logic   [255:0]      latest_hit_line;
    logic   [31:0]       latest_hit_line_addr;
    logic   [$clog2(ROB_DEPTH + 32)-1:0] rd_p_addr_rename_val;
    logic   [4:0]        cdb_paddr, rs1_s_dispatch_rename_out, rs2_s_dispatch_rename_out, rd_s_dispatch_rename_out;

    reg_ren_pkt_t        iss_alu_prf_reg_ren_pkt, iss_mul_prf_reg_ren_pkt, iss_div_prf_reg_ren_pkt, iss_br_prf_reg_ren_pkt, iss_ld_prf_reg_ren_pkt, iss_st_prf_reg_ren_pkt;
    reg_addr_pkt_t       iss_alu_prf_reg_addr_pkt, iss_mul_prf_reg_addr_pkt, iss_div_prf_reg_addr_pkt, iss_br_prf_reg_addr_pkt, iss_ld_prf_reg_addr_pkt, iss_st_prf_reg_addr_pkt;

    logic   [31:0]       prf_alu_rs1_data, prf_alu_rs2_data;
    logic   [31:0]       prf_mul_rs1_data, prf_mul_rs2_data;
    logic   [31:0]       prf_div_rs1_data, prf_div_rs2_data;
    logic   [31:0]       prf_br_rs1_data, prf_br_rs2_data;

    rs_data_pkt_t        issue_rs_alu_pkt, issue_rs_mul_pkt, issue_rs_div_pkt, issue_rs_br_pkt;
    stall_pkt_t          wb_unit_stalls, f_unit_stalls;

    logic                ld_unit_stall, st_unit_stall;

    wb_pkt_t             exec_alu_wb_pkt, exec_mul_wb_pkt, exec_div_wb_pkt, exec_br_wb_pkt, load_wb_pkt;

    // logic                rs_station_wen;
    cdb_pkt_t            cdb_pkt, cdb_pkt2;
    rs_full_pkt_t        rs_full_pkt;

    fetch_pkt_t fetch_pkt_current, instruction_queue_pkt_out;
    decode_pkt_t decode_pkt_current, decode_queue_pkt_out;
    ratatouille_t rs1_rat, rs2_rat;
    rs_data_pkt_t alu_rs_instr_pkt_out, mul_rs_instr_pkt_out, div_rs_instr_pkt_out, br_rs_instr_pkt_out;
    ld_st_data_pkt_t ld_rs_instr_pkt_out, st_rs_instr_pkt_out, issue_rs_ld_pkt, issue_rs_st_pkt;
    rvfi_pkt_t rvfi_pkt_out_out;
    logic [$clog2(ROB_DEPTH)-1:0] rob_index;
    
    logic  commit_read;
    logic  rrat_wen;
    logic [4:0] rrat_rd_s;
    logic [$clog2(ROB_DEPTH+32)-1:0] rrat_p_addr;


    logic   [$clog2(ROB_DEPTH + 32)-1:0] free_p_addr;
    logic   dispatch_ren;
    logic   write, read;

    logic            rrat_kick;
    logic [$clog2(ROB_DEPTH + 32)-1:0] rrat_kick_p_addr;

    // rob I/O
    rob_pkt_t   rob_enque_pkt;
    rob_pkt_t   rob_top_pkt;
    logic       rob_enque_wen;
    logic [$clog2(ROB_DEPTH):0] rob_enque_idx;      
    logic       rob_empty;


    reg_data_pkt_t   alu_prf_reg_data;
    reg_data_pkt_t   mul_prf_reg_data;
    reg_data_pkt_t   div_prf_reg_data;
    reg_data_pkt_t   br_prf_reg_data;
    reg_data_pkt_t   ld_prf_reg_data;
    reg_data_pkt_t   st_prf_reg_data;

    logic alu_rs_done, mul_rs_done, div_rs_done, br_rs_done, ld_rs_done, st_rs_done;
    logic [31:0] pc_branch;
    // logic [63:0] order_branch; 

    logic [$clog2(ROB_DEPTH + 32)-1:0] rrat_data[32];

    logic [31:0] dmem_addr, dmem_wdata;


    logic   [$clog2(ROB_DEPTH)-1:0] rob_head;

    logic [1:0] rob_prediction;
    logic [4:0] rd_s;

    // store tag list I/O
    logic   [$clog2(TAG_DEPTH)-1:0] curr_store_tag;
    logic   [$clog2(TAG_DEPTH)-1:0] free_store_tag;
    logic   store_tag_ren;

    logic   [$clog2(TAG_DEPTH)-1:0] wb_store_tag;
    logic   wb_store_tag_kick;

    logic   no_pending_stores;
    logic   all_pending_stores;
    logic   st_rs_wen;
    st_tag_pkt_t        st_tag_wb_pkt;
    logic br_load_stall;

    logic [$clog2(PRE_ST_DEPTH):0]    pre_st_r_tail_idx;
    logic [$clog2(PRE_ST_DEPTH):0]    pre_st_r_head_idx;   
    logic                             pre_st_flush;
    logic [$clog2(PRE_ST_DEPTH):0]    pre_st_w_tail_idx;

    logic              post_st_wen;
    logic [$clog2(LSQ_DEPTH):0] post_st_r_tail_idx;

    logic [$clog2(LSQ_DEPTH):0]   post_st_w_tail_idx;
    mem_pkt_t      post_st_bmask;
    logic   [TAG_DEPTH - 1:0] store_tag_list_real;

    logic [TAG_DEPTH - 1:0] br_store_tag_list;
    logic [$clog2(TAG_DEPTH)-1:0] br_curr_store_tag;
    logic pre_st_ren;

    ras_t br_ras_top;
    logic [$clog2(RAS_DEPTH)-1:0] br_stack_ptr_val;

    //Pre-fetch 
    logic nl_mem_resp, cache_miss_complete;
    logic [31:0] next_line_addr;
    logic [255:0] next_line_data;
    buffer_pkt_t  next_line_pkt;
    logic next_line_read;


    always_ff @(posedge clk) begin
        if(rst) curr_store_tag <= '0;
        else if(cdb_pkt2.cdb_broadcast && cdb_pkt2.br_mispred) curr_store_tag <= br_curr_store_tag;
        else if(st_rs_wen) curr_store_tag <= free_store_tag;
    end

    // instruction cache
    // Description: Interfaces with fetch stage, arbitor, and line buffer
    icache_eddie icache (
        .clk(clk),
        .rst(rst),

        .ufp_addr(imem_addr),
        .ufp_rmask(imem_rmask),
        .ufp_wmask(4'b0),
        .ufp_rdata(imem_rdata),
        .ufp_wdata(32'b0), 
        .ufp_resp(imem_resp),

        .latest_hit_line(latest_hit_line),
        .latest_hit_line_addr(latest_hit_line_addr),

        .dfp_addr(icache_addr),
        .dfp_read(icache_read),
        .dfp_write(icache_write),
        .dfp_rdata(icache_rdata),
        .dfp_wdata(icache_wdata),
        .dfp_resp(icache_resp),

        //Pre-fetch signals
        .cache_miss_complete(cache_miss_complete),
        .next_line_addr(next_line_addr)
    ); 


    logic [3:0] dmem_wmask, dmem_rmask;
    // data cache
    // Description: Interfaces with arbitor and load/store unit
    cache_pp_data dcache_eddie(
        .clk(clk),
        .rst(rst),

        .ufp_addr(dmem_addr), 
        .ufp_rmask(dmem_rmask), 
        .ufp_wmask(dmem_wmask), 
        .ufp_rdata(dmem_rdata),
        .ufp_wdata(dmem_wdata), 
        .ufp_resp(dmem_resp),

        .dfp_addr(dcache_addr),
        .dfp_read(dcache_read),
        .dfp_write(dcache_write),
        .dfp_rdata(dcache_rdata),
        .dfp_wdata(dcache_wdata),
        .dfp_resp(dcache_resp)
    ); 

    //On commit update GHR and PHT with correct results.
    //  -Already storing branch result in rat. Will need to also store prediction
    //  -Will need to store PHT index

    logic [1:0] prediction;
    // logic gshare_we;
    logic [$clog2(PHT_SIZE)-1:0] pht_index_in, pht_index_out;

    gshare #(.GHR_SIZE($clog2(PHT_SIZE)), .PHT_SIZE(PHT_SIZE)) gstring(
        .clk(clk),
        .rst(rst),
        .pc(imem_addr),
        .outcome(cdb_pkt2.br_en), //what is the actual result of the branch?
        .we(cdb_pkt2.cdb_broadcast & cdb_pkt2.is_branch),  //tells us when to write ghr and pht
        .pht_index_in(cdb_pkt2.pht_index),
        .rob_prediction(cdb_pkt2.prediction),

        .pht_index_out(pht_index_out),
        .prediction(prediction)
    );

    // Linebuffer
    // Description: linebuffer that interfaces with fetch and instruction cache
    linebuffer linebuffer(
        .clk(clk),
        .rst(rst),
        .latest_hit_line(latest_hit_line),
        .imem_resp(imem_resp),
        .latest_hit_line_addr(latest_hit_line_addr),

        .linebuffer_line(linebuffer_line),
        .linebuffer_addr(linebuffer_addr),
        .linebuffer_valid(linebuffer_valid)
    );

    // cacheline arbitor, interfaces with instruction cache, data cache, and dram
    nextline nextline(
        .clk(clk),
        .rst(rst),
        .next_line_data(next_line_data),
        .nl_mem_resp(nl_mem_resp),
        .cache_miss_complete(cache_miss_complete),
        .next_line_addr(next_line_addr),
        .next_line_read(next_line_read),

        .next_line_pkt(next_line_pkt)
    );

    // cacheline arbitor, interfaces with instruction cache, data cache, and dram
    cacheline_adp cacheline_adp(
        .clk(clk),
        .rst(rst),
        .bmem_addr(bmem_addr),
        .bmem_read(bmem_read),
        .bmem_write(bmem_write),
        .bmem_wdata(bmem_wdata),
        .bmem_ready(bmem_ready),

        .bmem_raddr(bmem_raddr),
        .bmem_rdata(bmem_rdata),
        .bmem_rvalid(bmem_rvalid),

        .icache_addr(icache_addr),
        .icache_read(icache_read),
        .icache_write(icache_write),
        .icache_rdata(icache_rdata),
        .icache_wdata(icache_wdata),
        .icache_resp(icache_resp),

        //prefetch signals
        .next_line_read(next_line_read),
        .nl_mem_resp(nl_mem_resp),
        .next_line_addr(next_line_pkt.addr),
        .next_line_data(next_line_data),

        .dcache_addr(dcache_addr),
        .dcache_read(dcache_read),
        .dcache_write(dcache_write),
        .dcache_rdata(dcache_rdata),
        .dcache_wdata(dcache_wdata),
        .dcache_resp(dcache_resp)
    );

    // fetch stage
    // Interfaces with line adapter, instruction cache, and instruction queue
    fetch #(.RAS_DEPTH(RAS_DEPTH)) fetch(
        //inputs
        .clk(clk),
        .rst(rst),
        .br_en(cdb_pkt2.br_mispred & cdb_pkt2.cdb_broadcast),
        .pc_branch(cdb_pkt2.pc_next),
        .order_branch(cdb_pkt2.rvfi_pkt.monitor_order),
        .imem_rdata(imem_rdata),
        .imem_resp(imem_resp),
        .fifo_full(fifo_full_instruction_queue),
        .linebuffer_line(linebuffer_line),
        .linebuffer_addr(linebuffer_addr),
        .linebuffer_valid(linebuffer_valid),
        .prediction(prediction),
        .pht_index(pht_index_out),
        .next_line_pkt(next_line_pkt),
        .next_line_read(next_line_read),

        //outputs
        .imem_addr(imem_addr),
        .imem_rmask(imem_rmask),
        .fetch_pkt_current(fetch_pkt_current),
        .br_ras_top(br_ras_top),
        .br_stack_ptr_val(br_stack_ptr_val),
        .cdb_pkt2(cdb_pkt2)
    );

    // instruction fifo
    // Description: between fetch and decode, fetch writes in, decode reads out
    fifo #(.WIDTH($bits(fetch_pkt_current)), .DEPTH(32)) instruction_queue ( 
        .clk(clk),
        .rst(rst || (cdb_pkt2.br_mispred & cdb_pkt2.cdb_broadcast)),
        .wen(fetch_pkt_current.valid),
        .ren(read_decode_queue), 
        .fifo_in(fetch_pkt_current), 
        
        .fifo_out(instruction_queue_pkt_out),
        .fifo_empty(fifo_empty_instruction_queue), 
        .fifo_full(fifo_full_instruction_queue)
    );

    // decode stage
    // interfaces with instruction queue and decode queue
    decode decode(
        //inputs
        .instruction_queue_pkt_in(instruction_queue_pkt_out),
        .fifo_empty_instruction_queue(fifo_empty_instruction_queue),

        //outputs
        .decode_pkt_out(decode_pkt_current)
    );

    // decode queue
    // interfaces with decode stage and dispatch / rename stage
    // fifo #(.WIDTH($bits(decode_pkt_current)), .DEPTH(8)) decode_queue ( 
    //     .clk(clk),
    //     .rst(rst || (cdb_pkt2.br_mispred & cdb_pkt2.cdb_broadcast)),

    //     .wen(decode_pkt_current.instr_pkt.i_valid),
    //     .ren(read_decode_queue), 
    //     .fifo_in(decode_pkt_current), 
        
    //     .fifo_out(decode_queue_pkt_out),
    //     .fifo_empty(fifo_empty_decode_queue), 
    //     .fifo_full(fifo_full_decode_queue)
    // );

    ratatouille_t  br_rat[32];
    logic [$clog2(ROB_DEPTH):0] br_rob_tail;
    logic [ROB_DEPTH + 31:0]  br_free_list;
    ratatouille_t  rat_data[32];
    logic [ROB_DEPTH + 31:0]  free_listdata;

    dispatch_rename #(.ROB_DEPTH(ROB_DEPTH), .LSQ_DEPTH(LSQ_DEPTH), .TAG_DEPTH(16), .BMASK_DEPTH(BMASK_DEPTH), .PRE_ST_DEPTH(PRE_ST_DEPTH),.RAS_DEPTH(RAS_DEPTH)) dispatch_rename (
        // Decode I/O
        .fifo_empty_decode_queue(fifo_empty_instruction_queue),
        .instruction_data(decode_pkt_current.instr_pkt),
        .rvfi_pkt(decode_pkt_current.rvfi_pkt),

        .read_decode_queue(read_decode_queue),

        // Rat I/O
        .rs1_rat(rs1_rat),
        .rs2_rat(rs2_rat),

        .rd_s(rd_s),
        .rd_rename_we(rat_rename_rd_we),
        .rd_p_addr_rename_val(rd_p_addr_rename_val),

        // ROB I/O
        .rob_full(rob_full),
        .rob_enque_idx(rob_enque_idx),

        .rob_enque_pkt(rob_enque_pkt),
        .rob_enque_wen(rob_enque_wen),

        // CDB I/O
        .cdb_pkt(cdb_pkt),
        .cdb_pkt2(cdb_pkt2),

        // free_list I/O
        .free_p_addr(free_p_addr),

        .dispatch_ren(dispatch_ren),

        // store tag list I/O
        .curr_store_tag(curr_store_tag),
        .free_store_tag(free_store_tag),
        .st_tag_wb_pkt(st_tag_wb_pkt),
        .no_pending_stores(no_pending_stores),
        .all_pending_stores(all_pending_stores),

        .store_tag_ren(store_tag_ren),

        // Issue I/O
        .rs_full_pkt(rs_full_pkt),

        .alu_rs_instr_pkt_out(alu_rs_instr_pkt_out),
        .mul_rs_instr_pkt_out(mul_rs_instr_pkt_out),
        .div_rs_instr_pkt_out(div_rs_instr_pkt_out),
        .br_rs_instr_pkt_out(br_rs_instr_pkt_out),
        .ld_rs_instr_pkt_out(ld_rs_instr_pkt_out),
        .st_rs_instr_pkt_out(st_rs_instr_pkt_out),
        // .rs_station_wen(rs_station_wen)

        // ebr
        .rrat_kick_p_addr(rrat_kick_p_addr),
        .rrat_kick(rrat_kick),

        .br_rat(br_rat),
        .br_free_list(br_free_list),
        .br_rob_tail(br_rob_tail),

        .clk(clk),
        .rst(rst),

        .rat(rat_data),
        .free_list(free_listdata),

        .pre_st_r_tail_idx(pre_st_r_tail_idx),
        .pre_st_r_head_idx(pre_st_r_head_idx),   
        .pre_st_flush(pre_st_flush),
        .pre_st_w_tail_idx(pre_st_w_tail_idx),

        .post_st_wen(post_st_wen),
        .post_st_r_tail_idx(post_st_r_tail_idx),
        .post_st_w_tail_idx(post_st_w_tail_idx),
        .post_st_bmask(post_st_bmask),
        .store_tag_list_real(store_tag_list_real),

        .br_store_tag_list(br_store_tag_list),
        .br_curr_store_tag(br_curr_store_tag),

        .pre_st_ren(pre_st_ren),

        .br_ras_top(br_ras_top),
        .br_stack_ptr_val(br_stack_ptr_val)
    );


    
    ratatouille #(.ROB_DEPTH(ROB_DEPTH)) ratatouille(
        .clk(clk),
        .rst(rst),
        // .br_en(br_en),

        // cdb I/O
        .cdb_pkt(cdb_pkt),
        .cdb_pkt2(cdb_pkt2),

        // Dispatch/rename I/O
        .rat_rename_rd_we(rat_rename_rd_we),
        .rd_p_addr_rename_val(rd_p_addr_rename_val),
        .rs1_s(decode_pkt_current.instr_pkt.rs1_addr),
        .rs2_s(decode_pkt_current.instr_pkt.rs2_addr),
        .rd_s(rd_s),
        
        .rs1_rat(rs1_rat),
        .rs2_rat(rs2_rat),

        .br_rat(br_rat),
        .rat_data(rat_data)
    );
   
    rob #(.ROB_DEPTH(ROB_DEPTH)) rob( 
        .clk(clk),
        .rst(rst),

        //cdb I/O
        .cdb_pkt(cdb_pkt),
        .cdb_pkt2(cdb_pkt2),

        // dispatch/rename I/O
        .rob_enque_wen(rob_enque_wen),
        .rob_enque_pkt(rob_enque_pkt), 
        .rob_enque_idx(rob_enque_idx), 
        .rob_full(rob_full), 

        // commit I/O
        .commit_ren(commit_read), 
        .rob_top_pkt(rob_top_pkt), 
        .rob_empty(rob_empty),

        .rob_head(rob_head),

        // ebr
        .br_rob_tail(br_rob_tail)
    ); 

    issue #(.PRE_ST_DEPTH(PRE_ST_DEPTH))issue 
    (
        // Inputs
        .clk(clk),
        .rst(rst),

        .dispatch_rename_pkt_alu_in(alu_rs_instr_pkt_out),
        .dispatch_rename_pkt_mul_in(mul_rs_instr_pkt_out),
        .dispatch_rename_pkt_div_in(div_rs_instr_pkt_out),
        .dispatch_rename_pkt_br_in(br_rs_instr_pkt_out),
        .dispatch_rename_pkt_ld_in(ld_rs_instr_pkt_out),
        .dispatch_rename_pkt_st_in(st_rs_instr_pkt_out),
        // .rs_station_wen(rs_station_wen),

        .cdb_pkt(cdb_pkt),
        .cdb_pkt2(cdb_pkt2),
        .st_tag_wb_pkt(st_tag_wb_pkt),

        .f_unit_stalls(f_unit_stalls),
        .ld_unit_stall(ld_unit_stall),
        .st_unit_stall(st_unit_stall),

        // Outputs
        .rs_full_pkt(rs_full_pkt),

        .alu_rs_done(alu_rs_done),
        .mul_rs_done(mul_rs_done),
        .div_rs_done(div_rs_done),
        .br_rs_done(br_rs_done),
        .ld_rs_done(ld_rs_done),
        .st_rs_done(st_rs_done),

        .st_rs_wen(st_rs_wen),

        .alu_prf_reg_addr(iss_alu_prf_reg_addr_pkt),
        .mul_prf_reg_addr(iss_mul_prf_reg_addr_pkt),
        .div_prf_reg_addr(iss_div_prf_reg_addr_pkt),
        .br_prf_reg_addr(iss_br_prf_reg_addr_pkt),
        .ld_prf_reg_addr(iss_ld_prf_reg_addr_pkt),
        .st_prf_reg_addr(iss_st_prf_reg_addr_pkt),

        .alu_prf_reg_ren_pkt(iss_alu_prf_reg_ren_pkt),
        .mul_prf_reg_ren_pkt(iss_mul_prf_reg_ren_pkt),
        .div_prf_reg_ren_pkt(iss_div_prf_reg_ren_pkt),
        .br_prf_reg_ren_pkt(iss_br_prf_reg_ren_pkt),
        .ld_prf_reg_ren_pkt(iss_ld_prf_reg_ren_pkt),
        .st_prf_reg_ren_pkt(iss_st_prf_reg_ren_pkt),

        .rs_alu_pkt(issue_rs_alu_pkt),
        .rs_mul_pkt(issue_rs_mul_pkt),
        .rs_div_pkt(issue_rs_div_pkt),
        .rs_br_pkt(issue_rs_br_pkt),
        .rs_ld_pkt(issue_rs_ld_pkt),
        .rs_st_pkt(issue_rs_st_pkt),

        .pre_st_r_tail_idx(pre_st_r_tail_idx),
        .pre_st_r_head_idx(pre_st_r_head_idx),   
        .pre_st_flush(pre_st_flush),
        .pre_st_w_tail_idx(pre_st_w_tail_idx),
        .pre_st_ren(pre_st_ren)
    );

    prf #(.PRF_DEPTH(ROB_DEPTH + 32)) prf( 
        .clk(clk),
        .rst(rst),

        .cdb_pkt(cdb_pkt),
        .cdb_pkt2(cdb_pkt2),

        .alu_prf_reg_addr(iss_alu_prf_reg_addr_pkt),
        .mul_prf_reg_addr(iss_mul_prf_reg_addr_pkt),
        .div_prf_reg_addr(iss_div_prf_reg_addr_pkt),
        .br_prf_reg_addr(iss_br_prf_reg_addr_pkt),
        .ld_prf_reg_addr(iss_ld_prf_reg_addr_pkt),
        .st_prf_reg_addr(iss_st_prf_reg_addr_pkt),

        .alu_prf_reg_ren_pkt(iss_alu_prf_reg_ren_pkt),
        .mul_prf_reg_ren_pkt(iss_mul_prf_reg_ren_pkt),
        .div_prf_reg_ren_pkt(iss_div_prf_reg_ren_pkt),
        .br_prf_reg_ren_pkt(iss_br_prf_reg_ren_pkt),
        .ld_prf_reg_ren_pkt(iss_ld_prf_reg_ren_pkt),
        .st_prf_reg_ren_pkt(iss_st_prf_reg_ren_pkt),

        .alu_prf_reg_data(alu_prf_reg_data),
        .mul_prf_reg_data(mul_prf_reg_data),
        .div_prf_reg_data(div_prf_reg_data),
        .br_prf_reg_data(br_prf_reg_data),
        .ld_prf_reg_data(ld_prf_reg_data),
        .st_prf_reg_data(st_prf_reg_data)
    );

    

    load_store_unit_split #(.ROB_DEPTH(ROB_DEPTH), .LSQ_DEPTH(LSQ_DEPTH)) load_store_unit_split(
        .clk(clk),
        .rst(rst),

        .dmem_resp(dmem_resp),
        .dmem_rdata(dmem_rdata),

        .ld_rs_done(ld_rs_done),
        .st_rs_done(st_rs_done),

        .rs_ld_pkt(issue_rs_ld_pkt),
        .rs_st_pkt(issue_rs_st_pkt),
        .ld_prf_reg_data(ld_prf_reg_data),
        .st_prf_reg_data(st_prf_reg_data),
        .rob_index(rob_head),

        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_wmask(dmem_wmask),
        .dmem_rmask(dmem_rmask),

        .ld_unit_stall(ld_unit_stall),
        .st_unit_stall(st_unit_stall),
        .load_wb_pkt(load_wb_pkt),
        .st_tag_pkt(st_tag_wb_pkt),

        .post_st_wen(post_st_wen),
        .post_st_r_tail_idx(post_st_r_tail_idx),
        .post_st_w_tail_idx(post_st_w_tail_idx),
        .post_st_bmask(post_st_bmask),
        .cdb_pkt2(cdb_pkt2)
        );
    
// RETIRED 
    // load_store_unit_split load_store_unit_split(
    //     .clk(clk),
    //     .rst(rst || br_en),
    //     .ld_st_data_pkt(ld_st_data_pkt),
    //     .dmem_rdata(dmem_rdata),
    //     .dmem_resp(dmem_resp),
    //     .cdb_pkt(cdb_pkt),
    //     .load_store_prf_reg_data(load_store_prf_reg_data),
    //     .ld_fifo_wen(ld_fifo_wen),
    //     .st_fifo_wen(st_fifo_wen),
    //     .dmem_addr(dmem_addr),
    //     .dmem_wdata(dmem_wdata),
    //     .load_store_stall(load_store_stall),
    //     .dmem_wmask(dmem_wmask),
    //     .dmem_rmask(dmem_rmask),
    //     .load_wb_pkt(load_wb_pkt),
    //     .load_store_prf_reg_addr(load_store_prf_reg_addr),
    //     .load_store_prf_reg_ren_pkt(load_store_prf_reg_ren_pkt),
    //     .rob_index(rob_head)
    // );

    execute execute( 
        // Inputs
        .clk(clk),
        .rst(rst),
        .rs_alu_pkt(issue_rs_alu_pkt),
        .rs_mul_pkt(issue_rs_mul_pkt),
        .rs_div_pkt(issue_rs_div_pkt),
        .rs_branch_pkt(issue_rs_br_pkt),
        .alu_rs_done(alu_rs_done),
        .mul_rs_done(mul_rs_done),
        .div_rs_done(div_rs_done),
        .branch_rs_done(br_rs_done),

        .alu_rs1_data(alu_prf_reg_data.rs1_data), 
        .alu_rs2_data(alu_prf_reg_data.rs2_data),
        .mul_rs1_data(mul_prf_reg_data.rs1_data), 
        .mul_rs2_data(mul_prf_reg_data.rs2_data),
        .div_rs1_data(div_prf_reg_data.rs1_data),
        .div_rs2_data(div_prf_reg_data.rs2_data),
        .branch_rs1_data(br_prf_reg_data.rs1_data),
        .branch_rs2_data(br_prf_reg_data.rs2_data),

        .wb_unit_stalls(wb_unit_stalls), // contains alu_stall, mul_stall, and div_stalls coming in from the WB stage

        // Outputs
        .f_unit_stalls(f_unit_stalls),   // contains stalls for the functional units when busy
        
        .alu_wb_pkt(exec_alu_wb_pkt),
        .mul_wb_pkt(exec_mul_wb_pkt),
        .div_wb_pkt(exec_div_wb_pkt),
        .branch_wb_pkt(exec_br_wb_pkt),
        .cdb_pkt2(cdb_pkt2)
    );

    writeback writeback 
    (
        // Inputs
        .alu_wb_pkt(exec_alu_wb_pkt),
        .mul_wb_pkt(exec_mul_wb_pkt),
        .div_wb_pkt(exec_div_wb_pkt),
        .br_wb_pkt(exec_br_wb_pkt), 
        .load_wb_pkt(load_wb_pkt), 

        // Outputs
        .wb_unit_stalls(wb_unit_stalls),

        .cdb_pkt(cdb_pkt),
        .cdb_pkt2(cdb_pkt2)
    );

    free_list #(.ROB_DEPTH(ROB_DEPTH)) free_list( 
        .clk(clk),
        .rst(rst),

        // RRAT I/O
        .rrat_kick_p_addr(rrat_kick_p_addr),
        .rrat_kick(rrat_kick),

        // Dispatch I/O
        .dispatch_ren(dispatch_ren), // issue read request

        .free_p_addr(free_p_addr), // free address output

        // Commit I/O
        // .rrat_wen(rrat_wen),
        // .br_en(br_en),
        // .rrat_p_addr(rrat_p_addr),

        // ebr I/O
        .br_free_list(br_free_list),
        .cdb_pkt2(cdb_pkt2),
        .free_listdata(free_listdata)
    );


    store_tag_list #(.TAG_DEPTH(16)) store_tag_list(
        .clk(clk),
        .rst(rst),

        // WB
        .wb_store_tag(st_tag_wb_pkt.store_tag),
        .wb_store_tag_kick(st_tag_wb_pkt.st_tag_broadcast),

        // Dispatch/Rename I/O
        .stq_ren(store_tag_ren),

        .no_pending_stores(no_pending_stores),
        .all_pending_stores(all_pending_stores),
        .free_store_tag(free_store_tag),

        .store_tag_list_real(store_tag_list_real),
        .br_store_tag_list(br_store_tag_list),
        .cdb_pkt2(cdb_pkt2)
    );

    // commit #(.ROB_DEPTH(ROB_DEPTH)) commit(
    //     // ROB I/O
    //     .rob_top_pkt(rob_top_pkt),
    //     .rob_empty(rob_empty),

    //     .commit_read(commit_read),

    //     // RRAT I/O
    //     .rrat_rd_s(rrat_rd_s),
    //     .rrat_p_addr(rrat_p_addr),
    //     .rrat_wen(rrat_wen)
    // );

    logic           monitor_valid;
    logic   [63:0]  monitor_order;
    logic   [31:0]  monitor_inst;
    logic   [4:0]   monitor_rs1_addr;
    logic   [4:0]   monitor_rs2_addr;
    logic   [31:0]  monitor_rs1_rdata;
    logic   [31:0]  monitor_rs2_rdata;
    logic           monitor_regf_we;
    logic   [4:0]   monitor_rd_addr;
    logic   [31:0]  monitor_rd_wdata;
    logic   [31:0]  monitor_pc_rdata;
    logic   [31:0]  monitor_pc_wdata;
    logic   [31:0]  monitor_mem_addr;
    logic   [3:0]   monitor_mem_rmask;
    logic   [3:0]   monitor_mem_wmask;
    logic   [31:0]  monitor_mem_rdata;
    logic   [31:0]  monitor_mem_wdata;



    rrat #(.ROB_DEPTH(ROB_DEPTH)) rrat(
        .clk(clk),
        .rst(rst),

        // Commit I/O
        .rrat_wen(rrat_wen),
        .rrat_rd_s(rrat_rd_s),
        .rrat_p_addr(rrat_p_addr),

        // Free List I/O
        .rrat_kick(rrat_kick),
        .rrat_kick_p_addr(rrat_kick_p_addr),
        .rrat_next(rrat_data)
    );

logic [63:0] total_jal_instructions, total_jal_missed;

always_ff @(posedge clk) begin
    if(rst) begin
        total_jal_instructions <= '0;
        total_jal_missed <= '0;
    end
    else if(cdb_pkt2.cdb_broadcast) begin
        if (cdb_pkt2.rvfi_pkt.monitor_inst[6:0] == op_b_jal) begin
            total_jal_instructions <= total_jal_instructions + 1'b1;
            if (cdb_pkt2.br_mispred) total_jal_missed <= total_jal_missed + 1'b1;
    end
end
end

logic [63:0] total_br_instructions, total_br_missed;
always_ff @(posedge clk) begin
    if(rst) begin
        total_br_instructions <= '0;
        total_br_missed <= '0;
    end
    else if(cdb_pkt2.cdb_broadcast) begin
        if (cdb_pkt2.rvfi_pkt.monitor_inst[6:0] == op_b_br) begin
            total_br_instructions <= total_br_instructions + 1'b1;
            if (cdb_pkt2.br_mispred) total_br_missed <= total_br_missed + 1'b1;
        end
    end
end

logic [63:0] total_jalr_instructions, total_jalr_missed;

always_ff @(posedge clk) begin
    if(rst) begin
        total_jalr_instructions <= '0;
        total_jalr_missed <= '0;
    end
    else if(cdb_pkt2.cdb_broadcast)
        if (cdb_pkt2.rvfi_pkt.monitor_inst[6:0] == op_b_jalr) begin
            total_jalr_instructions <= total_jalr_instructions + 1'b1;
            if (cdb_pkt2.br_mispred) total_jalr_missed <= total_jalr_missed + 1'b1;
    end
end

always_comb begin
    commit_read = '0;
    rrat_wen    = '0;
    rrat_rd_s   = rob_top_pkt.rd_s;
    rrat_p_addr = rob_top_pkt.p_addr;
    // remove instruction from rob and insert to rrat
    if(rob_top_pkt.done && ~rob_empty) begin
        commit_read = '1;
        rrat_wen    = '1; //may want to check if rd is zero
    end
end

assign    monitor_valid     = (rob_top_pkt.done && ~rob_empty ? rob_top_pkt.rvfi_pkt.monitor_valid : '0);
assign    monitor_order     = rob_top_pkt.rvfi_pkt.monitor_order;
assign    monitor_inst      = rob_top_pkt.rvfi_pkt.monitor_inst;
assign    monitor_rs1_addr  = rob_top_pkt.rvfi_pkt.monitor_rs1_addr;
assign    monitor_rs2_addr  = rob_top_pkt.rvfi_pkt.monitor_rs2_addr;
assign    monitor_rs1_rdata = rob_top_pkt.rvfi_pkt.monitor_rs1_rdata;
assign    monitor_rs2_rdata = rob_top_pkt.rvfi_pkt.monitor_rs2_rdata;
assign    monitor_rd_addr   = rob_top_pkt.rvfi_pkt.monitor_rd_addr;
assign    monitor_rd_wdata  = rob_top_pkt.rvfi_pkt.monitor_rd_wdata;
assign    monitor_pc_rdata  = rob_top_pkt.rvfi_pkt.monitor_pc_rdata;
assign    monitor_pc_wdata  = (rob_top_pkt.rvfi_pkt.monitor_pc_wdata);
assign    monitor_mem_addr  = rob_top_pkt.rvfi_pkt.monitor_mem_addr;
assign    monitor_mem_rmask     = rob_top_pkt.rvfi_pkt.monitor_mem_rmask;
assign    monitor_mem_wmask     = rob_top_pkt.rvfi_pkt.monitor_mem_wmask;
assign    monitor_mem_rdata     = rob_top_pkt.rvfi_pkt.monitor_mem_rdata;
assign    monitor_mem_wdata = rob_top_pkt.rvfi_pkt.monitor_mem_wdata;

endmodule : cpu