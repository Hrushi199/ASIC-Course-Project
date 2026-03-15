`timescale 1ns / 1ps

/* TB_METRICS - Throughput, Latency and TOPS measurement
   Paper Section III-A.6: ?T = 2 × NPE × fclk × ? × ?
   Set Vivado sim runtime to 50000ns before running.
*/
module tb_metrics;
    import pkg_IEC::*;

    logic                  clk, rst;
    logic                  start;
    logic                  layer_config_valid;
    logic                  layer_config_ack;
    logic [L_WIDTH-1:0]    FClast;
    logic [N_WIDTH-1:0]    N_classes;
    logic [COMP_WIDTH-1:0] layer_comp_type;
    logic [NL_WIDTH-1:0]   nl, rl;
    logic [L_WIDTH-1:0]    layer_num;
    logic                  done_interrupt;
    logic [N_WIDTH-1:0]    CN_DC_out;
    logic [2:0]            state_out;

    logic signed [K-1:0]   dram_I_data, dram_W_data, dram_B_data;
    logic                  dram_I_valid, dram_W_valid, dram_B_valid;
    logic                  dram_I_req, dram_W_req, dram_B_req;

    // ---- Counters (single always_ff driver) ----------------------
    int  active_cycles;
    int  total_cycles;
    bit  counting;

    always_ff @(posedge clk) begin
        if (rst) begin
            active_cycles <= 0;
            total_cycles  <= 0;
        end else if (counting) begin
            total_cycles <= total_cycles + 1;
            if (state_out == 3'd3)
                active_cycles <= active_cycles + 1;
        end
    end

    // ---- Metric variables at MODULE level (not inside initial) ---
    longint t_start;
    longint t_done;
    longint latency_ns;
    real    sigma;
    real    tops;
    real    fps;

    // ---- Architecture constants ----------------------------------
    localparam int  NPE        = M * N_PE;
    localparam real CLK_PERIOD = 10.0;
    localparam real CLK_HZ     = 1.0e9 / CLK_PERIOD;
    localparam real OMEGA      = 1.0;

    CNN_Inference_Engine dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    assign dram_I_data  = 16'sd256;
    assign dram_W_data  = 16'sd256;
    assign dram_B_data  = 16'sd0;
    assign dram_I_valid = 1'b1;
    assign dram_W_valid = 1'b1;
    assign dram_B_valid = 1'b1;

    // ---- Layer config task ---------------------------------------
    task automatic set_layer_config(
        input logic [L_WIDTH-1:0]    lnum,
        input logic [COMP_WIDTH-1:0] ctype,
        input logic [NL_WIDTH-1:0]   n_l,
        input logic [NL_WIDTH-1:0]   r_l,
        input logic [L_WIDTH-1:0]    fc_last,
        input logic [N_WIDTH-1:0]    n_cls
    );
        @(posedge clk);
        layer_num          = lnum;
        layer_comp_type    = ctype;
        nl                 = n_l;
        rl                 = r_l;
        FClast             = fc_last;
        N_classes          = n_cls;
        layer_config_valid = 1'b1;
        @(posedge layer_config_ack);
        @(posedge clk);
        layer_config_valid = 1'b0;
    endtask

    // ---- Layer 1 config provider (parallel initial) --------------
    initial begin
        @(negedge rst);
        wait(state_out == 3'd4);
        set_layer_config(L_WIDTH'(1), COMP_FC,
                         NL_WIDTH'(5), NL_WIDTH'(1),
                         L_WIDTH'(1), N_WIDTH'(5));
    end

    // ---- Main stimulus -------------------------------------------
    initial begin
        $dumpfile("inference_engine_waveform.vcd");
        $dumpvars(0, tb_metrics);

        rst                = 1;
        start              = 0;
        layer_config_valid = 0;
        counting           = 0;
        t_start            = 0;
        t_done             = 0;
        latency_ns         = 0;
        sigma              = 0.0;
        tops               = 0.0;
        fps                = 0.0;
        FClast             = L_WIDTH'(1);
        N_classes          = N_WIDTH'(5);
        layer_comp_type    = COMP_CONV;
        nl                 = NL_WIDTH'(16);
        rl                 = NL_WIDTH'(1);
        layer_num          = L_WIDTH'(0);

        repeat(4) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        $display("\n================================================================");
        $display("  CNN INFERENCE ENGINE - PERFORMANCE METRICS");
        $display("  NPE=%0d  fclk=%0.0f MHz  Q8.8  2-layer test",
                 NPE, CLK_HZ/1e6);
        $display("================================================================\n");

        // Start inference and begin measuring
        t_start  = $time;
        counting = 1;
        start    = 1'b1;

        set_layer_config(L_WIDTH'(0), COMP_CONV,
                         NL_WIDTH'(16), NL_WIDTH'(1),
                         L_WIDTH'(1), N_WIDTH'(5));

        // Wait for inference complete
        wait(done_interrupt);
        t_done   = $time;
        counting = 0;

        @(posedge clk); #1;

        // ---- Compute and display metrics -------------------------
        latency_ns = t_done - t_start;
        sigma = (total_cycles > 0) ?
                real'(active_cycles) / real'(total_cycles) : 0.0;
        tops  = (2.0 * real'(NPE) * CLK_HZ * OMEGA * sigma) / 1.0e12;
        fps   = (latency_ns > 0) ? 1.0e9 / real'(latency_ns) : 0.0;

        $display("================================================================");
        $display("  RESULTS");
        $display("================================================================");
        $display("  Detected class          : %0d", CN_DC_out);
        $display("  Inference correct       : %s",
                 (CN_DC_out == N_WIDTH'(4)) ? "YES [PASS]" : "NO [FAIL]");
        $display("  ----------------------------------------------------------------");
        $display("  --- Latency ---");
        $display("  Total latency           : %0d ns", latency_ns);
        $display("  Total cycles            : %0d  @ 100 MHz", total_cycles);
        $display("  ----------------------------------------------------------------");
        $display("  --- Throughput ---");
        $display("  Frame rate (sim)        : %0.2f fps", fps);
        $display("  ----------------------------------------------------------------");
        $display("  --- TOPS  (2 x NPE x fclk x Omega x sigma) ---");
        $display("  NPE  (M x N)            : %0d", NPE);
        $display("  fclk                    : %0.0f MHz", CLK_HZ/1e6);
        $display("  Omega (PE efficiency)   : %0.2f", OMEGA);
        $display("  Active COMPUTE cycles   : %0d / %0d",
                 active_cycles, total_cycles);
        $display("  sigma (time efficiency) : %0.4f  (%0.1f%%)",
                 sigma, sigma * 100.0);
        $display("  Theta_T @ 100MHz 54PE   : %0.6f TOPS", tops);
        $display("  ----------------------------------------------------------------");
        $display("  --- Scaled to paper ASIC ---");
        $display("  Theta_T @ 1.25GHz 54PE  : %0.4f TOPS",
                 2.0 * real'(NPE) * 1.25e9 * OMEGA * sigma / 1.0e12);
        $display("  Theta_T @ 3.85GHz 864PE : %0.4f TOPS  (paper: 6.65 TOPS)",
                 2.0 * 864.0 * 3.85e9 * 1.0 * 1.0 / 1.0e12);
        $display("================================================================\n");

        start = 0;
        #100 $finish;
    end

    // ---- Waveform event markers ----------------------------------
    always @(posedge done_interrupt)
        $display("  [MARKER] done_interrupt  t=%0t ps", $time);
    always @(posedge dut.kpu_inst.load_done)
        $display("  [MARKER] KPU load_done   t=%0t ps", $time);
    always @(posedge dut.cu_inst.result_valid)
        $display("  [MARKER] CU result_valid t=%0t ps", $time);

    // ---- Watchdog ------------------------------------------------
    initial begin
        #48000;
        $display("  [TIMEOUT] Increase Vivado runtime to 50000ns");
        $finish;
    end

endmodule