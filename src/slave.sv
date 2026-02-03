module slave #(
    parameter [6:0] SLAVE_ADDR = 7'h50
)(
    input logic clk,
    input logic rst_n,
    inout logic scl,
    inout logic sda,
    output logic [11:0] rx_data,
    output logic data_valid
);

logic sda_sync1, sda_sync2, scl_sync1, scl_sync2;
logic sda_prev, scl_prev;

// Registers
logic [7:0] shift_reg;
logic [3:0] bit_count_addr;
logic [3:0] bit_count_data;
logic [11:0] internal_memory;
logic addr_match, rw_bit, byte_count;

// Tri-state control
logic sda_out;                          // Internal SDA
logic sda_oe;                           // SDA output enable
assign sda = sda_oe ? sda_out : 1'bz;

// ============================================================
// Two-stage synchronizer for SDA and SCL
// ============================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        scl_sync1 <= 1'b1;
        scl_sync2 <= 1'b1;                                          
        scl_prev  <= 1'b1;             // Extra register for edge detection
        sda_sync1 <= 1'b1;
        sda_sync2 <= 1'b1;
        sda_prev  <= 1'b1;
    end else begin
        scl_sync1 <= scl;
        scl_sync2 <= scl_sync1;
        scl_prev  <= scl_sync2;
        
        sda_sync1 <= sda;
        sda_sync2 <= sda_sync1;
        sda_prev  <= sda_sync2;
    end
end

// Edge detection
wire scl_rising  = !scl_prev && scl_sync2;                          // 0→1 transition
wire scl_falling = scl_prev && !scl_sync2;                          // 1→0 transition
wire start_cond  = sda_prev && !sda_sync2 && scl_sync2;
wire stop_cond   = !sda_prev && sda_sync2 && scl_sync2;

// State machine
typedef enum logic [2:0] {
    IDLE, 
    ADDR, 
    ACK_ADDR, 
    DATA, 
    ACK_DATA
} state_t;

state_t state, next_state;

// ============================================================
// Main FSM
// ============================================================

// State register
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
    end 
    else begin
        if (stop_cond && (state == IDLE || state == ACK_ADDR || state == ACK_DATA)) begin
            state <= IDLE;
        end
        else if (start_cond && state == IDLE) begin
            state <= ADDR;
        end
        else begin
            state <= next_state;
        end
    end
end

// Next state logic
always_comb begin
    next_state = state;
    case (state)
        IDLE:     next_state = IDLE;
        
        ADDR: begin
            if (bit_count_addr >= 8 && scl_falling)
                next_state = ACK_ADDR;
        end
        
        ACK_ADDR: begin
            if (scl_falling)
                next_state = addr_match ? DATA : IDLE;
        end
        
        DATA: begin
            if (bit_count_data >= 8 && scl_falling)
                next_state = ACK_DATA;
        end
        
        ACK_DATA: begin
            if (scl_falling) begin
                if (rw_bit) begin
                    if (byte_count == 0)
                        next_state = DATA;
                    else if (byte_count == 1)
                        next_state = IDLE;
                end 
                else begin
                    if (byte_count == 0)
                        next_state = DATA;
                    else if (byte_count == 1)
                        next_state = IDLE;
                end
            end
        end
        
        default: next_state = IDLE;
    endcase
end

// Output logic
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sda_out <= 1'b1;
        sda_oe <= 1'b0;
        bit_count_addr <= 4'h0;
        bit_count_data <= 4'h0;
        byte_count <= 1'b0;
        shift_reg <= 8'h00;
        internal_memory <= 12'h000;
        rx_data <= 12'h000;
        addr_match <= 1'b0;
        rw_bit <= 1'b0;
        data_valid <= 1'b0;
    end 
    else begin
        case (state)
            IDLE: begin
                sda_oe <= 1'b0;
                sda_out <= 1'b1;
                bit_count_addr <= 4'h0;
                bit_count_data <= 4'h0;
                byte_count <= 1'b0;
                shift_reg <= 8'h00;
                addr_match <= 1'b0;
                rw_bit <= 1'b0;
                data_valid <= 1'b0;
            end
            
            ADDR: begin
                sda_oe <= 1'b0;
                
                if (scl_rising && bit_count_addr < 8) begin
                    shift_reg[7 - bit_count_addr] <= sda_sync2;
                    bit_count_addr <= bit_count_addr + 4'h1;
                end
                
                if (bit_count_addr == 8) begin
                    addr_match <= (shift_reg[7:1] == SLAVE_ADDR);
                    rw_bit <= shift_reg[0];
                end
            end
            
            ACK_ADDR: begin
                if (addr_match) begin
                    sda_out <= 1'b0;
                    sda_oe <= 1'b1;
                end else begin
                    sda_oe <= 1'b0;
                end
                
                if (scl_falling) begin
                    sda_oe <= 1'b0;
                    bit_count_data <= 4'h0;
                    
                    if (addr_match && rw_bit) begin
                        shift_reg <= internal_memory[11:4];
                    end else begin
                        shift_reg <= 8'h00;
                    end
                end
            end
            
            DATA: begin
                if (rw_bit) begin

                    // READ operation 
                    if (bit_count_data < 8) begin
                        // Update SDA on falling edge or when SCL is low
                        if (scl_falling || !scl_sync2) begin
                            sda_out <= shift_reg[7 - bit_count_data];
                            sda_oe <= 1'b1;
                        end
                    end 
                    else begin
                        sda_oe <= 1'b0;
                    end
                    
                    if (scl_falling && bit_count_data < 8) begin
                        bit_count_data <= bit_count_data + 4'h1;
                    end
                end 
                else begin
                    // WRITE operation
                    sda_oe <= 1'b0;
                    
                    if (scl_rising && bit_count_data < 8) begin
                        shift_reg[7 - bit_count_data] <= sda_sync2;
                        bit_count_data <= bit_count_data + 4'h1;
                    end
                end
            end
            
            ACK_DATA: begin
                if (!rw_bit) begin
                    // WRITE operation
                    sda_out <= 1'b0;
                    sda_oe <= 1'b1;
                    
                    if (scl_rising) begin
                        if (byte_count == 0) begin
                            internal_memory[11:4] <= shift_reg;
                            shift_reg <= 8'h00;
                        end 
                        else if (byte_count == 1) begin
                            internal_memory[3:0] <= shift_reg[7:4];
                            rx_data <= {internal_memory[11:4], shift_reg[7:4]};
                            data_valid <= 1'b1;
                        end
                    end
                    
                    if (scl_falling) begin
                        sda_oe <= 1'b0;
                        bit_count_data <= 4'h0;
                        if (byte_count == 0) byte_count <= 1'b1;
                    end
                end 
                else begin
                    // READ operation
                    sda_oe <= 1'b0;
                    
                    if (scl_falling) begin
                        bit_count_data <= 4'h0;
                        if (byte_count == 0) begin
                            byte_count <= 1'b1;
                            shift_reg <= {internal_memory[3:0], 4'h0};
                        end
                    end
                end
            end
            
            default: begin
                sda_oe <= 1'b0;
            end
        endcase
    end
end

endmodule