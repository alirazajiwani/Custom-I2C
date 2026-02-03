	module master #(
		 parameter DIVIDER = 100
	)(
		 input logic clk,
		 input logic rst_n,
		 input logic start,
		 input logic rw,
		 input logic [6:0] slave_address,
		 input logic [11:0] data_in,
		 output logic busy,
		 output logic ack_error,
		 output logic [11:0] data_out,
		 inout logic scl,
		 inout logic sda
	);

	// Internal signals
	logic scl_out;
	logic sda_out;
	logic sda_oe;
	logic sda_in_sync1, sda_in_sync2;
	logic scl_sync1, scl_sync2;
	logic [3:0] bit_count;
	logic [$clog2(DIVIDER)-1:0] scl_count;
	logic [7:0] shift_reg;
	logic [11:0] data_reg;
	logic [11:0] read_buffer;
	logic byte_count;
	logic scl_enable;
	logic rw_reg;
	logic ack_sampled;  

	// Tri-state buffers
	assign sda = sda_oe ? sda_out : 1'bz;
	assign scl = (scl_enable && !scl_out) ? 1'b0 : 1'bz;

	// ============================================================
	// Two-stage synchronizer for SDA and SCL
	// ============================================================
	always_ff @(posedge clk or negedge rst_n) begin
		 if (!rst_n) begin
			  sda_in_sync1 <= 1'b1;
			  sda_in_sync2 <= 1'b1;
			  scl_sync1 <= 1'b1;
			  scl_sync2 <= 1'b1;
		 end else begin
			  sda_in_sync1 <= sda;
			  sda_in_sync2 <= sda_in_sync1;
			  scl_sync1 <= scl;
			  scl_sync2 <= scl_sync1;
		 end
	end

	// ============================================================
	// SCL clock generation
	// ============================================================
	always_ff @(posedge clk or negedge rst_n) begin
		 if (!rst_n) begin
			  scl_count <= 0;
			  scl_out <= 1'b1;
		 end
		 else if (scl_enable) begin
			  if (scl_count == DIVIDER-1) begin
					scl_out <= ~scl_out;
					scl_count <= 0;
			  end
			  else begin
					scl_count <= scl_count + 1;
			  end
		 end
		 else begin
			  scl_count <= 0;
			  scl_out <= 1'b1;
		 end
	end

	// State machine type definition
	typedef enum logic [3:0] {
		 IDLE,
		 START,
		 ADDR,
		 ACK_ADDR,
		 WRITE_DATA,
		 ACK_WRITE,
		 READ_DATA,
		 ACK_READ,
		 STOP
	} state_t;

	state_t state, next_state;

	// ============================================================
	// Main FSM
	// ============================================================

	// State register (sequential)
	always_ff @(posedge clk or negedge rst_n) begin
		 if (!rst_n)
			  state <= IDLE;
		 else
			  state <= next_state;
	end


	// Next state logic
	always_comb begin
		 next_state = state;
		 case (state)
			  IDLE: begin
					if (start)
						 next_state = START;
			  end
			  
			  START: begin
					if (scl_count == DIVIDER-1 && !scl_out)
						 next_state = ADDR;
			  end
			  
			  ADDR: begin
					if (bit_count == 8 && scl_count == DIVIDER-1 && !scl_out)   //state transitions happen at predictable points in the SCL clock cycle, avoiding race conditions.
						 next_state = ACK_ADDR;
			  end
			  
			  ACK_ADDR: begin
					// Transition based on registered ack_error, not live sda_in_sync2
					if (scl_count == DIVIDER-1 && !scl_out) begin
						 if (ack_error)  // Use registered flag
							  next_state = STOP;
						 else if (rw_reg)
							  next_state = READ_DATA;
						 else
							  next_state = WRITE_DATA;
					end
			  end
			  
			  WRITE_DATA: begin
					if (bit_count == 8 && scl_count == DIVIDER-1 && !scl_out)
						 next_state = ACK_WRITE;
			  end
			  
			  ACK_WRITE: begin
					if (scl_count == DIVIDER-1 && !scl_out) begin
						 if (byte_count == 1)                                // Both bytes sent
							  next_state = STOP;
						 else
							  next_state = WRITE_DATA;
					end
			  end
			  
			  READ_DATA: begin
					if (bit_count == 8 && scl_count == DIVIDER-1 && !scl_out)
						 next_state = ACK_READ;
			  end
			  
			  ACK_READ: begin
					if (scl_count == DIVIDER-1 && !scl_out) begin
						 if (byte_count == 1)                                // Both bytes received
							  next_state = STOP;
						 else
							  next_state = READ_DATA;
					end
			  end
			  
			  STOP: begin
					if (scl_count == DIVIDER-1 && scl_out)
						 next_state = IDLE;
			  end
			  
			  default: next_state = IDLE;
		 endcase
	end

	// ============================================================
	// Output logic
	// ============================================================
	always_ff @(posedge clk or negedge rst_n) begin
		 if (!rst_n) begin
			  busy <= 1'b0;
			  ack_error <= 1'b0;
			  bit_count <= 4'h0;
			  byte_count <= 1'b0;
			  sda_out <= 1'b1;      
			  sda_oe <= 1'b0;
			  shift_reg <= 8'h00;
			  data_out <= 12'h000;
			  data_reg <= 12'h000;
			  read_buffer <= 12'h000;
			  rw_reg <= 1'b0;
			  scl_enable <= 1'b0;
			  ack_sampled <= 1'b0;
		 end
		 else begin
			  case (state)
					IDLE: begin
						 ack_error <= 1'b0;
						 bit_count <= 4'h0;
						 byte_count <= 1'b0;
						 sda_out <= 1'b1;      
						 sda_oe <= 1'b0;
						 scl_enable <= 1'b0;
						 ack_sampled <= 1'b0;
						 
						 if (start) begin
							  data_reg <= data_in;
							  rw_reg <= rw;
							  busy <= 1'b1;
							  scl_enable <= 1'b1;
							  read_buffer <= 12'h000;
							  shift_reg <= {slave_address, rw};
						 end
						 else begin
							  busy <= 1'b0;
						 end
					end
					
					START: begin
						 // Generate START: SDA goes low while SCL is high
						 if (scl_count == 0 && scl_out) begin
							  sda_out <= 1'b0;
							  sda_oe <= 1'b1;
						 end
						 
						 if (next_state == ADDR) begin
							  bit_count <= 4'h0;
							  sda_out <= shift_reg[7];
							  sda_oe <= 1'b1;
						 end
					end
					
					ADDR: begin
						 // Change SDA on falling edge of SCL
						 if (scl_count == 0 && !scl_out && bit_count < 8) begin
							  sda_out <= shift_reg[7 - bit_count];
							  sda_oe <= 1'b1;
						 end
						 
						 // Increment bit counter on rising edge of SCL
						 if (scl_count == DIVIDER/2 && scl_out && bit_count < 8) begin
							  bit_count <= bit_count + 4'h1;
						 end
						 
						 if (next_state == ACK_ADDR) begin
							  sda_oe <= 1'b0;                                 // Release SDA for ACK
							  ack_sampled <= 1'b0;                            // Reset ack_sampled flag
						 end
					end
					
					ACK_ADDR: begin
						 sda_oe <= 1'b0;
						 
						 // Sample ACK ONLY ONCE on rising edge of SCL
						 if (scl_count == DIVIDER/2 && scl_out && !ack_sampled) begin
							  if (sda_in_sync2) begin
									ack_error <= 1'b1;
							  end else begin
									ack_error <= 1'b0;                          // Clear error on valid ACK
							  end
							  ack_sampled <= 1'b1;                            // Mark ACK as sampled
						 end
						 
						 // Prepare for next state - set up first bit EARLY
						 if (next_state == WRITE_DATA) begin
							  bit_count <= 4'h0;
							  byte_count <= 1'b0;
							  shift_reg <= data_reg[11:4];
							  sda_out <= data_reg[11];                        // Set up first bit of data
							  sda_oe <= 1'b1;                                 // Drive it immediately
						 end
						 else if (next_state == READ_DATA) begin
							  bit_count <= 4'h0;
							  byte_count <= 1'b0;
							  shift_reg <= 8'h00;
							  sda_out <= 1'b0;                                // Prepare ACK for first byte
							  sda_oe <= 1'b0;                                 // Release SDA for slave to drive
						 end
					end
					
					WRITE_DATA: begin
						 // Transmit data on falling edge of SCL
						 if (scl_count == 0 && !scl_out && bit_count < 8) begin
							  sda_out <= shift_reg[7 - bit_count];
							  sda_oe <= 1'b1;
						 end
						 
						 // Increment bit counter on rising edge of SCL
						 if (scl_count == DIVIDER/2 && scl_out && bit_count < 8) begin
							  bit_count <= bit_count + 4'h1;
						 end
						 
						 // Prepare ACK when transitioning to ACK_WRITE
						 if (next_state == ACK_WRITE) begin
							  sda_oe <= 1'b0;
							  ack_sampled <= 1'b0;                            // Reset for next ACK
						 end
					end
					
					ACK_WRITE: begin
						 sda_oe <= 1'b0;
						 
						 // Sample ACK ONLY ONCE
						 if (scl_count == DIVIDER/2 && scl_out && !ack_sampled) begin
							  if (sda_in_sync2) begin
									ack_error <= 1'b1;
							  end
							  ack_sampled <= 1'b1;
						 end
						 
						 
						 if (next_state == WRITE_DATA) begin
							  bit_count <= 4'h0;
							  byte_count <= 1'b1;
							  shift_reg <= {data_reg[3:0], 4'h0};
							  sda_out <= data_reg[3];  
							  sda_oe <= 1'b1;                                 // Drive it immediately
						 end
					end
					
					READ_DATA: begin
						 // Sample data on rising edge of SCL
						 if (scl_count == DIVIDER/2 && scl_out && bit_count < 8) begin
							  shift_reg[7 - bit_count] <= sda_in_sync2;
						 end
						 
						 // Increment bit counter on falling edge of SCL
						 if (scl_count == DIVIDER-1 && !scl_out && bit_count < 8) begin
							  bit_count <= bit_count + 4'h1;
						 end
						 
						 // Store to buffer after 8th bit
						 if (bit_count == 8 && scl_count == 0 && !scl_out) begin
							  if (byte_count == 0) begin
									read_buffer[11:4] <= shift_reg;
							  end
							  else begin
									read_buffer[3:0] <= shift_reg[7:4];
							  end
						 end
						 
						 // Prepare ACK/NACK when transitioning to ACK_READ
						 // This ensures SDA is stable before SCL rises
						 if (next_state == ACK_READ) begin
							  sda_out <= (byte_count == 1) ? 1'b1 : 1'b0;     // ACK for first byte, NACK for second
							  sda_oe <= 1'b1;                                 // Drive SDA immediately
						 end
						 else begin
							  sda_oe <= 1'b0;                                 // Release SDA for slave to drive
						 end
					end
					
					ACK_READ: begin
						 // Maintain ACK/NACK on SDA - keep driving until ready to transition
						 
						 if (next_state == READ_DATA) begin
							  bit_count <= 4'h0;
							  byte_count <= 1'b1;
							  shift_reg <= 8'h00;
							  sda_oe <= 1'b0;                                 // Release for slave to drive next byte
							  sda_out <= 1'b1;
						 end
						 else if (next_state == STOP) begin
							  sda_oe <= 1'b0;                                 // Release for STOP condition
							  data_out <= read_buffer;
						 end
						 else begin
							  // Explicitly maintain ACK/NACK drive
							  sda_oe <= 1'b1;
						 end
					end
					
					STOP: begin
						 // Generate STOP: SDA goes high while SCL is high
						 if (scl_count == 0 && !scl_out) begin
							  sda_out <= 1'b0;
							  sda_oe <= 1'b1;
						 end
						 
						 if (scl_count == DIVIDER/2 && scl_out) begin
							  sda_out <= 1'b1;
						 end
						 
						 if (next_state == IDLE) begin
							  sda_oe <= 1'b0;
							  scl_enable <= 1'b0;
							  busy <= 1'b0;
						 end
					end
					
					default: begin
						 sda_oe <= 1'b0;
					end
			  endcase
		 end
	end

	endmodule