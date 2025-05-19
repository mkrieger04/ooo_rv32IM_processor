module dcache 
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

    // memory side signals, dfp -> downward facing port
    output  logic   [31:0]  dfp_addr,
    output  logic           dfp_read,
    output  logic           dfp_write,
    input   logic   [255:0] dfp_rdata,
    output  logic   [255:0] dfp_wdata,
    input   logic           dfp_resp
);
    // define state machine states
    enum integer unsigned {
        s_idle,
        s_hit,
        s_wb,
        s_alloc
    } state, state_next;

    // register ufp input values
    logic [31:0]  ufp_addr_reg;
    logic [31:0]  ufp_addr_reg_next;

    logic [3:0]   ufp_wmask_reg;
    logic [3:0]   ufp_wmask_reg_next;

    logic [31:0]  ufp_wdata_reg;
    logic [31:0]  ufp_wdata_reg_next;

    // lru logic types
    logic [1:0]     lru_decode;

    logic           web_lru;
    logic [2:0]     lru_write;
    logic [2:0]     lru_ro;

    // data array logic types
    logic [3:0]     web;
    logic [31:0]    wmask_data;
    logic [255:0]   data_write;
    logic [255:0]   data_ro[4];

    // tag_array logic types
    logic [22:0]    tag_ro [4]; // 4 indexes of 23 bits

    // dirty logic types
    logic           dirty_write;
    logic [3:0]     dirty_ro;

    // valid_array logic types
    logic [3:0]     valid_ro;


    // edit state machine states on clock cycle
    always_ff @(posedge clk) begin
        if (rst) begin
            state         <= s_idle;
            ufp_addr_reg  <= 'x;
            ufp_wmask_reg <= 'x;
            ufp_wdata_reg <= 'x;
        end
        else begin
            state         <= state_next;
            ufp_addr_reg  <= ufp_addr_reg_next;
            ufp_wmask_reg <= ufp_wmask_reg_next;
            ufp_wdata_reg <= ufp_wdata_reg_next;
        end
    end

    assign ufp_addr_reg_next  = ufp_addr;
    assign ufp_wmask_reg_next = ufp_wmask;
    assign ufp_wdata_reg_next = ufp_wdata;

    generate for (genvar i = 0; i < 4; i++) begin : arrays
        mp_cache_data_array data_array (
            .clk0       (clk),
            .csb0       ('0),
            .web0       (web[i]),   //  set write enable 
            .wmask0     (wmask_data), 
            .addr0      (ufp_addr[8:5]), // select the set
            .din0       (data_write),
            .dout0      (data_ro[i])
        );
        mp_cache_tag_array tag_array (
            .clk0       (clk),
            .csb0       ('0),
            .web0       (web[i]),
            .addr0      (ufp_addr[8:5]), // select the set
            .din0       (ufp_addr[31:9]), // write in the tag
            .dout0      (tag_ro[i]) 
        );
        sp_ff_array valid_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       ('0),  
            .web0       (web[i]),    
            .addr0      (ufp_addr[8:5]), // select the set
            .din0       ('1), // always write valid
            .dout0      (valid_ro[i]) 
        );
        sp_ff_array dirty_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       ('0),  
            .web0       (web[i]),     
            .addr0      (ufp_addr[8:5]),  // select the set
            .din0       (dirty_write),
            .dout0      (dirty_ro[i])
        );
    end endgenerate

    sp_ff_array #(
        .WIDTH      (3)
    ) lru_array (
        .clk0       (clk),
        .rst0       (rst),
        .csb0       ('0), // active low chip select
        .web0       (web_lru), //active low write enable
        .addr0      (ufp_addr[8:5]), // select the set
        .din0       (lru_write),
        .dout0      (lru_ro)
    );

    // decode plru to find lru way
    always_comb begin
        unique casez (lru_ro) 
            3'b0?0:  lru_decode = 2'd0; // replace way 0
            3'b1?0:  lru_decode = 2'd1; // replace way 1
            3'b?01:  lru_decode = 2'd2; // replace way 2
            3'b?11:  lru_decode = 2'd3; // replace way 3
            default: lru_decode = 'x;                   
        endcase
    end


    always_comb begin
        state_next  = state;

        // initialize module output's
        dfp_addr    = 'x;
        dfp_read    = '0;
        dfp_write   = '0;
        dfp_wdata   = 'x;

        ufp_resp    = '0;

        // initialize data array logic
        web         = '1;
        wmask_data  = '0;
        data_write  = 'x;

        // initialize dirty logic type
        dirty_write = '1;

        // initialize lru logic types
        web_lru     = '1;
        lru_write   = 'x;

        ufp_rdata = 'x;
    
    unique case(state) 
        /* Overview: if ufp sends a read or write request switch to the hit/tag check state
        */
        s_idle: begin
            if(|ufp_rmask || |ufp_wmask) begin
                state_next = s_hit;
            end
        end
        /* Overview: 
            1. Index the cache for the set from ufp_addr
            2. Compare tag against Valid Ways
            3. If Hit:
                On Read (ufp_read high):  
                On write (ufp_write_high): 
                    Overwrite bytes of way with ufp_wdata that ufp_wmask indicates
                UPDATE PLRU TO POINT TO CACHE WAY THAT was just accessed
                
                If Miss:
                 Check plru for least recently used way to replace, 
                 If it is dirty, send to wb stage
                 If it is clean, send to allocate stage   
        */
        s_hit: begin
            // set data_write
            // set wmask_data
                data_write[ufp_addr_reg[4:0]*8 +: 32]  = ufp_wdata_reg;
                wmask_data[ufp_addr_reg[4:0]+:4]       = ufp_wmask_reg;
            // check for hits tag match and valid
            if (valid_ro[0] == '1 && ufp_addr_reg[31:9] == tag_ro[0]) begin
                    // Hit, update plru for most recently accessed
                    ufp_rdata = data_ro[0][ufp_addr_reg[4:0]*8+:32];

                    lru_write    = {1'b1, lru_ro[1] ,1'b1};
                    web_lru      = '0;

                    // send out ufp resp
                    ufp_resp    = '1;

                    // make s_idle next state
                    state_next  = s_idle;
                    
                    
                    if(|ufp_wmask_reg) begin
                        // commit to writing to the cache by setting specific way csb_data to low and web to low
                        web[0]      = '0;
                    end
                end
                else if (valid_ro[1] == '1 && ufp_addr_reg[31:9] == tag_ro[1]) begin
                    ufp_rdata = data_ro[1][ufp_addr_reg[4:0]*8+:32];
                    //hit, update plru for most recently accessed
                    lru_write  = {1'b0, lru_ro[1] ,1'b1};
                    web_lru     = '0;

                    // send out ufp resp
                    ufp_resp    = '1;

                    // make idle the next state
                    state_next  = s_idle;

                    
                    if(|ufp_wmask_reg) begin
                        // commit to writing to the cache by setting specific way csb_data to low and web to low
                        web[1]    = '0;
                    end
                end
                else if (valid_ro[2] == '1 && ufp_addr_reg[31:9] == tag_ro[2]) begin
                    ufp_rdata = data_ro[2][ufp_addr_reg[4:0]*8+:32];
                    //Hit, update plru for most recently accessed
                    lru_write  = {lru_ro[2], 1'b1 ,1'b0};
                    web_lru    = '0;

                    // send out ufp response
                    ufp_resp    = '1;

                    // set state next to idle
                    state_next  = s_idle;

                    
                    if(|ufp_wmask_reg) begin
                        // commit to writing to the cache by setting specific way csb_data to low and web to low
                        web[2]    = '0;
                    end
                end
                else if (valid_ro[3] == '1 && ufp_addr_reg[31:9] == tag_ro[3]) begin
                    ufp_rdata = data_ro[3][ufp_addr_reg[4:0]*8+:32];

                    //hit, update plru for most recently accessed
                    lru_write  = {lru_ro[2], 1'b0 ,1'b0};
                    web_lru     = '0;

                    // send out ufp resp
                    ufp_resp    = '1;

                    // set state to idle
                    state_next  = s_idle;
                    
                    if(|ufp_wmask_reg) begin
                        // commit to writing to the cache by setting specific way csb_data to low and web to low
                        web[3]    = '0;
                    end
                end
                else begin
                    // Miss, if least recently accessed cache block is dirty go to writeback, else allocate
                    if (dirty_ro[lru_decode]) state_next = s_wb;
                    else  state_next = s_alloc;
                end

        end
        /* Overview: 
            1. set dfp_write high
            2. set dfp_wdata w/cache line that is plru

            3. On dfp _resp
                set state to allocate

            else:
                wait for wb
        */
        s_wb: begin
            dfp_write = '1;
            dfp_wdata = data_ro[lru_decode];
            // evicted tag
            dfp_addr  = {tag_ro[lru_decode], ufp_addr_reg[8:5], 5'b0};

            if(dfp_resp) begin
                state_next = s_alloc;
            end
        end

        /* Overview: 
            1. set dfp_read high
            2. On dfp _resp
                take data in dfp_rdata & replace the plru cache line
                send to the idle state

            else:
                wait for allocate
        */
        s_alloc: begin
            dfp_read = '1;
            dfp_addr = {ufp_addr_reg[31:5], 5'b0};
            if(dfp_resp) begin
                state_next = s_idle;

                // write to cache block, valid, not dirty, tag (hit will update lru)
                web[lru_decode]     = '0;
                data_write          = dfp_rdata;
                wmask_data          = '1;

                // clear dirty
                dirty_write         = '0;
            end
        end
        default: state_next = s_idle;
    endcase


    end

endmodule


