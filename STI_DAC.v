module STI_DAC(
    input            clk, reset,  // active high asynchronous
    input            load, pi_msb, pi_low, pi_end,
    input  [15:0]    pi_data,
    input  [1:0]     pi_length,
    input            pi_fill,

    output           so_data, so_valid, 
    output           oem_finish,
    output [7:0]     oem_dataout,
    output [4:0]     oem_addr,
    output           odd1_wr, odd2_wr, odd3_wr, odd4_wr, 
    output           even1_wr, even2_wr, even3_wr, even4_wr
);

STI u_sti(
    .clk(clk), 
    .reset(reset),
    .load(load), 
    .pi_msb(pi_msb), 
    .pi_low(pi_low), 
    .pi_end(pi_end),
    .pi_data(pi_data),
    .pi_length(pi_length),
    .pi_fill(pi_fill),
    .so_data(so_data), 
    .so_valid(so_valid)
);

DAC u_dac(
    .clk(clk), 
    .reset(reset),
    .so_data(so_data), 
    .so_valid(so_valid),
    .pi_end(pi_end),
    .oem_finish(oem_finish),
    .oem_dataout(oem_dataout),
    .oem_addr(oem_addr),
    .odd1_wr(odd1_wr), 
    .odd2_wr(odd2_wr), 
    .odd3_wr(odd3_wr), 
    .odd4_wr(odd4_wr), 
    .even1_wr(even1_wr), 
    .even2_wr(even2_wr), 
    .even3_wr(even3_wr), 
    .even4_wr(even4_wr)
);

endmodule