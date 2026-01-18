# FSM-Based AMBA APB Master & Slave Interface

## 1. Introduction
This project implements a robust **AMBA APB (Advanced Peripheral Bus)** Master and Slave communication system using SystemVerilog. The design focuses on a low-power, low-bandwidth control interface suitable for configuring registers in System-on-Chip (SoC) designs.

The core logic is driven by a **Finite State Machine (FSM)** that strictly adheres to the APB protocol phases (IDLE, SETUP, ACCESS), ensuring clean timing and reliable data transfer between the system controller and peripheral devices.

## 2. Key Features
* **FSM-Based Control:** The Master utilizes a dedicated 3-state FSM to manage bus timing and handshake signals automatically.
* **Configurable Transactions:** Supports both **Read** and **Write** operations triggered by a simple 2-bit multiplexer control signal.
* **Randomized Wait-States:** The included Slave module implements randomized wait-states (`PREADY` toggling) to verify the Master's ability to handle bus stalls correctly.
* **Parametrized Architecture:** Fully configurable `ADDR_WIDTH` and `DATA_WIDTH` (default 32-bit) via module parameters for flexible integration.
* **Enhanced Verification:** Includes **SystemVerilog Assertions (SVA)** for protocol compliance and **Functional Coverage** metrics.
* **Synchronous Design:** All internal registers and state transitions are synchronized to the rising edge of `PCLK`, with asynchronous active-low reset.

## 3. Architecture Overview
The system is divided into two main modules connected via the standard APB interface signals.

```mermaid
%%{init: {'themeVariables': { 'fontFamily': 'Arial', 'fontSize': '14px'}}}%%
graph LR
    %% Global Signals on the far left
    CLK((PCLK / PRESETn))

    subgraph TB [Testbench / System Host]
        GEN[Stimulus Generator]
    end

    subgraph DUT [APB System]
        %% The DUT components sit next to each other
        M[APB Master]
        S[APB Slave]
    end

    %% Clock connections (dotted lines)
    CLK -.- GEN
    CLK ==> M
    CLK ==> S

    %% Host to Master flow (left to right)
    GEN -->|"mux (1:0)"| M
    GEN ==>|addr_in, wdata_in| M

    %% Master to Slave flow (left to right)
    M ==>|PADDR, PWDATA| S
    M -->|PSEL, PENABLE, PWRITE| S

    %% Feedback from Slave to Master (right to left)
    S ==>|PRDATA| M
    S -->|PREADY, PSLVERR| M
    
```
### 3.1 APB Master (Controller)
The Master acts as the bridge between the high-level system logic and the APB bus. It translates simple commands into the precise APB protocol timing:
1.  **IDLE State:** Waits for a transaction request (`mux` input).
2.  **SETUP Phase:** Drives the Address (`PADDR`) and Selection (`PSEL`) signals. This phase lasts exactly one clock cycle.
3.  **ACCESS Phase:** Asserts `PENABLE` to validate the transfer. It waits for the Slave's `PREADY` signal before completing the transaction and latching data (for reads) or finishing the write.

### 3.2 APB Slave (Peripheral)
The Slave implements a simple 4-register file with dynamic timing:
* **Write Operations:** Data is written to the internal register array on the rising edge of `PCLK` when `PSEL`, `PENABLE`, and `PWRITE` are active.
* **Wait-State Generation:** The Slave uses a random generator to deassert `PREADY`, simulating realistic peripheral delays.

## 4. Interface Description
The module interacts with the host system on one side and the APB bus on the other. All operations are synchronized to the rising edge of the clock.

| Signal Group | Signal Name | Direction | Width | Description |
| :--- | :--- | :--- | :--- | :--- |
| **Global** | `PCLK` | Input | 1-bit | **System Clock**. All logic triggers on the rising edge. |
| | `PRESETn` | Input | 1-bit | **Active-Low Reset**. Asynchronous reset to initialize FSM and registers. |
| **System Interface** | `mux` | Input | 2-bit | **Operation Select**. Controls the transaction type:<br>`00`: IDLE (No op)<br>`01`: READ transaction<br>`11`: WRITE transaction |
| | `addr_in` | Input | `ADDR_WIDTH` | **Address Input**. Target address provided by the system. |
| | `wdata_in` | Input | `DATA_WIDTH` | **Write Data Input**. Payload to be written to the slave (valid when `mux=11`). |
| **APB Bus** | `PADDR` | Output | `ADDR_WIDTH` | **APB Address**. Driven to the peripheral during SETUP/ACCESS. |
| | `PSEL` | Output | 1-bit | **Slave Select**. Asserted to indicate a transaction start. |
| | `PENABLE` | Output | 1-bit | **Enable**. Asserted during the ACCESS phase to validate the transfer. |
| | `PWRITE` | Output | 1-bit | **Transfer Direction**. `1` = Write, `0` = Read. |
| | `PWDATA` | Output | `DATA_WIDTH` | **APB Write Data**. Driven by Master during write cycles. |
| | `PRDATA` | Input | `DATA_WIDTH` | **APB Read Data**. Incoming data from the Slave. |
| | `PREADY` | Input | 1-bit | **Ready Handshake**. Slave signal to extend the transfer (Wait states). |
| | `PSLVERR` | Input | 1-bit | **Slave Error**. Indicates a failed transfer (Supported in interface). |

## 5. Verification
The system is verified using a sophisticated testbench that includes a **Scoreboard** for data integrity and **Functional Coverage** for test completeness.

### Functional Flow Verified:
1.  **Write Transaction:**
    * System sets `mux=11` and provides data/address.
    * Master FSM transitions `IDLE -> SETUP -> ACCESS`.
    * Slave detects write command and updates internal register at `addr_in`.
2.  **Read Transaction:**
    * System sets `mux=01`.
    * Master FSM transitions `IDLE -> SETUP -> ACCESS`.
    * Slave drives data from the requested register onto `PRDATA`.
    * Master latches `PRDATA` into internal `rdata_reg` when `PREADY` is high.

### Simulation Waveform Snapshot
The waveform below captures the simulation results. It demonstrates a successful **Write** transaction followed by a **Read** verification to ensure data integrity.

![Simulation Waveform](images/simulation_wave.png)

**Analysis of Results:**
The simulation validates the FSM correctness through two key transactions:

1.  **Write Transaction (Left Side):**
    * The Master asserts `PSEL` and drives `PWRITE` **HIGH**, indicating a write operation.
    * The payload `0xDEADBEEF` is driven onto the `PWDATA` bus.
    * When `PENABLE` goes high, the Slave captures the data.

2.  **Read Transaction (Right Side):**
    * The Master asserts `PSEL` again but drives `PWRITE` **LOW**, indicating a read operation.
    * The Slave responds by driving the previously stored value, `0xDEADBEEF`, onto the `PRDATA` bus.
    * The simulation proves that the data was correctly stored in the Slave and retrieved by the Master without data loss or timing violations.

## 6. File Description
* `apb_master.sv`: The FSM-based Master controller RTL with SVA properties.
* `apb_slave_simple.sv`: A reference Slave module with randomized wait-states.
* `tb_apb_system.sv`: Top-level testbench with Scoreboard and Coverage.

## 7. Tools Used
* **Language:** SystemVerilog (IEEE 1800-2012)
* **Simulation:** Icarus Verilog (iverilog)
* **Waveform Analysis:** GTKWave

## 8. How to Run Simulation
To compile and simulate the design using Icarus Verilog:

```bash
# 1. Compile the design (Note the folder paths)
iverilog -g2012 -o apb_sim RTL/APB_master.sv RTL/APB_slave.sv TB/TB_APB_system.sv

# 2. Run the simulation
vvp apb_sim

# 3. View Waveforms
gtkwave apb_improved.vcd