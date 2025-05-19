module gshare #(
    parameter GHR_SIZE = 4,
    parameter PHT_SIZE = 16 
) (
    input logic clk,
    input logic rst,

    input logic [31:0] pc,         
    input logic outcome,     
    input logic we,     
    input logic [$clog2(PHT_SIZE)-1:0] pht_index_in,      
    input logic [1:0] rob_prediction,

    output logic [$clog2(PHT_SIZE)-1:0] pht_index_out,
    output logic [1:0] prediction       
);
// walt wuz here
    logic [GHR_SIZE-1:0] global_history_register; 
    logic [1:0] pattern_history_table [PHT_SIZE-1]; 
    logic [$clog2(PHT_SIZE)-1:0] index, index_prev, pht_index_in_prev;
    logic [1:0] new_prediction, sram_prediction, new_prediction_prev;
    logic [1:0] temp;
    logic [PHT_SIZE-1:0] valid;
    logic wen_prev;

    assign index = pc[31:25] ^ pc[24:18] ^ pc[17:11] ^ pc[10:4] ^ global_history_register; 
    assign pht_index_out = index_prev;

    always_comb begin
        if (index_prev == pht_index_in_prev && wen_prev) begin
            prediction = new_prediction_prev;
        end
        else if (valid[index_prev]) begin
            prediction = sram_prediction;
        end
        else begin
            prediction = 2'b01;
        end
    end

    gshare_pht_sram  gshare_pht_sram(
        //  read only port
        .clk0       (clk),
        .csb0       ('0),
        .web0       ('1),   
        .addr0      (index), 
        .din0       ('0),
        .dout0      (sram_prediction),

        //  write only port     
        .clk1       (clk & we),
        .csb1       (!we),
        .web1       (!we),   
        .addr1      (pht_index_in), 
        .din1       (new_prediction),
        .dout1      (temp)
    );

    always_comb begin
        new_prediction = '0;
        unique case (outcome)
            1'b0: new_prediction = (rob_prediction != 2'b00) ?  rob_prediction - 2'd1 : rob_prediction;
            1'b1: new_prediction = (rob_prediction != 2'b11) ?  rob_prediction + 2'd1 : rob_prediction;
            default: new_prediction = rob_prediction;
        endcase
    end

    always_ff @(posedge clk) begin   
        if (rst) begin
            global_history_register <= '0;
            valid <= '0;
        end
        else if (we) begin
            global_history_register <= {global_history_register[GHR_SIZE-2:0], outcome};
        end
        else if (wen_prev) begin
            valid[pht_index_in_prev] <= '1;
        end
    end

    always_ff @(posedge clk) begin   
        if (rst) begin
            index_prev <= '0;
            wen_prev  <= '0;
            pht_index_in_prev <= '0;
            new_prediction_prev <= '0;
        end
        else begin
            index_prev <= index;
            wen_prev  <= we;
            if(we) begin
                pht_index_in_prev <= pht_index_in;
                new_prediction_prev <= new_prediction;
            end
        end
    end


endmodule