module serializer #(
    parameter int DATA_WIDTH = 8
)(
    input logic clk,
    input logic reset,

    input logic [DATA_WIDTH-1:0] data_in,
    input logic data_valid,
    output logic data_ready,

    output logic bit_out,
    output logic bit_valid,
    input logic bit_ready
);

    localparam int INDEX_WIDTH = (DATA_WIDTH <= 1) ? 1 : $clog2(DATA_WIDTH);

    logic [DATA_WIDTH-1:0] data_reg;
    logic [INDEX_WIDTH-1:0] index;

    always_ff @(posedge clk) begin
        if (reset) begin
            index <= '0;
            bit_valid <= 1'b0;
        end
        else begin
            // If we don't have any new data, take data if it's valid
            if (!bit_valid) begin
                if (data_valid) begin
                    data_reg <= data_in;
                    index <= '0;
                    bit_valid <= 1'b1;
                end
            end
            // If we do have data and downstream is ready, a handshake occurs
            else if (bit_ready) begin
                // If we're at the last bit of data, try to load more data
                if (index == DATA_WIDTH - 1) begin
                    // If the input data is valid, take it
                    if (data_valid) begin
                        data_reg <= data_in;
                        index <= '0;
                        bit_valid <= 1'b1;
                    end
                    // Else, we aren't busy.
                    else begin
                        bit_valid <= 1'b0;
                    end
                end
                // If we aren't the last bit of data, the index should just increment
                else begin
                    index <= index + 1'b1;
                end
            end
        end
    end

    assign bit_out = data_reg[DATA_WIDTH - 1 - index]; // MSB-first
    assign data_ready = !reset &&
                        (!bit_valid || 
                        (bit_ready && 
                        (index == DATA_WIDTH - 1)));
endmodule