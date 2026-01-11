/* Michael Mostytskyy
 Project: FSM-Based AMBA APB Master & Slave Interface
 Description: 
    Testbench to verify the APB Master and Slave interaction.
    Performs a Write transaction followed by a Read transaction.
*/

`timescale 1ns / 1ps

module tb_apb_system;

   
    // Parameters & Statistics

    parameter CLK_PERIOD = 10;       // 100MHz clock
    parameter TIMEOUT_CYCLES = 100;  // Max cycles to wait for Slave response

    int errors = 0;     // Error counter
    int tests_run = 0;  // Total tests counter

    // Signal Declaration
  
    logic        PCLK;
    logic        PRESETn;

    // Host -> Master
    logic [1:0]  mux;
    logic [31:0] wdata_in;
    logic [31:0] addr_in;

    // APB Bus
    logic [31:0] PADDR;
    logic        PSEL;
    logic        PENABLE;
    logic        PWRITE;
    logic [31:0] PWDATA;
    logic [31:0] PRDATA;
    logic        PREADY;

    // Clock Generation
    initial begin
        PCLK = 0;
        forever #(CLK_PERIOD/2) PCLK = ~PCLK;
    end

   
    //  DUT Instantiation
    apb_master u_master (
        .PCLK     (PCLK),
        .PRESETn  (PRESETn),
        .mux      (mux),
        .wdata_in (wdata_in),
        .addr_in  (addr_in),
        .PADDR    (PADDR),
        .PSEL     (PSEL),
        .PENABLE  (PENABLE),
        .PWRITE   (PWRITE),
        .PWDATA   (PWDATA),
        .PRDATA   (PRDATA),
        .PREADY   (PREADY)
    );

    apb_slave_simple u_slave (
        .PCLK     (PCLK),
        .PRESETn  (PRESETn),
        .PADDR    (PADDR),
        .PSEL     (PSEL),
        .PENABLE  (PENABLE),
        .PWRITE   (PWRITE),
        .PWDATA   (PWDATA),
        .PRDATA   (PRDATA),
        .PREADY   (PREADY)
    );

    
  
    
    // --> FIXED: Simple Timeout Mechanism (No crash) <--
    task automatic wait_apb_done();
        int timeout_ctr = 0;
        
        // Wait until handshake is complete
        while (!(PSEL && PENABLE && PREADY)) begin
            @(posedge PCLK);
            timeout_ctr++;
            
            // Check for timeout
            if (timeout_ctr >= TIMEOUT_CYCLES) begin
                $error("[FATAL] Timeout! Slave did not assert PREADY within %0d cycles.", TIMEOUT_CYCLES);
                $finish;
            end
        end
        
        // Handshake done - wait one cycle for stability
        @(posedge PCLK); 
    endtask

    // WRITE Task
    task automatic apb_write(input [31:0] address, input [31:0] data);
        begin
            @(posedge PCLK);
            addr_in  <= address;
            wdata_in <= data;
            mux      <= 2'b11; // WRITE request

            @(posedge PCLK);
            mux      <= 2'b00; // Clear request

            wait_apb_done();
        end
    endtask

    // READ Task
    task automatic apb_read(input [31:0] address, output [31:0] data);
        begin
            @(posedge PCLK);
            addr_in <= address;
            mux     <= 2'b01; // READ request

            @(posedge PCLK);
            mux     <= 2'b00;

            wait_apb_done();
            data = u_master.rdata_reg; // Peek inside master
        end
    endtask

    // Verification Task
    task check_result(input [31:0] addr, input [31:0] expected, input [31:0] actual);
        tests_run++;
        if (expected !== actual) begin
            $error("[FAIL] Addr: 0x%h | Exp: 0x%h | Got: 0x%h", addr, expected, actual);
            errors++;
        end
    endtask


    // Main Test Sequence (Randomized)
 
    logic [31:0] rdata;
    logic [31:0] rand_addr;
    logic [31:0] rand_data;

    initial begin
        // Initialize
        PRESETn  = 0;
        mux      = 0;
        wdata_in = 0;
        addr_in  = 0;

        // Safe Reset Release
        $display("\n[INIT] Applying System Reset...");
        repeat(5) @(posedge PCLK);
        @(negedge PCLK); 
        PRESETn = 1;
        $display("[INIT] System Running.\n");
        
        // Phase 1: Directed Tests (Sanity)
        $display("--- Starting Directed Tests ---");
        apb_write(32'h00, 32'hDEAD_BEEF);
        apb_read (32'h00, rdata);
        check_result(32'h00, 32'hDEAD_BEEF, rdata);

        apb_write(32'h04, 32'hCAFE_BABE);
        apb_read (32'h04, rdata);
        check_result(32'h04, 32'hCAFE_BABE, rdata);

        // Phase 2: Randomized Stress Test 
        $display("\n--- Starting Random Stress Test (20 Iterations) ---");
        
        for (int i = 0; i < 20; i++) begin
            rand_addr = $urandom_range(0, 3) * 4; 
            rand_data = $urandom();

            apb_write(rand_addr, rand_data);
            apb_read (rand_addr, rdata);
            check_result(rand_addr, rand_data, rdata);
            
            if (i % 5 == 0) $write("."); 
        end
        $display(""); 

        //  Summary 
        $display("\n==========================================");
        if (errors == 0) begin
            $display("   STATUS: PASSED ");
            $display("   Ran %0d tests with 0 errors.", tests_run);
        end else begin
            $display("   STATUS: FAILED ");
            $display("   Detected %0d errors in %0d tests.", errors, tests_run);
        end
        $display("==========================================");
        
        $finish;
    end

    // VCD Dump setup
    initial begin
        $dumpfile("apb_improved.vcd");
        $dumpvars(0, tb_apb_system);
    end

endmodule