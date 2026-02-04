# I2C Master-Slave Communication Protocol

A robust SystemVerilog implementation of I2C (Inter-Integrated Circuit) master-slave communication protocol with 12-bit data transfer capability and comprehensive verification environment.

## Features

<img width="979" height="229" alt="image" src="https://github.com/user-attachments/assets/e2213e82-88de-4d4a-96a2-d565ee7bc0a2" />


- **12-bit Data Transfer**: Extended I2C implementation supporting 12-bit data payloads
- **Configurable Clock**: Adjustable SCL frequency via DIVIDER parameter
- **Programmable Addressing**: 7-bit slave address configuration
- **Complete Verification**: Full SystemVerilog testbench with self-checking capabilities
- **Clock Domain Crossing**: Proper synchronization with two-stage synchronizers
- **Error Handling**: ACK/NACK detection and reporting


## Architecture

The system consists of two main components:
<img width="979" height="535" alt="image" src="https://github.com/user-attachments/assets/4e6c3b76-665e-43d4-894b-69986850321f" />


### Master Module
- Initiates and controls all bus transactions
- Generates START and STOP conditions
- Configurable SCL clock generation
- Supports both read and write operations
- ACK/NACK detection with error reporting

### Slave Module
- Responds to master commands
- Programmable 7-bit address matching
- 12-bit internal memory for data storage
- Automatic ACK generation
- START/STOP condition detection

## File Structure

```
├──src/
  ├── master.sv          # I2C Master module implementation
  ├── slave.sv           # I2C Slave module implementation
├──testbenc/
  ├── I2C_tb.sv          # Complete verification testbench
└── README.md            # This file
```

## Protocol Specification

### Data Format
Data is transmitted in two consecutive 8-bit transactions:
- **First Byte**: Upper 8 bits (data[11:4])
- **Second Byte**: Lower 4 bits (data[3:0]) in upper nibble

### Write Transaction Sequence
1. START condition
2. Address byte (7-bit address + W bit)
3. Address ACK
4. Data byte 1 (upper 8 bits)
5. Data ACK 1
6. Data byte 2 (lower 4 bits)
7. Data ACK 2
8. STOP condition

### Read Transaction Sequence
1. START condition
2. Address byte (7-bit address + R bit)
3. Address ACK
4. Data byte 1 from slave (upper 8 bits)
5. Master ACK
6. Data byte 2 from slave (lower 4 bits)
7. Master NACK
8. STOP condition

## Getting Started

### Prerequisites
- SystemVerilog-compatible simulator (ModelSim, VCS, Xcelium, etc.)
- Basic understanding of I2C protocol

### Simulation

#### 0x5A3 Read and Write Waveform
<img width="975" height="201" alt="image" src="https://github.com/user-attachments/assets/27881d4c-2661-490e-8d5b-086365721925" />

#### All Test Waveform
<img width="975" height="192" alt="image" src="https://github.com/user-attachments/assets/a36f04b6-d8d2-4c0d-ab6a-568b9d8eb46d" />

### Configuration

#### Master Module Parameters
```systemverilog
master #(
    .DIVIDER(300)  // SCL clock divider
) master_inst (
    // ports...
);
```

**SCL Frequency Calculation:**
```
SCL_frequency = System_clock / (2 × DIVIDER)
```

**Examples:**
- Standard Mode (100 kHz): `DIVIDER = 500` @ 100 MHz system clock
- Fast Mode (400 kHz): `DIVIDER = 125` @ 100 MHz system clock
- Simulation Speed: `DIVIDER = 10` @ 100 MHz system clock

#### Slave Module Parameters
```systemverilog
slave #(
    .SLAVE_ADDR(7'h50)  // 7-bit I2C address
) slave_inst (
    // ports...
);
```

## Hardware Integration

### Required External Components
- **Pull-up Resistors**: 2.2 kΩ - 10 kΩ on both SCL and SDA lines
- **Level Shifters**: Required if connecting devices with different voltage levels

## Verification Environment

The testbench includes:

- **Transaction Class**: Randomizable transaction objects
- **Generator**: Creates write-read transaction pairs
- **Driver**: Converts transactions to pin-level signals
- **Monitor**: Observes and captures bus activity
- **Scoreboard**: Compares written and read data for verification

### Test Results
<img width="691" height="316" alt="image" src="https://github.com/user-attachments/assets/e60c2695-0ecd-4621-945d-98ec9f15d71c" />


## Signal Descriptions

### Master Interface
| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| clk | Input | 1 | System clock |
| rst_n | Input | 1 | Active-low reset |
| start | Input | 1 | Transaction start trigger |
| rw | Input | 1 | Read(1) / Write(0) |
| slave_address | Input | 7 | Target slave address |
| data_in | Input | 12 | Write data |
| busy | Output | 1 | Transaction in progress |
| ack_error | Output | 1 | ACK error flag |
| data_out | Output | 12 | Read data |
| scl | Inout | 1 | Serial clock line |
| sda | Inout | 1 | Serial data line |

### Slave Interface
| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| clk | Input | 1 | System clock |
| rst_n | Input | 1 | Active-low reset |
| scl | Inout | 1 | Serial clock line |
| sda | Inout | 1 | Serial data line |
| rx_data | Output | 12 | Received data |
| data_valid | Output | 1 | Data valid indicator |

## Timing Specifications

| Parameter | Condition | Value |
|-----------|-----------|-------|
| SDA Setup Time | Before SCL rising | DIVIDER/2 clock cycles |
| SDA Hold Time | After SCL rising | DIVIDER/2 clock cycles |
| SCL Low Period | Half SCL period | DIVIDER clock cycles |
| SCL High Period | Half SCL period | DIVIDER clock cycles |

## Multi-Slave Configuration

Multiple slaves can share the same I2C bus:
- Each slave must have a unique address
- Configure via `SLAVE_ADDR` parameter
- Avoid reserved addresses (7'h00-7'h07, 7'h78-7'h7F)


---

For detailed documentation, see the complete [Design Specification Document](Documentation.pdf).
