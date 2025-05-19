module nextline 
import rv32i_types::*;
(
    input  logic clk,
    input  logic rst,
    input  logic [255:0] next_line_data,
    input  logic         nl_mem_resp,
    input  logic         cache_miss_complete,
    input  logic [31:0]  next_line_addr,

    output buffer_pkt_t  next_line_pkt,
    output logic         next_line_read
);

buffer_pkt_t next_line_pkt_next;
logic next_line_read_next;

always_ff @(posedge clk) begin
    next_line_pkt <= rst ? '0 : next_line_pkt_next;
    next_line_read <= rst ? '0 : next_line_read_next;
end

always_comb begin 
    if(nl_mem_resp) begin
        next_line_pkt_next.addr = next_line_pkt.addr;
        next_line_pkt_next.data  = next_line_data;
        next_line_pkt_next.available = 1'b1;
        next_line_read_next = '0;
    end
    else if (cache_miss_complete && !next_line_read) begin
        next_line_pkt_next.addr = next_line_addr;
        next_line_pkt_next.data  = '0;
        next_line_pkt_next.available = 1'b0;
        next_line_read_next = '1;
    end
    else begin
        next_line_pkt_next = next_line_pkt;
        next_line_read_next = next_line_read;
    end
end

endmodule : nextline