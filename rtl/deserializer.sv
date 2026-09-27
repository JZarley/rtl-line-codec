module deserializer #(
    parameter int DATA_WIDTH = 8
)(
    input logic clk,
    input logic reset,

    input logic bit_in,
    input logic bit_valid,
    output logic bit_ready,

    output logic [DATA_WIDTH-1:0] data_out,
    output logic data_valid,
    input logic data_ready
);

    localparam int INDEX_WIDTH = (DATA_WIDTH <= 1) ? 1 : $clog2(DATA_WIDTH);

    logic [DATA_WIDTH-1:0] data_reg;
    logic [INDEX_WIDTH-1:0] index;

    always_ff @(posedge clk) begin
        if (reset) begin
            index <= '0;
            data_valid <= 1'b0;
        end
        else begin
            // If we don't have any room left, try to push data downstream
            if (data_valid) begin
                if (data_ready) begin
                    index <= '0;
                    data_valid <= 1'b0;
                end
            end

            // If we do have room and upstream is valid, a handshake occurs
            else if (bit_valid) begin

                // Store the current bit (MSB-first)
                data_reg[DATA_WIDTH - 1 - index] <= bit_in;

                // If we're at the last bit of data, the word is complete
                if (index == DATA_WIDTH - 1) begin
                    data_valid <= 1'b1;
                end

                // If we aren't at the last bit of data, increment the index
                else begin
                    index <= index + 1'b1;
                end
            end
        end
    end
    
    assign data_out = data_reg;
    assign bit_ready = !reset && (!data_valid || data_ready);

endmodule