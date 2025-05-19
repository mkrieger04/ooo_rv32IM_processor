// Module Desciption:
// Parameterized FIFO module that implements a circular buffer with configurable width and depth
// Remove at head
// Insert at tail
module post_st_fifo 
import rv32i_types::*;
#(
    parameter               DEPTH = 1 
)(
    input   logic             clk,
    input   logic             rst,
    input   cdb_pkt_t         cdb_pkt2,
    input   logic             wen,
    input   logic             ren,
    input   mem_pkt_t fifo_in,

    output  mem_pkt_t fifo_out,
    output  logic             fifo_empty,
    output  logic             fifo_full,

    output  logic [$clog2(DEPTH):0]   post_st_r_tail_idx,

    input   logic [$clog2(DEPTH):0]   post_st_w_tail_idx
);

// Computing pointer width
localparam PTR_WIDTH = (DEPTH == 1) ? 1 : $clog2(DEPTH); 

// Initializing local variables
mem_pkt_t   fifo_arr [DEPTH-1:0];
mem_pkt_t   fifo_arr_next [DEPTH-1:0];
logic [PTR_WIDTH:0] head_ptr, head_ptr_next;
logic [PTR_WIDTH:0] tail_ptr, tail_ptr_next;
logic full, empty;

// Assigning full and empty conditions
assign full  = (head_ptr[PTR_WIDTH] != tail_ptr[PTR_WIDTH] && head_ptr[PTR_WIDTH-1:0] == tail_ptr[PTR_WIDTH-1:0]);
assign empty = (tail_ptr == head_ptr);

assign post_st_r_tail_idx = tail_ptr;

always_comb begin 
    fifo_arr_next = fifo_arr;
    if (wen && !full) begin
        fifo_arr_next[tail_ptr[PTR_WIDTH-1:0]] = fifo_in;
    end
    for(integer unsigned i = 0; i < DEPTH; i++) begin
        if(cdb_pkt2.cdb_broadcast & ~cdb_pkt2.br_mispred) begin
            fifo_arr_next[i].bmask[cdb_pkt2.br_mispred] = '0;
        end
    end
end

// Computing pointer values for iteration
always_ff @(posedge clk) begin
    if(rst) begin
        head_ptr <= '0;
        tail_ptr <= '0;
    end
    else begin
        if (cdb_pkt2.cdb_broadcast & cdb_pkt2.br_mispred) tail_ptr <= post_st_w_tail_idx;
        else if (wen && !full) tail_ptr <= tail_ptr+1'b1;
        if (ren && !empty) head_ptr <= head_ptr+1'b1;
        if((wen && !full) || (cdb_pkt2.cdb_broadcast & ~cdb_pkt2.br_mispred)) fifo_arr <= fifo_arr_next;
    end
end

// Outputs
assign fifo_full  = full;
assign fifo_empty = empty;
assign fifo_out   = fifo_arr[head_ptr[PTR_WIDTH-1:0]];

endmodule;