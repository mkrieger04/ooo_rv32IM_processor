// Module Desciption:
// Parameterized FIFO module that implements a circular buffer with configurable width and depth
// Remove at head
// Insert at tail
module store_fifo 
import rv32i_types::*;
#(
    parameter               DEPTH = 1 
)(
    input   logic             clk,
    input   logic             rst,
    input   logic             wen,
    input   logic             ren,
    input   ld_st_data_pkt_t  fifo_in,
    input   cdb_pkt_t         cdb_pkt,

    output  ld_st_data_pkt_t  fifo_out,
    output  logic             fifo_empty,
    output  logic             fifo_full
);

// Computing pointer width
localparam PTR_WIDTH = (DEPTH == 1) ? 1 : $clog2(DEPTH); 

// Initializing local variables
ld_st_data_pkt_t   fifo_arr [DEPTH-1:0];
// set ready bits for rs1, rs2, and 
ld_st_data_pkt_t   fifo_arr_next [DEPTH-1:0];
logic [PTR_WIDTH:0] head_ptr, head_ptr_next;
logic [PTR_WIDTH:0] tail_ptr, tail_ptr_next;
logic full, empty;

// Assigning full and empty conditions
assign full  = (head_ptr[PTR_WIDTH] != tail_ptr[PTR_WIDTH] && head_ptr[PTR_WIDTH-1:0] == tail_ptr[PTR_WIDTH-1:0]);
assign empty = (tail_ptr == head_ptr);

// Computing pointer values for iteration
always_ff @(posedge clk) begin
    if(rst) begin
        head_ptr <= '0;
        tail_ptr <= '0;
    end
    else begin
        head_ptr <= head_ptr_next;
        tail_ptr <= tail_ptr_next;
        fifo_arr <= fifo_arr_next;
    end
end

// Computing next pointer values
assign tail_ptr_next = (wen && !full)  ? tail_ptr+1'b1 : tail_ptr;
assign head_ptr_next = (ren && !empty) ? head_ptr+1'b1 : head_ptr;

// Outputs
assign fifo_full  = full;
assign fifo_empty = empty;
assign fifo_out   = fifo_arr[head_ptr[PTR_WIDTH-1:0]];


always_comb begin
    fifo_arr_next = fifo_arr;
    if(cdb_pkt.cdb_broadcast) begin
        for(integer unsigned i = 0; i < DEPTH; i++) begin
            if((cdb_pkt.cdb_p_addr == fifo_arr[$clog2(DEPTH)'(i)].rs1_paddr)) fifo_arr_next[$clog2(DEPTH)'(i)].rs1_rdy = '1;
            if((cdb_pkt.cdb_p_addr == fifo_arr[$clog2(DEPTH)'(i)].rs2_paddr)) fifo_arr_next[$clog2(DEPTH)'(i)].rs2_rdy = '1;
            // can move to a different for loop
            if(fifo_arr_next[$clog2(DEPTH)'(i)].rs1_rdy && fifo_arr_next[$clog2(DEPTH)'(i)].rs2_rdy) fifo_arr_next[$clog2(DEPTH)'(i)].ready = '1;
        end
    end
    if (wen && !full) begin // probably a comb loop, just rename wen
        fifo_arr_next[tail_ptr[PTR_WIDTH-1:0]] = fifo_in;
    end

end


endmodule;