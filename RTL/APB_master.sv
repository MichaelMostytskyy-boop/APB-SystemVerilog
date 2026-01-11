/* Michael Mostytskyy
 Project: FSM-Based AMBA APB Master & Slave Interface
 Description: 
    Hardware implementation of an APB Master controller using a 3-state FSM.
    It handles Read/Write transactions with correct protocol timing (SETUP/ACCESS)
*/

module apb_master (
 // System -> Master inputs
    input  logic        PCLK,      // System Clock
    input  logic        PRESETn,   // Active-Low Reset
    input  logic [1:0]  mux,       // Op: 00 = Idle, 01 = Read, 11 = Write
    input  logic [31:0] wdata_in,  // Write Data Input
    input  logic [31:0] addr_in,   // Address Input

    // Master -> Slave outputs
    output logic [31:0] PADDR,     // APB Address
    output logic        PSEL,      // Slave Select
    output logic        PENABLE,   // Enable Signal
    output logic        PWRITE,    // 1 = Write, 0 = Read
    output logic [31:0] PWDATA,    // APB Write Data

    // Slave -> Master inputs
    input  logic [31:0] PRDATA,    // APB Read Data
    input  logic        PREADY     // Slave Ready Signal
  
);

// Internal Registers
    logic [31:0] addr_reg;   // Latched Address
    logic [31:0] wdata_reg;  // Latched Write Data
    logic [31:0] rdata_reg;  // Latched Read Data
    logic        write_reg;  // Latched Direction

    // FSM States
    typedef enum logic [1:0] {
        IDLE,    // Idle State
        SETUP,   // Setup Phase
        ACCESS   // Access Phase
    } apb_state;

    // FSM Variables
    apb_state current_state, next_state;



// FSM State Register
always @(posedge PCLK or negedge PRESETn) begin
    if (~PRESETn)
    current_state<=IDLE; 
    else
     current_state<=next_state; 
    
end


// FSM Next-State Logic
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

        case (current_state)
            IDLE: begin
                PSEL = 1'b0;
                PENABLE = 1'b0;
            end
            SETUP: begin
                PSEL = 1'b1;
                PENABLE = 1'b0;
            end
            ACCESS: begin
                PSEL = 1'b1;
                PENABLE = 1'b1; 
             end
        endcase
    end


// Data Path Logic
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        write_reg <= 1'b0;
        wdata_reg <= 32'b0;
        rdata_reg <= 32'b0;
        addr_reg  <= 32'b0;
    end
    else begin
        // Latch Transaction Inputs
        if (current_state == IDLE && next_state == SETUP) begin
            write_reg <= (mux == 2'b11); // 1 = Write, 0 = Read
            wdata_reg <= wdata_in;
            addr_reg  <= addr_in;
        end

        // Capture Read Data
        if (current_state == ACCESS && PREADY && !write_reg) begin
            rdata_reg <= PRDATA;
        end
    end
end
endmodule
