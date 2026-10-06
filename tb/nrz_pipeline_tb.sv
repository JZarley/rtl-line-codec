`timescale 1ns / 1ps

module nrz_pipeline_tb;

    localparam int DATA_WIDTH = 8;
    localparam int CLK_HZ = 100_000_000;
    localparam int BIT_RATE = 1_000_000;

    // Clock / Reset
    logic clk;
    logic reset;
    
    // Word input
    logic [DATA_WIDTH-1:0] data_in;
    logic data_valid;
    logic data_ready;

    // Word output
    logic [DATA_WIDTH-1:0] data_out;
    logic output_valid;
    logic output_ready;

    // Reference model
    logic [DATA_WIDTH-1:0] expected_queue[$];
    
    // Clock -----------------------------------------------------
    initial clk = 1'b0;
    always #5 clk <= ~clk; // Period of 10 ns, 100 MHz
    
    // DUT -----------------------------------------------------
    nrz_pipeline #(
        .DATA_WIDTH(DATA_WIDTH),
        .CLK_HZ(CLK_HZ),
        .BIT_RATE(BIT_RATE)
    ) dut (
        .clk(clk),
        .reset(reset),

        .data_in(data_in),
        .data_valid(data_valid),
        .data_ready(data_ready),

        .data_out(data_out),
        .output_valid(output_valid),
        .output_ready(output_ready)
    );

    // Send a word
    task automatic send_word(
        input logic [DATA_WIDTH-1:0] word
    );
        begin
            @(negedge clk);

            data_in = word;
            data_valid = 1'b1;

            do begin
                @(posedge clk);
            end while (!data_ready);

            expected_queue.push_back(word);

            @(negedge clk);
            data_valid = 1'b0;
        end
    endtask

    // Reference queue checks itself whenever an output handshake occurs
    always @(posedge clk) begin
        if (!reset && output_valid && output_ready) begin
            
            assert (expected_queue.size() > 0)
            else $fatal(1, "Received unexpected word: 0x%0h", data_out);

            assert (data_out === expected_queue[0]) // Account for unknown/high-impedance bits
            else $fatal(1, "Mismatch: expected 0x%0h, received 0x%0h", expected_queue[0], data_out);

            expected_queue.pop_front();
        end
    end

    initial begin
        reset = 1'b1;
        data_in = '0;
        data_valid = 1'b0;
        output_ready = 1'b1;

        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        send_word(8'h00);
        send_word(8'hFF);
        send_word(8'hA2);
        send_word(8'h2A);
        send_word(8'hCD);
        send_word(8'h99);

        wait (expected_queue.size() == 0);

        $display("PASS: NRZ pipeline test complete.");
        $finish;
    end

endmodule
