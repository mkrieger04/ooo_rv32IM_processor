module ratatouille
import rv32i_types::*;
#(
   parameter               ROB_DEPTH = 32
)(
   input   logic           clk,
   input   logic           rst,
//    input   logic           br_en, // branch reset signal


   // cdb I/O
   input   cdb_pkt_t       cdb_pkt,
   input   cdb_pkt_t       cdb_pkt2,


   // Dispatch/rename I/O
   input   logic           rat_rename_rd_we,
   input   logic   [$clog2(ROB_DEPTH + 32)-1:0] rd_p_addr_rename_val,
   input   logic   [4:0]   rs1_s, rs2_s, rd_s,

   output  ratatouille_t   rs1_rat, rs2_rat,

    // ebr
   input ratatouille_t  br_rat[32],
   output ratatouille_t  rat_data[32]
);

    
   ratatouille_t rat[32];

   assign rat_data = rat;
   always_ff @(posedge clk) begin
       if(rst) begin
           // set all arc regs to p0 and set valid
           for (integer i = 0; i < 32; i++) begin
               rat[i].p_addr <= '0;
               rat[i].valid  <= '1;
           end
       end
       else if(cdb_pkt2.br_mispred & cdb_pkt2.cdb_broadcast) begin
            rat <= br_rat;
       end
       // dispatch is renaming rd
       else begin
            if((rat_rename_rd_we)) begin
                if((cdb_pkt.cdb_broadcast && (rd_s != cdb_pkt.cdb_aaddr) && (rat[cdb_pkt.cdb_aaddr].p_addr == cdb_pkt.cdb_p_addr)) && (cdb_pkt2.cdb_broadcast && (rd_s != cdb_pkt2.cdb_aaddr) && (rat[cdb_pkt2.cdb_aaddr].p_addr == cdb_pkt2.cdb_p_addr))) begin
                    rat[rd_s].valid  <= '0;
                    rat[rd_s].p_addr <= rd_p_addr_rename_val;
                    rat[cdb_pkt.cdb_aaddr].valid <= '1;
                    rat[cdb_pkt2.cdb_aaddr].valid <= '1;
                end
                else if ((cdb_pkt.cdb_broadcast && (rd_s != cdb_pkt.cdb_aaddr) && (rat[cdb_pkt.cdb_aaddr].p_addr == cdb_pkt.cdb_p_addr))) begin
                    rat[rd_s].valid  <= '0;
                    rat[rd_s].p_addr <= rd_p_addr_rename_val;
                    rat[cdb_pkt.cdb_aaddr].valid <= '1;
                end
                else if((cdb_pkt2.cdb_broadcast && (rd_s != cdb_pkt2.cdb_aaddr) && (rat[cdb_pkt2.cdb_aaddr].p_addr == cdb_pkt2.cdb_p_addr))) begin
                    rat[rd_s].valid  <= '0;
                    rat[rd_s].p_addr <= rd_p_addr_rename_val;
                    rat[cdb_pkt2.cdb_aaddr].valid <= '1;
                end
                else begin
                    rat[rd_s].valid  <= '0;
                    rat[rd_s].p_addr <= rd_p_addr_rename_val;
                end
            end
            else begin
                if((cdb_pkt.cdb_broadcast  && (rat[cdb_pkt.cdb_aaddr].p_addr == cdb_pkt.cdb_p_addr)))begin
                    rat[cdb_pkt.cdb_aaddr].valid <= '1;
                end

                if((cdb_pkt2.cdb_broadcast && (rat[cdb_pkt2.cdb_aaddr].p_addr == cdb_pkt2.cdb_p_addr)))begin
                    rat[cdb_pkt2.cdb_aaddr].valid <= '1;
                end
            end
       end
   end


   // read rs1 and rs2 rat's
   always_comb begin
       rs1_rat = rat[rs1_s];
       rs2_rat = rat[rs2_s];
   end


endmodule : ratatouille
