module load_store_unit_split
import rv32i_types::*;
#(
    parameter               ROB_DEPTH = 32,
    parameter               LSQ_DEPTH = 8
)
(
    input   logic               clk,
    input   logic               rst,

    input   logic               dmem_resp,
    input   logic   [31:0]      dmem_rdata,

    input   logic               ld_rs_done,
    input   logic               st_rs_done,

    input   ld_st_data_pkt_t    rs_ld_pkt,
    input   ld_st_data_pkt_t    rs_st_pkt,
    input   reg_data_pkt_t      ld_prf_reg_data,
    input   reg_data_pkt_t      st_prf_reg_data,
    input   logic [$clog2(ROB_DEPTH)-1:0] rob_index,

    output  logic   [31:0]      dmem_addr,
    output  logic   [31:0]      dmem_wdata,
    output  logic   [3:0]       dmem_wmask,
    output  logic   [3:0]       dmem_rmask,

    output  logic               ld_unit_stall,
    output  logic               st_unit_stall,
    output  wb_pkt_t            load_wb_pkt,
    output  st_tag_pkt_t        st_tag_pkt,

    // ebr
    output  logic               post_st_wen, // wen signal into second queue
    output  logic [$clog2(LSQ_DEPTH):0] post_st_r_tail_idx, // st_r_tail_idx
    output  mem_pkt_t           post_st_bmask, 

    input   logic [$clog2(LSQ_DEPTH):0] post_st_w_tail_idx,
    input   cdb_pkt_t           cdb_pkt2
    );

    logic br_rst, br_en;

    logic st_pkt_fifo_empty, load_store_in_proggress, ld_fifo_empty, st_fifo_empty;
    logic ld_rs_done_latch, st_rs_done_latch;

    // Prf Reg data
    reg_data_pkt_t      ld_prf_reg_data_register, st_prf_reg_data_register, ld_prf_reg_data_register_next, st_prf_reg_data_register_next;

    reg_data_pkt_t      ld_prf_reg_data_real, st_prf_reg_data_real;

    // Mem Queue Output
    mem_pkt_t           ld_pkt_w_addr, st_pkt_w_addr;
    mem_pkt_t           st_pkt_rdy_for_op, st_pkt_rdy_for_op_real, ld_pkt_rdy_for_op, ld_pkt_rdy_for_op_real;  //st_pkt_rdy_for_op_mem, 
    mem_pkt_t           mem_unit_input_packet_next, mem_unit_input_packet_real, mem_unit_input_packet_two, mem_unit_input_packet_two_next;

    ld_st_data_pkt_t    rs_ld_pkt_reg, rs_ld_pkt_reg_next, rs_st_pkt_reg, rs_st_pkt_reg_next;


//  ld ooo queue signals
    //priority mux
    logic   ld_w_req_dispatch;
    logic   [LSQ_DEPTH-1:0] ld_ooo_queue_valid_bits;

    logic   [$clog2(LSQ_DEPTH)-1:0] ld_rs_waddr;

    logic   ld_mem_stall;

    logic   st_mem_stall;

    //ld_ooo queue
    logic ld_ooo_pkt_done;

    //priority decoder
    logic   [LSQ_DEPTH-1:0] ld_rs_ready;

    logic [$clog2(ROB_DEPTH)-1:0] rob_idx_last;

    logic   [$clog2(LSQ_DEPTH)-1:0] ld_ready_addr;

    logic st_read;
    logic ld_read;

    logic load_store_in_proggress_latch;

    logic  br_update_ld_mux;
    logic  [$clog2(LSQ_DEPTH)-1:0]  br_update_ld_mux_addr;

    logic waiting, waiting_next;
    logic load_in_proggers; 
    assign load_in_proggers = (mem_unit_input_packet_real.valid) && ((mem_unit_input_packet_real.rob_idx != rob_idx_last) || !dmem_resp);

    always_ff @(posedge clk) begin
        if(rst || br_rst) load_store_in_proggress_latch <= '0;
        else load_store_in_proggress_latch <= load_store_in_proggress;
    end

    // assign dmem_resp = st_dmem_resp | ld_dmem_resp;

    assign post_st_wen = st_pkt_w_addr.valid & ~st_unit_stall;
    assign post_st_bmask = st_pkt_w_addr;

    assign br_en = cdb_pkt2.cdb_broadcast && cdb_pkt2.br_mispred;

// Pipeline Register
always_ff @(posedge clk) begin
    if(rst) begin
        rs_ld_pkt_reg <= '0;
        rs_st_pkt_reg <= '0;

        ld_rs_done_latch <= '0;
        st_rs_done_latch <= '0;

        ld_prf_reg_data_register <= '0;
        st_prf_reg_data_register <= '0;

    end
    else begin
        ld_rs_done_latch <= ld_rs_done;
        st_rs_done_latch <= st_rs_done;

        ld_prf_reg_data_register <= ld_prf_reg_data_register_next;
        st_prf_reg_data_register <= st_prf_reg_data_register_next;

        rs_ld_pkt_reg <= rs_ld_pkt_reg_next;
        rs_st_pkt_reg <= rs_st_pkt_reg_next;
    end
end

always_comb begin
        if(ld_rs_done) begin
            rs_ld_pkt_reg_next = rs_ld_pkt;
            ld_prf_reg_data_register_next = ld_prf_reg_data;
            if(st_tag_pkt.st_tag_broadcast && (rs_ld_pkt.store_tag == st_tag_pkt.store_tag)) rs_ld_pkt_reg_next.store_tag_done = '1;

            if(cdb_pkt2.cdb_broadcast && cdb_pkt2.br_mispred && rs_ld_pkt.bmask[cdb_pkt2.br_bit]) rs_ld_pkt_reg_next.valid = '0;
            else if (cdb_pkt2.cdb_broadcast && ~cdb_pkt2.br_mispred) rs_ld_pkt_reg_next.bmask[cdb_pkt2.br_bit] = '0;
        end
        else if (ld_unit_stall) begin
            rs_ld_pkt_reg_next = rs_ld_pkt_reg;
            ld_prf_reg_data_register_next = ld_prf_reg_data_register;
            if(st_tag_pkt.st_tag_broadcast && (rs_ld_pkt_reg.store_tag == st_tag_pkt.store_tag)) rs_ld_pkt_reg_next.store_tag_done = '1;

            if(cdb_pkt2.cdb_broadcast && cdb_pkt2.br_mispred && rs_ld_pkt_reg.bmask[cdb_pkt2.br_bit]) rs_ld_pkt_reg_next.valid = '0;
            else if (cdb_pkt2.cdb_broadcast && ~cdb_pkt2.br_mispred) rs_ld_pkt_reg_next.bmask[cdb_pkt2.br_bit] = '0;
        end
        else begin
            rs_ld_pkt_reg_next = '0;
            ld_prf_reg_data_register_next = '0;
        end

        if(st_rs_done) begin
            rs_st_pkt_reg_next = rs_st_pkt;
            st_prf_reg_data_register_next = st_prf_reg_data;

            if(cdb_pkt2.cdb_broadcast && cdb_pkt2.br_mispred && rs_st_pkt.bmask[cdb_pkt2.br_bit]) rs_st_pkt_reg_next.valid = '0;
            else if (cdb_pkt2.cdb_broadcast && ~cdb_pkt2.br_mispred) rs_st_pkt_reg_next.bmask[cdb_pkt2.br_bit] = '0;
        end
        else if (st_unit_stall) begin
            rs_st_pkt_reg_next = rs_st_pkt_reg;
            st_prf_reg_data_register_next = st_prf_reg_data_register;

            if(cdb_pkt2.cdb_broadcast && cdb_pkt2.br_mispred && rs_st_pkt_reg.bmask[cdb_pkt2.br_bit]) rs_st_pkt_reg_next.valid = '0;
            else if (cdb_pkt2.cdb_broadcast && ~cdb_pkt2.br_mispred) rs_st_pkt_reg_next.bmask[cdb_pkt2.br_bit] = '0;
        end
        else begin
            rs_st_pkt_reg_next = '0;
            st_prf_reg_data_register_next = '0;
        end
end

assign ld_prf_reg_data_real = ld_unit_stall & ~ld_rs_done_latch ? ld_prf_reg_data_register : ld_prf_reg_data;
assign st_prf_reg_data_real = st_unit_stall & ~st_rs_done_latch ? st_prf_reg_data_register : st_prf_reg_data;

//Addr Calulation
//Calculate the info for the load/store send to memstage if it is not full, and decode from the fifo
addr_calculation ld_addr_calculation (
    .input_packet(rs_ld_pkt_reg),
    .rs1_data(ld_prf_reg_data_real.rs1_data),
    .rs2_data(ld_prf_reg_data_real.rs2_data),
    .st_tag_pkt(st_tag_pkt),
    .cdb_pkt2(cdb_pkt2),

    .output_packet(ld_pkt_w_addr)
);

//Addr Calulation
//Calculate the info for the load/store send to memstage if it is not full, and decode from the fifo
addr_calculation st_addr_calculation (
    .input_packet(rs_st_pkt_reg),
    .rs1_data(st_prf_reg_data_real.rs1_data),
    .rs2_data(st_prf_reg_data_real.rs2_data),
    .st_tag_pkt(st_tag_pkt),
    .cdb_pkt2(cdb_pkt2),

    .output_packet(st_pkt_w_addr)
);

// Stores
post_st_fifo #(.DEPTH(LSQ_DEPTH)) st_pkt_queue ( 
        .clk(clk),
        .rst(rst),
        .cdb_pkt2(cdb_pkt2),

        .wen(st_pkt_w_addr.valid & ~st_unit_stall),
        .ren(st_read), 
        .fifo_in(st_pkt_w_addr), 
        
        .fifo_out(st_pkt_rdy_for_op),
        .fifo_empty(st_pkt_fifo_empty), 
        .fifo_full(st_unit_stall),

        .post_st_r_tail_idx(post_st_r_tail_idx),
        .post_st_w_tail_idx(post_st_w_tail_idx)
);

// Loads
priority_mux #(.QUEUE_DEPTH(LSQ_DEPTH)) ld_priority_mux_avail_fin( 
    .w_req_left(ld_pkt_w_addr.valid),
    .valid_vect(ld_ooo_queue_valid_bits),

    .queue_raddr(ld_rs_waddr),
    .queue_full(ld_unit_stall)
);

ld_ooo_queue #(.QUEUE_DEPTH(LSQ_DEPTH)) ld_ooo_queue( 
    .clk(clk),
    .rst(rst),
    .ld_ooo_queue_wen(ld_pkt_w_addr.valid & ~ld_unit_stall),
    .ld_ooo_queue_complete(ld_ooo_pkt_done),
    .ld_ooo_queue_waddr(ld_rs_waddr),
    .ld_ooo_queue_raddr(ld_ready_addr),
    .ld_ooo_queue_pkt_in(ld_pkt_w_addr),
    .st_tag_pkt(st_tag_pkt),
    .cdb_pkt2(cdb_pkt2),

    .ld_ooo_queue_valid_bits(ld_ooo_queue_valid_bits),
    .ld_ooo_queue_ready_bits(ld_rs_ready),
    .ld_pkt_rdy_for_op(ld_pkt_rdy_for_op)
);

priority_decoder #(.QUEUE_DEPTH(LSQ_DEPTH)) ld_priority_decoder_ready_fin( 
    .clk(clk),
    .rst(rst),
    .w_req_left(ld_rs_ready),
    .w_req_right(ld_read),

    .w_req_out(ld_ooo_pkt_done),
    .queue_raddr(ld_ready_addr)
);

assign st_read = ~st_pkt_fifo_empty & ~st_mem_stall;
assign ld_read = ~ld_mem_stall;
assign st_pkt_rdy_for_op_real = ~st_pkt_fifo_empty ? st_pkt_rdy_for_op : '0;
assign ld_pkt_rdy_for_op_real = |ld_rs_ready ? ld_pkt_rdy_for_op : '0;

// -------------------------------------------------------------------

always_ff @(posedge clk) begin
    if(rst || br_rst) mem_unit_input_packet_two <= '0;
    else mem_unit_input_packet_two <= mem_unit_input_packet_two_next;
end

always_comb begin
    if (waiting) begin
        mem_unit_input_packet_two_next = mem_unit_input_packet_two;

        // if(cdb_pkt2.cdb_broadcast && cdb_pkt2.br_mispred && mem_unit_input_packet_two.bmask[cdb_pkt2.br_bit]) mem_unit_input_packet_two_next.valid = '0;
        // else if (cdb_pkt2.cdb_broadcast && ~cdb_pkt2.br_mispred) mem_unit_input_packet_two_next.bmask[cdb_pkt2.br_bit] = '0;
    end
    else if(~load_store_in_proggress_latch | dmem_resp) begin
        mem_unit_input_packet_two_next = mem_unit_input_packet_next;

        if(cdb_pkt2.cdb_broadcast && cdb_pkt2.br_mispred && mem_unit_input_packet_next.bmask[cdb_pkt2.br_bit]) mem_unit_input_packet_two_next.valid = '0;
        else if (cdb_pkt2.cdb_broadcast && ~cdb_pkt2.br_mispred) mem_unit_input_packet_two_next.bmask[cdb_pkt2.br_bit] = '0;
    end
    else begin
        mem_unit_input_packet_two_next = mem_unit_input_packet_two;
    end
end

// -------------------------------------------------------------------

logic [$clog2(ROB_DEPTH)-1:0] last_mem_issued_idx;
logic                         mem_resp_this_cycle, last_requested_mem;


always_ff @(posedge clk) begin
    if (rst || br_rst)
        last_mem_issued_idx <= '0;
    else if (~load_store_in_proggress_latch | dmem_resp)
        last_mem_issued_idx <= mem_unit_input_packet_real.rob_idx;
end

always_ff @(posedge clk) begin
    if (rst || br_rst)
        last_requested_mem <= '0;
    else if (~load_store_in_proggress_latch | dmem_resp)
        last_requested_mem <= mem_unit_input_packet_real.i_use_store;
end


assign mem_unit_input_packet_real = (~load_store_in_proggress_latch | dmem_resp) ? mem_unit_input_packet_next : mem_unit_input_packet_two;

// Arbitration of loads and stores
always_comb begin
    mem_unit_input_packet_next = '0;

    if(!(br_en && st_pkt_rdy_for_op_real.bmask[cdb_pkt2.br_bit]) && st_pkt_rdy_for_op_real.valid && ((rob_index == st_pkt_rdy_for_op_real.rob_idx) || ((st_pkt_rdy_for_op_real.rob_idx == last_mem_issued_idx+1'b1) && last_requested_mem))) begin
        mem_unit_input_packet_next = st_pkt_rdy_for_op_real;
    end
    else if(!(br_en && ld_pkt_rdy_for_op_real.bmask[cdb_pkt2.br_bit]) && ld_pkt_rdy_for_op_real.valid && ld_pkt_rdy_for_op_real.store_tag_done) begin
        mem_unit_input_packet_next = ld_pkt_rdy_for_op_real;
    end
end

always_comb begin
    ld_mem_stall = ld_pkt_rdy_for_op_real.valid && ld_pkt_rdy_for_op_real.store_tag_done || waiting;
    st_mem_stall = st_pkt_rdy_for_op_real.valid || waiting;
    if(mem_unit_input_packet_real.valid & mem_unit_input_packet_real.i_use_store) begin
        st_mem_stall = (load_store_in_proggress_latch & ~dmem_resp & st_pkt_rdy_for_op_real.valid) || waiting;
    end
    else if(mem_unit_input_packet_real.valid & ~mem_unit_input_packet_real.i_use_store) begin
        ld_mem_stall = (load_store_in_proggress_latch & ~dmem_resp & ld_pkt_rdy_for_op_real.valid && ld_pkt_rdy_for_op_real.store_tag_done) || waiting;
    end
end

// wb_pkt_t mem_pkt_out;
//Mem Stage
mem_unit #(.ROB_DEPTH(ROB_DEPTH)) mem_unit (
    //inputs
    .dmem_rdata(dmem_rdata),
    .dmem_resp(dmem_resp),
    .input_packet(mem_unit_input_packet_real),
    .clk(clk),
    .rst(rst || br_rst),
    .cdb_pkt2(cdb_pkt2),
    //outputs
    .load_store_in_proggress(load_store_in_proggress),
    .dmem_addr(dmem_addr),
    .dmem_wdata(dmem_wdata),
    .dmem_wmask(dmem_wmask),
    .dmem_rmask(dmem_rmask),
    .load_wb_pkt(load_wb_pkt),
    .st_tag_pkt(st_tag_pkt),
    .rob_idx_last(rob_idx_last)
);

always_comb begin
    if (br_en && mem_unit_input_packet_real.bmask[cdb_pkt2.br_bit] && load_in_proggers) begin
        waiting_next = 1'b1;
        br_rst = 1'b0;
    end
    else if (br_en && mem_unit_input_packet_real.bmask[cdb_pkt2.br_bit]) begin
        waiting_next = 1'b0;
        br_rst = 1'b1;
    end
    else if (waiting && dmem_resp) begin
        waiting_next = 1'b0;
        br_rst = 1'b1;
    end
    else if (waiting) begin
        waiting_next = 1'b1;
        br_rst = 1'b0;
    end
    else begin
        waiting_next = 1'b0;
        br_rst = 1'b0;
    end
end

always_ff @ (posedge clk) begin
    if (rst || br_rst) waiting <= '0;
    else waiting <= waiting_next;
end

// always_ff @(posedge clk) begin
//     if(rst) load_wb_pkt <= '0;
//     else load_wb_pkt <= mem_pkt_out;
// end


endmodule : load_store_unit_split