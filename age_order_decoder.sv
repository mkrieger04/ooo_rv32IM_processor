module age_order_decoder
import rv32i_types::*;
#(
    parameter       QUEUE_DEPTH
)(
    input   logic   clk,
    input   logic   rst,

    input   logic   [QUEUE_DEPTH-1:0] ready_bits,
    input   logic   [QUEUE_DEPTH-1:0] valid_bits,

    input   logic   clear_en,
    input   logic   wen,

    input   logic   [$clog2(QUEUE_DEPTH)-1:0] insert_idx,
    
    input   logic   w_req_right,

    output  logic   w_req_out,
    output  logic   [$clog2(QUEUE_DEPTH)-1:0] queue_raddr
);

    // Computing pointer width
    localparam PTR_WIDTH = (QUEUE_DEPTH == 1) ? 1 : $clog2(QUEUE_DEPTH); 

    // Initializing local variables
    logic [$clog2(QUEUE_DEPTH)-1:0]  fifo_arr [QUEUE_DEPTH-1:0];
    logic [$clog2(QUEUE_DEPTH)-1:0]  fifo_arr_next [QUEUE_DEPTH-1:0];
    logic [$clog2(QUEUE_DEPTH)-1:0]  fifo_arr_br [QUEUE_DEPTH-1:0];
    logic [PTR_WIDTH:0] tail_ptr, tail_ptr_next, tail_ptr_br;
    logic full, empty, entered;
    logic [$clog2(QUEUE_DEPTH)-1:0] found_idx;

    assign full  = (32'(tail_ptr) == unsigned'(QUEUE_DEPTH));
    assign empty = (tail_ptr == 0);

// ----------------------------------------------------------------------------------------------
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

        for(integer unsigned i = 0; i < QUEUE_DEPTH; i++) begin
            queue_list_next[$clog2(QUEUE_DEPTH)'(i)] = ready_bits[$clog2(QUEUE_DEPTH)'(i)];
        end

        if(w_req_right && queue_list[queue_raddr] == '1) begin
            w_req_out = '1;
            queue_list_next[queue_raddr] = '0;
        end

    end
// ----------------------------------------------------------------------------------------------


    always_ff @(posedge clk) begin
        if(rst) begin
            tail_ptr <= '0;
            for (integer unsigned i = 0; i < QUEUE_DEPTH; i++)
                fifo_arr[i] <= '0;
        end
        else if(clear_en) begin
            tail_ptr <= tail_ptr_br;
            for (integer unsigned i = 0; i < QUEUE_DEPTH; i++)
                fifo_arr[i] <= fifo_arr_br[i];
        end
        else begin
            tail_ptr <= tail_ptr_next;
            for (integer unsigned i = 0; i < QUEUE_DEPTH; i++)
                fifo_arr[i] <= fifo_arr_next[i];
        end
    end

    always_comb begin
        tail_ptr_next = tail_ptr;
        queue_raddr = '0;
        found_idx = '0;
        entered = '0;
        tail_ptr_br = '0;

        for (integer unsigned i = 0; i < QUEUE_DEPTH; i++) begin
            if(tail_ptr[PTR_WIDTH]) begin
                if ((($clog2(QUEUE_DEPTH))'(i) < ($clog2(QUEUE_DEPTH))'(tail_ptr - 1'b1)) && (queue_list[fifo_arr[i]]=='1)) begin
                    found_idx = ($clog2(QUEUE_DEPTH))'(i);
                    queue_raddr = fifo_arr[found_idx];
                    break;
                end
            end
            else begin
                if ((($clog2(QUEUE_DEPTH))'(i) < ($clog2(QUEUE_DEPTH))'(tail_ptr)) && (queue_list[fifo_arr[i]]=='1)) begin
                    found_idx = ($clog2(QUEUE_DEPTH))'(i);
                    queue_raddr = fifo_arr[found_idx];
                    break;
                end
            end
        end


        for (integer unsigned i = 0; i < QUEUE_DEPTH; i++) begin
            fifo_arr_next[i] = fifo_arr[i];
            fifo_arr_br[i]      = '0;
        end

        if (clear_en) begin

            for (integer unsigned i = 0; i < unsigned'(QUEUE_DEPTH); i++) begin
                if ((($clog2(QUEUE_DEPTH))'(i) < ($clog2(QUEUE_DEPTH))'(tail_ptr)) && 
                    (valid_bits[fifo_arr[i]] == '1) && 
                    ((($clog2(QUEUE_DEPTH))'(tail_ptr) ) > 0)) begin
                    fifo_arr_br[tail_ptr_br] = fifo_arr[i];
                    tail_ptr_br = tail_ptr_br + 1'b1;
                    entered = '1;
                end
            end

            if (wen && ((entered && (32'(tail_ptr_br) < unsigned'(QUEUE_DEPTH))) || (!entered && !full))) begin
                fifo_arr_br[tail_ptr_br] = insert_idx;
                tail_ptr_br = tail_ptr_br + 1'b1;
            end

        end

        else if (w_req_out && !wen && !empty) begin
            for (integer unsigned i = 0; i < unsigned'(QUEUE_DEPTH)-1; i++) begin
                if ((i >= 32'(found_idx)) && (($clog2(QUEUE_DEPTH))'(i) < ($clog2(QUEUE_DEPTH))'(tail_ptr)-1'b1) && (($clog2(QUEUE_DEPTH))'(tail_ptr) - 1'b1) > 0)
                    fifo_arr_next[i] = fifo_arr[i+1];
            end
            tail_ptr_next = tail_ptr - 1'b1;
        end
        else if (w_req_out && wen && !empty) begin
            for (integer unsigned i = 0; i < unsigned'(QUEUE_DEPTH)-1; i++) begin
                if ((i >= 32'(found_idx)) && (($clog2(QUEUE_DEPTH))'(i) < ($clog2(QUEUE_DEPTH))'(tail_ptr)-1'b1) && (($clog2(QUEUE_DEPTH))'(tail_ptr) - 1'b1) > 0)
                    fifo_arr_next[i] = fifo_arr[i+1];
            end
            fifo_arr_next[($clog2(QUEUE_DEPTH))'(tail_ptr)-1'b1] = insert_idx;
        end
        else if (wen && !full)  begin
            fifo_arr_next[($clog2(QUEUE_DEPTH))'(tail_ptr)] = insert_idx;
            tail_ptr_next = tail_ptr + 1'b1;
        end

    end

endmodule : age_order_decoder
