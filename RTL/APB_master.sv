/* Michael Mostytskyy
 Project: FSM-Based AMBA APB Master & Slave Interface
 Description: 
   Hardware implementation of an APB Master controller using a 3-state FSM.
   Handles Read/Write transactions and captures PSLVERR status.
   Compile with -DINJECT_SVA_BUG1 / -DINJECT_SVA_BUG2 to inject protocol
   violations (SVA sensitivity check).
*/
`timescale 1ns / 1ps
module apb_master #(
    parameter ADDR_WIDTH = 32, // Configurable Address width
    parameter DATA_WIDTH = 32  // Configurable Data width
)(
 // System -> Master inputs
    input  logic                    PCLK,      // System Clock
    input  logic                    PRESETn,   // Active-Low Reset
    input  logic [1:0]              mux,       // Op: 00 = Idle, 01 = Read, 11 = Write
    input  logic [DATA_WIDTH-1:0]   wdata_in,  // Write Data Input
    input  logic [ADDR_WIDTH-1:0]   addr_in,   // Address Input

    // NEW OUTPUT to report error status to the system/testbench
    output logic                    master_err_out, //  Status of last transaction

    // Master -> Slave outputs
    output logic [ADDR_WIDTH-1:0]   PADDR,     // APB Address
    output logic                    PSEL,      // Slave Select
    output logic                    PENABLE,   // Enable Signal
    output logic                    PWRITE,    // 1 = Write, 0 = Read
    output logic [DATA_WIDTH-1:0]   PWDATA,    // APB Write Data

    // Slave -> Master inputs
    input  logic [DATA_WIDTH-1:0]   PRDATA,    // APB Read Data
    input  logic                    PREADY,    // Slave Ready Signal
    input  logic                    PSLVERR    // Slave Error Signal
);

// Internal Registers
    logic [ADDR_WIDTH-1:0] addr_reg;   // Latched Address
    logic [DATA_WIDTH-1:0] wdata_reg;  // Latched Write Data
    logic [DATA_WIDTH-1:0] rdata_reg;  // Latched Read Data
    logic                  write_reg;  // Latched Direction
    logic                  error_reg;  //  Latched Error Status

    // FSM States
    typedef enum logic [1:0] {
        IDLE,    // Idle State
        SETUP,   // Setup Phase
        ACCESS   // Access Phase
    } apb_state;

    // FSM Variables
    apb_state current_state, next_state;

// Assign internal error register to output output
assign master_err_out = error_reg; 

// FSM State Register
always @(posedge PCLK or negedge PRESETn) begin
    if (~PRESETn)
    current_state<=IDLE; 
    else
     current_state<=next_state; 
    
end


// FSM Next-State Logic (No changes needed here for basic error latching)
   always @(*) begin
        next_state = current_state;  
        case (current_state)
            IDLE: begin
                if (mux == 2'b01 || mux == 2'b11) 
                    next_state = SETUP;
            end
            SETUP: begin
                next_state = ACCESS;   
            end
            ACCESS: begin
                
                if (PREADY)
                    next_state = IDLE; 
            end
            default: begin
                next_state = IDLE; 
            end
        endcase
    end

// APB Output Logic
   always @(*) begin
        PSEL    = 1'b0;
        PENABLE = 1'b0;
        PWDATA  = wdata_reg;
        PWRITE = write_reg;
        PADDR = addr_reg;

`ifdef INJECT_SVA_BUG2
        // intentional bug: PWDATA unstable while waiting for PREADY
        if (current_state == ACCESS && !PREADY) PWDATA = ~wdata_reg;
`endif

        case (current_state)
            IDLE: begin
                PSEL = 1'b0;
                PENABLE = 1'b0;
            end
            SETUP: begin
                PSEL = 1'b1;
`ifdef INJECT_SVA_BUG1
                PENABLE = 1'b1;   // intentional bug: PENABLE raised already in SETUP
`else
                PENABLE = 1'b0;
`endif
            end
            ACCESS: begin
                PSEL = 1'b1;
                PENABLE = 1'b1; 
             end
        endcase
    end


// Data Path Logic - UPDATED TO CAPTURE PSLVERR
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        write_reg <= 1'b0;
        wdata_reg <= {DATA_WIDTH{1'b0}};
        rdata_reg <= {DATA_WIDTH{1'b0}};
        addr_reg  <= {ADDR_WIDTH{1'b0}};
        error_reg <= 1'b0; //  Reset error register
    end
    else begin
        // Latch Transaction Inputs (Start of new transaction)
        if (current_state == IDLE && next_state == SETUP) begin
            write_reg <= (mux == 2'b11); // 1 = Write, 0 = Read
            wdata_reg <= wdata_in;
            addr_reg  <= addr_in;
            error_reg <= 1'b0; // Clear error status for new transaction
        end

        // Capture Read Data AND Error Status at the end of ACCESS phase
        // NEW condition logic below:
        if (current_state == ACCESS && PREADY) begin
            // Always capture error status on valid handshake
            error_reg <= PSLVERR; //   Latch the error signal from Slave
            
            // Capture data only if it was a read
            if (!write_reg) begin
                rdata_reg <= PRDATA;
            end
        end
    end
end

`ifdef APB_ASSERT
    // ---------------- Protocol assertions ----------------
    default clocking cb @(posedge PCLK); endclocking
    default disable iff (!PRESETn);

    // PENABLE is never asserted without PSEL
    a_penable_needs_psel: assert property (PENABLE |-> PSEL)
        else $error("[SVA] PENABLE asserted without PSEL");

    // SETUP lasts exactly one cycle, then ACCESS
    a_setup_one_cycle: assert property ((PSEL && !PENABLE) |=> (PSEL && PENABLE))
        else $error("[SVA] SETUP did not last exactly one cycle");

    // PENABLE rises only right after a SETUP cycle
    a_enable_after_setup: assert property ($rose(PENABLE) |-> $past(PSEL && !PENABLE))
        else $error("[SVA] PENABLE rose without a preceding SETUP");

    // Wait-states: while PREADY is low, ACCESS is held and the controls are stable
    a_wait_state_stable: assert property (
        (PSEL && PENABLE && !PREADY) |=>
        (PSEL && PENABLE && $stable(PADDR) && $stable(PWRITE) && $stable(PWDATA)))
        else $error("[SVA] Bus not stable / not held during wait-state");

    // No back-to-back transfers in this design: return to IDLE after the handshake
    a_idle_after_done: assert property ((PSEL && PENABLE && PREADY) |=> !PSEL)
        else $error("[SVA] PSEL still high after transfer completed");

    // Error status: master latches PSLVERR sampled at the handshake
    a_err_latched: assert property (
        (PSEL && PENABLE && PREADY) |=> (master_err_out == $past(PSLVERR)))
        else $error("[SVA] master_err_out does not match PSLVERR at handshake");

    // Cover: zero-wait (2-cycle) transfer, wait-state transfer, error transfer
    c_zero_wait:  cover property ((PSEL && !PENABLE) ##1 (PSEL && PENABLE && PREADY));
    c_wait_state: cover property ((PSEL && PENABLE && !PREADY) ##1 (PSEL && PENABLE && PREADY));
    c_error_xfer: cover property (PSEL && PENABLE && PREADY && PSLVERR);
`endif

endmodule