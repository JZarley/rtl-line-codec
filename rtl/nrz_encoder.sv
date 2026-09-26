module nrz_encoder #(
    parameter logic DEFAULT_OUT = 1'b0
)(
    input logic clk,
    input logic reset,

    input logic bit_tick,

    input logic data_valid,
    input logic data_in,

    output logic data_ready,
    output logic encoded_out
);

    always_ff @(posedge clk) begin
        if (reset) begin
            encoded_out <= DEFAULT_OUT;
        end
        else begin
            if (bit_tick) begin
                if (data_valid) begin
                    encoded_out <= data_in;
                end
            end
        end
    end

    assign data_ready = bit_tick && !reset;

endmodule