`timescale 1ns/1ps

module sync_fifo #(
    parameter int DATA_WIDTH = 8,
    parameter int DATA_DEPTH = 32
)(
    input logic clk,
    input logic reset,

    input logic [DATA_WIDTH-1:0] input_data,
    input logic input_valid,
    output logic input_ready,

    output logic [DATA_WIDTH-1:0] output_data,
    output logic output_valid,
    input logic output_ready
);

    localparam int PTR_WIDTH = (DATA_DEPTH <= 1) ? 1 : $clog2(DATA_DEPTH);
    localparam int COUNT_WIDTH = (DATA_DEPTH <= 1) ? 1 : $clog2(DATA_DEPTH + 1);
    localparam logic [COUNT_WIDTH-1:0] DEPTH_COUNT = COUNT_WIDTH'(DATA_DEPTH);

    logic [DATA_WIDTH-1:0] regs [0:DATA_DEPTH-1];

    logic [PTR_WIDTH-1:0] read_ptr;
    logic [PTR_WIDTH-1:0] write_ptr;
    logic [COUNT_WIDTH-1:0] counter;

    logic full, empty;
    assign full = counter == DEPTH_COUNT;
    assign empty = counter == '0;

    logic handshake_out, handshake_in;
    assign handshake_out = output_valid && output_ready;
    assign handshake_in = input_valid && input_ready;

    assign output_data = (counter == '0) ? input_data : regs[read_ptr];
    assign output_valid = !empty || input_valid; // input ready is implied by empty, input_valid is equivalent to handshake_in
    assign input_ready = !full || handshake_out;

    function automatic logic [PTR_WIDTH-1:0] next_ptr(
        input logic [PTR_WIDTH-1:0] ptr
    );
        if (ptr == PTR_WIDTH'(DATA_DEPTH-1)) begin
            next_ptr = '0;
        end
        else begin
            next_ptr = ptr + PTR_WIDTH'(1);
        end
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            counter <= '0;
            read_ptr <= '0;
            write_ptr <= '0; // note: could set read ptr to write_ptr or vice versa, but this seems equivalently complex hardware-wise and more clear
        end
        else begin
            case ({handshake_out, handshake_in})
                2'b01: begin
                    regs[write_ptr] <= input_data;
                    write_ptr <= next_ptr(write_ptr);
                    counter <= counter + COUNT_WIDTH'(1);
                end
                2'b10: begin
                    read_ptr <= next_ptr(read_ptr);
                    counter <= counter - COUNT_WIDTH'(1);
                end
                2'b11:
                    if (!empty) begin
                        regs[write_ptr] <= input_data;
                        read_ptr <= next_ptr(read_ptr);
                        write_ptr <= next_ptr(write_ptr);
                    end
                default: ;
            endcase
        end
    end

endmodule
