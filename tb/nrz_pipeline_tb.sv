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

    // Serializer
    logic serialized_bit;
    logic serialized_valid;
    logic serialized_ready;

    // Timing
    logic tx_bit_tick;
    logic rx_bit_tick;

    // Physical line
    logic encoded_line;

    // Decoder
    logic decoded_bit;
    logic decoded_valid;
    logic decoded_ready;

    // Word output
    logic [DATA_WIDTH-1:0] data_out;
    logic output_valid;
    logic output_ready;

    // Reference model
    logic [DATA_WIDTH-1:0] expected_queue[$];
    logic [DATA_WIDTH-1:0] expected_word;

    // Clock -----------------------------------------------------
    initial clk = 1'b0;
    always #5 clk <= ~clk; // Period of 10 ns, 100 MHz
    
    // Timing -----------------------------------------------------
    bit_tick_gen #(
        .CLK_HZ(CLK_HZ),
        .BIT_RATE(BIT_RATE)
    ) tx_bit_tick_gen (
        .clk(clk),
        .reset(reset),

        .bit_tick(tx_bit_tick)
    );

    // For initial testing, the encoded result will be sampled 1 clock cycle behind the transmitter's bit tick
    always_ff @(posedge clk) begin
        if (reset) begin
            rx_bit_tick <= 1'b0;
        end
        else begin
            rx_bit_tick <= tx_bit_tick;
        end
    end
    
    // Serializer -----------------------------------------------------
    serializer #(
        .DATA_WIDTH(DATA_WIDTH)
    ) serializer (
        .clk(clk),
        .reset(reset),

        .data_in(data_in),
        .data_valid(data_valid),
        .data_ready(data_ready),

        .bit_out(serialized_bit),
        .bit_valid(serialized_valid),
        .bit_ready(serialized_ready)
    );

    // Encoder -----------------------------------------------------
    nrz_encoder #(
        .DEFAULT_OUT(0)
    ) encoder (
        .clk(clk),
        .reset(reset),

        .bit_tick(tx_bit_tick),

        .data_valid(serialized_valid),
        .data_in(serialized_bit),
        .data_ready(serialized_ready),

        .encoded_out(encoded_line)
    );
    
    // Decoder -----------------------------------------------------
    nrz_decoder #(
        .DEFAULT_OUT(0)
    ) decoder (
        .clk(clk),
        .reset(reset),

        .bit_tick(rx_bit_tick),

        .encoded_in(encoded_line),

        .data_valid(decoded_valid),
        .data_out(decoded_bit)
    );

    // Deserializer -----------------------------------------------------
    deserializer #(
        .DATA_WIDTH(DATA_WIDTH)
    ) deserializer (
        .clk(clk),
        .reset(reset),

        .bit_in(decoded_bit),
        .bit_valid(decoded_valid),
        .bit_ready(decoded_ready),

        .data_out(data_out),
        .data_valid(output_valid),
        .data_ready(output_ready)
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

            expected_word <= expected_queue.pop_front();

            assert (data_out === expected_word) // Account for unknown/high-impedance bits
            else $fatal(1, "Mismatch: expected 0x%0h, received 0x%0h", expected_word, data_out);
        end
    end

    // Verify some decoder -> deserializer behavior
    always @(posedge clk) begin
        if (!reset && decoded_valid) begin
            assert (decoded_ready)
            else $fatal(
                1, "Deserializer recieved bit while unable to accept it");
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
