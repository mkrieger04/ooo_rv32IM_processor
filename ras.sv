// module ras 
// import rv32i_types::*;
// #(
//     parameter STACK_DEPTH = 32
// )(
//     input  logic clk,           
//     input  logic rst,           
//     input  logic push,          
//     input  logic pop,         
//     input  logic pop_push,  
//     input  logic [31:0] din,    

//     output logic [31:0] dout,   
//     output logic empty         
// );

// localparam integer STACK_DEPTH_BITS = $clog2(STACK_DEPTH);

// logic [31:0] stack [0:STACK_DEPTH-1]; 
// logic [STACK_DEPTH_BITS-1:0] stack_top; 
// logic [STACK_DEPTH_BITS-1:0] stack_bottom; 
// logic [STACK_DEPTH_BITS:0] count; 

// assign dout = stack[(stack_top - 1) & (STACK_DEPTH-1)]; 
// assign empty = (count == 0);

// always_ff @(posedge clk) begin
//     if (rst) begin
//         stack_top <= '0;
//         stack_bottom <= '0;
//         count <= '0;
//     end else begin
//         if (pop_push) begin
//             if (!empty) begin
//                 stack_top <= (stack_top - 1'b1) & (STACK_DEPTH_BITS'(STACK_DEPTH-1));
//                 stack[(stack_top - 1'b1) & (STACK_DEPTH_BITS'(STACK_DEPTH-1))] <= din;
//             end else begin
//                 stack[stack_top] <= din;
//                 stack_top <= (stack_top + 1'b1) & (STACK_DEPTH_BITS'(STACK_DEPTH-1));
//                 count <= 6'd1;
//             end
//         end
//         else if (push) begin
//             stack[stack_top] <= din;
//             stack_top <= (stack_top + 1'b1) & (STACK_DEPTH_BITS'(STACK_DEPTH-1));
//             if (count == STACK_DEPTH[STACK_DEPTH_BITS:0]) begin
//                 stack_bottom <= (stack_bottom + 1'b1) & (STACK_DEPTH_BITS'(STACK_DEPTH-1));
//             end else begin
//                 count <= count + 1'b1;
//             end
//         end 
//         else if (pop) begin
//             if (!empty) begin
//                 stack_top <= (stack_top - 1'b1) & (STACK_DEPTH_BITS'(STACK_DEPTH-1));;
//                 count <= count - 1'b1;
//             end
//         end
//     end
// end

// endmodule

module ras 
import rv32i_types::*;
#(
    parameter STACK_DEPTH = 32
)(
    input  logic clk,           
    input  logic rst,           
    input  logic push,          
    input  logic pop,         
    input  logic pop_push,  
    input  logic [31:0] din,    

    output logic [31:0] dout,   
    output logic empty         
);

localparam integer STACK_DEPTH_BITS = $clog2(STACK_DEPTH);
localparam logic [STACK_DEPTH_BITS-1:0] STACK_MAX_INDEX = STACK_DEPTH - 1;

logic [31:0] stack [0:STACK_DEPTH-1]; 
logic [STACK_DEPTH_BITS-1:0] stack_top; 
logic [STACK_DEPTH_BITS-1:0] stack_bottom; 
logic [STACK_DEPTH_BITS:0] count; 

assign dout = stack[(stack_top + STACK_MAX_INDEX) & STACK_MAX_INDEX]; 
assign empty = (count == 0);

always_ff @(posedge clk) begin
    if (rst) begin
        stack_top <= '0;
        stack_bottom <= '0;
        count <= '0;
    end else begin
        if (pop_push) begin
            if (!empty) begin
                stack_top <= (stack_top + STACK_MAX_INDEX) & STACK_MAX_INDEX;
                stack[(stack_top + STACK_MAX_INDEX) & STACK_MAX_INDEX] <= din;
            end else begin
                stack[stack_top] <= din;
                stack_top <= (stack_top + 1'b1) & STACK_MAX_INDEX;
                count <= 6'd1;
            end
        end
        else if (push) begin
            stack[stack_top] <= din;
            stack_top <= (stack_top + 1'b1) & STACK_MAX_INDEX;
            if (count == STACK_DEPTH[STACK_DEPTH_BITS:0]) begin
                stack_bottom <= (stack_bottom + 1'b1) & STACK_MAX_INDEX;
            end else begin
                count <= count + 1'b1;
            end
        end 
        else if (pop) begin
            if (!empty) begin
                stack_top <= (stack_top + STACK_MAX_INDEX) & STACK_MAX_INDEX;
                count <= count - 1'b1;
            end
        end
    end
end

endmodule