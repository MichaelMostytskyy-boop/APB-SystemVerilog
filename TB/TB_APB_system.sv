/* Michael Mostytskyy
 Project: FSM-Based AMBA APB Master & Slave Interface
 Description: 
   Testbench to verify the APB Master and Slave interaction.
*/

`timescale 1ns / 1ps

module tb_apb_system;

    // Parameters
    parameter CLK_PERIOD = 10;
    parameter TIMEOUT_CYCLES = 100;
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;

    int errors = 0;
    int tests_run = 0;

    // Signals
    logic                    PCLK;
    logic                    PRESETn;
    logic [1:0]              mux;
    logic [DATA_WIDTH-1:0]   wdata_in;
    logic [ADDR_WIDTH-1:0]   addr_in;
    logic [ADDR_WIDTH-1:0]   PADDR;
    logic                    PSEL;
    logic                    PENABLE;
    logic                    PWRITE;
    logic [DATA_WIDTH-1:0]   PWDATA;
    logic [DATA_WIDTH-1:0]   PRDATA;
    logic                    PREADY;
    logic                    PSLVERR;

    /* // Scoreboard Class (Commented out for Icarus Verilog compatibility)
    class APB_Scoreboard;
        logic [DATA_WIDTH-1:0] expected_data [int];
        function void write_expect(input int addr, input logic [DATA_WIDTH-1:0] data);
            expected_data[addr] = data;
        endfunction
        function bit compare(input int addr, input logic [DATA_WIDTH-1:0] actual);
            if (expected_data.exists(addr)) begin
                return (expected_data[addr] === actual);
            end
            return 0;
        endfunction
    endclass
    APB_Scoreboard sb;
    */

    /*
    // Functional Coverage (Commented out for Icarus Verilog)
    covergroup cg_apb @(posedge PCLK);
        cp_addr: coverpoint PADDR[3:2];
        cp_write: coverpoint PWRITE;
        cp_cross: cross cp_addr, cp_write;
    endgroup
    cg_apb cg_inst;
    */

    // Clock Generation
    initial begin
        PCLK = 0;
        forever #(CLK_PERIOD/2) PCLK = ~PCLK;
    end

    // DUT Instantiation
    apb_master #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_master (
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
        .PREADY   (PREADY),
        .PSLVERR  (PSLVERR)
    );

    apb_slave_simple #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
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
            // sb.write_expect(address, data); // Commented out
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

    // Verification Task (Simplified)
    task check_result(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] expected, input [DATA_WIDTH-1:0] actual);
        tests_run++;
        if (expected !== actual) begin
            $error("[FAIL] Addr: 0x%h | Exp: 0x%h | Got: 0x%h", addr, expected, actual);
            errors++;
        end
    endtask

    logic [DATA_WIDTH-1:0] rdata;
    logic [ADDR_WIDTH-1:0] rand_addr;
    logic [DATA_WIDTH-1:0] rand_data;

    initial begin
        // sb = new();
        // cg_inst = new();
        PRESETn  = 0;
        mux      = 0;
        wdata_in = 0;
        addr_in  = 0;

        $display("\n[INIT] Applying System Reset...");
        repeat(5) @(posedge PCLK);
        @(negedge PCLK); 
        PRESETn = 1;
        $display("[INIT] System Running.\n");
        
        // --- Directed Tests ---
        $display("--- Starting Directed Tests ---");
        
        // Test 1
        apb_write(32'h00, 32'hDEAD_BEEF);
        apb_read (32'h00, rdata);
        check_result(32'h00, 32'hDEAD_BEEF, rdata);

        // Test 2
        apb_write(32'h04, 32'hCAFE_BABE);
        apb_read (32'h04, rdata);
        check_result(32'h04, 32'hCAFE_BABE, rdata);

        //Random Tests
        $display("\n--- Starting Random Stress Test (20 Iterations) ---");
        
        for (int i = 0; i < 20; i++) begin
            rand_addr = $urandom_range(0, 3) * 4; 
            rand_data = $urandom();

            apb_write(rand_addr, rand_data);
            apb_read (rand_addr, rdata);
            
            // Compare directly (no need for Scoreboard class)
            check_result(rand_addr, rand_data, rdata);
            
            if (i % 5 == 0) $write("."); 
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
        $display("==========================================");
        
        $finish;
    end

    initial begin
        $dumpfile("apb_improved.vcd");
        $dumpvars(0, tb_apb_system);
    end

endmodule