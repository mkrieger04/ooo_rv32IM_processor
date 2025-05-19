module set_ufp_wdata 
(
    input  logic [31:0]   ufp_addr_reg,
    input  logic [31:0]  ufp_wdata_reg,
    input  logic [3:0]  ufp_wmask_reg,
    output logic [255:0]  data_write_tmp,
    output logic [31:0]   wmask_write_tmp
);
    always_comb begin
        // Write to the cache on a cache write
        unique case (ufp_addr_reg[4:0]) 
            5'd0: begin
                data_write_tmp       = {224'bx,ufp_wdata_reg};
                wmask_write_tmp      = {28'b0,ufp_wmask_reg};
            end
            5'd4: begin
                data_write_tmp       = {192'bx,ufp_wdata_reg, 32'bx};
                wmask_write_tmp      = {24'b0,ufp_wmask_reg, 4'b0};
            end
            5'd8: begin
                data_write_tmp       = {160'bx,ufp_wdata_reg, 64'bx};
                wmask_write_tmp      = {20'b0,ufp_wmask_reg, 8'b0};
            end
            5'd12: begin
                data_write_tmp       = {128'bx,ufp_wdata_reg, 96'bx};
                wmask_write_tmp      = {16'b0,ufp_wmask_reg, 12'b0};
            end
            5'd16: begin
                data_write_tmp       = {96'bx,ufp_wdata_reg, 128'bx};
                wmask_write_tmp      = {12'b0,ufp_wmask_reg, 16'b0};
            end
            5'd20: begin
                data_write_tmp       = {64'bx,ufp_wdata_reg, 160'bx};
                wmask_write_tmp      = {8'b0,ufp_wmask_reg, 20'b0};
            end
            5'd24: begin
                data_write_tmp       = {32'bx,ufp_wdata_reg, 192'bx};
                wmask_write_tmp      = {4'b0,ufp_wmask_reg, 24'b0};
            end
            5'd28: begin
                data_write_tmp       = {ufp_wdata_reg, 224'bx};
                wmask_write_tmp      = {ufp_wmask_reg, 28'b0};
            end
            default: begin
                data_write_tmp       = 'x;
                wmask_write_tmp      = '0;
            end
        endcase
    end
endmodule