/*
將 16 位元的並列資料 (Parallel Data)，依照不同的長度與格式設定，轉換為串列資料 (Serial Data) 輸出
*/

module STI(
    input            clk, reset,  // active high asynchronous
    input            load, pi_msb, pi_low, pi_end,
    input  [15:0]    pi_data,
    input  [1:0]     pi_length,
    input            pi_fill,

    output           so_data, so_valid
);

    localparam IDLE   = 3'b000,
               READ   = 3'b001,
               CAL    = 3'b010, 
               OUTPUT = 3'b011,
               FINISH = 3'b100;

    reg [2:0] curr_state, next_state;
    reg [4:0] cnt;  
    reg [15:0] data;
    reg [31:0] data_o;

/*
    優化：
    觀察二進制的規律，7 是 00111，15 是 01111，23 是 10111，31 是 11111
    會發現後三位固定是 111，前兩位剛好就是 pi_length

    直接用 max_bits = {pi_length, 3'b111}; 來組合 ：
    pi_length 為 00 (8-bit) 變成 00111 (十進位 7) 
    pi_length 為 01 (16-bit)變成 01111 (十進位 15) 
    pi_length 為 11 (32-bit)變成 11111 (十進位 31) 
    節省硬體資源 
*/
    wire [4:0] max_bits = {pi_length, 3'b111}; 

    //-----------------------------------------------------------------
    // FSM: Current State
    //-----------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset) curr_state <= IDLE;
        else       curr_state <= next_state;
    end

    //-----------------------------------------------------------------
    // FSM: Next State Logic
    //-----------------------------------------------------------------
    always @(*) begin
        case(curr_state) 
            IDLE:    next_state = load ? READ : IDLE;
            READ:    next_state = CAL;
            CAL:     next_state = OUTPUT;
            OUTPUT:
                if (cnt == max_bits)
                    next_state = pi_end ? FINISH : IDLE;
                else
                    next_state = OUTPUT;
            FINISH:  next_state = FINISH;
            default: next_state = IDLE;
        endcase
    end

    //-----------------------------------------------------------------
    // Counter Logic
    //-----------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset) 
            cnt <= 5'b0;
        else if (curr_state == OUTPUT)
            cnt <= cnt + 5'b1;
        else
            cnt <= 5'b0;
    end

    //-----------------------------------------------------------------
    // Data Register
    //-----------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset) 
            data <= 16'b0;
        else if (curr_state == READ) 
            data <= pi_data;
    end

    //-----------------------------------------------------------------
    // Data Output Formatting (Combinational)
    //-----------------------------------------------------------------
    // 優化：明確定義所有狀態，避免潛在的 MUX 推導錯誤
    always @(*) begin
        case({pi_length, pi_fill})
            // 8-bit
            3'b00_0, 3'b00_1: data_o = pi_low ? {24'b0, data[15:8]} : {24'b0, data[7:0]};
            // 16-bit
            3'b01_0, 3'b01_1: data_o = {16'b0, data};
            // 24-bit
            3'b10_0:          data_o = {16'b0, data};
            3'b10_1:          data_o = {8'b0, data, 8'b0};
            // 32-bit
            3'b11_0:          data_o = {16'b0, data};
            3'b11_1:          data_o = {data, 16'b0};
            
            default:          data_o = 32'b0; 
        endcase
    end

    //-----------------------------------------------------------------
    // Output Assignments
    //-----------------------------------------------------------------
    wire [4:0] bit_idx;
    //bit_idx 會根據 pi_msb 決定是倒著數 (max_bits - cnt) 還是正著數 (cnt) 
    assign bit_idx  = pi_msb ? (max_bits - cnt) : cnt;
    
    assign so_data  = data_o[bit_idx];
    assign so_valid = (curr_state == OUTPUT);

endmodule
