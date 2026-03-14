`timescale 1ns / 1ps

module tb_KPU();
    import pkg_KPU::*;

    // --------------------------------------------------
    // 1. Top-Level Signals (Driven by Testbench)
    // --------------------------------------------------
    logic signed [K-1:0] BIAS_Bus [0:M-1];
    logic signed [K-1:0] Line_Memory_INPUTS_Bus [0:M-1];
    logic signed [K-1:0] WEIGHTS_Bus [0:M-1][0:N-1];
    logic clk;
    logic layer_information;

    // Outputs from the KPU_cluster
    logic signed [K-1:0] adderOutStage1 [2:0];
    logic signed [K-1:0] adderOutStage2;

    int error_count = 0;

    // --------------------------------------------------
    // 2. Interconnect Wires (Wiring KPC to KPU_cluster)
    // --------------------------------------------------
    logic Stride_Request_Bus[0:N-1][0:M-1];
    logic MAC_MAX_Bus[0:M-1][0:N-1];
    logic [M_Bit_Width-1:0] Line_Selection_Control_Bus[0:M-1][0:N-1]; 
    logic S_Ovd_Bus[0:M-1][0:N-1];
    logic [1:0] Wr_Rr_Bus[0:M-1][0:N-1];
    logic [2*Z_Bit_Width:0] R6_r_Delta_Bus[0:M-1][0:N-1];
    
    logic Read_Selector_Bus[0:M-1];
    logic Write_Selector_Bus[0:M-1];
    logic Reuse_Selector_Bus[0:M-1];
    logic [A_Bit_Width-1:0] RA_n_Bus[0:M-1];
    logic [A_Bit_Width-1:0] RA_r_Bus[0:M-1];
    logic Next_Stride_Bus[0:M-1];
    logic [A_Bit_Width+N_Bit_Width-1:0] r_ns_Bus[0:M-1];

    // --------------------------------------------------
    // 3. Instantiate the Controller (KPC)
    // --------------------------------------------------
    KPC controller (
        .Stride_Request_Bus(Stride_Request_Bus),
        .S_Ovd_Bus(S_Ovd_Bus),
        .MAC_MAX_Bus(MAC_MAX_Bus),
        .Line_Selection_Control_Bus(Line_Selection_Control_Bus),    
        .Wr_Rr_Bus(Wr_Rr_Bus),
        .R6_r_Delta_Bus(R6_r_Delta_Bus),
        .Read_Selector_Bus(Read_Selector_Bus),
        .Write_Selector_Bus(Write_Selector_Bus),
        .Reuse_Selector_Bus(Reuse_Selector_Bus),
        .RA_n_Bus(RA_n_Bus),
        .RA_r_Bus(RA_r_Bus),
        .Next_Stride_Bus(Next_Stride_Bus),
        .r_ns_Bus(r_ns_Bus),
        .clk(clk),
        .layer_information(layer_information) // Need to make sure your FSM has this input
    );

    // --------------------------------------------------
    // 4. Instantiate the Datapath (KPU_cluster)
    // --------------------------------------------------
    KPU_cluster datapath (
        .BIAS_Bus(BIAS_Bus),
        .Line_Memory_INPUTS_Bus(Line_Memory_INPUTS_Bus),
        .WEIGHTS_Bus(WEIGHTS_Bus),
        .clk(clk),
        .Stride_Request_Bus(Stride_Request_Bus),
        .MAC_MAX_Bus(MAC_MAX_Bus),
        .Line_Selection_Control_Bus(Line_Selection_Control_Bus),
        .S_Ovd_Bus(S_Ovd_Bus),
        .Wr_Rr_Bus(Wr_Rr_Bus),
        .R6_r_Delta_Bus(R6_r_Delta_Bus),
        .adderOutStage1(adderOutStage1),
        .adderOutStage2(adderOutStage2),
        .Read_Selector_Bus(Read_Selector_Bus),
        .Write_Selector_Bus(Write_Selector_Bus),
        .Reuse_Selector_Bus(Reuse_Selector_Bus),
        .RA_n_Bus(RA_n_Bus),
        .RA_r_Bus(RA_r_Bus),
        .Next_Stride_Bus(Next_Stride_Bus),
        .r_ns_Bus(r_ns_Bus)
    );

    // --------------------------------------------------
    // 5. Clock Generation (100 MHz)
    // --------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // --------------------------------------------------
    // 6. Test Sequence
    // --------------------------------------------------
    initial begin
        // Setup Waveforms
        $dumpfile("kpu_cluster_waveform.vcd");
        $dumpvars(0, tb_KPU);

        $display("\n==================================================");
        $display("   STARTING KPU CLUSTER & KPC VERIFICATION");
        $display("   Array: %0d x %0d | Weights Depth: %0d", M, N, Z);
        $display("==================================================\n");

        // --------------------------------------------------
        // Phase 1: Initialize 
        // --------------------------------------------------
        layer_information = 1; // Bypass SZD for Layer 1
        
        for (int m = 0; m < M; m++) begin
            BIAS_Bus[m] = 16'd1;           
            Line_Memory_INPUTS_Bus[m] = 0; 
            for (int n = 0; n < N; n++) begin
                // Give every PE a weight of 2 (using Q8.8 format: 2 << 8 = 512)
                WEIGHTS_Bus[m][n] = 16'd2 << 8; 
            end
        end

        @(negedge clk);
        @(negedge clk);
        $display("[%0t] FSM State: LOAD_WEIGHTS (Filling PE local memories...)", $time);

        // --------------------------------------------------
        // Phase 2: Wait for Weights to Load
        // --------------------------------------------------
        repeat(Z) @(negedge clk); // Waits for depth Z
        
        $display("[%0t] FSM State: LOAD_FEAT (Streaming Input Image...)", $time);

        // --------------------------------------------------
        // Phase 3: Stream Input Features
        // --------------------------------------------------
        for (int i = 0; i < N + 2; i++) begin
            @(negedge clk);
            for (int m = 0; m < M; m++) begin
                Line_Memory_INPUTS_Bus[m] = (i + 1) << 8; 
            end
        end

        $display("[%0t] FSM State: COMPUTE (Firing Pipeline...)", $time);

        // --------------------------------------------------
        // Phase 4: Wait for Pipeline to Flush
        // --------------------------------------------------
        repeat(Z + N + 20) @(negedge clk);

        // --------------------------------------------------
        // Phase 5: Verification
        // --------------------------------------------------
        $display("\n--- Output Verification at %0t ---", $time);
        
        // We now probe the new adderOutStage2 port from your cluster!
        $display("  Final Cluster Output (adderOutStage2): %0d", adderOutStage2);

        if (adderOutStage2 === 16'hx || adderOutStage2 === 16'hz) begin
            $display("  [FAIL] Output is unknown ('X'). Check interconnects or FSM.");
            error_count++;
        end else if (adderOutStage2 == 16'd0) begin
            $display("  [FAIL] Output is 0. Math is not accumulating.");
            error_count++;
        end else begin
            $display("  [PASS] Valid data successfully propagated through the Adder Tree!");
        end

        // --------------------------------------------------
        // Final Summary
        // --------------------------------------------------
        $display("\n==================================================");
        if (error_count == 0) begin
            $display("  [SUCCESS] CLUSTER AND CONTROLLER FULLY INTEGRATED!");
        end else begin
            $display("  [ERROR] Check waveform for pipeline breaks.");
        end
        $display("==================================================\n");

        $finish;
    end
endmodule