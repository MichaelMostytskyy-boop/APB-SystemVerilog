//=============================================================
// Michael Mostytskyy
// FSM-Based Implementation of an  APB Master Interface
//=============================================================
module apb_master (
    // System -> Master inputs
    input  logic        PCLK,     // System clock. All APB operations are synchronized to posedge PCLK
    input  logic        PRESETn,   // Active-low reset. Forces the master FSM to IDLE and clears control signals
    input  logic  [1:0]  mux,      // Operation select:  00 = No operation (IDLE)  01 = Read transaction  11 = Write transaction
    input  logic  [31:0] wdata_in,
    input  logic  [31:0] addr_in,
    // Master -> Slave outputs
    output logic [31:0] PADDR,    // Address bus. Specifies the target slave register
    output logic        PSEL,     // Slave select. Asserted during SETUP and ACCESS phases
    output logic        PENABLE,  // Transfer enable. Asserted in ACCESS phase only
    output logic        PWRITE,   // Transfer direction: 1 = Write, 0 = Read
    output logic [31:0] PWDATA,   // Write data bus. Valid only when PWRITE = 1

    // Slave -> Master inputs
    input  logic [31:0] PRDATA,   // Read data bus. Sampled when PREADY = 1 and PWRITE = 0
    input  logic        PREADY   // Ready handshake. Indicates completion of the APB transfer
  
);

// Internal registers to hold transaction information
logic [31:0] addr_reg;   // Latched address
logic [31:0] wdata_reg;  // Latched write data
logic [31:0] rdata_reg;  // Latched read data (optional)
logic        write_reg;  // Latched transfer direction

//APB Master FSM state encoding
 typedef enum logic [1:0] {
        IDLE,    // No active transaction
        SETUP,   // Address and control phase
        ACCESS   // Data transfer phase
    } apb_state;

    // Current FSM state (registered)
    apb_state current_state,next_state;



//State register: synchronous update with asynchronous reset
always @(posedge PCLK or negedge PRESETn) begin
    if (~PRESETn)
    current_state<=IDLE; // Reset returns FSM to IDLE
    else
     current_state<=next_state; // Advance to next state
    
end


// FSM next-state combinational logic
   always @(*) begin
        next_state = current_state;  // Default behavior: remain in the current state
        case (current_state)
            IDLE: begin
                if (mux == 2'b01 || mux == 2'b11) // Wait for a valid transaction request  Only READ (01) or WRITE (11) requests start a transfer
                    next_state = SETUP;
            end
            SETUP: begin
                next_state = ACCESS;   // Setup phase always lasts exactly one clock cycle  APB protocol requires SETUP -> ACCESS
            end
            ACCESS: begin
                
                if (PREADY)
                    next_state = IDLE; // Stay in ACCESS until the slave asserts PREADY  This allows insertion of wait states
            end
            default: begin
                next_state = IDLE; // Safety fallback
            end
        endcase
    end


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



always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        write_reg <= 1'b0;
        wdata_reg <= 32'b0;
        rdata_reg <= 32'b0;
        addr_reg  <= 32'b0;
        
    end
    else begin
        // Latch transaction attributes at start of transfer
        if (current_state == IDLE && next_state == SETUP) begin
            write_reg <= (mux == 2'b11);   // 1 = WRITE, 0 = READ
            wdata_reg <= wdata_in;           // write data source
            addr_reg<= addr_in;
        end

        // Latch read data at end of ACCESS phase
        if (current_state == ACCESS && PREADY && !write_reg) begin
            rdata_reg <= PRDATA;
        end
    end
end
endmodule
