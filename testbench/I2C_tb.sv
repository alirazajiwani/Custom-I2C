// Transaction Class
class i2c_transaction;
    rand bit rw;
    rand bit [6:0] slave_addr;
    rand bit [11:0] data;
    bit ack_error;
    bit [11:0] read_data;
    
    constraint addr_c {
        slave_addr == 7'h50;
    }
    
    function void display(string tag = "");
        $display("[%0t] %s RW=%0b ADDR=0x%h DATA=0x%h ACK_ERR=%0b READ=0x%h", 
                 $time, tag, rw, slave_addr, data, ack_error, read_data);
    endfunction
    
    function i2c_transaction copy();
        i2c_transaction trans = new();
        trans.rw = this.rw;
        trans.slave_addr = this.slave_addr;
        trans.data = this.data;
        trans.ack_error = this.ack_error;
        trans.read_data = this.read_data;
        return trans;
    endfunction
endclass

// Driver Class
class i2c_driver;
    virtual i2c_if vif;
    mailbox #(i2c_transaction) gen2drv;
    mailbox #(i2c_transaction) drv2scb;
    int trans_count = 0;
    
    function new(virtual i2c_if vif, mailbox #(i2c_transaction) gen2drv, 
                 mailbox #(i2c_transaction) drv2scb);
        this.vif = vif;
        this.gen2drv = gen2drv;
        this.drv2scb = drv2scb;
    endfunction
    
    task run();
        i2c_transaction trans;
        
        forever begin
            gen2drv.get(trans);
            drive_transaction(trans);
            drv2scb.put(trans.copy());
            trans_count++;
        end
    endtask
    
    task drive_transaction(i2c_transaction trans);
        // Wait for bus idle
        wait(!vif.busy);
        repeat(10) @(posedge vif.clk);
        
        // Drive transaction
        vif.slave_address = trans.slave_addr;
        vif.rw = trans.rw;
        vif.data_in = trans.data;
        vif.start = 1'b1;
        
        @(posedge vif.clk);
        vif.start = 1'b0;
        
        // Wait for busy to go high
        wait(vif.busy);
        $display("[%0t] DRIVER: Transaction started, busy=1", $time);
        
        // Wait for completion - busy goes low
        wait(!vif.busy);
        $display("[%0t] DRIVER: Transaction complete, busy=0, data_out=0x%h", $time, vif.data_out);
        
        // Additional settling time for data_out to be valid
        repeat(10) @(posedge vif.clk);
        
        // Capture results
        trans.ack_error = vif.ack_error;
        if (trans.rw)
            trans.read_data = vif.data_out;
        
        $display("[%0t] DRIVER: After wait, data_out=0x%h", $time, vif.data_out);
        trans.display("DRIVER");
    endtask
endclass

// Monitor Class
class i2c_monitor;
    virtual i2c_if vif;
    mailbox #(i2c_transaction) mon2scb;
    
    function new(virtual i2c_if vif, mailbox #(i2c_transaction) mon2scb);
        this.vif = vif;
        this.mon2scb = mon2scb;
    endfunction
    
    task run();
        i2c_transaction trans;
        
        forever begin
            @(posedge vif.clk);
            
            if (vif.start && !vif.busy) begin
                trans = new();
                trans.slave_addr = vif.slave_address;
                trans.rw = vif.rw;
                trans.data = vif.data_in;
                
                // Wait for transaction to complete
                wait(vif.busy);
                wait(!vif.busy);
                @(posedge vif.clk);
                
                // Capture results
                trans.ack_error = vif.ack_error;
                if (trans.rw)
                    trans.read_data = vif.data_out;
                
                trans.display("MONITOR");
                mon2scb.put(trans);
            end
        end
    endtask
endclass

// Scoreboard Class
class i2c_scoreboard;
    mailbox #(i2c_transaction) drv2scb;
    int transactions_checked;
    int transactions_passed;
    int transactions_failed;
    bit [11:0] last_written_data;
    bit write_pending;
    
    function new(mailbox #(i2c_transaction) drv2scb);
        this.drv2scb = drv2scb;
        transactions_checked = 0;
        transactions_passed = 0;
        transactions_failed = 0;
        write_pending = 0;
    endfunction
    
    task run();
        i2c_transaction trans;
        
        forever begin
            drv2scb.get(trans);
            check_transaction(trans);
        end
    endtask
    
    task check_transaction(i2c_transaction trans);
        transactions_checked++;
        
        // Check for ACK errors
        if (trans.ack_error) begin
            $display("ERROR: ACK Error in transaction %0d", transactions_checked);
            transactions_failed++;
            return;
        end
        
        if (trans.rw == 0) begin
            // WRITE transaction
            last_written_data = trans.data;
            write_pending = 1;
            $display("SCOREBOARD: Stored WRITE data=0x%h", trans.data);
            transactions_passed++;
        end
        else begin
            // READ transaction
            if (write_pending) begin
                if (trans.read_data === last_written_data) begin
                    $display("SCOREBOARD: READ PASS - Expected=0x%h Got=0x%h", 
                             last_written_data, trans.read_data);
                    transactions_passed++;
                end
                else begin
                    $display("ERROR: READ MISMATCH - Expected=0x%h Got=0x%h", 
                             last_written_data, trans.read_data);
                    transactions_failed++;
                end
                write_pending = 0;
            end
            else begin
                $display("WARNING: READ without prior WRITE");
                transactions_checked--;
            end
        end
    endtask
    
    function void report();
        $display("\n======================================================================");
        $display("                    SCOREBOARD REPORT");
        $display("======================================================================");
        $display("Total Transactions: %0d", transactions_checked);
        $display("Passed:            %0d", transactions_passed);
        $display("Failed:            %0d", transactions_failed);
        $display("----------------------------------------------------------------------");
        if (transactions_failed == 0)
            $display("STATUS: ALL TESTS PASSED!");
        else
            $display("STATUS: %0d TEST(S) FAILED!", transactions_failed);
        $display("======================================================================\n");
    endfunction
endclass

// Generator Class
class i2c_generator;
    mailbox #(i2c_transaction) gen2drv;
    int num_transactions;
    
    function new(mailbox #(i2c_transaction) gen2drv, int num_trans = 10);
        this.gen2drv = gen2drv;
        this.num_transactions = (num_trans % 2 == 0) ? num_trans : num_trans + 1;
    endfunction
    
    task run();
        i2c_transaction trans;
        
        $display("\n[%0t] GENERATOR: Starting %0d transactions (write-read pairs)", 
                 $time, num_transactions);
        
        for (int i = 0; i < num_transactions/2; i++) begin
            // WRITE transaction
            trans = new();
            assert(trans.randomize() with {rw == 0;});
            $display("[%0t] GENERATOR: WRITE #%0d data=0x%h", $time, i, trans.data);
            gen2drv.put(trans);
            
            // READ transaction
            trans = new();
            assert(trans.randomize() with {rw == 1;});
            $display("[%0t] GENERATOR: READ #%0d", $time, i);
            gen2drv.put(trans);
        end
        
        $display("[%0t] GENERATOR: Generation complete\n", $time);
    endtask
endclass

// Environment Class
class i2c_environment;
    i2c_generator gen;
    i2c_driver drv;
    i2c_monitor mon;
    i2c_scoreboard scb;
    
    mailbox #(i2c_transaction) gen2drv;
    mailbox #(i2c_transaction) drv2scb;
    mailbox #(i2c_transaction) mon2scb;
    
    virtual i2c_if vif;
    
    function new(virtual i2c_if vif, int num_trans = 10);
        this.vif = vif;
        gen2drv = new();
        drv2scb = new();
        mon2scb = new();
        gen = new(gen2drv, num_trans);
        drv = new(vif, gen2drv, drv2scb);
        mon = new(vif, mon2scb);
        scb = new(drv2scb);
    endfunction
    
    task run();
        fork
            gen.run();
            drv.run();
            mon.run();
            scb.run();
        join_none
        
        // Wait for all transactions to complete
        wait(drv.trans_count == gen.num_transactions);
        repeat(100) @(posedge vif.clk);
    endtask
    
    function void report();
        scb.report();
    endfunction
endclass

// Interface
interface i2c_if(input logic clk);
    logic rst_n;
    logic start;
    logic rw;
    logic [6:0] slave_address;
    logic [11:0] data_in;
    logic busy;
    logic ack_error;
    logic [11:0] data_out;
    wire scl;
    wire sda;
    
    logic [11:0] slave_rx_data;
    logic slave_data_valid;
endinterface

// Test Program
program i2c_test(i2c_if tif);
    i2c_environment env;
    
    initial begin
        $display("\n======================================================================");
        $display("              STARTING I2C VERIFICATION TEST");
        $display("======================================================================");
        
        // Create environment with 10 transaction pairs (20 total)
        env = new(tif, 20);
        
        // Reset sequence
        tif.rst_n = 0;
        tif.start = 0;
        tif.rw = 0;
        tif.slave_address = 7'h50;
        tif.data_in = 12'h000;
        
        repeat(10) @(posedge tif.clk);
        tif.rst_n = 1;
        repeat(10) @(posedge tif.clk);
        
        // Run test
        env.run();
        
        $display("\n======================================================================");
        $display("              I2C TEST COMPLETE");
        $display("======================================================================");
        env.report();
        
        $finish;
    end
endprogram

// Top-level Testbench
module I2C_tb;
    logic clk;
    
    // 10ns clock period (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Interface
    i2c_if i2c_if_inst(clk);
    
    // Pullup resistors (required for I2C)
    pullup(i2c_if_inst.scl);
    pullup(i2c_if_inst.sda);
    
    // Master instance
    master #(.DIVIDER(10)) master_inst (
        .clk(i2c_if_inst.clk),
        .rst_n(i2c_if_inst.rst_n),
        .start(i2c_if_inst.start),
        .rw(i2c_if_inst.rw),
        .slave_address(i2c_if_inst.slave_address),
        .data_in(i2c_if_inst.data_in),
        .busy(i2c_if_inst.busy),
        .ack_error(i2c_if_inst.ack_error),
        .data_out(i2c_if_inst.data_out),
        .scl(i2c_if_inst.scl),
        .sda(i2c_if_inst.sda)
    );
    
    // Slave instance
    slave #(.SLAVE_ADDR(7'h50)) slave_inst (
        .clk(i2c_if_inst.clk),
        .rst_n(i2c_if_inst.rst_n),
        .scl(i2c_if_inst.scl),
        .sda(i2c_if_inst.sda),
        .rx_data(i2c_if_inst.slave_rx_data),
        .data_valid(i2c_if_inst.slave_data_valid)
    );
    
    // Test program
    i2c_test test_inst(i2c_if_inst);
    
    // Timeout watchdog
    initial begin
        #5000000;  // 5ms timeout
        $display("\nERROR: Testbench timeout!");
        $finish;
    end
    

endmodule
