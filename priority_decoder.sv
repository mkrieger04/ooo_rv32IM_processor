module priority_decoder
import rv32i_types::*;
#(
    parameter       QUEUE_DEPTH
)(
    input   logic   clk,
    input   logic   rst,

    input   logic   [QUEUE_DEPTH-1:0] w_req_left,
    
    input   logic   w_req_right,

    output  logic   w_req_out,
    output  logic   [$clog2(QUEUE_DEPTH)-1:0] queue_raddr
);

    logic   [QUEUE_DEPTH-1:0]  queue_list;
    logic   [QUEUE_DEPTH-1:0]  queue_list_next;

    always_ff @(posedge clk) begin
        if (rst) begin
            queue_list <= '0;
        end 
        else queue_list <= queue_list_next;
    end
    
    always_comb begin
        queue_list_next      = queue_list;
        w_req_out            = '0;
        queue_raddr          = '0;

        for(integer unsigned i = 0; i < QUEUE_DEPTH; i++) begin
            queue_list_next[$clog2(QUEUE_DEPTH)'(i)] = w_req_left[$clog2(QUEUE_DEPTH)'(i)];
        end

        for(integer unsigned i = 0; i < QUEUE_DEPTH; i++) begin
            if(queue_list[$clog2(QUEUE_DEPTH)'(i)] == '1) begin
                queue_raddr = $clog2(QUEUE_DEPTH)'(i);
                break;
            end
        end

        if(w_req_right && queue_list[queue_raddr] == '1) begin
            w_req_out = '1;
            queue_list_next[queue_raddr] = '0;
        end

    end

endmodule : priority_decoder


/*
    This module implements the queue structure necessary to track issue queue occupancy. 
    The functionality is detailed below:

    1.) A write request from the left side (dispatch/rename) does NOT need to specify an address
    because it would always write to an open slot in the queue (if available). Thus, there is only
    a write request signal (w_req_left).
        - After initiating a request on the left side, the address of the free slot can be seen 
INCOMPLETE DESCRIPTION
*/