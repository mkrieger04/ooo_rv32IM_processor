// Module Desciption:

module cacheline_adp
(
   input   logic               clk,
   input   logic               rst,


   output  logic   [31:0]      bmem_addr, // set addr that is being requested
   output  logic               bmem_read, // set high for one cycle to send request to bmem
   output  logic               bmem_write, // set high when writing burst of memory
   output  logic   [63:0]      bmem_wdata,
   input   logic               bmem_ready, // needs to be high to do anything


   input   logic   [31:0]      bmem_raddr, // burstmem addr that is being read from
   input   logic   [63:0]      bmem_rdata, // burst data bmem sends on read
   input   logic               bmem_rvalid, // when bmem starts outputing


   input  logic   [31:0]       icache_addr,
   input  logic                icache_read,
   input  logic                icache_write,
   output logic   [255:0]      icache_rdata,
   input  logic   [255:0]      icache_wdata,
   output logic                icache_resp,

   //--------------------- prefetch signals
   input  logic                 next_line_read,
   output logic                 nl_mem_resp,
   input  logic   [31:0]        next_line_addr,
   output logic   [255:0]       next_line_data,
   //---------------------

   input  logic   [31:0]       dcache_addr,
   input  logic                dcache_read,
   input  logic                dcache_write,
   output logic   [255:0]      dcache_rdata,
   input  logic   [255:0]      dcache_wdata,
   output logic                dcache_resp
  
);

   logic [31:0]      bmem_raddr_lat;
   assign bmem_raddr_lat = bmem_raddr;
   // State machine that interfaces between cache->bmem
   typedef enum logic [1:0] {
       idle = 2'b00,
       instruction = 2'b01,
       data = 2'b10,
       nextline = 2'b11
   } state_t;


   // Internal logic types
   logic [1:0]   counter;
   logic [63:0]  read_data  [3:0];
   logic [63:0]  write_data [3:0];
   logic         counter_done;


   state_t current_state, state_next;


   // Update state logic
   always_ff @ (posedge clk) begin
       if (rst) current_state <= idle;
       else     current_state <= state_next;
   end


   //Interfaces between bmem->cache
   always_ff @(posedge clk) begin
       if(rst) begin
           counter <= '0;
           counter_done <= 1'b0;
       end
       else if(counter == 2'b11) begin
           counter <= '0;
           counter_done <= 1'b1;
       end
       else if((bmem_rvalid || bmem_write) && bmem_ready) begin
           counter <= counter + 1'b1;
           counter_done <= 1'b0;
       end
       else begin
           counter_done <= 1'b0;
       end
   end


   // Read
   always_ff @(posedge clk) begin
       if(rst || !bmem_rvalid) begin
           read_data[0] <= 'x;
           read_data[1] <= 'x;
           read_data[2] <= 'x;
           read_data[3] <= 'x;
       end
       else if(bmem_rvalid && bmem_ready) begin
           read_data[counter[1:0]] <= bmem_rdata;
       end
   end
  
   always_comb begin
       next_line_data = '0;
       nl_mem_resp = '0;
       bmem_addr     = 'x;
       bmem_read     = '0;
       bmem_write    = '0;
       icache_resp   = '0;
       dcache_resp   = '0;
       icache_rdata  = 'x;
       dcache_rdata  = 'x;
  
       write_data[0] = 'x;
       write_data[1] = 'x;
       write_data[2] = 'x;
       write_data[3] = 'x;
      
       unique case (current_state)
           idle : begin
               if (dcache_read && bmem_ready) begin
                   bmem_addr    = dcache_addr;
                   bmem_read    = dcache_read;


                   state_next = data;
               end
               else if (dcache_write && bmem_ready) begin
                   bmem_write    = dcache_write;
                   bmem_addr     = dcache_addr;
                   write_data[0] = dcache_wdata[63:0];


                   state_next = data;
               end
               else if (icache_read && bmem_ready) begin
                   bmem_addr    = icache_addr;
                   bmem_read    = icache_read;


                   state_next   = instruction;
               end
               else if (icache_write && bmem_ready) begin
                   bmem_write    = icache_write;
                   write_data[0] = icache_wdata[63:0];


                   state_next = instruction;
               end

               else if (next_line_read && bmem_ready) begin
                   bmem_addr    = next_line_addr;
                   bmem_read    = next_line_read;
                   state_next   = nextline;
               end
               
               else begin
                   state_next = idle;
               end
           end
           
           nextline : begin 
                state_next     = counter_done ? idle : nextline;
                next_line_data = {read_data[3], read_data[2], read_data[1], read_data[0]};
                nl_mem_resp    = counter_done;
                bmem_addr      = next_line_addr; //todo may want to write to icache
           end

           instruction : begin
               state_next   = counter_done || (icache_write && counter == 2'b11) ? idle : instruction;
               bmem_addr    = icache_write ? icache_addr : 'x;
               bmem_write   = counter_done ? '0 : icache_write;
               icache_resp  = icache_write ? counter == 2'b11 : counter_done;

               write_data[1] = icache_wdata[127:64];
               write_data[2] = icache_wdata[191:128];
               write_data[3] = icache_wdata[255:192];
              
               icache_rdata = counter_done ? {read_data[3], read_data[2], read_data[1], read_data[0]} : 'x;
           end


           data : begin
               state_next   = counter_done || (dcache_write && counter == 2'b11) ? idle : data;
               bmem_addr    = dcache_write ? dcache_addr : 'x;
               bmem_write   = counter_done ? '0 : dcache_write;
               dcache_resp  = dcache_write ? counter == 2'b11 : counter_done;


               write_data[1] = dcache_wdata[127:64];
               write_data[2] = dcache_wdata[191:128];
               write_data[3] = dcache_wdata[255:192];


               dcache_rdata = counter_done ? {read_data[3], read_data[2], read_data[1], read_data[0]} : 'x;
           end


           default : begin
               state_next = idle;
           end
       endcase
   end


   // Write
   assign bmem_wdata = bmem_write && bmem_ready ? write_data[counter[1:0]] : 'x;




endmodule