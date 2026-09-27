`timescale 1ns / 1ps

module bit_tick_gen #(
    parameter int CLK_HZ = 100_000_000,
    parameter int BIT_RATE = 1_000_000
)(
    input logic clk,
    input logic reset,

    output logic bit_tick
);

    // IMPORTANT: Assumes CLK_HZ / BIT_RATE has no remainder
    // Eventually, should enforce or implement workaround
    
    localparam int CYCLES_PER_BIT = CLK_HZ / BIT_RATE;
    localparam int COUNT_WIDTH = (CYCLES_PER_BIT <= 1) ? 1 : $clog2(CYCLES_PER_BIT);

    logic [COUNT_WIDTH-1:0] count;

    always_ff @(posedge clk) begin
        if (reset) begin
            count <= '0;
            bit_tick <= 1'b0;
        end
        else begin
            bit_tick <= 1'b0;
            
            if (int'(count) == CYCLES_PER_BIT - 1) begin
                count <= '0;
                bit_tick <= 1'b1;
            end
            else begin
                count <= count + 1'b1;
            end
        end
    end
endmodule
