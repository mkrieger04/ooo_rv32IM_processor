module load_store_unit
import rv32i_types::*;
#(
    parameter               ROB_DEPTH = 32
)
(
    input   logic               clk,
    input   logic               rst,
    // input   logic [31:0]        load_store_rs1_data, load_store_rs2_data,   
    input   ld_st_data_pkt_t    ld_st_data_pkt,
    input   logic   [31:0]      dmem_rdata,
    input   cdb_pkt_t           cdb_pkt,
    input   reg_data_pkt_t      load_store_prf_reg_data,
    input   logic               ld_st_fifo_wen,
    input   logic               dmem_resp,
    input   logic [$clog2(ROB_DEPTH)-1:0] rob_index,

    output  logic   [31:0]      dmem_addr,
    output  logic   [31:0]      dmem_wdata,
    output  logic               load_store_stall,
    output  logic   [3:0]       dmem_wmask,
    output  logic   [3:0]       dmem_rmask,
    output  wb_pkt_t            load_wb_pkt,
    output  reg_addr_pkt_t      load_store_prf_reg_addr,
    output  reg_ren_pkt_t       load_store_prf_reg_ren_pkt);


logic mem_pkt_fifo_full, mem_pkt_fifo_empty, load_store_in_proggress, load_store_fifo_empty;
logic load_store_rs_done_next, load_store_rs_done;
reg_data_pkt_t      load_store_prf_reg_data_register, load_store_prf_reg_data_real;
ld_st_data_pkt_t    packet_out_of_fifo, packet_out_of_fifo_next;
mem_pkt_t           packet_out_of_register, mem_unit_input_packet_next;

// fifo input's /output
// Input from dispatch rename if not full
// Output full signal to dispatch rename (load_store_stall)
// input from writeback station to set bits in fifo to ready
// if for specific things (wake up)
// output to addr calc station if instr at head of fifo not full and addr calc station not busy
load_store_fifo #(4) load_store_fifo (
    .clk(clk),
    .rst(rst),
    .wen(ld_st_fifo_wen),
    .ren(load_store_rs_done_next), 
    .fifo_in(ld_st_data_pkt),
    .cdb_pkt(cdb_pkt),
    .fifo_empty(load_store_fifo_empty),
    .fifo_out(packet_out_of_fifo),
    .fifo_full(load_store_stall)
);

//todo (Eddie)
//The flow of this module is load_store_fifo (pretty much dispatch rename)
//Register -> we need you to imitate issue where load_store_rs_done along with register values enter addr_calc one cycle later. Similar to execute interaction
//Then we have addr calcuation (same as execute in pipeline)
//Then we have a register that is used as the input of mem_unit
//Then we have mem_unit (same as mem in pipeline)

assign load_store_rs_done = (~load_store_fifo_empty & ~mem_pkt_fifo_full & packet_out_of_fifo.ready & ~load_store_rs_done_next);

always_comb begin
    load_store_prf_reg_addr    = '0;
    load_store_prf_reg_ren_pkt = '0;

    if(load_store_rs_done) begin
        if(packet_out_of_fifo.i_use_rs1) begin
            load_store_prf_reg_addr.rs1_paddr = packet_out_of_fifo.rs1_paddr;
            load_store_prf_reg_ren_pkt.prf_ren_rs1 = 1'b1;
        end
        if(packet_out_of_fifo.i_use_rs2)
            load_store_prf_reg_addr.rs2_paddr = packet_out_of_fifo.rs2_paddr;
            load_store_prf_reg_ren_pkt.prf_ren_rs2 = 1'b1;
    end
end

always_ff @ (posedge clk) begin
    if (rst) begin
        load_store_rs_done_next <= '0;
    end
    else if (load_store_rs_done) begin
        load_store_rs_done_next <= '1;
    end
    else begin
        load_store_rs_done_next <= '0;
    end
end 

always_ff @ (posedge clk) begin
    if (rst) begin
        packet_out_of_fifo_next <= '0;
        load_store_prf_reg_data_register <= '0;
    end
    else begin
        if (load_store_rs_done_next) begin
            packet_out_of_fifo_next <= packet_out_of_fifo;
            load_store_prf_reg_data_register <= load_store_prf_reg_data;
        end
        else if(packet_out_of_register.valid)begin
            packet_out_of_fifo_next <= '0;
            load_store_prf_reg_data_register <= '0;
        end
    end
end 

//Addr Calulation
//Calculate the info for the load/store send to memstage if it is not full, and decode from the fifo
addr_calculation addr_calculation (
    .input_packet(packet_out_of_fifo_next),
    .rs1_data(load_store_prf_reg_data_register.rs1_data),
    .rs2_data(load_store_prf_reg_data_register.rs2_data),
    .mem_pkt_fifo_full(mem_pkt_fifo_full),

    .output_packet(packet_out_of_register)
);

fifo #(.WIDTH($bits(mem_pkt_t)), .DEPTH(4)) mem_pkt_queue ( 
        .clk(clk),
        .rst(rst),

        .wen(packet_out_of_register.valid),
        .ren(dmem_resp), 
        .fifo_in(packet_out_of_register), 
        
        .fifo_out(mem_unit_input_packet_next),
        .fifo_empty(mem_pkt_fifo_empty), 
        .fifo_full(mem_pkt_fifo_full)
);

// always_comb begin
//     load_store_rs_done = '0;
//     if(store_at_top)
//         load_store_rs_done = '1;
//     else if(~load_store_fifo_empty & ~packet_out_of_fifo.i_use_store & ~mem_pkt_fifo_full & packet_out_of_fifo.ready)
//         load_store_rs_done = '1;
// end


//Mem Stage
mem_unit #(.ROB_DEPTH(ROB_DEPTH)) mem_unit (
    //inputs
    .dmem_rdata(dmem_rdata),
    .dmem_resp(dmem_resp),
    .input_packet(mem_unit_input_packet_next),
    .fifo_empty(mem_pkt_fifo_empty),
    .rob_index(rob_index),
    //outputs
    .load_store_in_proggress(load_store_in_proggress),
    .dmem_addr(dmem_addr),
    .dmem_wdata(dmem_wdata),
    .dmem_wmask(dmem_wmask),
    .dmem_rmask(dmem_rmask),
    .load_wb_pkt(load_wb_pkt)
);

endmodule : load_store_unit