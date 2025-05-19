module icache_eddie 
//import cache_pack::*;
(
    input   logic           clk,
    input   logic           rst,

    // cpu side signals, ufp -> upward facing port
    input   logic   [31:0]  ufp_addr,
    input   logic   [3:0]   ufp_rmask,
    input   logic   [3:0]   ufp_wmask,
    output  logic   [31:0]  ufp_rdata,
    input   logic   [31:0]  ufp_wdata,
    output  logic           ufp_resp,

    output  logic   [255:0] latest_hit_line,
    output  logic   [31:0]  latest_hit_line_addr,

    // memory side signals, dfp -> downward facing port
    output  logic   [31:0]  dfp_addr,
    output  logic           dfp_read,
    output  logic           dfp_write,
    input   logic   [255:0] dfp_rdata,
    output  logic   [255:0] dfp_wdata,
    input   logic           dfp_resp,

    output  logic           cache_miss_complete,
    output  logic   [31:0]  next_line_addr
);

logic [22:0] way_tag [3:0];
logic [255:0] way_data [3:0];
logic way_valid [3:0];
logic [2:0] way_lru;

logic [22:0] way_tag_write   [3:0];
logic [255:0] way_data_write [3:0];
logic [31:0] way_data_wmask  [3:0];
logic way_valid_write        [3:0];
logic [2:0] way_lru_write;

logic data_write  [3:0];
logic valid_write [3:0];
logic tag_write   [3:0];
logic lru_write;

logic data_select  [3:0];
logic valid_select [3:0];
logic tag_select   [3:0];
logic lru_select;

logic [255:0] way_data_temp;


logic [1:0] way_addr;
logic [1:0] lru_way_addr;

logic   [31:0]  ufp_addr_reg;
logic   [3:0]   ufp_rmask_reg;
logic   [3:0]   ufp_wmask_reg;
logic   [31:0]  ufp_wdata_reg;

logic tag_hit;

logic [255:0] dfp_rdata_reg;

logic [3:0] addr_sel;


    generate for (genvar i = 0; i < 4; i++) begin : arrays
        mp_cache_data_array data_array (
            .clk0       (clk),
            .csb0       (data_select[i[1:0]]),
            .web0       (data_write[i[1:0]]),
            .wmask0     (way_data_wmask[i[1:0]]),
            .addr0      (addr_sel),
            .din0       (way_data_write[i[1:0]]),
            .dout0      (way_data[i[1:0]])
        );
        mp_cache_tag_array tag_array (
            .clk0       (clk),
            .csb0       (tag_select[i[1:0]]),
            .web0       (tag_write[i[1:0]]),
            .addr0      (addr_sel),
            .din0       (way_tag_write[i[1:0]]),
            .dout0      (way_tag[i[1:0]])
        );
        sp_ff_array valid_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       (valid_select[i[1:0]]),
            .web0       (valid_write[i[1:0]]),
            .addr0      (addr_sel),
            .din0       (way_valid_write[i[1:0]]),
            .dout0      (way_valid[i[1:0]])
        );

    end endgenerate

    sp_ff_array #(
        .WIDTH      (3)
    ) lru_array (
        .clk0       (clk),
        .rst0       (rst),
        .csb0       (lru_select),
        .web0       (lru_write),
        .addr0      (addr_sel),
        .din0       (way_lru_write),
        .dout0      (way_lru)
    );

    enum integer unsigned {
        s_idle,
        s_compare,
        s_allocate
    } state, state_next;

    assign addr_sel = state == s_idle ? ufp_addr[8:5] : ufp_addr_reg[8:5];

    always_ff @(posedge clk) begin
        if(rst) begin
            ufp_addr_reg  <= '0;
            ufp_rmask_reg <= '0;
            ufp_wmask_reg <= '0;
            ufp_wdata_reg <= '0;
        end
        else if(state == s_idle) begin
            ufp_addr_reg  <= ufp_addr;
            ufp_rmask_reg <= ufp_rmask;
            ufp_wmask_reg <= ufp_wmask;
            ufp_wdata_reg <= ufp_wdata;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= s_idle;
        end else begin
            state <= state_next;
        end
    end

    always_comb begin
        // for(integer i = 0; i < 4; i++) begin
        //     data_select[unsigned'(i[1:0])]     = 1'b0;
        //     tag_select[unsigned'(i[1:0])]      = 1'b0;
        //     valid_select[unsigned'(i[1:0])]    = 1'b0;
        //     dirty_select[unsigned'(i[1:0])]    = 1'b0;

        //     data_write[unsigned'(i[1:0])]      = 1'b1;
        //     tag_write[unsigned'(i[1:0])]       = 1'b1;
        //     valid_write[unsigned'(i[1:0])]     = 1'b1;
        //     dirty_write[unsigned'(i[1:0])]     = 1'b1;

        //     way_data_write[unsigned'(i[1:0])]  = 'x;
        //     way_tag_write[unsigned'(i[1:0])]   = 'x;
        //     way_valid_write[unsigned'(i[1:0])] = 'x;
        //     way_dirty_write[unsigned'(i[1:0])] = 'x;
        //     way_data_wmask[unsigned'(i[1:0])]  = '0;
        // end
            data_select[0]     = 1'b0;
            tag_select[0]      = 1'b0;
            valid_select[0]    = 1'b0;
            data_write[0]      = 1'b1;
            tag_write[0]       = 1'b1;
            valid_write[0]     = 1'b1;
            way_data_write[0]  = 'x;
            way_tag_write[0]   = 'x;
            way_valid_write[0] = 'x;
            way_data_wmask[0]  = '0;

            data_select[1]     = 1'b0;
            tag_select[1]      = 1'b0;
            valid_select[1]    = 1'b0;
            data_write[1]      = 1'b1;
            tag_write[1]       = 1'b1;
            valid_write[1]     = 1'b1;
            way_data_write[1]  = 'x;
            way_tag_write[1]   = 'x;
            way_valid_write[1] = 'x;
            way_data_wmask[1]  = '0;

            data_select[2]     = 1'b0;
            tag_select[2]      = 1'b0;
            valid_select[2]    = 1'b0;
            data_write[2]      = 1'b1;
            tag_write[2]       = 1'b1;
            valid_write[2]     = 1'b1;
            way_data_write[2]  = 'x;
            way_tag_write[2]   = 'x;
            way_valid_write[2] = 'x;
            way_data_wmask[2]  = '0;

            data_select[3]     = 1'b0;
            tag_select[3]      = 1'b0;
            valid_select[3]    = 1'b0;
            data_write[3]      = 1'b1;
            tag_write[3]       = 1'b1;
            valid_write[3]     = 1'b1;
            way_data_write[3]  = 'x;
            way_tag_write[3]   = 'x;
            way_valid_write[3] = 'x;
            way_data_wmask[3]  = '0;

            cache_miss_complete = '0;
            next_line_addr = '0;


        lru_select = 1'b0;
        lru_write = 1'b1;
        way_lru_write = 'x;

        tag_hit = 1'b0;
        way_data_temp = '0;

        way_addr = 'x;

        ufp_resp = 1'b0;
        ufp_rdata = 'x;

        dfp_addr = 'x;
        dfp_read = 1'b0;
        dfp_write = 1'b0;
        dfp_wdata = 'x;

        latest_hit_line = 'x;
        latest_hit_line_addr = 'x;


        unique case(state)
        s_idle: begin
            if(ufp_rmask != '0 || ufp_wmask != '0) begin
                state_next = s_compare;
            end
            else begin
                state_next = s_idle;
            end
        end
        s_compare: begin
            // for(integer i = 0; i < 4; i++) begin
            //     if(way_tag[unsigned'(i[1:0])] == ufp_addr_reg[31:9] && way_valid[unsigned'(i[1:0])]) begin
            //         tag_hit = 1'b1;
            //         way_addr = unsigned'(i[1:0]);
            //     end
            // end
            if((way_tag[0] == ufp_addr_reg[31:9]) && way_valid[0]) begin
                tag_hit = 1'b1;
                way_addr = 2'd0;
                latest_hit_line      = way_data[0];
                latest_hit_line_addr = ufp_addr_reg;
            end
            else if((way_tag[1] == ufp_addr_reg[31:9]) && way_valid[1]) begin
                tag_hit = 1'b1;
                way_addr = 2'd1;
                latest_hit_line      = way_data[1];
                latest_hit_line_addr = ufp_addr_reg;
            end
            else if((way_tag[2] == ufp_addr_reg[31:9]) && way_valid[2]) begin
                tag_hit = 1'b1;
                way_addr = 2'd2;
                latest_hit_line      = way_data[2];
                latest_hit_line_addr = ufp_addr_reg;
            end
            else if((way_tag[3] == ufp_addr_reg[31:9]) && way_valid[3]) begin
                tag_hit = 1'b1;
                way_addr = 2'd3;
                latest_hit_line      = way_data[3];
                latest_hit_line_addr = ufp_addr_reg;
            end

            if(tag_hit) begin
                ufp_resp = 1'b1;
                way_data_temp = way_data[way_addr];
                if(ufp_rmask_reg != '0 && ufp_wmask_reg == '0) begin
                    ufp_rdata = way_data_temp[ufp_addr_reg[4:0] * 8 +: 32];
                end
                else if(ufp_rmask_reg == '0 && ufp_wmask_reg != '0) begin
                    data_write[way_addr]  = 1'b0;

                    if(ufp_wmask_reg[0]) begin
                        way_data_temp[(ufp_addr_reg[4:0] * 8) +: 8] = ufp_wdata_reg[0 +: 8];
                    end

                    if(ufp_wmask_reg[1]) begin
                        way_data_temp[(ufp_addr_reg[4:0] * 8) + 8 +: 8] = ufp_wdata_reg[8 +: 8];
                    end

                    if(ufp_wmask_reg[2]) begin
                        way_data_temp[(ufp_addr_reg[4:0] * 8) + 16 +: 8] = ufp_wdata_reg[16 +: 8];
                    end

                    if(ufp_wmask_reg[3]) begin
                        way_data_temp[(ufp_addr_reg[4:0] * 8) + 24 +: 8] = ufp_wdata_reg[24 +: 8];
                    end

                    data_write[way_addr]  = 1'b0;
                    way_data_wmask[way_addr] = 32'hFFFFFFFF;
                    way_data_write[way_addr] = way_data_temp;

                end
                
                lru_write = 1'b0;

                way_lru_write = way_lru;

                unique case (way_addr)
                2'b00: way_lru_write = {way_lru[2], 2'b00};

                2'b01: way_lru_write = {way_lru[2], 2'b10};

                2'b10: way_lru_write = {1'b0, way_lru[1], 1'b1};

                2'b11: way_lru_write = {1'b1, way_lru[1], 1'b1};

                default: way_lru_write = 'x;
                endcase


                state_next = s_idle;
            end
            else begin
                state_next = s_allocate;
            end
        end
        s_allocate: begin
            dfp_addr = {{ufp_addr_reg[31:5]},{5'd0}};
            dfp_read = 1'b1;
            dfp_write = 1'b0;

            if(dfp_resp) begin
                data_write[lru_way_addr]  = 1'b0;
                way_data_wmask[lru_way_addr] = 32'hFFFFFFFF;
                way_data_write[lru_way_addr] = dfp_rdata;

                tag_write[lru_way_addr] = 1'b0;
                way_tag_write[lru_way_addr] = ufp_addr_reg[31:9];

                valid_write[lru_way_addr] = 1'b0;
                way_valid_write[lru_way_addr] = 1'b1;

                state_next = s_idle;

                 // prefetch
                cache_miss_complete = '1;
                next_line_addr = {ufp_addr_reg[31:5], 5'b0} + 32;
            end
            else begin
                state_next = s_allocate;
            end
        end
        default:
            state_next = s_idle;
        endcase
    end


    always_comb begin
        unique casez (way_lru)
            3'b?11: lru_way_addr = 2'b00;
            3'b?01: lru_way_addr = 2'b01;
            3'b1?0: lru_way_addr = 2'b10;
            3'b0?0: lru_way_addr = 2'b11;
            default: lru_way_addr = 'x;
        endcase
    end


endmodule : icache_eddie