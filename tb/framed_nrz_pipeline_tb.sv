`timescale 1ns/1ps

module framed_nrz_pipeline_tb;

    localparam int CLK_HZ   = 100_000_000;
    localparam int BIT_RATE = 25_000_000;

    localparam logic [7:0] FRAME_TYPE_DATA     = 8'h01;
    localparam logic [7:0] FRAME_TYPE_ACK      = 8'h02;
    localparam logic [7:0] FRAME_TYPE_DATA_ACK = 8'h03;
    localparam logic [7:0] FRAME_TYPE_CONTROL  = 8'h04;


    // ============================================================
    // DUT signals
    // ============================================================

    logic clk;
    logic reset;

    logic       tx_frame_start;
    logic       tx_frame_start_ready;

    logic [7:0] tx_frame_type;
    logic [7:0] tx_seq;
    logic [7:0] tx_payload_length;

    logic [7:0] tx_payload_data;
    logic       tx_payload_valid;
    logic       tx_payload_ready;

    logic       rx_frame_start;
    logic       rx_frame_start_ready;

    logic [7:0] rx_frame_type;
    logic [7:0] rx_seq;
    logic [7:0] rx_payload_length;

    logic [7:0] rx_payload_data;
    logic       rx_payload_valid;
    logic       rx_payload_ready;

    logic randomize_rx_backpressure;

    integer descriptor_ready_hold;
    integer payload_ready_hold;


    // ============================================================
    // Expected-output queues
    // ============================================================

    logic [7:0] expected_type_queue[$];
    logic [7:0] expected_seq_queue[$];
    logic [7:0] expected_length_queue[$];

    logic [7:0] expected_payload_queue[$];


    // ============================================================
    // DUT
    // ============================================================

    framed_nrz_pipeline #(
        .DATA_WIDTH (8),
        .CLK_HZ     (CLK_HZ),
        .BIT_RATE   (BIT_RATE)
    ) dut (
        .*
    );


    // ============================================================
    // Clock
    // ============================================================

    initial clk = 1'b0;

    always #5 clk <= ~clk;


    // ============================================================
    // Randomized RX backpressure
    //
    // When enabled, descriptor and payload ready each remain in a
    // randomly-selected state for multiple cycles. Long hold periods
    // are intentional so stalls last long enough for bytes to build
    // up in the RX FIFO.
    // ============================================================

    always @(negedge clk) begin
        if (reset || !randomize_rx_backpressure) begin
            rx_frame_start_ready <= 1'b1;
            rx_payload_ready     <= 1'b1;

            descriptor_ready_hold <= 0;
            payload_ready_hold    <= 0;
        end
        else begin

            // Descriptor consumer
            if (descriptor_ready_hold == 0) begin

                // Ready about 65% of randomly-selected intervals.
                rx_frame_start_ready <=
                    ($urandom_range(99, 0) < 65);

                descriptor_ready_hold <=
                    $urandom_range(200, 10);
            end
            else begin
                descriptor_ready_hold <=
                    descriptor_ready_hold - 1;
            end


            // Payload consumer
            if (payload_ready_hold == 0) begin

                // Ready about 65% of randomly-selected intervals.
                rx_payload_ready <=
                    ($urandom_range(99, 0) < 65);

                payload_ready_hold <=
                    $urandom_range(200, 10);
            end
            else begin
                payload_ready_hold <=
                    payload_ready_hold - 1;
            end
        end
    end


    // ============================================================
    // RX descriptor scoreboard
    // ============================================================

    always @(posedge clk) begin
        if (!reset &&
            rx_frame_start &&
            rx_frame_start_ready) begin

            assert (
                expected_type_queue.size() > 0 &&
                expected_seq_queue.size() > 0 &&
                expected_length_queue.size() > 0
            )
                else $fatal(
                    1,
                    "Unexpected RX descriptor: type=%02h seq=%02h length=%0d",
                    rx_frame_type,
                    rx_seq,
                    rx_payload_length
                );

            assert (
                rx_frame_type === expected_type_queue[0]
            )
                else $fatal(
                    1,
                    "RX type mismatch: expected %02h, got %02h",
                    expected_type_queue[0],
                    rx_frame_type
                );

            assert (
                rx_seq === expected_seq_queue[0]
            )
                else $fatal(
                    1,
                    "RX seq mismatch: expected %02h, got %02h",
                    expected_seq_queue[0],
                    rx_seq
                );

            assert (
                rx_payload_length === expected_length_queue[0]
            )
                else $fatal(
                    1,
                    "RX length mismatch: expected %0d, got %0d",
                    expected_length_queue[0],
                    rx_payload_length
                );

            expected_type_queue.pop_front();
            expected_seq_queue.pop_front();
            expected_length_queue.pop_front();
        end
    end


    // ============================================================
    // RX payload scoreboard
    // ============================================================

    always @(posedge clk) begin
        if (!reset &&
            rx_payload_valid &&
            rx_payload_ready) begin

            assert (expected_payload_queue.size() > 0)
                else $fatal(
                    1,
                    "Unexpected RX payload byte %02h",
                    rx_payload_data
                );

            assert (
                rx_payload_data === expected_payload_queue[0]
            )
                else $fatal(
                    1,
                    "RX payload mismatch: expected %02h, got %02h",
                    expected_payload_queue[0],
                    rx_payload_data
                );

            expected_payload_queue.pop_front();
        end
    end


    // ============================================================
    // RX descriptor stability monitor
    // ============================================================

    logic       descriptor_stalled_last_cycle;
    logic [7:0] stalled_rx_type;
    logic [7:0] stalled_rx_seq;
    logic [7:0] stalled_rx_length;

    always_ff @(posedge clk) begin
        if (reset) begin
            descriptor_stalled_last_cycle <= 1'b0;

            stalled_rx_type   <= '0;
            stalled_rx_seq    <= '0;
            stalled_rx_length <= '0;
        end
        else begin

            if (descriptor_stalled_last_cycle) begin
                assert (rx_frame_start)
                    else $fatal(
                        1,
                        "RX frame_start dropped while stalled"
                    );

                assert (rx_frame_type === stalled_rx_type)
                    else $fatal(
                        1,
                        "RX frame type changed while stalled"
                    );

                assert (rx_seq === stalled_rx_seq)
                    else $fatal(
                        1,
                        "RX sequence changed while stalled"
                    );

                assert (
                    rx_payload_length === stalled_rx_length
                )
                    else $fatal(
                        1,
                        "RX payload length changed while stalled"
                    );
            end

            descriptor_stalled_last_cycle <=
                rx_frame_start && !rx_frame_start_ready;

            if (rx_frame_start &&
                !rx_frame_start_ready) begin

                stalled_rx_type   <= rx_frame_type;
                stalled_rx_seq    <= rx_seq;
                stalled_rx_length <= rx_payload_length;
            end
        end
    end


    // ============================================================
    // RX payload stability monitor
    // ============================================================

    logic       payload_stalled_last_cycle;
    logic [7:0] stalled_rx_payload;

    always_ff @(posedge clk) begin
        if (reset) begin
            payload_stalled_last_cycle <= 1'b0;
            stalled_rx_payload         <= '0;
        end
        else begin

            if (payload_stalled_last_cycle) begin
                assert (rx_payload_valid)
                    else $fatal(
                        1,
                        "RX payload_valid dropped while stalled"
                    );

                assert (
                    rx_payload_data === stalled_rx_payload
                )
                    else $fatal(
                        1,
                        "RX payload_data changed while stalled"
                    );
            end

            payload_stalled_last_cycle <=
                rx_payload_valid && !rx_payload_ready;

            if (rx_payload_valid &&
                !rx_payload_ready) begin

                stalled_rx_payload <= rx_payload_data;
            end
        end
    end


    // ============================================================
    // Helpers
    // ============================================================

    task automatic clear_expected;
        begin
            expected_type_queue.delete();
            expected_seq_queue.delete();
            expected_length_queue.delete();
            expected_payload_queue.delete();
        end
    endtask


    task automatic expect_frame(
        input logic [7:0] type_value,
        input logic [7:0] seq_value,
        input logic [7:0] length_value
    );
        begin
            expected_type_queue.push_back(type_value);
            expected_seq_queue.push_back(seq_value);
            expected_length_queue.push_back(length_value);
        end
    endtask


    task automatic apply_reset;
        begin
            clear_expected();

            @(negedge clk);

            reset = 1'b1;

            tx_frame_start   = 1'b0;
            tx_payload_valid = 1'b0;

            randomize_rx_backpressure = 1'b0;

            repeat (3) @(posedge clk);

            @(negedge clk);

            reset = 1'b0;

            repeat (2) @(posedge clk);
        end
    endtask


    // ------------------------------------------------------------
    // Accept one TX frame descriptor.
    // ------------------------------------------------------------

    task automatic start_tx_frame(
        input logic [7:0] type_value,
        input logic [7:0] seq_value,
        input logic [7:0] length_value
    );
        begin
            expect_frame(
                type_value,
                seq_value,
                length_value
            );

            @(negedge clk);

            tx_frame_type     = type_value;
            tx_seq            = seq_value;
            tx_payload_length = length_value;
            tx_frame_start    = 1'b1;

            while (!tx_frame_start_ready) begin
                @(negedge clk);
            end

            @(posedge clk);

            @(negedge clk);

            tx_frame_start = 1'b0;
        end
    endtask


    // ------------------------------------------------------------
    // Send one TX payload byte.
    // ------------------------------------------------------------

    task automatic send_tx_payload_byte(
        input logic [7:0] value
    );
        begin
            expected_payload_queue.push_back(value);

            @(negedge clk);

            tx_payload_data  = value;
            tx_payload_valid = 1'b1;

            while (!tx_payload_ready) begin
                @(negedge clk);
            end

            @(posedge clk);

            @(negedge clk);

            tx_payload_valid = 1'b0;
        end
    endtask


    // ------------------------------------------------------------
    // Randomized source timing.
    // ------------------------------------------------------------

    task automatic send_tx_payload_byte_random(
        input logic [7:0] value
    );
        integer gap_cycles;
        integer timeout;

        begin
            expected_payload_queue.push_back(value);

            gap_cycles = $urandom_range(5, 0);

            repeat (gap_cycles) begin
                @(negedge clk);
                tx_payload_valid = 1'b0;
            end

            @(negedge clk);

            tx_payload_data  = value;
            tx_payload_valid = 1'b1;

            timeout = 0;

            while (!tx_payload_ready) begin
                @(negedge clk);

                timeout = timeout + 1;

                if (timeout > 5000) begin
                    $fatal(
                        1,
                        "TX payload transfer timed out"
                    );
                end
            end

            @(posedge clk);

            @(negedge clk);

            tx_payload_valid = 1'b0;
        end
    endtask


    // ------------------------------------------------------------
    // Wait until all expected RX information has arrived.
    // ------------------------------------------------------------

    task automatic wait_for_all_received(
        input integer timeout_cycles
    );
        integer timeout;

        begin
            timeout = 0;

            while (
                expected_type_queue.size() != 0 ||
                expected_seq_queue.size() != 0 ||
                expected_length_queue.size() != 0 ||
                expected_payload_queue.size() != 0
            ) begin

                @(posedge clk);

                timeout = timeout + 1;

                if (timeout > timeout_cycles) begin
                    $fatal(
                        1,
                        "Timed out waiting for complete frame reception: ",
                        "desc=%0d payload=%0d",
                        expected_type_queue.size(),
                        expected_payload_queue.size()
                    );
                end
            end
        end
    endtask


    task automatic verify_empty;
        begin
            assert (expected_type_queue.size() == 0)
                else $fatal(
                    1,
                    "Expected TYPE queue not empty"
                );

            assert (expected_seq_queue.size() == 0)
                else $fatal(
                    1,
                    "Expected SEQ queue not empty"
                );

            assert (expected_length_queue.size() == 0)
                else $fatal(
                    1,
                    "Expected LENGTH queue not empty"
                );

            assert (expected_payload_queue.size() == 0)
                else $fatal(
                    1,
                    "Expected payload queue not empty"
                );
        end
    endtask


    // ============================================================
    // Test sequence
    // ============================================================

    initial begin : tests

        integer i;
        integer frame_index;
        integer byte_index;

        logic [7:0] random_type;
        logic [7:0] random_seq;
        logic [7:0] random_length;
        logic [7:0] random_payload;


        // --------------------------------------------------------
        // Initial values
        // --------------------------------------------------------

        reset = 1'b0;

        tx_frame_start    = 1'b0;
        tx_frame_type     = '0;
        tx_seq            = '0;
        tx_payload_length = '0;

        tx_payload_data  = '0;
        tx_payload_valid = 1'b0;

        randomize_rx_backpressure = 1'b0;


        // --------------------------------------------------------
        // 1. Reset
        // --------------------------------------------------------

        $display("TEST 1: reset");

        apply_reset();

        assert (tx_frame_start_ready)
            else $fatal(
                1,
                "TX framer not ready after reset"
            );


        // --------------------------------------------------------
        // 2. Zero-length ACK
        // --------------------------------------------------------

        $display("TEST 2: zero-length ACK");

        start_tx_frame(
            FRAME_TYPE_ACK,
            8'h10,
            8'd0
        );

        wait_for_all_received(10000);
        verify_empty();


        // --------------------------------------------------------
        // 3. Single-byte DATA
        // --------------------------------------------------------

        $display("TEST 3: one-byte DATA");

        start_tx_frame(
            FRAME_TYPE_DATA,
            8'h11,
            8'd1
        );

        send_tx_payload_byte(8'hA5);

        wait_for_all_received(10000);
        verify_empty();


        // --------------------------------------------------------
        // 4. Multi-byte DATA
        // --------------------------------------------------------

        $display("TEST 4: multi-byte DATA");

        start_tx_frame(
            FRAME_TYPE_DATA,
            8'h12,
            8'd5
        );

        send_tx_payload_byte(8'h10);
        send_tx_payload_byte(8'h20);
        send_tx_payload_byte(8'h30);
        send_tx_payload_byte(8'h40);
        send_tx_payload_byte(8'h50);

        wait_for_all_received(20000);
        verify_empty();


        // --------------------------------------------------------
        // 5. Preamble value inside payload
        //
        // Important: 0x55 must survive the entire pipeline as data.
        // --------------------------------------------------------

        $display("TEST 5: 0x55 inside payload");

        start_tx_frame(
            FRAME_TYPE_DATA,
            8'h13,
            8'd5
        );

        send_tx_payload_byte(8'hAA);
        send_tx_payload_byte(8'h55);
        send_tx_payload_byte(8'h00);
        send_tx_payload_byte(8'h55);
        send_tx_payload_byte(8'hBB);

        wait_for_all_received(20000);
        verify_empty();


        // --------------------------------------------------------
        // 6. Different opaque frame types
        // --------------------------------------------------------

        $display("TEST 6: frame types");

        start_tx_frame(
            FRAME_TYPE_CONTROL,
            8'h20,
            8'd2
        );

        send_tx_payload_byte(8'hC1);
        send_tx_payload_byte(8'hC2);

        wait_for_all_received(10000);


        start_tx_frame(
            FRAME_TYPE_DATA_ACK,
            8'h21,
            8'd1
        );

        send_tx_payload_byte(8'hD1);

        wait_for_all_received(10000);


        // Unknown type should also survive unchanged.
        start_tx_frame(
            8'hE7,
            8'h22,
            8'd0
        );

        wait_for_all_received(10000);

        verify_empty();


        // --------------------------------------------------------
        // 7. Payload source stalls
        //
        // The TX side waits between payload bytes while the link
        // remains otherwise operational.
        // --------------------------------------------------------

        $display("TEST 7: TX payload source stalls");

        start_tx_frame(
            FRAME_TYPE_DATA,
            8'h30,
            8'd4
        );

        send_tx_payload_byte(8'h01);

        repeat (20) @(posedge clk);

        send_tx_payload_byte(8'h02);

        repeat (50) @(posedge clk);

        send_tx_payload_byte(8'h03);

        repeat (7) @(posedge clk);

        send_tx_payload_byte(8'h04);

        wait_for_all_received(20000);

        verify_empty();


        // --------------------------------------------------------
        // 8. Sequential frames
        // --------------------------------------------------------

        $display("TEST 8: sequential frames");

        for (i = 0; i < 8; i = i + 1) begin

            start_tx_frame(
                FRAME_TYPE_DATA,
                i[7:0],
                8'd3
            );

            send_tx_payload_byte(i[7:0]);
            send_tx_payload_byte(i[7:0] + 8'h40);
            send_tx_payload_byte(i[7:0] + 8'h80);
        end

        wait_for_all_received(100000);

        verify_empty();


        // --------------------------------------------------------
        // 9. Maximum payload
        // --------------------------------------------------------

        $display("TEST 9: 255-byte frame");

        start_tx_frame(
            FRAME_TYPE_DATA,
            8'hFE,
            8'hFF
        );

        for (i = 0; i < 255; i = i + 1) begin
            send_tx_payload_byte(
                i[7:0] ^ 8'hA5
            );
        end

        wait_for_all_received(500000);

        verify_empty();


        // --------------------------------------------------------
        // 10. Randomized end-to-end stress
        //
        // Randomness is applied to:
        // - type
        // - sequence
        // - length
        // - payload values
        // - TX producer timing
        // - RX descriptor backpressure
        // - RX payload backpressure
        // --------------------------------------------------------

        $display("TEST 10: randomized end-to-end stress with RX backpressure");

        randomize_rx_backpressure = 1'b1;

        for (
            frame_index = 0;
            frame_index < 50;
            frame_index = frame_index + 1
        ) begin

            random_type     = 8'($urandom_range(255, 0));
            random_seq      = 8'($urandom_range(255, 0));
            random_length   = 8'($urandom_range(20, 0));

            start_tx_frame(
                random_type,
                random_seq,
                random_length
            );

            for (
                byte_index = 0;
                byte_index < random_length;
                byte_index = byte_index + 1
            ) begin

                random_payload =
                    8'($urandom_range(255, 0));

                send_tx_payload_byte_random(
                    random_payload
                );
            end
        end

        wait_for_all_received(500000);

        verify_empty();

        randomize_rx_backpressure = 1'b0;
        @(negedge clk);


        // --------------------------------------------------------
        // Finished
        // --------------------------------------------------------

        $display(
            "PASS: all framed NRZ pipeline tests completed successfully."
        );

        $finish;
    end
endmodule
