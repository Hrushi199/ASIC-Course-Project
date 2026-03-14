`timescale 1ns / 1ps

module tb_Memory();

    // Parameters
    parameter int DATA_WIDTH = 16;
    parameter int DATA_DEPTH = 64;
    parameter int ADDR_WIDTH = 6;

    // Signals
    logic WE, RE;
    logic [DATA_WIDTH-1:0] Din;
    logic [ADDR_WIDTH-1:0] RA, WA;
    logic clk;
    logic [DATA_WIDTH-1:0] Dout;

    int error_count = 0;

    // Instantiate the DUT
    Memory #(
        .Data_Width(DATA_WIDTH),
        .Data_Depth(DATA_DEPTH),
        .Address_Bit_Width(ADDR_WIDTH)
    ) uut (.*); // Shortened instantiation since names match exactly

    // Clock Generation (100 MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // Main Test Sequence
    initial begin
        $dumpfile("memory_waveform.vcd");
        $dumpvars(0, tb_Memory);

        // 1. Initialization
        WE = 0; 
        RE = 0; 
        Din = 0; 
        RA = 0; 
        WA = 0;
        
        $display("\n==================================================");
        $display("   STARTING MEMORY (SDP RAM) VERIFICATION");
        $display("==================================================\n");

        #25; // Wait a few cycles

        // --------------------------------------------------
        // Phase 1: Write Data to RAM (Race-Free)
        // --------------------------------------------------
        $display("[%0t] PHASE 1: Writing test data to RAM...", $time);
        
        for (int i = 0; i < 5; i++) begin
            @(negedge clk);     // Apply inputs on falling edge!
            WE = 1;
            WA = i;
            Din = i * 10 + 5;   // 5, 15, 25, 35, 45
        end
        
        @(negedge clk);
        WE = 0; // Disable Writing safely
        #20;

        // --------------------------------------------------
        // Phase 2: Read Data and Verify (Race-Free)
        // --------------------------------------------------
        $display("\n[%0t] PHASE 2: Reading and verifying data...", $time);
        
        for (int i = 0; i < 5; i++) begin
            @(negedge clk);     // Provide read address on falling edge
            RE = 1; 
            RA = i;           
            
            @(posedge clk);     // Wait for Memory to trigger on the rising edge
            #1;                 // Wait 1ns for Dout to physically update in simulation
            
            if (Dout === (i * 10 + 5)) begin
                $display("  [PASS] Address %0d -> Expected: %0d, Got: %0d", i, (i*10+5), Dout);
            end else begin
                $display("  [FAIL] Address %0d -> Expected: %0d, Got: %0d", i, (i*10+5), Dout);
                error_count++;
            end
        end
        
        @(negedge clk);
        RE = 0;

        // --------------------------------------------------
        // Final Summary
        // --------------------------------------------------
        $display("\n==================================================");
        if (error_count == 0) begin
            $display("  [SUCCESS] ALL MEMORY TESTS PASSED! RAM is working perfectly.");
        end else begin
            $display("  [ERROR] SIMULATION FAILED WITH %0d ERRORS.", error_count);
        end
        $display("==================================================\n");

        $finish;
    end
endmodule