//Ideas:
//need to hold rmask, and all those other values. implementation for that commented below. broke at 8 k
//other idea is only allow memory stuff to happen when not rst. broke at 19k. something weird happens with bren
//also commented below is the base version that breaks around 15k

module mem_unit
import rv32i_types::*;
#(
    parameter               ROB_DEPTH = 32
)
(
    input   logic                   clk,
    input   logic                   rst,
    input                           dmem_resp,
    input   logic   [31:0]          dmem_rdata,
    input   mem_pkt_t               input_packet,
    input   cdb_pkt_t               cdb_pkt2,

    output  logic   [31:0]          dmem_addr,
    output  logic   [31:0]          dmem_wdata,
    output  logic   [3:0]           dmem_wmask, 
    output  logic   [3:0]           dmem_rmask,
    output  logic                   load_store_in_proggress,
    output  wb_pkt_t                load_wb_pkt,
    output  st_tag_pkt_t            st_tag_pkt,
    output  logic [$clog2(ROB_DEPTH)-1:0] rob_idx_last                  
);

mem_pkt_t input_packet_prev, input_packet_next;

assign rob_idx_last = input_packet_prev.rob_idx;

always_comb begin
if (!rst) begin
    dmem_addr = {input_packet.mem_addr[31:2], 2'b0};
    dmem_wdata = input_packet.mem_wdata;
    load_wb_pkt = '0;
    load_wb_pkt.rd_data = '0;
    load_store_in_proggress = '0;
    dmem_wmask = '0;
    dmem_rmask = '0;
    st_tag_pkt = '0;

    //Store 
    if (input_packet.valid && input_packet.i_use_store) begin
        if ((input_packet.rob_idx != input_packet_prev.rob_idx) || !dmem_resp) begin 
            load_store_in_proggress = '1;
            dmem_wmask = input_packet.dmem_mask;
        end
    end

    //Load
    else if (input_packet.valid && !input_packet.i_use_store) begin 
        if ((input_packet.rob_idx != input_packet_prev.rob_idx) || !dmem_resp) begin
                dmem_rmask = input_packet.dmem_mask;
                load_store_in_proggress = '1;
        end
    end

    if (dmem_resp && input_packet_prev.valid && !input_packet_prev.i_use_store) begin
            case (input_packet_prev.mem_funct3)
            load_f3_lb : load_wb_pkt.rd_data = {{24{dmem_rdata[7 +8*input_packet_prev.mem_addr[1:0]]}}, dmem_rdata[8*input_packet_prev.mem_addr[1:0] +: 8]};
            load_f3_lbu: load_wb_pkt.rd_data = {{24{1'b0}}, dmem_rdata[8*input_packet_prev.mem_addr[1:0] +: 8]};
            load_f3_lh : load_wb_pkt.rd_data = {{16{dmem_rdata[15+16*input_packet_prev.mem_addr[1]]}}, dmem_rdata[16*input_packet_prev.mem_addr[1] +: 16]};
            load_f3_lhu: load_wb_pkt.rd_data = {{16{1'b0}}, dmem_rdata[16*input_packet_prev.mem_addr[1] +: 16]};
            load_f3_lw : load_wb_pkt.rd_data = dmem_rdata;
            default    : load_wb_pkt.rd_data = 'x;
        endcase
    end

    if(input_packet_prev.valid && dmem_resp && input_packet_prev.i_use_store) begin
        st_tag_pkt.st_tag_broadcast = '1;
        st_tag_pkt.store_tag = input_packet_prev.store_tag;
    end

    load_wb_pkt.valid = input_packet_prev.valid && dmem_resp && !rst; 
    load_wb_pkt.rvfi_pkt = input_packet_prev.rvfi_pkt;
    load_wb_pkt.rvfi_pkt.monitor_mem_wmask = (input_packet_prev.i_use_store ? input_packet_prev.dmem_mask : '0);
    load_wb_pkt.rvfi_pkt.monitor_mem_rmask = (!input_packet_prev.i_use_store ? input_packet_prev.dmem_mask : '0);
    load_wb_pkt.rvfi_pkt.monitor_mem_addr = {input_packet_prev.mem_addr[31:2], 2'b0};
    load_wb_pkt.rvfi_pkt.monitor_mem_wdata = input_packet_prev.mem_wdata;
    load_wb_pkt.rvfi_pkt.monitor_mem_rdata = dmem_rdata;
    load_wb_pkt.rvfi_pkt.monitor_valid = input_packet_prev.valid && dmem_resp && !rst; 
    load_wb_pkt.rd_paddr = input_packet_prev.i_use_store ? '0 : input_packet_prev.rd_paddr;
    load_wb_pkt.rob_idx = input_packet_prev.rob_idx;
    load_wb_pkt.rd_aaddr = input_packet_prev.rd_aaddr;
    load_wb_pkt.rvfi_pkt.monitor_rd_wdata = load_wb_pkt.rd_data;
end
else begin
    load_wb_pkt = '0;
    dmem_addr = '0;
    dmem_wdata = '0;
    dmem_wmask = '0;
    dmem_rmask = '0;
    load_store_in_proggress = '0;
    load_wb_pkt = '0;
    st_tag_pkt = '0;
end
end

always_ff @ (posedge clk) begin
    if (rst) input_packet_prev <= '0;
    else input_packet_prev <= input_packet_next;
end

always_comb begin
    input_packet_next = input_packet;

    if(cdb_pkt2.cdb_broadcast && cdb_pkt2.br_mispred && input_packet.bmask[cdb_pkt2.br_bit]) input_packet_next.valid = '0;
    else if (cdb_pkt2.cdb_broadcast && ~cdb_pkt2.br_mispred) input_packet_next.bmask[cdb_pkt2.br_bit] = '0;
end

endmodule : mem_unit





// module mem_unit
// import rv32i_types::*;
// #(
//     parameter               ROB_DEPTH = 32
// )
// (
//     input                           dmem_resp,
//     // input   logic                   st_dmem_resp,
//     // input   logic                   ld_dmem_resp,
//     input   logic   [31:0]          dmem_rdata,
//     input   mem_pkt_t               input_packet,
//     input   logic                   clk,
//     input   logic                   rst,

//     output  logic   [31:0]          dmem_addr,
//     output  logic   [31:0]          dmem_wdata,
//     output  logic   [3:0]           dmem_wmask,
//     output  logic   [3:0]           dmem_rmask,
//     output  logic                   load_store_in_proggress,
//     output  wb_pkt_t                load_wb_pkt,
//     output  st_tag_pkt_t            st_tag_pkt
// );

// assign dmem_addr = {input_packet.mem_addr[31:2], 2'b0};
// assign dmem_wdata = input_packet.mem_wdata;
// mem_pkt_t input_packet_prev;

// always_comb begin
//     load_wb_pkt = '0;
//     load_wb_pkt.rd_data = '0;
//     load_store_in_proggress = '0;
//     dmem_wmask = '0;
//     dmem_rmask = '0;
//     st_tag_pkt = '0;

//     //Store 
//     if (input_packet.valid && input_packet.i_use_store) begin
//         if ((input_packet.rob_idx != input_packet_prev.rob_idx) || !dmem_resp) begin 
//             load_store_in_proggress = '1;
//             dmem_wmask = input_packet.dmem_mask;
//         end
//     end

//     //Load
//     else if (input_packet.valid && !input_packet.i_use_store) begin 
//         if ((input_packet.rob_idx != input_packet_prev.rob_idx) || !dmem_resp) begin
//                 dmem_rmask = input_packet.dmem_mask;
//                 load_store_in_proggress = '1;
//         end
//     end

//     if (dmem_resp && input_packet_prev.valid && !input_packet_prev.i_use_store) begin
//             case (input_packet_prev.mem_funct3)
//             load_f3_lb : load_wb_pkt.rd_data = {{24{dmem_rdata[7 +8*input_packet_prev.mem_addr[1:0]]}}, dmem_rdata[8*input_packet_prev.mem_addr[1:0] +: 8]};
//             load_f3_lbu: load_wb_pkt.rd_data = {{24{1'b0}}, dmem_rdata[8*input_packet_prev.mem_addr[1:0] +: 8]};
//             load_f3_lh : load_wb_pkt.rd_data = {{16{dmem_rdata[15+16*input_packet_prev.mem_addr[1]]}}, dmem_rdata[16*input_packet_prev.mem_addr[1] +: 16]};
//             load_f3_lhu: load_wb_pkt.rd_data = {{16{1'b0}}, dmem_rdata[16*input_packet_prev.mem_addr[1] +: 16]};
//             load_f3_lw : load_wb_pkt.rd_data = dmem_rdata;
//             default    : load_wb_pkt.rd_data = 'x;
//         endcase
//     end

//     if(input_packet_prev.valid && dmem_resp && input_packet_prev.i_use_store) begin
//         st_tag_pkt.st_tag_broadcast = '1;
//         st_tag_pkt.store_tag = input_packet_prev.store_tag;
//     end

//     load_wb_pkt.valid = input_packet_prev.valid && dmem_resp; 
//     load_wb_pkt.rvfi_pkt = input_packet_prev.rvfi_pkt;
//     load_wb_pkt.rvfi_pkt.monitor_mem_wmask = (input_packet_prev.i_use_store ? input_packet_prev.dmem_mask : '0);
//     load_wb_pkt.rvfi_pkt.monitor_mem_rmask = (!input_packet_prev.i_use_store ? input_packet_prev.dmem_mask : '0);
//     load_wb_pkt.rvfi_pkt.monitor_mem_addr = {input_packet_prev.mem_addr[31:2], 2'b0};
//     load_wb_pkt.rvfi_pkt.monitor_mem_wdata = input_packet_prev.mem_wdata;
//     load_wb_pkt.rvfi_pkt.monitor_mem_rdata = dmem_rdata;
//     load_wb_pkt.rvfi_pkt.monitor_valid = input_packet_prev.valid && dmem_resp; 
//     load_wb_pkt.rd_paddr = input_packet_prev.rd_paddr;
//     load_wb_pkt.rob_idx = input_packet_prev.rob_idx;
//     load_wb_pkt.rd_aaddr = input_packet_prev.rd_aaddr;
//     load_wb_pkt.rvfi_pkt.monitor_rd_wdata = load_wb_pkt.rd_data;
// end

// always_ff @ (posedge clk) begin
//     if (rst) input_packet_prev <= '0;
//     else input_packet_prev <= input_packet;
// end

// endmodule : mem_unit







// module mem_unit
// import rv32i_types::*;
// #(
//     parameter               ROB_DEPTH = 32
// )
// (
//     input                           dmem_resp,
//     input   logic   [31:0]          dmem_rdata,
//     input   mem_pkt_t               input_packet,
//     input   logic                   clk,
//     input   logic                   rst,

//     output  logic   [31:0]          dmem_addr,
//     output  logic   [31:0]          dmem_wdata,
//     output  logic   [3:0]           dmem_wmask,
//     output  logic   [3:0]           dmem_rmask,
//     output  logic                   load_store_in_proggress,
//     output  wb_pkt_t                load_wb_pkt,
//     output  st_tag_pkt_t            st_tag_pkt
// );

// mem_pkt_t input_packet_prev;
// logic waiting, waiting_next;

// always_comb begin
//     dmem_addr = {input_packet.mem_addr[31:2], 2'b0};
//     dmem_wdata = input_packet.mem_wdata;
//     load_wb_pkt = '0;
//     load_wb_pkt.rd_data = '0;
//     load_store_in_proggress = '0;
//     dmem_wmask = '0;
//     dmem_rmask = '0;
//     st_tag_pkt = '0;
//     waiting_next = '0;

//     if (waiting) begin
//         dmem_addr = {input_packet_prev.mem_addr[31:2], 2'b0};
//         dmem_wdata = input_packet_prev.mem_wdata;
//         dmem_wmask = input_packet.i_use_store ? input_packet_prev.dmem_mask : '0;
//         dmem_rmask = !input_packet.i_use_store ? input_packet_prev.dmem_mask : '0;
//         if (dmem_resp) waiting_next = '0;
//         else waiting_next = '1;
//     end

//     else begin

//         //Store 
//         if (input_packet.valid && input_packet.i_use_store) begin
//             if ((input_packet.rob_idx != input_packet_prev.rob_idx) || !dmem_resp) begin 
//                 load_store_in_proggress = '1;
//                 dmem_wmask = input_packet.dmem_mask;
//             end
//         end

//         //Load
//         else if (input_packet.valid && !input_packet.i_use_store) begin 
//             if ((input_packet.rob_idx != input_packet_prev.rob_idx) || !dmem_resp) begin
//                     dmem_rmask = input_packet.dmem_mask;
//                     load_store_in_proggress = '1;
//             end
//         end

//         if (dmem_resp && input_packet_prev.valid && !input_packet_prev.i_use_store) begin
//                 case (input_packet_prev.mem_funct3)
//                 load_f3_lb : load_wb_pkt.rd_data = {{24{dmem_rdata[7 +8*input_packet_prev.mem_addr[1:0]]}}, dmem_rdata[8*input_packet_prev.mem_addr[1:0] +: 8]};
//                 load_f3_lbu: load_wb_pkt.rd_data = {{24{1'b0}}, dmem_rdata[8*input_packet_prev.mem_addr[1:0] +: 8]};
//                 load_f3_lh : load_wb_pkt.rd_data = {{16{dmem_rdata[15+16*input_packet_prev.mem_addr[1]]}}, dmem_rdata[16*input_packet_prev.mem_addr[1] +: 16]};
//                 load_f3_lhu: load_wb_pkt.rd_data = {{16{1'b0}}, dmem_rdata[16*input_packet_prev.mem_addr[1] +: 16]};
//                 load_f3_lw : load_wb_pkt.rd_data = dmem_rdata;
//                 default    : load_wb_pkt.rd_data = 'x;
//             endcase
//         end

//         if(input_packet_prev.valid && dmem_resp && input_packet_prev.i_use_store) begin
//             st_tag_pkt.st_tag_broadcast = '1;
//             st_tag_pkt.store_tag = input_packet_prev.store_tag;
//         end
//     end

//     load_wb_pkt.valid = input_packet_prev.valid && dmem_resp && !waiting; 
//     load_wb_pkt.rvfi_pkt = input_packet_prev.rvfi_pkt;
//     load_wb_pkt.rvfi_pkt.monitor_mem_wmask = (input_packet_prev.i_use_store ? input_packet_prev.dmem_mask : '0);
//     load_wb_pkt.rvfi_pkt.monitor_mem_rmask = (!input_packet_prev.i_use_store ? input_packet_prev.dmem_mask : '0);
//     load_wb_pkt.rvfi_pkt.monitor_mem_addr = {input_packet_prev.mem_addr[31:2], 2'b0};
//     load_wb_pkt.rvfi_pkt.monitor_mem_wdata = input_packet_prev.mem_wdata;
//     load_wb_pkt.rvfi_pkt.monitor_mem_rdata = dmem_rdata;
//     load_wb_pkt.rvfi_pkt.monitor_valid = input_packet_prev.valid && dmem_resp && !waiting;; 
//     load_wb_pkt.rd_paddr = input_packet_prev.rd_paddr;
//     load_wb_pkt.rob_idx = input_packet_prev.rob_idx;
//     load_wb_pkt.rd_aaddr = input_packet_prev.rd_aaddr;
//     load_wb_pkt.rvfi_pkt.monitor_rd_wdata = load_wb_pkt.rd_data;
// end

// always_ff @ (posedge clk) begin
//     if (rst && load_store_in_proggress) begin
//         input_packet_prev <= input_packet_prev;
//         waiting <= '1;
//     end
//     else if (rst) begin
//         input_packet_prev <= '0;
//         waiting <= '0;
//     end
//     else if (waiting) begin
//         waiting <= waiting_next;
//         input_packet_prev <= input_packet_prev;
//     end
//     else begin
//         input_packet_prev <= input_packet;
//         waiting <= '0;
//     end
// end

// endmodule : mem_unit




