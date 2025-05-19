module linebuffer 
import rv32i_types::*;
(
    input logic clk,
    input logic rst,
    input  logic [255:0] latest_hit_line,
    input  logic         imem_resp,
    input  logic [31:0]  latest_hit_line_addr,

    output logic [255:0] linebuffer_line,
    output logic [31:0]  linebuffer_addr,  
    output logic         linebuffer_valid
);

logic [255:0] lb;
logic [255:0] lb_next;

logic [31:0]  lb_addr;
logic [31:0]  lb_addr_next;

logic         lb_valid;
logic         lb_valid_next;

always_ff @(posedge clk) begin
    if(rst) begin
        lb          <= 'x;
        lb_addr     <= '0;
        lb_valid    <= '0;
    end
    else begin
        lb          <= lb_next;
        lb_addr     <= lb_addr_next;
        lb_valid    <= lb_valid_next;       
    end
end

always_comb begin 
    if(imem_resp) begin
        lb_next       = latest_hit_line;
        lb_addr_next  = latest_hit_line_addr;
        lb_valid_next = '1;
    end
    else begin
        lb_next       = lb;
        lb_addr_next  = lb_addr;
        lb_valid_next = lb_valid;
    end
end

assign linebuffer_line  = lb;
assign linebuffer_addr  = lb_addr;
assign linebuffer_valid = lb_valid;


endmodule : linebuffer