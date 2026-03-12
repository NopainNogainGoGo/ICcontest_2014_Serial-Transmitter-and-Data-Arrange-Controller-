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

    reg [7:0] cnt_mem;
    reg [1:0] state, next_state;
    reg [4:0] idle_cnt;
    reg       wr_en;    // 真正的記憶體寫入脈衝

    // cs
    always @(posedge clk or posedge reset) begin
        if (reset) state <= S_IDLE;
        else       state <= next_state;
    end

    //ns
    always @(*) begin
        case(state)
            S_IDLE: next_state = so_valid ? S_WORK : (pi_end ? S_WAIT : S_IDLE);
            S_WORK: next_state = (cnt_mem == 8'hFF && wr_en) ? S_IDLE : 
                                 (pi_end && !so_valid)       ? S_WAIT : S_WORK;
            S_WAIT: next_state = so_valid ? S_WORK : (idle_cnt == 5'd31 ? S_PAD : S_WAIT);
            S_PAD:  next_state = (cnt_mem == 8'hFF && wr_en) ? S_IDLE : S_PAD;
            default:next_state = S_IDLE;
        endcase
    end

    // 閒置計數器：只在 S_WAIT 狀態下計數
    always @(posedge clk or posedge reset) begin
        if (reset)               idle_cnt <= 5'd0;
        else if (state != S_WAIT)idle_cnt <= 5'd0;
        else                     idle_cnt <= idle_cnt + 5'd1;
    end


    reg [6:0] shift_reg;
    reg [2:0] bit_cnt;
    reg       pad_tick; // 補零時的減速器

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            shift_reg <= 7'd0;
            bit_cnt   <= 3'd0;
            pad_tick  <= 1'b0;
        end else begin
            if (so_valid) begin
                shift_reg <= {shift_reg[5:0], so_data};
                bit_cnt   <= bit_cnt + 3'd1;
            end
            if (state == S_PAD) pad_tick <= ~pad_tick;
            else                pad_tick <= 1'b0;
        end
    end

    // =========================================================================
    // 3. 核心管線化設計 (Dataout 與 Write Enable 的精準對齊)
    // =========================================================================
    // data_prep: 資料湊齊 8 bits 的瞬間，或是補零時的觸發瞬間
    wire data_prep = (so_valid && bit_cnt == 3'd7) || (state == S_PAD && !pad_tick);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            oem_dataout <= 8'd0;
            wr_en       <= 1'b0;
        end else begin
            // 當資料準備好時，更新 oem_dataout
            if (data_prep) oem_dataout <= (state == S_PAD) ? 8'h00 : {shift_reg, so_data};
            // 將 data_prep 延遲一拍變成 wr_en，創造完美的 Setup Time！
            wr_en <= data_prep;
        end
    end

    // =========================================================================
    // 4. 極簡化記憶體定址與分配 (Memory Decoding)
    // =========================================================================
    always @(posedge clk or posedge reset) begin
        if (reset)    cnt_mem <= 8'd0;
        else if(wr_en)cnt_mem <= cnt_mem + 8'd1;
    end

    assign oem_addr = cnt_mem[5:1];

    // ✨ 業界精華：利用 One-Hot 解碼取代又臭又長的 Case 敘述
    wire       is_odd = (cnt_mem[3] == cnt_mem[0]);    // Checkerboard 交錯演算法
    wire [3:0] bank   = 4'b0001 << cnt_mem[7:6];       // 將 00, 01, 10, 11 轉為 0001, 0010, 0100, 1000

    always @(*) begin
        // 預設全部拉低
        {odd4_wr, odd3_wr, odd2_wr, odd1_wr}   = 4'b0000;
        {even4_wr, even3_wr, even2_wr, even1_wr} = 4'b0000;
        
        // 透過陣列拼接直接給值，硬體會合成為非常小顆的 Decoder 邏輯閘
        if (wr_en) begin
            if (is_odd) {odd4_wr, odd3_wr, odd2_wr, odd1_wr}   = bank;
            else        {even4_wr, even3_wr, even2_wr, even1_wr} = bank;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) oem_finish <= 1'b0;
        else       oem_finish <= (cnt_mem == 8'hFF && wr_en); // 最後一筆寫完當下發出
    end

endmodule
