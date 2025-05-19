module cache_pp_inst
import rv32i_types::*;
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

    // output  logic   [255:0] latest_hit_line,
    // output  logic   [31:0]  latest_hit_line_addr,

    // memory side signals, dfp -> downward facing port
    output  logic   [31:0]  dfp_addr,
    output  logic           dfp_read,
    output  logic           dfp_write,
    input   logic   [255:0] dfp_rdata,
    output  logic   [255:0] dfp_wdata,
    input   logic           dfp_resp
);

logic [22:0] way_tag [3:0];
logic [255:0] way_data [3:0];
// logic way_valid [3:0];
// logic way_dirty [3:0];
// logic [2:0] way_lru;

logic [22:0] way_tag_write   [3:0];
logic [255:0] way_data_write [3:0];
logic [31:0] way_data_wmask;
// logic way_valid_write        [3:0];
// logic way_dirty_write        [3:0];
// logic [2:0] way_lru_write;

logic data_write  [3:0];
// logic valid_write [3:0];
logic tag_write   [3:0];
// logic dirty_write [3:0];
// logic lru_write;

logic data_select  [3:0];
// logic valid_select [3:0];
logic tag_select   [3:0];
// logic dirty_select [3:0];
// logic lru_select;


logic [1:0] way_addr;
logic [1:0] lru_way_addr;

logic tag_hit;

logic [3:0] addr_sel, data_addr_sel;

logic back_stall;

cache_pkt    compare_cachepp_next;
cache_pkt    idle_cache_pp;



logic way_valid_curr [3:0];
logic way_valid_write_curr [3:0];
logic valid_write_curr [3:0];
logic valid_select_curr [3:0];

logic way_valid_inc [3:0];
logic way_valid_write_inc [3:0];
logic valid_write_inc [3:0];
logic valid_select_inc [3:0];

logic way_valid_real [3:0];


    generate for (genvar i = 0; i < 4; i++) begin : arrays
        mp_cache_data_array data_array (
            .clk0       (clk),
            .csb0       (data_select[i[1:0]]),
            .web0       (data_write[i[1:0]]),
            .wmask0     (way_data_wmask),
            .addr0      (data_addr_sel),
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

        dp_ff_array #(
            .WIDTH      (1)
        ) valid_array (
            .clk0(clk),
            .rst0(rst),

            .csb0(valid_select_curr[i[1:0]]),
            .web0(valid_write_curr[i[1:0]]),
            .addr0(compare_cachepp_next.ufp_addr[8:5]),
            .din0(way_valid_write_curr[i[1:0]]),
            .dout0(way_valid_curr[i[1:0]]),

            .csb1(valid_select_inc[i[1:0]]),
            .web1(valid_write_inc[i[1:0]]),
            .addr1(ufp_addr[8:5]),
            .din1(way_valid_write_inc[i[1:0]]),
            .dout1(way_valid_inc[i[1:0]])
        );
    end
    endgenerate

    logic lru_select_curr, lru_select_inc, lru_write_curr, lru_write_inc;
    logic [2:0] way_lru_write_curr, way_lru_write_inc, way_lru_curr, way_lru_inc, way_lru_inc_real, way_lru_inc_forw;
    logic way_lru_forward_en, way_lru_forward_en_delay;

    logic [2:0] way_lru_real;
    logic new_req;
    logic new_req_reg;
    logic primed;
    logic write_hit;

    always_ff @(posedge clk) begin
        if(rst) way_lru_forward_en_delay <= '0;
        else way_lru_forward_en_delay <= way_lru_forward_en;
    end

    always_ff @(posedge clk) begin
        if(rst) way_lru_inc_forw <= '0;
        else way_lru_inc_forw <= way_lru_write_curr;
    end

    assign way_lru_inc_real = way_lru_forward_en_delay ? way_lru_inc_forw : way_lru_inc;

    dp_ff_array #(
        .WIDTH      (3)
    ) lru_array (
        .clk0(clk),
        .rst0(rst),

        .csb0(lru_select_curr),
        .web0(lru_write_curr),
        .addr0(compare_cachepp_next.ufp_addr[8:5]),
        .din0(way_lru_write_curr),
        .dout0(way_lru_curr),

        .csb1(lru_select_inc),
        .web1(lru_write_inc),
        .addr1(ufp_addr[8:5]),
        .din1(way_lru_write_inc),
        .dout1(way_lru_inc)
    );

    assign addr_sel = back_stall ? compare_cachepp_next.ufp_addr[8:5] : ufp_addr[8:5];
    assign data_addr_sel = write_hit ? compare_cachepp_next.ufp_addr[8:5] : addr_sel;

    always_ff @(posedge clk) begin
        if(rst) new_req_reg <= '0;
        else new_req_reg <= new_req;
    end

// —————————————————————————————————— Pipeline Register ——————————————————————————————————

    always_ff @(posedge clk) begin
        if(rst) begin
            compare_cachepp_next <= '0;
        end
        else if(!back_stall) begin      
            compare_cachepp_next <= idle_cache_pp;
        end
    end

// —————————————————————————————————— Pipeline Register ——————————————————————————————————

    enum integer unsigned {
        s_compare,
        s_allocate,
        s_prime
    } state, state_next;

    always_ff @(posedge clk) begin
        if(rst) 
            primed <= '0;
        else if(state == s_prime)
            primed <= '1;
        else 
            primed <= '0;
    end


    always_ff @(posedge clk) begin
        if (rst) begin
            state <= s_compare;
        end else begin
            state <= state_next;
        end
    end

    assign way_lru_real   = (state == s_compare) & ~primed ? way_lru_inc_real : way_lru_curr;
    assign way_valid_real = (state == s_compare) & ~primed ? way_valid_inc    : way_valid_curr;

    always_comb begin
        new_req = '0;
        idle_cache_pp = '0;
        back_stall = '0;

        idle_cache_pp.ufp_addr  = ufp_addr;
        idle_cache_pp.ufp_rmask = ufp_rmask;
        idle_cache_pp.ufp_wmask = ufp_wmask;
        idle_cache_pp.ufp_wdata = ufp_wdata;

        for(integer unsigned i = 0; i < unsigned'(4); i++) begin
            // Way data chip select signals
            data_select[i]     = 1'b1;
            tag_select[i]      = 1'b1;
            valid_select_curr[i]   = 1'b1;
            valid_select_inc[i]    = 1'b1;
            lru_select_inc     = 1'b1;
            lru_select_curr    = 1'b1;

            // Way data write enable signals
            data_write[i]      = 1'b1;
            tag_write[i]       = 1'b1;
            valid_write_curr[i]     = 1'b1;
            valid_write_inc[i]     = 1'b1;
            lru_write_inc      = 1'b1;
            lru_write_curr     = 1'b1;

            // Way data that we are writing
            way_data_write[i]  = 'x;
            way_tag_write[i]   = 'x;
            way_valid_write_curr[i] = 'x;
            way_valid_write_inc[i] = 'x;
            way_lru_write_inc  = 'x;
            way_lru_write_curr = 'x;

            // Mask for doing a data write 
            way_data_wmask  = '0;
        end

        if((ufp_rmask != '0 || ufp_wmask != '0) && !back_stall) begin
            new_req = '1;
            for(integer unsigned i = 0; i < unsigned'(4); i++) begin
                // Way data chip select signals
                data_select[i]     = 1'b0;
                tag_select[i]      = 1'b0;
                valid_select_curr[i]   = 1'b0;
                valid_select_inc[i]    = 1'b0;

                lru_select_inc     = 1'b0;
                lru_select_curr    = 1'b0;
            end
        end
// —————————————————————————————————— ^^^Fetch Stage^^^ ——————————————————————————————————

        tag_hit = 1'b0;

        way_addr = 'x;

        ufp_resp = 1'b0;
        ufp_rdata = 'x;

        dfp_addr = 'x;
        dfp_read = 1'b0;
        dfp_write = 1'b0;
        dfp_wdata = 'x;
        way_lru_forward_en = '0;
        write_hit = '0;

        unique case(state)
        s_compare: begin
            back_stall = '0;
            if(new_req_reg | primed) begin
                for(integer unsigned i = 0; i < unsigned'(4); i++) begin
                    if(way_tag[i] == compare_cachepp_next.ufp_addr[31:9] && way_valid_real[i]) begin
                        tag_hit = 1'b1;
                        way_addr = 2'(i);
                        // latest_hit_line      = way_data[i];
                        // latest_hit_line_addr = compare_cachepp_next.ufp_addr;
                    end
                end

                if(tag_hit) begin
                    way_lru_forward_en = compare_cachepp_next.ufp_addr[8:5] == ufp_addr[8:5] ? '1 : '0;

                    ufp_resp = 1'b1;

                    if(compare_cachepp_next.ufp_rmask != '0 && compare_cachepp_next.ufp_wmask == '0) begin
                        ufp_rdata = way_data[way_addr][compare_cachepp_next.ufp_addr[4:0] * 8 +: 32];
                    end

                    lru_select_curr         = 1'b0;
                    lru_write_curr          = 1'b0;

                    way_lru_write_curr = way_lru_real;

                    unique case (way_addr)
                    2'b00: way_lru_write_curr = {way_lru_real[2], 2'b00};

                    2'b01: way_lru_write_curr = {way_lru_real[2], 2'b10};

                    2'b10: way_lru_write_curr = {1'b0, way_lru_real[1], 1'b1};

                    2'b11: way_lru_write_curr = {1'b1, way_lru_real[1], 1'b1};

                    default: way_lru_write_curr = 'x;
                    endcase


                    state_next = s_compare;
                end
                else begin
                    back_stall = '1;
                    state_next = s_allocate;
                end
            end
            else begin
                state_next = s_compare;
            end
        end
        s_allocate: begin
            back_stall = '1;
            dfp_addr = {{compare_cachepp_next.ufp_addr[31:5]},{5'd0}};
            dfp_read = 1'b1;
            dfp_write = 1'b0;

            if(dfp_resp) begin

                data_select[lru_way_addr]  = '0;
                tag_select[lru_way_addr]   = '0;
                valid_select_curr[lru_way_addr] = '0;

                data_write[lru_way_addr]      = 1'b0;
                way_data_wmask                = 32'hFFFFFFFF;
                way_data_write[lru_way_addr]  = dfp_rdata;

                tag_write[lru_way_addr]       = 1'b0;
                way_tag_write[lru_way_addr]   = compare_cachepp_next.ufp_addr[31:9];

                valid_write_curr[lru_way_addr]     = 1'b0;
                way_valid_write_curr[lru_way_addr] = 1'b1;

                state_next = s_prime;
            end
            else begin
                state_next = s_allocate;
            end
        end
        s_prime: begin
            back_stall = '1;
            state_next = s_compare;
            for(integer unsigned i = 0; i < unsigned'(4); i++) begin
                data_select[i]          = '0;
                tag_select[i]           = '0;
                valid_select_curr[i]    = '0;
            end
            lru_select_curr         = '0;
        end
        default:
            state_next = s_compare;
        endcase
    end


    always_comb begin
        unique casez (way_lru_real)
            3'b?11: lru_way_addr = 2'b00;
            3'b?01: lru_way_addr = 2'b01;
            3'b1?0: lru_way_addr = 2'b10;
            3'b0?0: lru_way_addr = 2'b11;
            default: lru_way_addr = 'x;
        endcase
    end

endmodule : cache_pp_inst