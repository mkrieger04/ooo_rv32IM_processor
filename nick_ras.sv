module nick_ras 
import rv32i_types::*;
#(
    parameter RAS_DEPTH = 32
)(
    input  logic clk,           
    input  logic rst,           
    input  logic push,          
    input  logic pop,         
    input  ras_t din,   
    output ras_t dout,
    output [$clog2(RAS_DEPTH)-1:0] stack_ptr_val,
    input ras_t br_ras_top,
    input logic [$clog2(RAS_DEPTH)-1:0] br_stack_ptr_val,
    input cdb_pkt_t cdb_pkt2       
);

ras_t ras[RAS_DEPTH];
logic [$clog2(RAS_DEPTH)-1:0] stack_ptr;
logic empty;

always_ff @(posedge clk) begin
    if(rst) begin
        for(integer unsigned i = 0; i < RAS_DEPTH; i++) begin
            ras[i].valid <= '0;
        end
        stack_ptr <= '0;
    end
    else if(cdb_pkt2.cdb_broadcast & cdb_pkt2.br_mispred)begin
        ras[br_stack_ptr_val - 1'b1] <= br_ras_top;
        stack_ptr <= br_stack_ptr_val;
    end
    else if(push) begin
        ras[stack_ptr] <= din;
        stack_ptr <= stack_ptr + 1'b1;
    end
    else if (pop) begin
        ras[stack_ptr - 1'b1].valid <= '0;
        stack_ptr <= stack_ptr - 1'b1;
    end
end

assign dout = ras[stack_ptr - 1'b1];
assign stack_ptr_val = stack_ptr;

endmodule