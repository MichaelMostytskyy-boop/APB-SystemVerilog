/* Michael Mostytskyy
 Project: FSM-Based AMBA APB Master & Slave Interface
 Description: 
   Testbench to verify the APB Master and Slave interaction.
   Includes directed tests, random tests, error injection tests,
   a bus-level scoreboard and (with +define+APB_ASSERT) functional
   coverage and SVA.
*/

`timescale 1ns / 1ps

module tb_apb_system;

    // Parameters
    parameter CLK_PERIOD = 10;
    parameter TIMEOUT_CYCLES = 100;
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    parameter NUM_REGS_TEST = 8; 
    parameter NUM_RANDOM = 200;

    int errors = 0;
    int tests_run = 0;

    // Signals
    logic                    PCLK;
    logic                    PRESETn;
    logic [1:0]              mux;
    logic [DATA_WIDTH-1:0]   wdata_in;
    logic [ADDR_WIDTH-1:0]   addr_in;
    logic                    master_err; 

    // APB Bus Signals
    logic [ADDR_WIDTH-1:0]   PADDR;
    logic                    PSEL;
    logic                    PENABLE;
    logic                    PWRITE;
    logic [DATA_WIDTH-1:0]   PWDATA;
    logic [DATA_WIDTH-1:0]   PRDATA;
    logic                    PREADY;
    logic                    PSLVERR;

    // Clock Generation
    initial begin
        PCLK = 0;
        forever #(CLK_PERIOD/2) PCLK = ~PCLK;
    end

    // DUT Instantiation: Master
    apb_master #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_master (
        .PCLK           (PCLK),
        .PRESETn        (PRESETn),
        .mux            (mux),
        .wdata_in       (wdata_in),
        .addr_in        (addr_in),
        .master_err_out (master_err), 
        .PADDR          (PADDR),
        .PSEL           (PSEL),
        .PENABLE        (PENABLE),
        .PWRITE         (PWRITE),
        .PWDATA         (PWDATA),
        .PRDATA         (PRDATA),
        .PREADY         (PREADY),
        .PSLVERR        (PSLVERR)
    );

    // DUT Instantiation: Slave
    apb_slave_simple #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_REGS  (NUM_REGS_TEST) 
    ) u_slave (
        .PCLK     (PCLK),
        .PRESETn  (PRESETn),
        .PADDR    (PADDR),
        .PSEL     (PSEL),
        .PENABLE  (PENABLE),
        .PWRITE   (PWRITE),
        .PWDATA   (PWDATA),
        .PRDATA   (PRDATA),
        .PREADY   (PREADY),
        .PSLVERR  (PSLVERR)
    );

`ifdef APB_ASSERT
    // ================= Functional Coverage =================
    covergroup apb_cg with function sample(bit wr, bit oob, int waits, bit err, int ridx);
        cp_dir:  coverpoint wr  { bins read = {0}; bins write = {1}; }
        cp_oob:  coverpoint oob { bins in_range = {0}; bins out_of_range = {1}; }
        cp_wait: coverpoint waits {
            bins zero_wait = {0};
            bins one_wait  = {1};
            bins few_waits = {[2:3]};
            bins many_wait = {[4:$]};
        }
        cp_err:  coverpoint err;
        cp_reg:  coverpoint ridx { bins regs[] = {[0:NUM_REGS_TEST-1]}; }
        x_dir_oob:  cross cp_dir, cp_oob;
        x_dir_wait: cross cp_dir, cp_wait;
    endgroup
    apb_cg cg = new();

    // ================= Decode-error assertion =================
    // Out-of-range access must be reported by the master after the handshake
    a_decode_err: assert property (
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && PENABLE && PREADY && ((PADDR >> 2) >= NUM_REGS_TEST)) |=> master_err)
        else $error("[SVA] Out-of-range access did not produce master error");
`endif

    // ================= Scoreboard (reference model + bus monitor) =================
    logic [DATA_WIDTH-1:0] sb_mem [0:NUM_REGS_TEST-1];
    int sb_checks = 0;
    int wait_cnt  = 0;
    int sb_idx;
    bit sb_oob;

    initial begin
        for (int k = 0; k < NUM_REGS_TEST; k++) sb_mem[k] = '0;
    end

    always @(posedge PCLK) begin
        if (!PRESETn) begin
            for (int k = 0; k < NUM_REGS_TEST; k++) sb_mem[k] = '0;
            wait_cnt = 0;
        end else if (PSEL && PENABLE) begin
            if (!PREADY) begin
                wait_cnt++;
            end else begin
                sb_idx = PADDR >> 2;
                sb_oob = (sb_idx >= NUM_REGS_TEST);
                sb_checks++;

                if (PSLVERR !== sb_oob) begin
                    $error("[SB] PSLVERR=%b expected %b @0x%h", PSLVERR, sb_oob, PADDR);
                    errors++;
                end
                if (!sb_oob) begin
                    if (PWRITE) sb_mem[sb_idx] = PWDATA;
                    else if (PRDATA !== sb_mem[sb_idx]) begin
                        $error("[SB] Read mismatch @0x%h exp 0x%h got 0x%h", PADDR, sb_mem[sb_idx], PRDATA);
                        errors++;
                    end
                end else if (!PWRITE && PRDATA !== '0) begin
                    $error("[SB] OOB read should return 0, got 0x%h", PRDATA);
                    errors++;
                end

`ifdef APB_ASSERT
                cg.sample(PWRITE, sb_oob, wait_cnt, PSLVERR, sb_oob ? 0 : sb_idx);
`endif
                wait_cnt = 0;
            end
        end
    end

    // Timeout Logic
    task automatic wait_apb_done();
        int timeout_ctr = 0;
        while (!(PSEL && PENABLE && PREADY)) begin
            @(posedge PCLK);
            timeout_ctr++;
            if (timeout_ctr >= TIMEOUT_CYCLES) begin
                $error("[FATAL] Timeout! Slave did not assert PREADY.");
                $finish;
            end
        end
        @(posedge PCLK); 
    endtask

    // Write Task
    task automatic apb_write(input [ADDR_WIDTH-1:0] address, input [DATA_WIDTH-1:0] data);
        begin
            @(posedge PCLK);
            addr_in  <= address;
            wdata_in <= data;
            mux      <= 2'b11; 
            @(posedge PCLK);
            mux      <= 2'b00;
            wait_apb_done();
        end
    endtask

    // Read Task
    task automatic apb_read(input [ADDR_WIDTH-1:0] address, output [DATA_WIDTH-1:0] data);
        begin
            @(posedge PCLK);
            addr_in <= address;
            mux     <= 2'b01; 
            @(posedge PCLK);
            mux     <= 2'b00;
            wait_apb_done();
            data = u_master.rdata_reg; 
        end
    endtask

    // Verification Task (Data comparison)
    task check_result(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] expected, input [DATA_WIDTH-1:0] actual);
        tests_run++;
        if (expected !== actual) begin
            $error("[FAIL] Data Mismatch at 0x%h | Exp: 0x%h | Got: 0x%h", addr, expected, actual);
            errors++;
        end
    endtask

    // Verification Task (Error Status check)
    task check_error_status(input logic expected_err, input string msg);
        tests_run++;
        // Check the latched error register in the master
        if (u_master.error_reg !== expected_err) begin
            $error("[FAIL] %s. Expected Error Status: %b, Got: %b", msg, expected_err, u_master.error_reg);
            errors++;
        end
    endtask


    logic [DATA_WIDTH-1:0] rdata;
    logic [ADDR_WIDTH-1:0] rand_addr;
    logic [DATA_WIDTH-1:0] rand_data;
    
    logic [ADDR_WIDTH-1:0] last_valid_addr;
    logic [ADDR_WIDTH-1:0] out_of_bounds_addr;


    initial begin
        PRESETn  = 0;
        mux      = 0;
        wdata_in = 0;
        addr_in  = 0;

        $display("\n[INIT] Applying System Reset...");
        repeat(5) @(posedge PCLK);
        @(negedge PCLK); 
        PRESETn = 1;
        $display("[INIT] System Running with %0d Registers.\n", NUM_REGS_TEST);
        
        // Directed Tests (Regressions) 
        $display("--- Starting Directed Tests ---");
        
        // Test 1
        apb_write(32'h00, 32'hDEAD_BEEF);
        check_error_status(1'b0, "Write 0x00"); 
        apb_read (32'h00, rdata);
        check_error_status(1'b0, "Read 0x00");  
        check_result(32'h00, 32'hDEAD_BEEF, rdata);

        // Test 2
        apb_write(32'h04, 32'hCAFE_BABE);
        check_error_status(1'b0, "Write 0x04"); 
        apb_read (32'h04, rdata);
        check_error_status(1'b0, "Read 0x04");  
        check_result(32'h04, 32'hCAFE_BABE, rdata);


        // Error (PSLVERR) Tests 
        $display("\n--- Starting Error (PSLVERR) Tests ---");
        
        last_valid_addr    = (NUM_REGS_TEST - 1) * 4;
        out_of_bounds_addr = NUM_REGS_TEST * 4;

        // 1. Boundary Test: Write to the very last valid register (Should pass)
        apb_write(last_valid_addr, 32'h00C0FFEE);
        check_error_status(1'b0, "Boundary Write");

        // 2. Negative Test: Write Out-of-Bounds (Should error)
        apb_write(out_of_bounds_addr, 32'hBADACCE5);
        check_error_status(1'b1, "OOB Write");

        // 3. Negative Test: Read Out-of-Bounds (Should error)
        apb_read(out_of_bounds_addr, rdata);
        check_error_status(1'b1, "OOB Read");


        // Random Tests (~10% out-of-range accesses)
        $display("\n--- Starting Random Stress Test (%0d Iterations) ---", NUM_RANDOM);
        for (int i = 0; i < NUM_RANDOM; i++) begin
            if ($urandom_range(0, 9) == 0)
                rand_addr = $urandom_range(NUM_REGS_TEST, NUM_REGS_TEST + 3) * 4;
            else
                rand_addr = $urandom_range(0, NUM_REGS_TEST - 1) * 4;
            rand_data = $urandom();

            apb_write(rand_addr, rand_data);
            apb_read (rand_addr, rdata);

            if (rand_addr < NUM_REGS_TEST * 4) begin
                check_error_status(1'b0, "Random in-range access");
                check_result(rand_addr, rand_data, rdata);
            end else begin
                check_error_status(1'b1, "Random OOB access");
            end

            if (i % 20 == 0) $write(".");
        end
        $display("");

        $display("\n==========================================");
        if (errors == 0) begin
            $display("   STATUS: PASSED ");
            $display("   Ran %0d tests with 0 errors.", tests_run);
        end else begin
            $display("   STATUS: FAILED ");
            $display("   Detected %0d errors.", errors);
        end
`ifdef APB_ASSERT
        $display("   Scoreboard checks: %0d | Functional coverage: %0.1f%%",
                 sb_checks, cg.get_inst_coverage());
`else
        $display("   Scoreboard checks: %0d", sb_checks);
`endif
        $display("==========================================");
        
        $finish;
    end

    initial begin
        $dumpfile("apb_final.vcd");
        $dumpvars(0, tb_apb_system);
    end

endmodule