/* Michael Mostytskyy
 Project: FSM-Based AMBA APB Master & Slave Interface
 Description: 
   APB Slave peripheral with configurable number of 32-bit registers.
   Implements randomized wait state and PSLVERR on address decode error.
   Compile with -DINJECT_BUG to inject a write-data bug (testbench sensitivity check).
*/
`timescale 1ns / 1ps
module apb_slave_simple #(
    parameter ADDR_WIDTH = 32, // Configurable Address width
    parameter DATA_WIDTH = 32, // Configurable Data width
    parameter NUM_REGS   = 4   // Configurable number of registers
)(
    input  logic                    PCLK,
    input  logic                    PRESETn,

    // APB inputs from Master
    input  logic [ADDR_WIDTH-1:0]   PADDR,
    input  logic                    PSEL,
    input  logic                    PENABLE,
    input  logic                    PWRITE,
    input  logic [DATA_WIDTH-1:0]   PWDATA,

    // APB outputs to Master
    output logic [DATA_WIDTH-1:0]   PRDATA,
    output logic                    PREADY,
    output logic                    PSLVERR
);

    // Calculate required address bits for the registers
    localparam ADDR_SHIFT = 2; // Assuming 32-bit word alignment
    localparam REG_IDX_WIDTH = (NUM_REGS > 1) ? $clog2(NUM_REGS) : 1;

    // Internal register file
    logic [DATA_WIDTH-1:0]    regfile [0:NUM_REGS-1];
    logic [REG_IDX_WIDTH-1:0] addr_idx;
    logic                     addr_error;
    logic                     ready_gen; // For random wait states
    integer                   i; // Loop iterator for reset

    // Word-aligned address decoding
    assign addr_idx = PADDR[ADDR_SHIFT +: REG_IDX_WIDTH];

    // Address error detection
    assign addr_error = ((PADDR >> ADDR_SHIFT) >= NUM_REGS);

    // APB response signals
    assign PSLVERR = (PSEL && PENABLE && addr_error);
    assign PREADY  = (PSEL && PENABLE) ? ready_gen : 1'b1; // Insert Wait States

    // Random Wait-State Generator
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            ready_gen <= 1'b0;
        else
            ready_gen <= $urandom_range(0, 1);
    end
  
    // Write operation (ACCESS phase)
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            for (i = 0; i < NUM_REGS; i++) begin
                 regfile[i] <= {DATA_WIDTH{1'b0}};
            end
        end
        else if (PSEL && PENABLE && PWRITE && PREADY && !addr_error) begin
`ifdef INJECT_BUG
            regfile[addr_idx] <= PWDATA ^ {{(DATA_WIDTH-1){1'b0}}, 1'b1}; // intentional bug: flips bit 0
`else
            regfile[addr_idx] <= PWDATA;
`endif
        end
    end

    // Read operation (combinational)
    always @(*) begin
        if (PSEL && !PWRITE && PENABLE && PREADY && !addr_error)
            PRDATA = regfile[addr_idx];
        else
            PRDATA = {DATA_WIDTH{1'b0}};
    end

endmodule