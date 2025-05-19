// Module rob:
// Reorder buffer interacting with cdb, dispatch/rename stage, and commit stage

module rob
import rv32i_types::*;
#(
    parameter               ROB_DEPTH  = 64
)(
    input   logic                   clk,
    input   logic                   rst,

    // cdb I/O
    input   cdb_pkt_t               cdb_pkt,
    input   cdb_pkt_t               cdb_pkt2,

    // dispatch/rename stage I/O
    input   logic                   rob_enque_wen,
    input   rob_pkt_t               rob_enque_pkt,

    output  logic [$clog2(ROB_DEPTH):0] rob_enque_idx,
    output  logic                         rob_full,

    // commit stage I/O
    input   logic                   commit_ren,

    output  rob_pkt_t               rob_top_pkt,
    output  logic                   rob_empty,

    output  logic   [$clog2(ROB_DEPTH)-1:0] rob_head,


    // ebr I/O
    input   logic [$clog2(ROB_DEPTH):0] br_rob_tail

);

// Computing pointer width
localparam PTR_WIDTH = (ROB_DEPTH == 1) ? 1 : $clog2(ROB_DEPTH); 

// Initializing local variables
rob_pkt_t   rob_fifo [ROB_DEPTH-1:0];
logic [PTR_WIDTH:0] head_ptr, head_ptr_next;
logic [PTR_WIDTH:0] tail_ptr, tail_ptr_next;
logic full, empty;

// Assigning full and empty conditions
assign full  = (head_ptr[PTR_WIDTH] != tail_ptr[PTR_WIDTH]) && (head_ptr[PTR_WIDTH-1:0] == tail_ptr[PTR_WIDTH-1:0]);
assign empty = (tail_ptr == head_ptr);

assign rob_head  = head_ptr[PTR_WIDTH-1:0];
// Computing pointer values for iteration
always_ff @(posedge clk) begin
    if(rst) begin
        head_ptr <= '0;
        tail_ptr <= '0;
    end
    else if (cdb_pkt2.br_mispred & cdb_pkt2.cdb_broadcast) begin
        if (commit_ren && !empty) head_ptr <= head_ptr+1'b1;
        tail_ptr <= br_rob_tail;

        if (cdb_pkt.cdb_broadcast) begin //& ~cdb_pkt.br_bmask[cdb_pkt2.br_bit]
            rob_fifo[cdb_pkt.cdb_rob_idx].done <= '1;
            rob_fifo[cdb_pkt.cdb_rob_idx].rvfi_pkt <= cdb_pkt.rvfi_pkt;
        end

            rob_fifo[cdb_pkt2.cdb_rob_idx].done <= '1;
            rob_fifo[cdb_pkt2.cdb_rob_idx].rvfi_pkt <= cdb_pkt2.rvfi_pkt;

    end
    else begin
        if (commit_ren && !empty) head_ptr <= head_ptr+1'b1;
        if (rob_enque_wen && !full) tail_ptr <= tail_ptr+1'b1;
        // head_ptr <= head_ptr_next;
        // tail_ptr <= tail_ptr_next;

        // enque to rob
        if (rob_enque_wen && !full) begin
            rob_fifo[tail_ptr[PTR_WIDTH-1:0]] <= rob_enque_pkt;
        end
        
        // mark instr on cdb to done
        if (cdb_pkt.cdb_broadcast) begin
            rob_fifo[cdb_pkt.cdb_rob_idx].done <= '1;
            rob_fifo[cdb_pkt.cdb_rob_idx].rvfi_pkt <= cdb_pkt.rvfi_pkt;
            // rob_fifo[cdb_pkt.cdb_rob_idx].br_en <= cdb_pkt.br_en;
            // rob_fifo[cdb_pkt.cdb_rob_idx].pc_next <= cdb_pkt.pc_next;
        end

        if (cdb_pkt2.cdb_broadcast) begin
            rob_fifo[cdb_pkt2.cdb_rob_idx].done <= '1;
            rob_fifo[cdb_pkt2.cdb_rob_idx].rvfi_pkt <= cdb_pkt2.rvfi_pkt;
            // rob_fifo[cdb_pkt2.cdb_rob_idx].br_en <= cdb_pkt2.br_en;
            // rob_fifo[cdb_pkt2.cdb_rob_idx].pc_next <= cdb_pkt2.pc_next;
        end
    end
end

// Computing next pointer values
// assign tail_ptr_next = (rob_enque_wen && !full)  ? tail_ptr+1'b1 : tail_ptr;
// //Head should increment when the current instruction at head is ready to be commited
// assign head_ptr_next = (commit_ren && !empty) ? head_ptr+1'b1 : head_ptr;

// Outputs
assign rob_full     = full;
assign rob_empty    = empty;
assign rob_top_pkt  = rob_fifo[head_ptr[PTR_WIDTH-1:0]];
assign rob_enque_idx = tail_ptr[PTR_WIDTH:0]; 

endmodule;