`timescale 1ns / 1ps

module tb_pe();
    import pkg_PE::*;

    // Inputs
    logic S_Ovd;
    logic [Line_Selection_Width-1:0] Line_Selection_Control;
    logic signed [K-1:0] B_Psum;
    logic [1:0] Wr_Rr;
    logic signed [K-1:0] W;
    logic [2*Z_Bit_Width:0] R6_r_Delta;
    logic signed [K-1:0] Ix [0:M-1];
    logic MAC_MAX;
    logic rst;
    logic clk;

    // Outputs
    wire signed [K-1:0] Psum;
    wire Stride_Request;

    int error_count = 0;

    // Instantiate the PE
    PE uut (.*);

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns period
    end

    // Helper Task to wait exactly for the pipeline to align
    task wait_for_pipeline();
        wait(Stride_Request); // Wait for the trigger
        @(posedge clk);       // input_reg loads new Ix (10). Memory is outputting 20.
        @(posedge clk);       // Memory rolls over to Address 0 and outputs 5.
        @(posedge clk);       // MAC grabs the 5 and multiplies (5 * 10).
        @(posedge clk);       // multiplier_out_reg stores 50. (Psum shows 202 here!)
        @(posedge clk);       // Psum correctly updates to 52!
        #1;                   // Wait 1ns to read the clean signal
    endtask

    initial begin
        $dumpfile("pe_waveform.vcd");
        $dumpvars(0, tb_pe);
        
        // --------------------------------------------------------
        // INITIALIZATION
        // --------------------------------------------------------
        rst = 1;
        S_Ovd = 1; // 1 = SZD OFF (allowing normal math)
        Line_Selection_Control = 0;
        B_Psum = 0;
        Wr_Rr = 2'b00; 
        W = 0;
        R6_r_Delta = 0; 
        MAC_MAX = 1; 
        for (int i = 0; i < M; i++) Ix[i] = 0;

        #20 rst = 0;
        $display("\n==================================================");
        $display("   STARTING PE CYCLE-ACCURATE TESTBENCH");
        $display("==================================================\n");

        // --------------------------------------------------------
        // TEST 1: Load Weights (Shifted for Fixed Point)
        // --------------------------------------------------------
        R6_r_Delta = {1'b0, 4'd0, 4'd4}; 
        Wr_Rr = 2'b11; 
        
        @(posedge clk) W = 16'd5 << 8;  
        @(posedge clk) W = 16'd10 << 8; 
        @(posedge clk) W = 16'd15 << 8; 
        @(posedge clk) W = 16'd20 << 8; 
        @(posedge clk) Wr_Rr = 2'b00; 
        #20;

        // --------------------------------------------------------
        // TEST 2: MAC Operation
        // --------------------------------------------------------
        Wr_Rr = 2'b01; 
        Line_Selection_Control = 0; 
        Ix[0] = 16'd10 << 8; // Input = 10 
        B_Psum = 16'd2;      // Bias = 2
        MAC_MAX = 1; 
        S_Ovd = 1;           // SZD OFF
        
        wait_for_pipeline(); // Use our new cycle-accurate task!
        
        if (Psum === 16'd52) begin
            $display("  [PASS] TEST 2 (MAC): Expected 52, Got %0d", Psum);
        end else begin
            $display("  [FAIL] TEST 2 (MAC): Expected 52, Got %0d", Psum);
            error_count++;
        end

        // --------------------------------------------------------
        // TEST 3: SZD Power Gating 
        // --------------------------------------------------------
        S_Ovd = 0;               // SZD ON! (Block negatives to save power)
        Ix[0] = -(16'd10 << 8);  // Negative input
        
        wait_for_pipeline();
        
        if (Psum === 16'd2) begin
            $display("  [PASS] TEST 3 (SZD): Expected 2, Got %0d", Psum);
        end else begin
            $display("  [FAIL] TEST 3 (SZD): Expected 2, Got %0d", Psum);
            error_count++;
        end

        // --------------------------------------------------------
        // TEST 4: Max Pooling
        // --------------------------------------------------------
        MAC_MAX = 0;         // Switch to MAX mode
        Ix[0] = 16'd25; 
        B_Psum = 16'd50; 
        S_Ovd = 1;           // SZD OFF
        
        wait_for_pipeline();
        
        if (Psum === 16'd50) begin
            $display("  [PASS] TEST 4 (MAX): Expected 50, Got %0d", Psum);
        end else begin
            $display("  [FAIL] TEST 4 (MAX): Expected 50, Got %0d", Psum);
            error_count++;
        end

        // --------------------------------------------------------
        // FINAL SUMMARY
        // --------------------------------------------------------
        $display("\n==================================================");
        if (error_count == 0) begin
            $display("  [SUCCESS] ALL PE TESTS PASSED! Ready for Sign-off.");
        end else begin
            $display("  [ERROR] SIMULATION FAILED WITH %0d ERRORS.", error_count);
        end
        $display("==================================================\n");

        $finish;
    end
endmodule