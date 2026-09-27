`timescale 1ns / 1ps

module nrz_decoder #(
    parameter logic DEFAULT_OUT = 1'b0
)(
    input logic clk,
    input logic reset, 

    input logic bit_tick,

    input logic encoded_in,

    output logic data_valid,
    output logic data_out
);

    always_ff @(posedge clk) begin
        if (reset) begin
            data_valid <= 1'b0;
            data_out <= DEFAULT_OUT;
        end
        else begin
            data_valid <= 1'b0;
            if (bit_tick) begin
                data_out <= encoded_in;
                data_valid <= 1'b1;
            end
        end
    end

endmodule
