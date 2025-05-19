module set_ufp_rdata 
(
    input  logic [31:0]  ufp_addr_reg,
    input  logic [255:0] read_data_tmp,
    output logic [31:0]  ufp_rdata

);
    always_comb begin
        // initialize ufp_rdata with appropriate values
        unique case (ufp_addr_reg[4:0]) 
            5'd0: begin
                ufp_rdata = read_data_tmp[31:0];
            end
            5'd4: begin
                ufp_rdata = read_data_tmp[63:32];
            end
            5'd8: begin
                ufp_rdata = read_data_tmp[95:64];
            end
            5'd12: begin
                ufp_rdata = read_data_tmp[127:96];
            end
            5'd16: begin
                ufp_rdata = read_data_tmp[159:128];
            end
            5'd20: begin
                ufp_rdata = read_data_tmp[191:160];
            end
            5'd24: begin
                ufp_rdata = read_data_tmp[223:192];
            end
            5'd28: begin
                ufp_rdata = read_data_tmp[255:224];
            end
            default: begin
                ufp_rdata = 'x;
            end
        endcase
    end
endmodule