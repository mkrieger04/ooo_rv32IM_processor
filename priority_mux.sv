module priority_mux
import rv32i_types::*;
#(
    parameter        QUEUE_DEPTH = 3
)(
    input   logic   w_req_left,

    input   logic[QUEUE_DEPTH-1:0]   valid_vect,

    output  logic   [$clog2(QUEUE_DEPTH)-1:0] queue_raddr,
    output  logic   queue_full
);

    assign queue_full = &valid_vect;

    always_comb begin
        queue_raddr = '0;
        if (w_req_left) begin
            for(integer unsigned i = 0; i < QUEUE_DEPTH; i++) begin
                if(valid_vect[$clog2(QUEUE_DEPTH)'(i)] == '0) begin
                    queue_raddr = $clog2(QUEUE_DEPTH)'(i);
                    break;
                end
            end
        end
    end


endmodule : priority_mux


/*
    This module implements the queue structure necessary to track issue queue occupancy. 
    The functionality is detailed below:

    1.) A write request from the left side (dispatch/rename) does NOT need to specify an address
    because it would always write to an open slot in the queue (if available). Thus, there is only
    a write request signal (w_req_left).
        - After initiating a request on the left side, the address of the free slot can be seen 
INCOMPLETE DESCRIPTION
*/