// Module Desciption:
// Parameterized FIFO module that implements a circular buffer with configurable width and depth
// Remove at head
// Insert at tail

module fifo #(
    parameter               WIDTH = 8,
    parameter               DEPTH = 1 
)(
    input   logic             clk,
    input   logic             rst,
    input   logic             wen,
    input   logic             ren,
    input   logic [WIDTH-1:0] fifo_in,

    output  logic [WIDTH-1:0] fifo_out,
    output  logic             fifo_empty,
    output  logic             fifo_full
);

// Computing pointer width
localparam PTR_WIDTH = (DEPTH == 1) ? 1 : $clog2(DEPTH); 

// Initializing local variables
logic [WIDTH-1:0]   fifo_arr [DEPTH-1:0];
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

        if (wen && !full) begin
            fifo_arr[tail_ptr[PTR_WIDTH-1:0]] <= fifo_in;
        end
    end
end

// Computing next pointer values
assign tail_ptr_next = (wen && !full)  ? tail_ptr+1'b1 : tail_ptr;
assign head_ptr_next = (ren && !empty) ? head_ptr+1'b1 : head_ptr;

// Outputs
assign fifo_full  = full;
assign fifo_empty = empty;
assign fifo_out   = fifo_arr[head_ptr[PTR_WIDTH-1:0]];

endmodule;