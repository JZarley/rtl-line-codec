module nexys_a7_top (
    input  logic        CLK100MHZ,
    input  logic        BTNC,
    input  logic        BTNU,
    input  logic [7:0]  SW,
    output logic [15:0] LED
);

    logic reset;

    // TX descriptor
    logic       tx_frame_start;
    logic       tx_frame_start_ready;
    logic [7:0] tx_frame_type;
    logic [7:0] tx_seq;
    logic [7:0] tx_payload_length;

    // TX payload
    logic [7:0] tx_payload_data;
    logic       tx_payload_valid;
    logic       tx_payload_ready;

    // RX descriptor
    logic       rx_frame_start;
    logic       rx_frame_start_ready;
    logic [7:0] rx_frame_type;
    logic [7:0] rx_seq;
    logic [7:0] rx_payload_length;

    // RX payload
    logic [7:0] rx_payload_data;
    logic       rx_payload_valid;
    logic       rx_payload_ready;

    logic [7:0] received_data;

    logic btn_meta;
    logic btn_sync;
    logic btn_sync_d;

    typedef enum logic [1:0] {
        IDLE,
        SEND_DESCRIPTOR,
        SEND_PAYLOAD
    } tx_state_t;

    tx_state_t tx_state;

    logic [7:0] pending_payload;
    logic [7:0] sequence_counter;
    logic [7:0] pending_sequence;
    logic send_pressed;

    logic tx_descriptor_seen;
    logic tx_payload_seen;
    logic rx_descriptor_seen;
    logic rx_payload_seen;

    assign reset = BTNC;
    assign rx_frame_start_ready = 1'b1;
    assign rx_payload_ready     = 1'b1;

    framed_nrz_pipeline #(
        .DATA_WIDTH(8),
        .CLK_HZ(100_000_000),
        .BIT_RATE(1_000_000),
        .RX_FIFO_DEPTH(32)
    ) u_pipeline (
        .clk(CLK100MHZ),
        .reset(reset),

        .tx_frame_start(tx_frame_start),
        .tx_frame_start_ready(tx_frame_start_ready),
        .tx_frame_type(tx_frame_type),
        .tx_seq(tx_seq),
        .tx_payload_length(tx_payload_length),

        .tx_payload_data(tx_payload_data),
        .tx_payload_valid(tx_payload_valid),
        .tx_payload_ready(tx_payload_ready),
        
        .rx_frame_start(rx_frame_start),
        .rx_frame_start_ready(rx_frame_start_ready),
        .rx_frame_type(rx_frame_type),
        .rx_seq(rx_seq),
        .rx_payload_length(rx_payload_length),
        
        .rx_payload_data(rx_payload_data),
        .rx_payload_valid(rx_payload_valid),
        .rx_payload_ready(rx_payload_ready)
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

    assign tx_frame_type     = 8'h01;  // DATA
    assign tx_payload_length = 8'd1;

    assign tx_seq          = pending_sequence;
    assign tx_payload_data = pending_payload;

    assign tx_frame_start  = (tx_state == SEND_DESCRIPTOR);
    assign tx_payload_valid = (tx_state == SEND_PAYLOAD);   

    always_ff @(posedge CLK100MHZ) begin
        if (reset) begin
            tx_state         <= IDLE;
            pending_payload  <= '0;
            pending_sequence <= '0;
            sequence_counter <= '0;
        end
        else begin
            case (tx_state)

                IDLE: begin
                    if (send_pressed) begin
                        pending_payload  <= SW;
                        pending_sequence <= sequence_counter;
                        tx_state         <= SEND_DESCRIPTOR;
                    end
                end

                SEND_DESCRIPTOR: begin
                    if (tx_frame_start_ready) begin
                        tx_state <= SEND_PAYLOAD;
                    end
                end

                SEND_PAYLOAD: begin
                    if (tx_payload_ready) begin
                        sequence_counter <= sequence_counter + 8'd1;
                        tx_state         <= IDLE;
                    end
                end

                default: begin
                    tx_state <= IDLE;
                end

            endcase
        end
    end

    // Latch received byte
    always_ff @(posedge CLK100MHZ) begin
        if (reset) begin
            received_data <= '0;
        end
        else if (rx_payload_valid && rx_payload_ready) begin
            received_data <= rx_payload_data;
        end
    end

    always_ff @(posedge CLK100MHZ) begin
        if (reset) begin
            tx_descriptor_seen <= 1'b0;
            tx_payload_seen    <= 1'b0;
            rx_descriptor_seen <= 1'b0;
            rx_payload_seen    <= 1'b0;
        end
        else begin
            if (tx_frame_start && tx_frame_start_ready)
                tx_descriptor_seen <= 1'b1;

            if (tx_payload_valid && tx_payload_ready)
                tx_payload_seen <= 1'b1;

            if (rx_frame_start && rx_frame_start_ready)
                rx_descriptor_seen <= 1'b1;

            if (rx_payload_valid && rx_payload_ready)
                rx_payload_seen <= 1'b1;
        end
    end

    assign LED[7:0]   = received_data;

    assign LED[8]     = tx_descriptor_seen;
    assign LED[9]     = tx_payload_seen;
    assign LED[10]    = rx_descriptor_seen;
    assign LED[11]    = rx_payload_seen;

    assign LED[15:12] = '0;

endmodule