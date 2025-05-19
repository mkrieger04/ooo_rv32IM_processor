module fetch
import rv32i_types::*;
#(
    parameter RAS_DEPTH = 32
)(
    input   logic           clk,
    input   logic           rst,
    input   logic   [31:0]  imem_rdata,
    input   logic           imem_resp, 
    input   logic           fifo_full,
    input   logic   [255:0] linebuffer_line,
    input   logic   [31:0]  linebuffer_addr,
    input   logic           linebuffer_valid,
    input   logic   [31:0]  pc_branch,
    input   logic   [63:0]  order_branch,
    input   logic           br_en,
    input   logic   [1:0]   prediction,
    input   logic [$clog2(PHT_SIZE)-1:0] pht_index,
    input   buffer_pkt_t    next_line_pkt,
    input   logic           next_line_read,

    output  fetch_pkt_t     fetch_pkt_current,
    output  logic   [31:0]  imem_addr,
    output  logic   [3:0]   imem_rmask,

    input ras_t br_ras_top,
    input logic [$clog2(RAS_DEPTH)-1:0] br_stack_ptr_val,
    input cdb_pkt_t cdb_pkt2
    );

logic [31:0] pc, pc_next, pc_branch_next;
logic [63:0] order, order_next;
logic        br_wait, br_wait_next;
logic        push, pop;
ras_t dout, din;
logic [$clog2(RAS_DEPTH)-1:0] stack_ptr_val;
logic using_prefetch;

assign imem_addr = pc_next;  

always_ff @(posedge clk) begin
    if (rst) pc_branch_next <= '0;
    else if (br_en) pc_branch_next <= pc_branch;
    pc <= pc_next;  
    order <= order_next;
    br_wait <= br_wait_next;
end
//fix
always_comb begin
    using_prefetch = 1'b0;
    fetch_pkt_current = '0;
    fetch_pkt_current.pc = pc;
    fetch_pkt_current.pht_index = pht_index;
    fetch_pkt_current.pc_next = pc_next;
    fetch_pkt_current.order = order;
    imem_rmask = '0;   
    br_wait_next = '0;
    push = '0;
    pop = '0;
    din = '0;
    fetch_pkt_current.ras_top       = dout;
    fetch_pkt_current.stack_ptr_val = stack_ptr_val;

    // reset
    if (rst) begin
        order_next = '0;
        pc_next = 32'haaaaa000; 
    end

    else if (br_wait && imem_resp && br_en) begin
        order_next = order_branch + 1;
        pc_next = pc_branch;
    end

    else if (br_wait && !imem_resp && br_en) begin
        order_next = order_branch + 1;
        pc_next = pc_branch_next;
        br_wait_next = '1;
        imem_rmask = '1;
    end

    else if (br_wait && imem_resp) begin
        order_next = order;
        pc_next = pc_branch_next;
    end

    else if (br_wait && !imem_resp) begin
        br_wait_next = '1;
        order_next = order;
        pc_next = pc;
        imem_rmask = '1;
    end

    else if (br_en && (imem_resp || (linebuffer_valid && (pc[31:5] == linebuffer_addr[31:5])))   ) begin
        order_next = order_branch + 1;
        pc_next = pc_branch;
    end

    else if (br_en && (imem_resp || (next_line_pkt.available && (pc[31:5] == next_line_pkt.addr[31:5])))) begin
        order_next = order_branch + 1;
        pc_next = pc_branch;
    end

    else if (br_en && !imem_resp) begin
        br_wait_next = '1;
        order_next = order_branch + 1;
        pc_next = pc;
        imem_rmask = '1;
    end

    // instruction queue is full, stall
    else if (fifo_full) begin
        order_next = order;
        pc_next = pc;
    end

    // linebuffer contains the current desired instruction, fetch from there
    else if (linebuffer_valid && pc[31:5] == linebuffer_addr[31:5]) begin
        order_next = order + 1;
        pc_next = pc + 4;
        fetch_pkt_current.valid = '1;
        fetch_pkt_current.inst = linebuffer_line[pc[4:0]*8 +: 32 ];

        if (fetch_pkt_current.inst[6:0] == op_b_jal) begin
            pc_next = {{12{fetch_pkt_current.inst[31]}}, fetch_pkt_current.inst[19:12], fetch_pkt_current.inst[20], fetch_pkt_current.inst[30:21], 1'b0} + pc;
            fetch_pkt_current.prediction = '1;
            if ((fetch_pkt_current.inst[11:7] == 5'd1)) begin 
                push = '1;
                din.valid = '1;
                din.ra    = pc + 32'd4;
            end
        end
        else if (fetch_pkt_current.inst[6:0] == op_b_br) begin
            if(prediction[1]) pc_next = {{20{fetch_pkt_current.inst[31]}}, fetch_pkt_current.inst[7], fetch_pkt_current.inst[30:25], fetch_pkt_current.inst[11:8], 1'b0} + pc;
            fetch_pkt_current.prediction = prediction;
        end
        else if (fetch_pkt_current.inst[6:0] == op_b_jalr) begin
            // handle function call
            if(((fetch_pkt_current.inst[11:7] == 5'd1))) begin
                push = '1;
                din.valid = '1;
                din.ra    = pc + 32'd4;
                fetch_pkt_current.ras_top         = din;
                fetch_pkt_current.stack_ptr_val = stack_ptr_val + 1'd1;
            end
            // handle function return
            else if (dout.valid && ((fetch_pkt_current.inst[19:15] == 5'd1))) begin
                pop  = '1;
                pc_next = dout.ra;
                fetch_pkt_current.pc_pred = dout.ra;
            end
        end
        if(pc_next[4:0] == '0 && !((next_line_pkt.available && pc_next[31:5] == next_line_pkt.addr[31:5]) || (next_line_read && pc_next[31:5] == next_line_pkt.addr[31:5]))) begin
            imem_rmask = '1;
        end
    end

    else if (next_line_pkt.available && pc[31:5] == next_line_pkt.addr[31:5]) begin
        order_next = order + 1;
        pc_next = pc + 4;
        fetch_pkt_current.valid = '1;
        fetch_pkt_current.inst = next_line_pkt.data[pc[4:0]*8 +: 32 ];
        using_prefetch = 1'b1;

        if (fetch_pkt_current.inst[6:0] == op_b_jal) begin
            pc_next = {{12{fetch_pkt_current.inst[31]}}, fetch_pkt_current.inst[19:12], fetch_pkt_current.inst[20], fetch_pkt_current.inst[30:21], 1'b0} + pc;
            fetch_pkt_current.prediction = '1;
            if ((fetch_pkt_current.inst[11:7] == 5'd1)) begin 
                push = '1;
                din.valid = '1;
                din.ra    = pc + 32'd4;
            end
        end
        else if (fetch_pkt_current.inst[6:0] == op_b_br) begin
            if(prediction[1]) pc_next = {{20{fetch_pkt_current.inst[31]}}, fetch_pkt_current.inst[7], fetch_pkt_current.inst[30:25], fetch_pkt_current.inst[11:8], 1'b0} + pc;
            fetch_pkt_current.prediction = prediction;
        end
        else if (fetch_pkt_current.inst[6:0] == op_b_jalr) begin
            // handle function call
            if(((fetch_pkt_current.inst[11:7] == 5'd1))) begin
                push = '1;
                din.valid = '1;
                din.ra    = pc + 32'd4;
                fetch_pkt_current.ras_top         = din;
                fetch_pkt_current.stack_ptr_val = stack_ptr_val + 1'd1;
            end
            // handle function return
            else if (dout.valid && ((fetch_pkt_current.inst[19:15] == 5'd1))) begin
                pop  = '1;
                pc_next = dout.ra;
                fetch_pkt_current.pc_pred = dout.ra;
            end
        end
    end

    else if (!imem_resp && (next_line_read && !next_line_pkt.available && pc[31:5] == next_line_pkt.addr[31:5])) begin
        imem_rmask = '0;
        order_next = order;
        pc_next = pc;
    end

    // No memory response, send read request from imem
    else if (!imem_resp) begin
        imem_rmask = '1;
        order_next = order;
        pc_next = pc;
    end

    // received notification from icache, instruction fetched
    else begin 
        order_next = order + 1;
        pc_next = pc + 4;
        fetch_pkt_current.valid = '1;
        fetch_pkt_current.inst = imem_rdata;
        if (fetch_pkt_current.inst[6:0] == op_b_jal) begin
            pc_next = {{12{fetch_pkt_current.inst[31]}}, fetch_pkt_current.inst[19:12], fetch_pkt_current.inst[20], fetch_pkt_current.inst[30:21], 1'b0} + pc;
            fetch_pkt_current.prediction = '1;
            if ((fetch_pkt_current.inst[11:7] == 5'd1)) begin 
                push = '1;
                din.valid = '1;
                din.ra    = pc + 32'd4;
            end
        end
        else if (fetch_pkt_current.inst[6:0] == op_b_br) begin
            if(prediction[1]) pc_next = {{20{fetch_pkt_current.inst[31]}}, fetch_pkt_current.inst[7], fetch_pkt_current.inst[30:25], fetch_pkt_current.inst[11:8], 1'b0} + pc;
            fetch_pkt_current.prediction = prediction;
        end
        else if (fetch_pkt_current.inst[6:0] == op_b_jalr) begin
            // handle function call
            if(((fetch_pkt_current.inst[11:7] == 5'd1))) begin
                push = '1;
                din.valid = '1;
                din.ra    = pc + 32'd4;
                fetch_pkt_current.ras_top         = din;
                fetch_pkt_current.stack_ptr_val = stack_ptr_val + 1'd1;
            end
            // handle function return
            else if (dout.valid && ((fetch_pkt_current.inst[19:15] == 5'd1))) begin
                pop  = '1;
                pc_next = dout.ra;
                fetch_pkt_current.pc_pred = dout.ra;
            end
        end
    end
end


nick_ras #(.RAS_DEPTH(RAS_DEPTH))ras (
    .clk(clk),
    .rst(rst),
    .push(push),
    .pop(pop),
    .din(din),
    .dout(dout),
    .stack_ptr_val(stack_ptr_val),
    .br_ras_top(br_ras_top),
    .br_stack_ptr_val(br_stack_ptr_val),
    .cdb_pkt2(cdb_pkt2)
);
endmodule : fetch