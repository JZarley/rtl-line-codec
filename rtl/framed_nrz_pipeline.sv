`timescale 1ns/1ps

module framed_nrz_pipeline #(
    parameter int DATA_WIDTH = 8,
    parameter int CLK_HZ     = 100_000_000,
    parameter int BIT_RATE   = 1_000_000
)(
    input logic clk,
    input logic reset,

    // ------------------------------------------------------------
    // TX frame descriptor
    // ------------------------------------------------------------

    input  logic       tx_frame_start,
    output logic       tx_frame_start_ready,

    input  logic [7:0] tx_frame_type,
    input  logic [7:0] tx_seq,
    input  logic [7:0] tx_payload_length,

    // ------------------------------------------------------------
    // TX payload stream
    // ------------------------------------------------------------

    input  logic [7:0] tx_payload_data,
    input  logic       tx_payload_valid,
    output logic       tx_payload_ready,

    // ------------------------------------------------------------
    // RX frame descriptor
    // ------------------------------------------------------------

    output logic       rx_frame_start,
    input  logic       rx_frame_start_ready,

    output logic [7:0] rx_frame_type,
    output logic [7:0] rx_seq,
    output logic [7:0] rx_payload_length,

    // ------------------------------------------------------------
    // RX payload stream
    // ------------------------------------------------------------

    output logic [7:0] rx_payload_data,
    output logic       rx_payload_valid,
    input  logic       rx_payload_ready
);

    // ------------------------------------------------------------
    // Framer -> NRZ pipeline byte stream
    // ------------------------------------------------------------

    logic [7:0] framed_data;
    logic       framed_valid;
    logic       framed_ready;

    // ------------------------------------------------------------
    // NRZ pipeline -> deframer byte stream
    // ------------------------------------------------------------

    logic [7:0] received_data;
    logic       received_valid;
    logic       received_ready;


    // ============================================================
    // TX framer
    // ============================================================

    framer tx_framer (
        .clk               (clk),
        .reset             (reset),

        .frame_start       (tx_frame_start),
        .frame_start_ready (tx_frame_start_ready),

        .frame_type        (tx_frame_type),
        .seq               (tx_seq),
        .payload_length    (tx_payload_length),

        .payload_data      (tx_payload_data),
        .payload_valid     (tx_payload_valid),
        .payload_ready     (tx_payload_ready),

        .frame_data        (framed_data),
        .frame_valid       (framed_valid),
        .frame_ready       (framed_ready)
    );


    // ============================================================
    // Existing byte -> NRZ -> byte pipeline
    // ============================================================

    nrz_pipeline #(
        .DATA_WIDTH (DATA_WIDTH),
        .CLK_HZ     (CLK_HZ),
        .BIT_RATE   (BIT_RATE)
    ) transport (
        .clk          (clk),
        .reset        (reset),

        .data_in      (framed_data),
        .data_valid   (framed_valid),
        .data_ready   (framed_ready),

        .data_out     (received_data),
        .output_valid (received_valid),
        .output_ready (received_ready)
    );


    // ============================================================
    // RX deframer
    // ============================================================

    deframer rx_deframer (
        .clk               (clk),
        .reset             (reset),

        .input_data        (received_data),
        .input_valid       (received_valid),
        .input_ready       (received_ready),

        .frame_start       (rx_frame_start),
        .frame_start_ready (rx_frame_start_ready),

        .frame_type        (rx_frame_type),
        .seq               (rx_seq),
        .payload_length    (rx_payload_length),

        .payload_data      (rx_payload_data),
        .payload_valid     (rx_payload_valid),
        .payload_ready     (rx_payload_ready)
    );

endmodule
