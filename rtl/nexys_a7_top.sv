module nexys_a7_top (
    input  logic        CLK100MHZ,
    input  logic        BTNC,
    input  logic        BTNU,
    input  logic [7:0]  SW,
    output logic [15:0] LED
);

    logic reset;

    logic [7:0] pipeline_data_in;
    logic       pipeline_data_valid;
    logic       pipeline_data_ready;

    logic [7:0] pipeline_data_out;
    logic       pipeline_output_valid;
    logic       pipeline_output_ready;

    logic [7:0] received_data;

    logic btn_meta;
    logic btn_sync;
    logic btn_sync_d;

    logic send_pending;
    logic send_pressed;

    logic send_seen;
    logic receive_seen;

    assign reset = BTNC;
    assign pipeline_output_ready = 1'b1;

    nrz_pipeline #(
        .DATA_WIDTH(8),
        .CLK_HZ(100_000_000),
        .BIT_RATE(1_000_000)
    ) u_pipeline (
        .clk(CLK100MHZ),
        .reset(reset),

        .data_in(pipeline_data_in),
        .data_valid(pipeline_data_valid),
        .data_ready(pipeline_data_ready),

        .data_out(pipeline_data_out),
        .output_valid(pipeline_output_valid),
        .output_ready(pipeline_output_ready)
    );

    // Synchronize send button
    always_ff @(posedge CLK100MHZ) begin
        if (reset) begin
            btn_meta   <= 1'b0;
            btn_sync   <= 1'b0;
            btn_sync_d <= 1'b0;
        end
        else begin
            btn_meta   <= BTNU;
            btn_sync   <= btn_meta;
            btn_sync_d <= btn_sync;
        end
    end

    assign send_pressed = btn_sync && !btn_sync_d;

    // Convert button edge into ready/valid request
    always_ff @(posedge CLK100MHZ) begin
        if (reset) begin
            send_pending     <= 1'b0;
            pipeline_data_in <= '0;
        end
        else begin
            if (send_pressed && !send_pending) begin
                pipeline_data_in <= SW;
                send_pending     <= 1'b1;
            end
            else if (send_pending && pipeline_data_ready) begin
                send_pending <= 1'b0;
            end
        end
    end

    assign pipeline_data_valid = send_pending;

    // Latch received byte
    always_ff @(posedge CLK100MHZ) begin
        if (reset) begin
            received_data <= '0;
        end
        else if (pipeline_output_valid && pipeline_output_ready) begin
            received_data <= pipeline_data_out;
        end
    end

    // Sticky debug indicators
    always_ff @(posedge CLK100MHZ) begin
        if (reset) begin
            send_seen    <= 1'b0;
            receive_seen <= 1'b0;
        end
        else begin
            if (send_pressed)
                send_seen <= 1'b1;

            if (pipeline_output_valid && pipeline_output_ready)
                receive_seen <= 1'b1;
        end
    end

    assign LED[7:0]  = received_data;
    assign LED[8]    = send_seen;
    assign LED[9]    = receive_seen;
    assign LED[15:10] = '0;

endmodule