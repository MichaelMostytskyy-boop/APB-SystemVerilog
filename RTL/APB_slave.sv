/* Michael Mostytskyy
 Project: FSM-Based AMBA APB Master & Slave Interface
 Description: 
    APB Slave peripheral with 4 internal 32-bit registers.
    Implements zero-wait state read/write access logic.
*/

module apb_slave_simple (
    input  logic        PCLK,
    input  logic        PRESETn,

    // APB inputs from Master
    input  logic [31:0] PADDR,
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic        PWRITE,
    input  logic [31:0] PWDATA,

    // APB outputs to Master
    output logic [31:0] PRDATA,
    output logic        PREADY
    
);

    // Internal register file: 4 registers 
   
    logic [31:0] regfile [0:3];
    logic [1:0]  addr_idx;

    // Word-aligned address decoding
    assign addr_idx = PADDR[3:2];

  
    // APB response signals
    assign PREADY  = 1'b1;   // No wait states
  

    // Write operation (ACCESS phase)
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            regfile[0] <= 32'b0;
            regfile[1] <= 32'b0;
            regfile[2] <= 32'b0;
            regfile[3] <= 32'b0;
        end
        else if (PSEL && PENABLE && PWRITE) begin
            regfile[addr_idx] <= PWDATA;
        end
    end
    // Read operation (combinational)
     always @(*) begin
        if (PSEL && !PWRITE)
            PRDATA = regfile[addr_idx];
        else
            PRDATA = 32'b0;
    end

endmodule
