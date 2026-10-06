`timescale 1ns/1ps

module nrz_pipeline #(
    parameter int DATA_WIDTH = 8,
    parameter int CLK_HZ = 100_000_000,
    parameter int BIT_RATE = 1_000_000
)(
    input logic clk,
    input logic reset,

    input logic [DATA_WIDTH-1:0] data_in,
    input logic data_valid,
    output logic data_ready,

    output logic [DATA_WIDTH-1:0] data_out,
    output logic output_valid,
    input logic output_ready
);

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
    /* verilator lint_off UNUSEDSIGNAL */
    logic decoded_ready;
    /* verilator lint_on UNUSEDSIGNAL */

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
    // NOT REAL RX TIMING RECOVERY
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
        .DEFAULT_OUT(1'b0)
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
        .DEFAULT_OUT(1'b0)
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
endmodule
