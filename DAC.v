module DAC(
    input            clk, reset,  
    input            so_data, so_valid,
    input            pi_end,      

    output reg       oem_finish,
    output reg [7:0] oem_dataout,
    output [4:0]     oem_addr,
    output reg       odd1_wr, odd2_wr, odd3_wr, odd4_wr, 
    output reg       even1_wr, even2_wr, even3_wr, even4_wr
);

    localparam  S_IDLE = 2'd0, 
                S_WORK = 2'd1, 
                S_WAIT = 2'd2, 
                S_PAD  = 2'd3;

    reg [1:0] state, next_state;
    
    reg [7:0] buffer;
    reg [2:0] bit_cnt;
    reg       wr_en;    
    reg [7:0] cnt_mem;
    reg [1:0] idle_cnt;
    
    // cs
    always @(posedge clk or posedge reset) begin
        if (reset) state <= S_IDLE;
        else       state <= next_state;
    end

    //ns
    always @(*) begin
        // 預設保持當前狀態 (防止 Latch，省去大量 else 敘述)
        next_state = state;
        case(state)
            S_IDLE: begin
                if (so_valid)    
                    next_state = S_WORK;
                else if (pi_end) 
                    next_state = S_WAIT;
            end
            
            S_WORK: begin
                if (cnt_mem == 8'hFF && wr_en) 
                    next_state = S_IDLE;
                else if (pi_end && !so_valid)  
                    next_state = S_WAIT;
            end
            
            S_WAIT: begin
                if (so_valid)                  
                    next_state = S_WORK;
                else if (idle_cnt == 2'd3)     
                    next_state = S_PAD;
            end
            
            S_PAD: begin
                if (cnt_mem == 8'hFF && wr_en) 
                    next_state = S_IDLE;
            end
            
            default: next_state = S_IDLE;
        endcase
    end

    // 閒置計數器：只在 S_WAIT 狀態下計數
    always @(posedge clk or posedge reset) begin
        if (reset)               idle_cnt <= 2'd0;
        else if (state != S_WAIT)idle_cnt <= 2'd0;
        else                     idle_cnt <= idle_cnt + 2'd1;
    end

    // 補零用的時鐘生成 (每兩個 clock 觸發一次)
    reg pad_tick;
    always @(posedge clk or posedge reset) begin
        if (reset) pad_tick <= 1'b0;
        else if (state == S_PAD) pad_tick <= ~pad_tick; 
        else pad_tick <= 1'b0;
    end

    // 移位暫存器 (buffer)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            buffer <= 8'd0;
        end else if (so_valid) begin
            buffer <= {buffer[6:0], so_data};
        end
    end

    // 計算目前收到了第幾個 bit
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            bit_cnt <= 3'd0;
        end else if (so_valid) begin
            // 3-bit 計數器加到 7 (3'b111) 後再 +1 會自動歸零，因此直接寫 +1 
            bit_cnt <= bit_cnt + 3'd1; 
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            wr_en <= 1'b0;
        end else if (so_valid && bit_cnt == 3'd7) begin
            wr_en <= 1'b1;  // 情況 A：真實資料湊滿 8 bits，觸發寫入
        end else if (state == S_PAD && pad_tick == 1'b1) begin
            wr_en <= 1'b1;  // 情況 B：補零模式且時脈到位，觸發寫入
        end else begin
            wr_en <= 1'b0;  // 預設不寫入 (取代你原本寫在最上面的 wr_en <= 1'b0)
        end
    end

    // 資料輸出 (oem_dataout)
    // 決定當下要輸出給記憶體的 8-bit 資料內容是什麼
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            oem_dataout <= 8'd0;
        end else if (so_valid && bit_cnt == 3'd7) begin
            oem_dataout <= {buffer[6:0], so_data}; 
        end else if (state == S_PAD && pad_tick == 1'b1) begin
            oem_dataout <= 8'h00;                  
        end
    end

    // 記憶體計數器：每次成功寫入一筆，就 +1
    always @(posedge clk or posedge reset) begin
        if (reset)     cnt_mem <= 8'd0;
        else if(wr_en) cnt_mem <= cnt_mem + 8'd1; 
    end

    // 擷取計數器的 [5:1] 作為共用實體位址
    assign oem_addr = cnt_mem[5:1];

    // 利用計數器高兩位來決定要寫入哪一個 Bank (區塊)
    wire [1:0] bank_select = cnt_mem[7:6]; 

    // 利用位元特性判斷要寫入 Odd 還是 Even
    wire is_odd = (cnt_mem[3] == cnt_mem[0]); // Checkerboard 交錯演算法

    always @(*) begin
        {odd4_wr, odd3_wr, odd2_wr, odd1_wr}     = 4'b0000;
        {even4_wr, even3_wr, even2_wr, even1_wr} = 4'b0000;
        
        if (wr_en) begin
            case (bank_select)
                2'b00: if (is_odd) odd1_wr = 1'b1; else even1_wr = 1'b1;
                2'b01: if (is_odd) odd2_wr = 1'b1; else even2_wr = 1'b1;
                2'b10: if (is_odd) odd3_wr = 1'b1; else even3_wr = 1'b1;
                2'b11: if (is_odd) odd4_wr = 1'b1; else even4_wr = 1'b1;
            endcase
        end
    end
/*  
    wire [3:0] bank   = 4'b0001 << cnt_mem[7:6];       // 將 00, 01, 10, 11 轉為 0001, 0010, 0100, 1000

    always @(*) begin
        // 預設全部拉低
        {odd4_wr, odd3_wr, odd2_wr, odd1_wr}   = 4'b0000;
        {even4_wr, even3_wr, even2_wr, even1_wr} = 4'b0000;
        
        // 透過陣列拼接直接給值，硬體會合成為非常小的 Decoder 
        if (wr_en) begin
            if (is_odd) {odd4_wr, odd3_wr, odd2_wr, odd1_wr}   = bank;
            else        {even4_wr, even3_wr, even2_wr, even1_wr} = bank;
        end
    end
*/

    always @(posedge clk or posedge reset) begin
        if (reset) oem_finish <= 1'b0;
        // 當寫到第 255 筆 (8'hFF) 
        else       oem_finish <= (cnt_mem == 8'hFF && wr_en);  // 最後一筆寫完當下發出
    end
endmodule
