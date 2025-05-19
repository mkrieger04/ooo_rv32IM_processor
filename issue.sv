module issue
import rv32i_types::*;
#(
    parameter PRE_ST_DEPTH = 8 
)
(
    input                    clk,
    input                    rst,
    input   rs_data_pkt_t    dispatch_rename_pkt_alu_in,
    input   rs_data_pkt_t    dispatch_rename_pkt_mul_in,
    input   rs_data_pkt_t    dispatch_rename_pkt_div_in,
    input   rs_data_pkt_t    dispatch_rename_pkt_br_in,
    input   ld_st_data_pkt_t dispatch_rename_pkt_ld_in,
    input   ld_st_data_pkt_t dispatch_rename_pkt_st_in,
    // input   logic            rs_station_wen,

    input   cdb_pkt_t        cdb_pkt,
    input   cdb_pkt_t        cdb_pkt2,
    input   st_tag_pkt_t     st_tag_wb_pkt,

    input   stall_pkt_t      f_unit_stalls,
    input   logic            ld_unit_stall,
    input   logic            st_unit_stall,

    output  rs_full_pkt_t    rs_full_pkt,

    output  logic            alu_rs_done,
    output  logic            mul_rs_done,
    output  logic            div_rs_done,
    output  logic            br_rs_done,
    output  logic            ld_rs_done,
    output  logic            st_rs_done,

    output  logic            st_rs_wen,

    output  reg_addr_pkt_t   alu_prf_reg_addr,
    output  reg_addr_pkt_t   mul_prf_reg_addr,
    output  reg_addr_pkt_t   div_prf_reg_addr,
    output  reg_addr_pkt_t   br_prf_reg_addr,
    output  reg_addr_pkt_t   ld_prf_reg_addr,
    output  reg_addr_pkt_t   st_prf_reg_addr,

    output  reg_ren_pkt_t    alu_prf_reg_ren_pkt,
    output  reg_ren_pkt_t    mul_prf_reg_ren_pkt,
    output  reg_ren_pkt_t    div_prf_reg_ren_pkt,
    output  reg_ren_pkt_t    br_prf_reg_ren_pkt,
    output  reg_ren_pkt_t    ld_prf_reg_ren_pkt,
    output  reg_ren_pkt_t    st_prf_reg_ren_pkt,

    output  rs_data_pkt_t    rs_alu_pkt, 
    output  rs_data_pkt_t    rs_mul_pkt, 
    output  rs_data_pkt_t    rs_div_pkt,
    output  rs_data_pkt_t    rs_br_pkt,
    output  ld_st_data_pkt_t rs_ld_pkt,
    output  ld_st_data_pkt_t rs_st_pkt,

    // ebr
    // NOT HAVE TO CHANGE to match local param
    output logic [$clog2(PRE_ST_DEPTH):0]    pre_st_r_tail_idx,
    output logic [$clog2(PRE_ST_DEPTH):0]    pre_st_r_head_idx,
    output logic                             pre_st_ren,

    input  logic                             pre_st_flush,
    input  logic [$clog2(PRE_ST_DEPTH):0]    pre_st_w_tail_idx
);

    localparam queue_depth = 3;
    localparam alu_queue_depth = 16;
    //localparam st_queue_depth = 8;
    localparam ld_st_queue_depth = 16;

//  Alu side signals
    //priority mux
    logic   alu_w_req_dispatch;
    logic   [alu_queue_depth-1:0] alu_rs_valid;
    logic   [alu_queue_depth-1:0] alu_incoming_valid;

    logic   [$clog2(alu_queue_depth)-1:0] alu_rs_waddr;
    logic   alu_queue_full;

    //priority decoder
    logic   [alu_queue_depth-1:0] alu_rs_ready;

    // logic   alu_avail_wen_decoder; //alu_w_req_right;
    logic   [$clog2(alu_queue_depth)-1:0] alu_ready_addr;


//  Mul side signals
    //priority mux
    logic   mul_w_req_dispatch;
    logic   [queue_depth-1:0] mul_rs_valid;
    logic   [queue_depth-1:0] mul_incoming_valid;

    logic   [$clog2(queue_depth)-1:0] mul_rs_waddr;
    logic   mul_queue_full;

    //priority decoder
    logic   [queue_depth-1:0] mul_rs_ready;

    //logic   mul_rs_done; //mul_w_req_right;
    logic   [$clog2(queue_depth)-1:0] mul_ready_addr;


//  Div side signals
    //priority mux
    logic   div_w_req_dispatch;
    logic   [queue_depth-1:0] div_rs_valid;
    logic   [queue_depth-1:0] div_incoming_valid;

    logic   [$clog2(queue_depth)-1:0] div_rs_waddr;
    logic   div_queue_full;

    //priority decoder
    logic   [queue_depth-1:0] div_rs_ready;

    //logic   div_rs_done; //div_w_req_right;
    logic   [$clog2(queue_depth)-1:0] div_ready_addr;



//  br side signals
    //priority mux
    logic   br_w_req_dispatch;
    logic   [queue_depth-1:0] br_rs_valid;
    logic   [queue_depth-1:0] br_incoming_valid;

    logic   [$clog2(queue_depth)-1:0] br_rs_waddr;
    logic   br_queue_full;

    //priority decoder
    logic   [queue_depth-1:0] br_rs_ready;

    //logic   br_rs_done; //div_w_req_right;
    logic   [$clog2(queue_depth)-1:0] br_ready_addr;


//  ld side signals
    //priority mux
    logic   ld_w_req_dispatch;
    logic   [ld_st_queue_depth-1:0] ld_rs_valid;
    logic   [ld_st_queue_depth-1:0] ld_incoming_valid;

    logic   [$clog2(ld_st_queue_depth)-1:0] ld_rs_waddr;
    logic   ld_queue_full;

    //priority decoder
    logic   [ld_st_queue_depth-1:0] ld_rs_ready;

    logic   ld_rs_wen;

    //logic   br_rs_done; //div_w_req_right;
    logic   [$clog2(ld_st_queue_depth)-1:0] ld_ready_addr;


//  st side signals
    logic   st_queue_full;
    logic   st_fifo_empty;


/***************************************************************************************/
    logic alu_rs_wen, mul_rs_wen, div_rs_wen, br_rs_wen;

// full signals
    always_comb begin
        rs_full_pkt.alu_rs_full = alu_queue_full;
        rs_full_pkt.mul_rs_full = mul_queue_full;
        rs_full_pkt.div_rs_full = div_queue_full;
        rs_full_pkt.br_rs_full  = br_queue_full;
        rs_full_pkt.ld_rs_full  = ld_queue_full;
        rs_full_pkt.st_rs_full  = st_queue_full;
    end

// rs write enable signals
    // assign alu_rs_wen = rs_station_wen & dispatch_rename_pkt_alu_in.valid & ~alu_queue_full;
    // assign mul_rs_wen = rs_station_wen & dispatch_rename_pkt_alu_in.valid & ~mul_queue_full;
    // assign div_rs_wen = rs_station_wen & dispatch_rename_pkt_alu_in.valid & ~div_queue_full;

    // assign alu_w_req_dispatch = rs_station_wen & dispatch_rename_pkt_alu_in.valid;
    // assign mul_w_req_dispatch = rs_station_wen & dispatch_rename_pkt_alu_in.valid;
    // assign div_w_req_dispatch = rs_station_wen & dispatch_rename_pkt_alu_in.valid;

    assign alu_rs_wen = dispatch_rename_pkt_alu_in.valid & ~alu_queue_full;
    assign mul_rs_wen = dispatch_rename_pkt_mul_in.valid & ~mul_queue_full;
    assign div_rs_wen = dispatch_rename_pkt_div_in.valid & ~div_queue_full;
    assign br_rs_wen  = dispatch_rename_pkt_br_in.valid  & ~br_queue_full;
    assign ld_rs_wen  = dispatch_rename_pkt_ld_in.valid  & ~ld_queue_full;
    assign st_rs_wen  = dispatch_rename_pkt_st_in.valid  & ~st_queue_full;

    assign alu_w_req_dispatch = dispatch_rename_pkt_alu_in.valid;
    assign mul_w_req_dispatch = dispatch_rename_pkt_mul_in.valid;
    assign div_w_req_dispatch = dispatch_rename_pkt_div_in.valid;
    assign br_w_req_dispatch  = dispatch_rename_pkt_br_in.valid;
    assign ld_w_req_dispatch  = dispatch_rename_pkt_ld_in.valid;

    assign st_rs_done         = ~st_fifo_empty & ~st_unit_stall & rs_st_pkt.ready;

    priority_mux #(.QUEUE_DEPTH(alu_queue_depth)) alu_priority_mux_avail( 
        .w_req_left(alu_w_req_dispatch),
        .valid_vect(alu_rs_valid),

        .queue_raddr(alu_rs_waddr),
        .queue_full(alu_queue_full)
    );

    issue_queue_age_order #(.QUEUE_DEPTH(alu_queue_depth)) alu_issue_queue( 
        .clk(clk),
        .rst(rst),
        .rs_station_wen(alu_rs_wen),
        .rs_station_complete(alu_rs_done),
        .rs_station_waddr(alu_rs_waddr),
        .rs_station_raddr(alu_ready_addr),
        .dispatch_rename_pkt_in(dispatch_rename_pkt_alu_in),
        .cdb_pkt(cdb_pkt),
        .cdb_pkt2(cdb_pkt2),

        .rs_prf_reg_addr(alu_prf_reg_addr),
        .rs_prf_reg_ren_pkt(alu_prf_reg_ren_pkt),
        .rs_queue_valid_bits(alu_rs_valid),
        .incoming_valid_bits(alu_incoming_valid), 
        .rs_ready_bits(alu_rs_ready),
        .rs_pkt_out(rs_alu_pkt)
    );


    age_order_decoder #(.QUEUE_DEPTH(alu_queue_depth)) alu_priority_decoder_ready( 
        .clk(clk),
        .rst(rst),

        .ready_bits(alu_rs_ready),
        .valid_bits(alu_incoming_valid),

        .wen(alu_rs_wen),
        .insert_idx(alu_rs_waddr),
        .clear_en(cdb_pkt2.cdb_broadcast & cdb_pkt2.br_mispred),
        
        .w_req_right(~f_unit_stalls.alu_stall),

        .w_req_out(alu_rs_done),
        .queue_raddr(alu_ready_addr)
    );

    // priority_decoder #(.QUEUE_DEPTH(alu_queue_depth)) alu_priority_decoder_ready( 
    //     .clk(clk),
    //     .rst(rst),
    //     .w_req_left(alu_rs_ready),
    //     .w_req_right(~f_unit_stalls.alu_stall),

    //     .w_req_out(alu_rs_done),
    //     .queue_raddr(alu_ready_addr)
    // );

    priority_mux #(.QUEUE_DEPTH(queue_depth)) mul_priority_mux_avail( 
        .w_req_left(mul_w_req_dispatch),
        .valid_vect(mul_rs_valid),

        .queue_raddr(mul_rs_waddr),
        .queue_full(mul_queue_full)
    );

    issue_queue_age_order #(.QUEUE_DEPTH(queue_depth)) mul_issue_queue( 

        .clk(clk),
        .rst(rst),
        .rs_station_wen(mul_rs_wen),
        .rs_station_complete(mul_rs_done),
        .rs_station_waddr(mul_rs_waddr),
        .rs_station_raddr(mul_ready_addr),
        .dispatch_rename_pkt_in(dispatch_rename_pkt_mul_in),
        .cdb_pkt(cdb_pkt),
        .cdb_pkt2(cdb_pkt2),

        .rs_prf_reg_addr(mul_prf_reg_addr),
        .rs_prf_reg_ren_pkt(mul_prf_reg_ren_pkt),
        .rs_queue_valid_bits(mul_rs_valid),
        .rs_ready_bits(mul_rs_ready),
        .incoming_valid_bits(mul_incoming_valid), 
        .rs_pkt_out(rs_mul_pkt)
    );

    age_order_decoder #(.QUEUE_DEPTH(queue_depth)) mul_priority_decoder_ready( 
        .clk(clk),
        .rst(rst),

        .ready_bits(mul_rs_ready),
        .valid_bits(mul_incoming_valid),

        .wen(mul_rs_wen),
        .insert_idx(mul_rs_waddr),
        .clear_en(cdb_pkt2.cdb_broadcast & cdb_pkt2.br_mispred),
        
        .w_req_right(~f_unit_stalls.mul_stall),

        .w_req_out(mul_rs_done),
        .queue_raddr(mul_ready_addr)
    );

    // priority_decoder #(.QUEUE_DEPTH(queue_depth)) mul_priority_decoder_ready( 
    //     .clk(clk),
    //     .rst(rst),
    //     .w_req_left(mul_rs_ready),
    //     .w_req_right(~f_unit_stalls.mul_stall),

    //     .w_req_out(mul_rs_done),
    //     .queue_raddr(mul_ready_addr)
    // );

    priority_mux #(.QUEUE_DEPTH(queue_depth)) div_priority_mux_avail( 
        .w_req_left(div_w_req_dispatch),
        .valid_vect(div_rs_valid),

        .queue_raddr(div_rs_waddr),
        .queue_full(div_queue_full)
    );

    issue_queue_age_order #(.QUEUE_DEPTH(queue_depth)) div_issue_queue( 

        .clk(clk),
        .rst(rst),
        .rs_station_wen(div_rs_wen),
        .rs_station_complete(div_rs_done),
        .rs_station_waddr(div_rs_waddr),
        .rs_station_raddr(div_ready_addr),
        .dispatch_rename_pkt_in(dispatch_rename_pkt_div_in),
        .cdb_pkt(cdb_pkt),
        .cdb_pkt2(cdb_pkt2),

        .rs_prf_reg_addr(div_prf_reg_addr),
        .rs_prf_reg_ren_pkt(div_prf_reg_ren_pkt),
        .rs_queue_valid_bits(div_rs_valid),
        .rs_ready_bits(div_rs_ready),
        .incoming_valid_bits(div_incoming_valid), 
        .rs_pkt_out(rs_div_pkt)
    );

    age_order_decoder #(.QUEUE_DEPTH(queue_depth)) div_priority_decoder_ready( 
        .clk(clk),
        .rst(rst),

        .ready_bits(div_rs_ready),
        .valid_bits(div_incoming_valid),

        .wen(div_rs_wen),
        .insert_idx(div_rs_waddr),
        .clear_en(cdb_pkt2.cdb_broadcast & cdb_pkt2.br_mispred),
        
        .w_req_right(~f_unit_stalls.div_stall),

        .w_req_out(div_rs_done),
        .queue_raddr(div_ready_addr)
    );

    // priority_decoder #(.QUEUE_DEPTH(queue_depth)) div_priority_decoder_ready( 
    //     .clk(clk),
    //     .rst(rst),
    //     .w_req_left(div_rs_ready),
    //     .w_req_right(~f_unit_stalls.div_stall),

    //     .w_req_out(div_rs_done),
    //     .queue_raddr(div_ready_addr)
    // );

    priority_mux #(.QUEUE_DEPTH(queue_depth)) br_priority_mux_avail( 
        .w_req_left(br_w_req_dispatch),
        .valid_vect(br_rs_valid),

        .queue_raddr(br_rs_waddr),
        .queue_full(br_queue_full)
    );

    issue_queue_age_order #(.QUEUE_DEPTH(queue_depth)) br_issue_queue( 

        .clk(clk),
        .rst(rst),
        .rs_station_wen(br_rs_wen),
        .rs_station_complete(br_rs_done),
        .rs_station_waddr(br_rs_waddr),
        .rs_station_raddr(br_ready_addr),
        .dispatch_rename_pkt_in(dispatch_rename_pkt_br_in),
        .cdb_pkt(cdb_pkt),
        .cdb_pkt2(cdb_pkt2),

        .rs_prf_reg_addr(br_prf_reg_addr),
        .rs_prf_reg_ren_pkt(br_prf_reg_ren_pkt),
        .rs_queue_valid_bits(br_rs_valid),
        .rs_ready_bits(br_rs_ready),
        .incoming_valid_bits(br_incoming_valid), 
        .rs_pkt_out(rs_br_pkt)
    );

    age_order_decoder #(.QUEUE_DEPTH(queue_depth)) br_priority_decoder_ready( 
        .clk(clk),
        .rst(rst),

        .ready_bits(br_rs_ready),
        .valid_bits(br_incoming_valid),

        .wen(br_rs_wen),
        .insert_idx(br_rs_waddr),
        .clear_en(cdb_pkt2.cdb_broadcast & cdb_pkt2.br_mispred),
        
        .w_req_right(~f_unit_stalls.br_stall),

        .w_req_out(br_rs_done),
        .queue_raddr(br_ready_addr)
    );

    // priority_decoder #(.QUEUE_DEPTH(queue_depth)) br_priority_decoder_ready( 
    //     .clk(clk),
    //     .rst(rst),
    //     .w_req_left(br_rs_ready),
    //     .w_req_right(~f_unit_stalls.br_stall),

    //     .w_req_out(br_rs_done),
    //     .queue_raddr(br_ready_addr)
    // );
    
    priority_mux #(.QUEUE_DEPTH(ld_st_queue_depth)) ld_priority_mux_avail( 
        .w_req_left(ld_w_req_dispatch),
        .valid_vect(ld_rs_valid),

        .queue_raddr(ld_rs_waddr),
        .queue_full(ld_queue_full)
    );

    ld_st_issue_queue_age_order #(.QUEUE_DEPTH(ld_st_queue_depth)) ld_issue_queue( 

        .clk(clk),
        .rst(rst),
        .rs_station_wen(ld_rs_wen),
        .rs_station_complete(ld_rs_done),
        .rs_station_waddr(ld_rs_waddr),
        .rs_station_raddr(ld_ready_addr),
        .dispatch_rename_pkt_in(dispatch_rename_pkt_ld_in),
        .cdb_pkt(cdb_pkt),
        .cdb_pkt2(cdb_pkt2),
        .st_tag_pkt(st_tag_wb_pkt),

        .rs_prf_reg_addr(ld_prf_reg_addr),
        .rs_prf_reg_ren_pkt(ld_prf_reg_ren_pkt),
        .rs_queue_valid_bits(ld_rs_valid),
        .rs_ready_bits(ld_rs_ready),
        .incoming_valid_bits(ld_incoming_valid), 
        .rs_pkt_out(rs_ld_pkt)
    );

    age_order_decoder #(.QUEUE_DEPTH(ld_st_queue_depth)) ld_priority_decoder_ready( 
        .clk(clk),
        .rst(rst),

        .ready_bits(ld_rs_ready),
        .valid_bits(ld_incoming_valid),

        .wen(ld_rs_wen),
        .insert_idx(ld_rs_waddr),
        .clear_en(cdb_pkt2.cdb_broadcast & cdb_pkt2.br_mispred),
        
        .w_req_right(~ld_unit_stall),

        .w_req_out(ld_rs_done),
        .queue_raddr(ld_ready_addr)
    );

    // priority_decoder #(.QUEUE_DEPTH(ld_st_queue_depth)) ld_priority_decoder_ready( 
    //     .clk(clk),
    //     .rst(rst),
    //     .w_req_left(ld_rs_ready),
    //     .w_req_right(~ld_unit_stall),

    //     .w_req_out(ld_rs_done),
    //     .queue_raddr(ld_ready_addr)
    // );

    assign pre_st_ren = st_rs_done;

    //NOTE IF YOU CHANGE DEPTH HAVE TO CHANGE PARAM IN CPU.sv
    load_store_fifo #(.DEPTH(PRE_ST_DEPTH)) store_fifo (
        .clk(clk),
        .rst(rst),
        .wen(st_rs_wen),
        .ren(st_rs_done), 
        .fifo_in(dispatch_rename_pkt_st_in),
        .cdb_pkt(cdb_pkt),
        .cdb_pkt2(cdb_pkt2),

        .st_prf_reg_addr(st_prf_reg_addr),
        .st_prf_reg_ren_pkt(st_prf_reg_ren_pkt),
        .fifo_empty(st_fifo_empty),
        .fifo_out(rs_st_pkt),
        .fifo_full(st_queue_full),

        .pre_st_r_tail_idx(pre_st_r_tail_idx),
        .pre_st_r_head_idx(pre_st_r_head_idx),
        .pre_st_flush(pre_st_flush),
        .pre_st_w_tail_idx(pre_st_w_tail_idx)
    );


endmodule : issue