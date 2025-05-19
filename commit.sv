// module commit
// import rv32i_types::*;
// #(
//     parameter               ROB_DEPTH  = 32
// )
// (
//     // ROB I/O
//     input  rob_pkt_t rob_top_pkt,
//     input  logic     rob_empty,

//     output logic     commit_read,

//     // RRAT I/O
//     output logic [4:0] rrat_rd_s,
//     output logic [$clog2(ROB_DEPTH+32)-1:0] rrat_p_addr,
//     output logic     rrat_wen
// );

// // logic           monitor_valid;
// // logic   [63:0]  monitor_order;
// // logic   [31:0]  monitor_inst;
// // logic   [4:0]   monitor_rs1_addr;
// // logic   [4:0]   monitor_rs2_addr;
// // logic   [31:0]  monitor_rs1_rdata;
// // logic   [31:0]  monitor_rs2_rdata;
// // logic           monitor_regf_we;
// // logic   [4:0]   monitor_rd_addr;
// // logic   [31:0]  monitor_rd_wdata;
// // logic   [31:0]  monitor_pc_rdata;
// // logic   [31:0]  monitor_pc_wdata;


// always_comb begin
//     commit_read = '0;
//     rrat_wen    = '0;
//     rrat_rd_s   = rob_top_pkt.rd_s; 
//     rrat_p_addr = rob_top_pkt.p_addr;

//     // remove instruction from rob and insert to rrat
//     if(rob_top_pkt.done && ~rob_empty) begin
//         commit_read = '1;
//         rrat_wen    = '1;
//     end
// end

// assign monitor_valid     = (rob_top_pkt.done && ~rob_empty ? rob_top_pkt.rvfi_pkt.monitor_valid : '0);
// assign monitor_order     = rob_top_pkt.rvfi_pkt.monitor_order;
// assign monitor_inst      = rob_top_pkt.rvfi_pkt.monitor_inst;
// assign monitor_rs1_addr  = rob_top_pkt.rvfi_pkt.monitor_rs1_addr;
// assign monitor_rs2_addr  = rob_top_pkt.rvfi_pkt.monitor_rs2_addr;
// assign monitor_rs1_rdata = rob_top_pkt.rvfi_pkt.monitor_rs1_rdata;
// assign monitor_rs2_rdata = rob_top_pkt.rvfi_pkt.monitor_rs2_rdata;
// assign monitor_rd_addr   = rob_top_pkt.rvfi_pkt.monitor_rd_addr;
// assign monitor_rd_wdata  = rob_top_pkt.rvfi_pkt.monitor_rd_wdata;
// assign monitor_pc_rdata  = rob_top_pkt.rvfi_pkt.monitor_pc_rdata;
// assign monitor_pc_wdata  = rob_top_pkt.rvfi_pkt.monitor_pc_wdata;

// endmodule: commit