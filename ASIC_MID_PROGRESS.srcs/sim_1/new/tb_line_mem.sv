`timescale 1ns/1ps

package pkg_tb;

    parameter A = 128;
    parameter A_Bit_Width = 7;

    parameter N = 6;
    parameter N_Bit_Width = 3;

    parameter K = 16;

endpackage


module tb_line_memory;

import pkg_tb::*;

//--------------------------------------------------
// Signals
//--------------------------------------------------

logic signed [K-1:0] I;
logic clk;
logic Write_Selector;
logic Read_Selector;

logic [A_Bit_Width-1:0] RA_n, RA_r;

logic Next_Stride;
logic Reuse_Selector;
logic [A_Bit_Width+N_Bit_Width-1:0] r_ns;

logic rst;

logic signed [K-1:0] O[0:N-1];


//--------------------------------------------------
// DUT
//--------------------------------------------------

Line_Memory dut(
    .I(I),
    .clk(clk),
    .Write_Selector(Write_Selector),
    .Read_Selector(Read_Selector),

    .RA_n(RA_n),
    .RA_r(RA_r),

    .Next_Stride(Next_Stride),
    .Reuse_Selector(Reuse_Selector),
    .r_ns(r_ns),
    .rst(rst),

    .O(O)
);


//--------------------------------------------------
// Clock generation
//--------------------------------------------------

initial begin
    clk = 0;
    forever #5 clk = ~clk;
end


//--------------------------------------------------
// Test sequence
//--------------------------------------------------

initial begin

    //----------------------------------
    // Initialize
    //----------------------------------

    rst = 1;
    Write_Selector = 0;
    Read_Selector  = 0;
    Next_Stride    = 0;
    Reuse_Selector = 0;

    RA_n = 0;
    RA_r = 0;

    r_ns = 0;

    I = 0;

    repeat(4) @(posedge clk);

    rst = 0;

    //----------------------------------
    // Write first row
    //----------------------------------

    Write_Selector = 1;

    for(int i=0;i<20;i++) begin
        @(posedge clk);
        I = i + 1;
    end

    @(posedge clk);
    Write_Selector = 0;

    //----------------------------------
    // Enable read
    //----------------------------------

    Read_Selector = 1;

    // r = 0, ns = 1
    r_ns = {7'd0,3'd1};

    //----------------------------------
    // Start sliding window
    //----------------------------------

    @(posedge clk);
    Next_Stride = 1;

   

    //----------------------------------
    // Let it run
    //----------------------------------

    repeat(6) @(posedge clk);
    RA_n = 1;
    repeat(6) @(posedge clk);
    RA_n = 2;
    repeat(6) @(posedge clk);
    $finish;

end


//--------------------------------------------------
// Monitor outputs
//--------------------------------------------------

always @(posedge clk) begin

    $display("t=%0t | WA=%0d RA=%0d AddrDec=%0d | O = %0d %0d %0d %0d %0d %0d",
        $time,
        dut.WA,
        dut.RA,
        dut.Address_Decoder_In,
        O[0],O[1],O[2],O[3],O[4],O[5]);

end


endmodule