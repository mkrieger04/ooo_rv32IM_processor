module execute
import rv32i_types::*;
(
    input   logic          clk, rst,
    input   rs_data_pkt_t  rs_alu_pkt,
    input   rs_data_pkt_t  rs_mul_pkt,
    input   rs_data_pkt_t  rs_div_pkt,
    input   rs_data_pkt_t  rs_branch_pkt,
    input   logic [31:0]   alu_rs1_data, alu_rs2_data,
    input   logic [31:0]   mul_rs1_data, mul_rs2_data,
    input   logic [31:0]   div_rs1_data, div_rs2_data,
    input   logic [31:0]   branch_rs1_data, branch_rs2_data,
    input   stall_pkt_t    wb_unit_stalls, 
    input   logic          alu_rs_done,
    input   logic          branch_rs_done,
    input   logic          mul_rs_done,
    input   logic          div_rs_done,

    output  stall_pkt_t    f_unit_stalls,
    output  wb_pkt_t       alu_wb_pkt,
    output  wb_pkt_t       mul_wb_pkt,
    output  wb_pkt_t       div_wb_pkt,
    output  wb_pkt_t       branch_wb_pkt,

    input cdb_pkt_t        cdb_pkt2
);

logic [31:0]   alu_rd_data, branch_rd_data;
logic [63:0]   mul_rd_data, signed_data;
logic [31:0]   quotient, remainder;
logic          divide_by_zero, div_complete, mul_complete;
rs_data_pkt_t  rs_mul_pkt_prev, rs_div_pkt_prev, rs_alu_pkt_prev, rs_branch_pkt_prev;
wb_pkt_t mul_wb_pkt_next, div_wb_pkt_next, alu_wb_pkt_next, branch_wb_pkt_next;

logic multipling, multipling_next, dividing, dividing_next;
logic alu_rs_done_next, branch_rs_done_next, mul_rs_done_next, div_rs_done_next;
logic br_en;
logic [31:0] div_rs1_data_next, div_rs2_data_next, mul_rs1_data_next, mul_rs2_data_next;
logic [31:0] pc_next;
logic false_complete_mul, false_complete_mul_next;
logic false_complete_div, false_complete_div_next;

rs_data_pkt_t  rs_alu_pkt_next;
rs_data_pkt_t  rs_mul_pkt_next;
rs_data_pkt_t  rs_div_pkt_next;
rs_data_pkt_t  rs_branch_pkt_next;

always_comb begin

rs_alu_pkt_next    = rs_alu_pkt;
rs_mul_pkt_next    = rs_mul_pkt;
rs_div_pkt_next    = rs_div_pkt;
rs_branch_pkt_next =  rs_branch_pkt;



if(cdb_pkt2.cdb_broadcast) begin
    if(cdb_pkt2.br_mispred) begin
        if(rs_alu_pkt.bmask[cdb_pkt2.br_bit]) rs_alu_pkt_next.valid        = '0;
        if(rs_mul_pkt.bmask[cdb_pkt2.br_bit]) rs_mul_pkt_next.valid        = '0;
        if(rs_div_pkt.bmask[cdb_pkt2.br_bit]) rs_div_pkt_next.valid        = '0;
        if(rs_branch_pkt.bmask[cdb_pkt2.br_bit]) rs_branch_pkt_next.valid  = '0;
    end
    else begin
        rs_alu_pkt_next.bmask[cdb_pkt2.br_bit] = '0;
        rs_mul_pkt_next.bmask[cdb_pkt2.br_bit] = '0;
        rs_div_pkt_next.bmask[cdb_pkt2.br_bit] = '0;
        rs_branch_pkt_next.bmask[cdb_pkt2.br_bit] = '0;
    end
end

end

always_ff @ (posedge clk) begin
    if (!wb_unit_stalls.alu_stall) alu_rs_done_next <= alu_rs_done;
    if (!wb_unit_stalls.br_stall) branch_rs_done_next <= branch_rs_done;
    if (!wb_unit_stalls.mul_stall) mul_rs_done_next <= mul_rs_done;
    if (!wb_unit_stalls.div_stall) div_rs_done_next <= div_rs_done;
    false_complete_mul <= false_complete_mul_next;
    false_complete_div <= false_complete_div_next;
    multipling_next <= multipling;
    dividing_next <= dividing;
    
    if (rst) begin
        rs_alu_pkt_prev <= '0;
        rs_mul_pkt_prev <= '0;
        rs_div_pkt_prev <= '0;
        rs_branch_pkt_prev <= '0;
    end
    else begin
        if(alu_rs_done) rs_alu_pkt_prev <= rs_alu_pkt_next;
        else begin
            if(cdb_pkt2.cdb_broadcast) begin
                if(cdb_pkt2.br_mispred && rs_alu_pkt_prev.bmask[cdb_pkt2.br_bit]) begin
                    rs_alu_pkt_prev.valid        <= '0;
                end
                else if (~cdb_pkt2.br_mispred) begin
                    rs_alu_pkt_prev.bmask[cdb_pkt2.br_bit] <= '0;
                end
            end
        end
        if(mul_rs_done) rs_mul_pkt_prev <= rs_mul_pkt_next;
        else begin
            if(cdb_pkt2.cdb_broadcast) begin
                if(cdb_pkt2.br_mispred && rs_mul_pkt_prev.bmask[cdb_pkt2.br_bit]) begin
                    rs_mul_pkt_prev.valid        <= '0;
                end
                else if (~cdb_pkt2.br_mispred) begin
                    rs_mul_pkt_prev.bmask[cdb_pkt2.br_bit] <= '0;
                end
            end
        end
        if(div_rs_done) rs_div_pkt_prev <= rs_div_pkt_next;
        else begin
            if(cdb_pkt2.cdb_broadcast) begin
                if(cdb_pkt2.br_mispred && rs_div_pkt_prev.bmask[cdb_pkt2.br_bit]) begin
                    rs_div_pkt_prev.valid        <= '0;
                end
                else if (~cdb_pkt2.br_mispred) begin
                    rs_div_pkt_prev.bmask[cdb_pkt2.br_bit] <= '0;
                end
            end
        end
        if(branch_rs_done) rs_branch_pkt_prev <= rs_branch_pkt_next;
        else begin
            if(cdb_pkt2.cdb_broadcast) begin
                if(cdb_pkt2.br_mispred && rs_branch_pkt_prev.bmask[cdb_pkt2.br_bit]) begin
                    rs_branch_pkt_prev.valid        <= '0;
                end
                else if (~cdb_pkt2.br_mispred) begin
                    rs_branch_pkt_prev.bmask[cdb_pkt2.br_bit] <= '0;
                end
            end
        end
    end

    if (div_rs_done_next) begin 
        div_rs1_data_next <= div_rs1_data;
        div_rs2_data_next <= div_rs2_data;
    end

    if (mul_rs_done_next) begin 
        mul_rs1_data_next <= mul_rs1_data;
        mul_rs2_data_next <= mul_rs2_data;
    end
end

//Logic to determine if we have recived first complete singal
//First complete signal sent from IP in not valid
always_comb begin
    if (rst) begin
        false_complete_mul_next = '0;
        false_complete_div_next = '0;
    end
    else begin
        if (mul_rs_done_next) false_complete_mul_next = '1;
        else false_complete_mul_next = false_complete_mul;

        if (div_rs_done_next) false_complete_div_next = '1;
        else false_complete_div_next = false_complete_div;
    end
end

//Logic to determine if a multiplication or division operation is currently running
always_comb begin
    if (rst) multipling = 1'b0;
    else if (mul_rs_done_next) multipling = 1'b1;
    else if (false_complete_mul_next && mul_complete && !wb_unit_stalls.mul_stall) multipling = 1'b0;
    else multipling = multipling_next;
    
    if (rst) dividing = 1'b0;
    else if (div_rs_done_next) dividing = 1'b1;
    else if (false_complete_div_next && div_complete && false_complete_div && !wb_unit_stalls.div_stall) dividing = 1'b0;
    else dividing = dividing_next;
end

alu alu (
    .rs_input_pkt(rs_alu_pkt_prev),
    .rs1_data(alu_rs1_data),
    .rs2_data(alu_rs2_data),

    .rd_data(alu_rd_data)
);

alu_branch alu_branch (
    .rs_input_pkt(rs_branch_pkt_prev),
    .rs1_data(branch_rs1_data),
    .rs2_data(branch_rs2_data),

    .br_en_out(br_en),
    .rd_data(branch_rd_data),
    .pc_next(pc_next)
);

  parameter inst_a_width        = 32;
  parameter inst_b_width        = 32;
  parameter inst_tc_mode        = 0;
  parameter inst_num_cyc_div    = 16;
  parameter inst_num_cyc_mul    = 3;
  parameter inst_rst_mode       = 0;
  parameter inst_input_mode     = 1;
  parameter inst_output_mode    = 0;
  parameter inst_early_start    = 0;

DW_mult_seq #(
    .a_width(inst_a_width),
    .b_width(inst_b_width),
    .tc_mode(inst_tc_mode), 
    .num_cyc(inst_num_cyc_mul),
    .rst_mode(inst_rst_mode),
    .input_mode(inst_input_mode),
    .output_mode(inst_output_mode),
    .early_start(inst_early_start)
    ) multiplier (
    .clk(clk),
    .rst_n(!rst), 
    .hold('0),
    .start(mul_rs_done_next),
    .a((rs_mul_pkt_prev.signed_mul[1] && mul_rs1_data[31]) ? (~(mul_rs1_data) + 1): mul_rs1_data),
    .b((rs_mul_pkt_prev.signed_mul[0] && mul_rs2_data[31]) ? (~(mul_rs2_data) + 1): mul_rs2_data),
    .complete(mul_complete),
    .product(mul_rd_data) 
);

  DW_div_seq #(
    .a_width(inst_a_width),
    .b_width(inst_b_width),
    .tc_mode(inst_tc_mode),
    .num_cyc(inst_num_cyc_div),
    .rst_mode(inst_rst_mode),
    .input_mode(inst_input_mode),
    .output_mode(inst_output_mode),
    .early_start(inst_early_start)
  ) divider (
    .clk(clk),
    .rst_n(!rst),
    .hold('0),
    .start(div_rs_done_next),
    .a((rs_div_pkt_prev.signed_div && div_rs1_data[31]) ? (~(div_rs1_data) + 1): div_rs1_data),
    .b((rs_div_pkt_prev.signed_div && div_rs2_data[31]) ? (~(div_rs2_data) + 1): div_rs2_data),
    .complete(div_complete),
    .divide_by_0(divide_by_zero),
    .quotient(quotient),
    .remainder(remainder)
  );

always_ff @ (posedge clk) begin
    if (rst) begin
        mul_wb_pkt <= '0;
        div_wb_pkt <= '0;
        alu_wb_pkt <= '0;
        branch_wb_pkt <= '0;
    end
    else begin
        if (!wb_unit_stalls.br_stall) branch_wb_pkt <= branch_wb_pkt_next;
        else begin
            if(cdb_pkt2.cdb_broadcast) begin
                if(cdb_pkt2.br_mispred && branch_wb_pkt.br_bmask[cdb_pkt2.br_bit]) begin
                    branch_wb_pkt.valid        <= '0;
                end
                else if (~cdb_pkt2.br_mispred) begin
                    branch_wb_pkt.br_bmask[cdb_pkt2.br_bit] <= '0;
                end
            end
        end
        if (!wb_unit_stalls.div_stall) div_wb_pkt <= div_wb_pkt_next;
        else begin
            if(cdb_pkt2.cdb_broadcast) begin
                if(cdb_pkt2.br_mispred && div_wb_pkt.br_bmask[cdb_pkt2.br_bit]) begin
                    div_wb_pkt.valid        <= '0;
                end
                else if (~cdb_pkt2.br_mispred) begin
                    div_wb_pkt.br_bmask[cdb_pkt2.br_bit] <= '0;
                end
            end
        end
        if (!wb_unit_stalls.mul_stall) mul_wb_pkt <= mul_wb_pkt_next;
        else begin
            if(cdb_pkt2.cdb_broadcast) begin
                if(cdb_pkt2.br_mispred && mul_wb_pkt.br_bmask[cdb_pkt2.br_bit]) begin
                    mul_wb_pkt.valid        <= '0;
                end
                else if (~cdb_pkt2.br_mispred) begin
                    mul_wb_pkt.br_bmask[cdb_pkt2.br_bit] <= '0;
                end
            end
        end
        if (!wb_unit_stalls.alu_stall) alu_wb_pkt <= alu_wb_pkt_next;
        else begin
            if(cdb_pkt2.cdb_broadcast) begin
                if(cdb_pkt2.br_mispred && alu_wb_pkt.br_bmask[cdb_pkt2.br_bit]) begin
                    alu_wb_pkt.valid        <= '0;
                end
                else if (~cdb_pkt2.br_mispred) begin
                    alu_wb_pkt.br_bmask[cdb_pkt2.br_bit] <= '0;
                end
            end
        end
    end
end

always_comb begin
    f_unit_stalls.mul_stall <= (wb_unit_stalls.mul_stall || multipling);
    f_unit_stalls.div_stall <= (wb_unit_stalls.div_stall || dividing);
    f_unit_stalls.alu_stall <= wb_unit_stalls.alu_stall;
    f_unit_stalls.br_stall  <= wb_unit_stalls.br_stall;
end

always_comb begin

    alu_wb_pkt_next.br_mispred   = '0;
    alu_wb_pkt_next.prediction   = '0;
    alu_wb_pkt_next.pht_index    = '0;

    alu_wb_pkt_next.valid        = rs_alu_pkt_prev.valid && alu_rs_done_next;
    alu_wb_pkt_next.br_bmask     = rs_alu_pkt_prev.bmask;

    if(cdb_pkt2.cdb_broadcast) begin
        if(cdb_pkt2.br_mispred && rs_alu_pkt_prev.bmask[cdb_pkt2.br_bit]) begin
            alu_wb_pkt_next.valid        = '0;
        end
        else if (~cdb_pkt2.br_mispred) begin
            alu_wb_pkt_next.br_bmask[cdb_pkt2.br_bit] = '0;
        end
    end

    alu_wb_pkt_next.br_bit       = '0;
    
    alu_wb_pkt_next.rs1_paddr    = rs_alu_pkt_prev.rs1_paddr;
    alu_wb_pkt_next.rs1_aaddr    = rs_alu_pkt_prev.rs1_aaddr;
    alu_wb_pkt_next.rs2_paddr    = rs_alu_pkt_prev.rs2_paddr;
    alu_wb_pkt_next.rs2_aaddr    = rs_alu_pkt_prev.rs2_aaddr;
    alu_wb_pkt_next.rob_idx      = rs_alu_pkt_prev.rob_idx;
    alu_wb_pkt_next.rd_paddr     = rs_alu_pkt_prev.rd_paddr;
    alu_wb_pkt_next.rd_aaddr     = rs_alu_pkt_prev.rd_addr;
    alu_wb_pkt_next.rd_data      = alu_rd_data;
    alu_wb_pkt_next.rvfi_pkt     = rs_alu_pkt_prev.rvfi_pkt; 
    alu_wb_pkt_next.br_en        = '0;
    alu_wb_pkt_next.pc_next  = '0;
    alu_wb_pkt_next.rvfi_pkt.monitor_rs1_rdata = rs_alu_pkt_prev.i_use_rs1 ? alu_rs1_data : '0;
    alu_wb_pkt_next.rvfi_pkt.monitor_rs2_rdata = rs_alu_pkt_prev.i_use_rs2 ? alu_rs2_data : '0;
    alu_wb_pkt_next.rvfi_pkt.monitor_valid = alu_wb_pkt_next.valid; 
    alu_wb_pkt_next.rvfi_pkt.monitor_rd_wdata  = alu_rd_data;
    alu_wb_pkt_next.is_branch       = '0;

    mul_wb_pkt_next.br_en        = '0;
    mul_wb_pkt_next.br_mispred   = '0;
    mul_wb_pkt_next.prediction   = '0;
    mul_wb_pkt_next.pht_index    = '0;
    mul_wb_pkt_next.br_bmask     = rs_mul_pkt_prev.bmask;
    mul_wb_pkt_next.br_bit       = '0;
    mul_wb_pkt_next.valid        = rs_mul_pkt_prev.valid && mul_complete && false_complete_mul && multipling_next;// && mul_rs_done_next;

    if(cdb_pkt2.cdb_broadcast) begin
        if(cdb_pkt2.br_mispred && rs_mul_pkt_prev.bmask[cdb_pkt2.br_bit]) begin
            mul_wb_pkt_next.valid        = '0;
        end
        else if (~cdb_pkt2.br_mispred) begin
            mul_wb_pkt_next.br_bmask[cdb_pkt2.br_bit] = '0;
        end
    end


    mul_wb_pkt_next.rvfi_pkt                   = rs_mul_pkt_prev.rvfi_pkt;
    mul_wb_pkt_next.rvfi_pkt.monitor_valid     = mul_wb_pkt_next.valid;
    mul_wb_pkt_next.rvfi_pkt.monitor_rs1_rdata = mul_rs1_data_next;
    mul_wb_pkt_next.rvfi_pkt.monitor_rs2_rdata = mul_rs2_data_next;
    mul_wb_pkt_next.rs1_paddr    = rs_mul_pkt_prev.rs1_paddr;
    mul_wb_pkt_next.rs1_aaddr    = rs_mul_pkt_prev.rs1_aaddr;
    mul_wb_pkt_next.rs2_paddr    = rs_mul_pkt_prev.rs2_paddr;
    mul_wb_pkt_next.rs2_aaddr    = rs_mul_pkt_prev.rs2_aaddr;
    mul_wb_pkt_next.rob_idx      = rs_mul_pkt_prev.rob_idx;
    mul_wb_pkt_next.rd_paddr     = rs_mul_pkt_prev.rd_paddr;
    mul_wb_pkt_next.rd_aaddr     = rs_mul_pkt_prev.rd_addr;
    mul_wb_pkt_next.pc_next = '0;

    if ((rs_mul_pkt_prev.signed_mul[1] && mul_rs1_data_next[31]) ^ (rs_mul_pkt_prev.signed_mul[0] && mul_rs2_data_next[31])) signed_data = ~(mul_rd_data) + 1'b1;
    else signed_data = mul_rd_data;

    mul_wb_pkt_next.rd_data                    = (rs_mul_pkt_prev.high_bits ? signed_data[63:32] : signed_data[31:0]);
    mul_wb_pkt_next.rvfi_pkt.monitor_rd_wdata  = (rs_mul_pkt_prev.high_bits ? signed_data[63:32] : signed_data[31:0]);
    mul_wb_pkt_next.is_branch       = '0;

    div_wb_pkt_next.br_bmask     = rs_div_pkt_prev.bmask;
    div_wb_pkt_next.valid        = rs_div_pkt_prev.valid && div_complete && false_complete_div && dividing_next;// && div_rs_done_next;


    if(cdb_pkt2.cdb_broadcast) begin
        if(cdb_pkt2.br_mispred && rs_div_pkt_prev.bmask[cdb_pkt2.br_bit]) begin
            div_wb_pkt_next.valid        = '0;
        end
        else if (~cdb_pkt2.br_mispred) begin
            div_wb_pkt_next.br_bmask[cdb_pkt2.br_bit] = '0;
        end
    end


    div_wb_pkt_next.br_mispred   = '0;
    div_wb_pkt_next.prediction   = '0;
    div_wb_pkt_next.pht_index    = '0;
    div_wb_pkt_next.br_bit       = '0;
    div_wb_pkt_next.br_en        = '0;
    div_wb_pkt_next.rvfi_pkt     = rs_div_pkt_prev.rvfi_pkt;
    div_wb_pkt_next.rs1_paddr    = rs_div_pkt_prev.rs1_paddr;
    div_wb_pkt_next.rs1_aaddr    = rs_div_pkt_prev.rs1_aaddr;
    div_wb_pkt_next.rs2_paddr    = rs_div_pkt_prev.rs2_paddr;
    div_wb_pkt_next.rs2_aaddr    = rs_div_pkt_prev.rs2_aaddr;
    div_wb_pkt_next.rob_idx      = rs_div_pkt_prev.rob_idx;
    div_wb_pkt_next.rd_paddr     = rs_div_pkt_prev.rd_paddr;
    div_wb_pkt_next.rd_aaddr     = rs_div_pkt_prev.rd_addr;
    div_wb_pkt_next.rvfi_pkt.monitor_rs1_rdata = div_rs1_data_next;
    div_wb_pkt_next.rvfi_pkt.monitor_rs2_rdata = div_rs2_data_next;
    div_wb_pkt_next.rd_data      = (divide_by_zero && !rs_div_pkt_prev.use_remainder) ? '1 : (rs_div_pkt_prev.use_remainder ? (rs_div_pkt_prev.signed_div && (div_rs1_data_next[31]) ? ~(remainder) + 1: remainder) : (rs_div_pkt_prev.signed_div && (div_rs1_data_next[31] ^ div_rs2_data_next[31]) ? (~quotient) + 1 : quotient));
    div_wb_pkt_next.rvfi_pkt.monitor_rd_wdata  = (divide_by_zero && !rs_div_pkt_prev.use_remainder) ? '1 : (rs_div_pkt_prev.use_remainder ? (rs_div_pkt_prev.signed_div && (div_rs1_data_next[31]) ? ~(remainder) + 1: remainder) : (rs_div_pkt_prev.signed_div && (div_rs1_data_next[31] ^ div_rs2_data_next[31]) ? (~quotient) + 1 : quotient));
    div_wb_pkt_next.rvfi_pkt.monitor_valid = div_wb_pkt_next.valid;
    div_wb_pkt_next.pc_next = '0;
    div_wb_pkt_next.is_branch       = '0;


    branch_wb_pkt_next              = '0;
    branch_wb_pkt_next.valid        = rs_branch_pkt_prev.valid && branch_rs_done_next;
    branch_wb_pkt_next.br_bmask     = rs_branch_pkt_prev.bmask;
    if(cdb_pkt2.cdb_broadcast) begin
        if(cdb_pkt2.br_mispred && rs_branch_pkt_prev.bmask[cdb_pkt2.br_bit]) begin
            branch_wb_pkt_next.valid        = '0;
        end
        else if (~cdb_pkt2.br_mispred) begin
            branch_wb_pkt_next.br_bmask[cdb_pkt2.br_bit] = '0;
        end
    end


    branch_wb_pkt_next.br_en        = br_en;
    branch_wb_pkt_next.br_mispred   = (rs_branch_pkt_prev.i_use_rs1 & ~rs_branch_pkt_prev.i_use_rs2) ? (rs_branch_pkt_prev.pc_pred != pc_next): br_en ^ rs_branch_pkt_prev.prediction[1];
    branch_wb_pkt_next.prediction   = rs_branch_pkt_prev.prediction;
    branch_wb_pkt_next.pht_index    = rs_branch_pkt_prev.pht_index;
    branch_wb_pkt_next.br_bit       = rs_branch_pkt_prev.free_bmask_bit;
    branch_wb_pkt_next.is_branch       = rs_branch_pkt_prev.is_branch;


    branch_wb_pkt_next.rob_idx      = rs_branch_pkt_prev.rob_idx;
    branch_wb_pkt_next.pc_next      = pc_next;
    branch_wb_pkt_next.rd_paddr     = rs_branch_pkt_prev.rd_paddr;
    branch_wb_pkt_next.rd_aaddr     = rs_branch_pkt_prev.rd_addr;
    branch_wb_pkt_next.rd_data      = branch_rd_data;
    branch_wb_pkt_next.rvfi_pkt     = rs_branch_pkt_prev.rvfi_pkt; 
    branch_wb_pkt_next.rvfi_pkt.monitor_rs1_rdata = rs_branch_pkt_prev.i_use_rs1 ? branch_rs1_data : '0;
    branch_wb_pkt_next.rvfi_pkt.monitor_rs2_rdata = rs_branch_pkt_prev.i_use_rs2 ? branch_rs2_data : '0;
    branch_wb_pkt_next.rvfi_pkt.monitor_valid = branch_wb_pkt_next.valid;
    branch_wb_pkt_next.rvfi_pkt.monitor_rd_wdata = ~rs_branch_pkt_prev.i_use_alu_cmpop ? branch_rd_data : '0;
    branch_wb_pkt_next.rvfi_pkt.monitor_pc_wdata =  pc_next;
end

endmodule