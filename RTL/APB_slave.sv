/* Michael Mostytskyy
 Project: FSM-Based AMBA APB Master & Slave Interface
 Description: 
   APB Slave peripheral with 4 internal 32-bit registers.
   Implements zero-wait state read/write access logic.
*/

module apb_slave_simple #(
    parameter ADDR_WIDTH = 32, // Configurable Address width
    parameter DATA_WIDTH = 32  // Configurable Data width
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

    // Internal register file: 4 registers 
   
    logic [DATA_WIDTH-1:0] regfile [0:3];
    logic [1:0]  addr_idx;
    logic        ready_gen; // For random wait states

    // Word-aligned address decoding
    assign addr_idx = PADDR[3:2];
    assign PSLVERR  = 1'b0; // No error support yet

    // Random Wait-State Generator
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            ready_gen <= 1'b0;
        else
            ready_gen <= $urandom_range(0, 1);
    end
  
    // APB response signals
    assign PREADY  = (PSEL && PENABLE) ? ready_gen : 1'b1; // Insert Wait States
  

    // Write operation (ACCESS phase)
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            regfile[0] <= {DATA_WIDTH{1'b0}};
            regfile[1] <= {DATA_WIDTH{1'b0}};
            regfile[2] <= {DATA_WIDTH{1'b0}};
            regfile[3] <= {DATA_WIDTH{1'b0}};
        end
        else if (PSEL && PENABLE && PWRITE && PREADY) begin
            regfile[addr_idx] <= PWDATA;
        end
    end
    // Read operation (combinational)
     always @(*) begin
        if (PSEL && !PWRITE && PENABLE && PREADY)
            PRDATA = regfile[addr_idx];
        else
            PRDATA = {DATA_WIDTH{1'b0}};
    end

endmodule