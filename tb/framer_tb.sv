`timescale 1ns/1ps

module framer_tb;

    localparam logic [7:0] PREAMBLE = 8'h55;

    localparam logic [7:0] FRAME_TYPE_DATA     = 8'h01;
    localparam logic [7:0] FRAME_TYPE_ACK      = 8'h02;
    //localparam logic [7:0] FRAME_TYPE_DATA_ACK = 8'h03;
    //localparam logic [7:0] FRAME_TYPE_CONTROL  = 8'h04;

    logic clk;
    logic reset;

    logic       frame_start;
    logic       frame_start_ready;

    logic [7:0] frame_type;
    logic [7:0] seq;
    logic [7:0] payload_length;

    logic [7:0] payload_data;
    logic       payload_valid;
    logic       payload_ready;

    logic [7:0] frame_data;
    logic       frame_valid;
    logic       frame_ready;

    logic [7:0] expected_queue[$];

    logic       stalled_last_cycle;
    logic [7:0] stalled_data;


    framer dut (
        .*
    );


    // ----------------------------------------------------------------
    // Clock
    // ----------------------------------------------------------------

    initial clk = 1'b0;

    always #5 clk <= ~clk;


    // ----------------------------------------------------------------
    // Output scoreboard
    //
    // Every successful output handshake must correspond exactly to the
    // next byte expected by the testbench.
    // ----------------------------------------------------------------

    always @(posedge clk) begin
        if (!reset && frame_valid && frame_ready) begin
            assert (expected_queue.size() > 0)
                else $fatal(
                    1,
                    "Unexpected output byte: %02h",
                    frame_data
                );

            assert (frame_data === expected_queue[0])
                else $fatal(
                    1,
                    "Output mismatch: expected %02h, got %02h",
                    expected_queue[0],
                    frame_data
                );

            expected_queue.pop_front();
        end
    end


    // ----------------------------------------------------------------
    // Ready/valid stability monitor
    //
    // Once the framer asserts valid while downstream is stalled,
    // valid must remain asserted and data must remain unchanged.
    // ----------------------------------------------------------------

    always_ff @(posedge clk) begin
        if (reset) begin
            stalled_last_cycle <= 1'b0;
            stalled_data       <= '0;
        end
        else begin
            if (stalled_last_cycle) begin
                assert (frame_valid)
                    else $fatal(
                        1,
                        "frame_valid dropped while output was stalled"
                    );

                assert (frame_data === stalled_data)
                    else $fatal(
                        1,
                        "frame_data changed while output was stalled"
                    );
            end

            stalled_last_cycle <= frame_valid && !frame_ready;

            if (frame_valid && !frame_ready) begin
                stalled_data <= frame_data;
            end
        end
    end


    // ----------------------------------------------------------------
    // Payload pass-through contract
    //
    // Whenever the payload producer is told a byte was accepted,
    // that same byte must also be transferring on the frame output.
    // ----------------------------------------------------------------

    always @(posedge clk) begin
        if (!reset && payload_valid && payload_ready) begin
            assert (frame_valid && frame_ready)
                else $fatal(
                    1,
                    "Payload handshake occurred without output handshake"
                );

            assert (frame_data === payload_data)
                else $fatal(
                    1,
                    "Payload handshake did not forward payload_data"
                );
        end
    end


    // ================================================================
    // Helpers
    // ================================================================

    task automatic apply_reset;
        begin
            expected_queue.delete();

            @(negedge clk);

            reset          = 1'b1;
            frame_start    = 1'b0;
            payload_valid  = 1'b0;
            frame_ready    = 1'b0;

            repeat (2) @(posedge clk);

            @(negedge clk);
            reset = 1'b0;

            #1;

            assert (frame_start_ready)
                else $fatal(1, "Framer not ready after reset");

            assert (!frame_valid)
                else $fatal(1, "frame_valid asserted while idle");

            assert (!payload_ready)
                else $fatal(1, "payload_ready asserted while idle");
        end
    endtask


    task automatic enqueue_header(
        input logic [7:0] type_value,
        input logic [7:0] seq_value,
        input logic [7:0] length_value
    );
        begin
            expected_queue.push_back(PREAMBLE);
            expected_queue.push_back(type_value);
            expected_queue.push_back(seq_value);
            expected_queue.push_back(length_value);
        end
    endtask


    // Presents a descriptor and holds frame_start until accepted.
    task automatic start_frame(
        input logic [7:0] type_value,
        input logic [7:0] seq_value,
        input logic [7:0] length_value
    );
        begin
            enqueue_header(type_value, seq_value, length_value);

            @(negedge clk);

            frame_type     = type_value;
            seq            = seq_value;
            payload_length = length_value;
            frame_start    = 1'b1;

            while (!frame_start_ready) begin
                @(negedge clk);
            end

            @(posedge clk);

            @(negedge clk);
            frame_start = 1'b0;
        end
    endtask


    // Presents one payload byte and holds it until accepted.
    task automatic send_payload_byte(
        input logic [7:0] value
    );
        begin
            expected_queue.push_back(value);

            @(negedge clk);

            payload_data  = value;
            payload_valid = 1'b1;

            while (!payload_ready) begin
                @(negedge clk);
            end

            @(posedge clk);

            @(negedge clk);
            payload_valid = 1'b0;
        end
    endtask


    task automatic wait_for_idle(
        input integer timeout_cycles
    );
        integer i;
        begin
            for (i = 0; i < timeout_cycles; i = i + 1) begin
                @(negedge clk);

                if ((expected_queue.size() == 0) &&
                    frame_start_ready &&
                    !frame_valid) begin
                    return;
                end
            end

            $fatal(
                1,
                "Timed out waiting for framer to return to idle"
            );
        end
    endtask


    // Assumes frame_ready is already 0.
    task automatic check_stalled_byte(
        input logic [7:0] expected_byte,
        input integer cycles
    );
        integer i;
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                @(negedge clk);
                #1;

                assert (frame_valid)
                    else $fatal(
                        1,
                        "frame_valid was low during header stall"
                    );

                assert (frame_data === expected_byte)
                    else $fatal(
                        1,
                        "Expected stalled byte %02h, got %02h",
                        expected_byte,
                        frame_data
                    );

                assert (!payload_ready)
                    else $fatal(
                        1,
                        "payload_ready asserted during header"
                    );

                assert (!frame_start_ready)
                    else $fatal(
                        1,
                        "frame_start_ready asserted during header"
                    );
            end
        end
    endtask


    // Transfers exactly one currently-valid output byte, then stalls
    // downstream again.
    task automatic accept_one_output;
        begin
            @(negedge clk);
            frame_ready = 1'b1;

            @(posedge clk);

            @(negedge clk);
            frame_ready = 1'b0;
        end
    endtask


    // Random-backpressure payload sender used by the stress test.
    task automatic send_payload_byte_random(
        input logic [7:0] value
    );
        integer gap_cycles;
        integer timeout;
        begin
            gap_cycles = $urandom_range(0, 3);

            // Producer occasionally waits before presenting its byte.
            repeat (gap_cycles) begin
                @(negedge clk);

                payload_valid = 1'b0;
                frame_ready   = 1'($urandom_range(0, 1));
            end

            expected_queue.push_back(value);

            @(negedge clk);

            payload_data  = value;
            payload_valid = 1'b1;

            timeout = 0;

            while (1) begin
                frame_ready = 1'($urandom_range(0, 1));

                #1;

                if (payload_ready) begin
                    @(posedge clk);

                    @(negedge clk);
                    payload_valid = 1'b0;
                    return;
                end

                @(posedge clk);
                @(negedge clk);

                timeout = timeout + 1;

                if (timeout > 200) begin
                    $fatal(
                        1,
                        "Random payload transfer timed out"
                    );
                end
            end
        end
    endtask


    task automatic finish_zero_length_random;
        integer timeout;
        begin
            timeout = 0;

            while (1) begin
                @(negedge clk);

                if ((expected_queue.size() == 0) &&
                    frame_start_ready) begin
                    return;
                end

                frame_ready = 1'($urandom_range(0, 1));

                timeout = timeout + 1;

                if (timeout > 200) begin
                    $fatal(
                        1,
                        "Random zero-length frame timed out"
                    );
                end
            end
        end
    endtask


    // ================================================================
    // Tests
    // ================================================================

    initial begin

        reset          = 1'b0;

        frame_start    = 1'b0;
        frame_type     = '0;
        seq            = '0;
        payload_length = '0;

        payload_data   = '0;
        payload_valid  = 1'b0;

        frame_ready    = 1'b0;


        // ------------------------------------------------------------
        // 1. Reset / idle behavior
        // ------------------------------------------------------------

        $display("TEST 1: reset and idle");
        apply_reset();

        repeat (3) begin
            @(negedge clk);

            assert (frame_start_ready)
                else $fatal(1, "frame_start_ready low while idle");

            assert (!frame_valid)
                else $fatal(1, "frame_valid high while idle");

            assert (!payload_ready)
                else $fatal(1, "payload_ready high while idle");
        end


        // ------------------------------------------------------------
        // 2. Basic one-byte frame
        //
        // Also presents payload before header transmission finishes,
        // verifying that the framer holds it off until PAYLOAD.
        // ------------------------------------------------------------

        $display("TEST 2: basic one-byte frame");

        frame_ready = 1'b1;

        start_frame(
            FRAME_TYPE_DATA,
            8'h10,
            8'd1
        );

        send_payload_byte(8'hA5);

        wait_for_idle(50);


        // ------------------------------------------------------------
        // 3. Stall every header state
        //
        // Checks:
        // - valid remains asserted
        // - data remains stable
        // - payload_ready stays low
        // - frame_start_ready stays low
        // ------------------------------------------------------------

        $display("TEST 3: header backpressure");

        frame_ready = 1'b0;

        start_frame(
            FRAME_TYPE_DATA,
            8'h23,
            8'd1
        );

        check_stalled_byte(PREAMBLE, 3);
        accept_one_output();

        check_stalled_byte(FRAME_TYPE_DATA, 2);
        accept_one_output();

        check_stalled_byte(8'h23, 2);
        accept_one_output();

        check_stalled_byte(8'd1, 2);
        accept_one_output();

        frame_ready = 1'b1;
        send_payload_byte(8'h5A);

        wait_for_idle(50);


        // ------------------------------------------------------------
        // 4. Delayed payload producer
        //
        // Header finishes, but producer supplies no payload for several
        // cycles. Framer must wait without creating bytes.
        // ------------------------------------------------------------

        $display("TEST 4: delayed payload");

        frame_ready   = 1'b1;
        payload_valid = 1'b0;

        start_frame(
            FRAME_TYPE_DATA,
            8'h31,
            8'd2
        );

        // Wait until the complete header has left and PAYLOAD can
        // accept data.
        begin
            integer timeout;

            timeout = 0;

            while (!payload_ready) begin
                @(negedge clk);

                timeout = timeout + 1;

                if (timeout > 30)
                    $fatal(1, "Never entered PAYLOAD state");
            end
        end

        repeat (3) begin
            @(negedge clk);
            #1;

            assert (payload_ready)
                else $fatal(
                    1,
                    "Framer stopped being ready for delayed payload"
                );

            assert (!frame_valid)
                else $fatal(
                    1,
                    "Framer invented payload while payload_valid=0"
                );
        end

        send_payload_byte(8'h11);
        send_payload_byte(8'h22);

        wait_for_idle(50);


        // ------------------------------------------------------------
        // 5. Payload backpressure
        //
        // Producer presents a valid byte while downstream stalls.
        // ------------------------------------------------------------

        $display("TEST 5: payload backpressure");

        frame_ready = 1'b1;

        start_frame(
            FRAME_TYPE_DATA,
            8'h42,
            8'd1
        );

        // Allow header to advance while payload is already waiting.
        expected_queue.push_back(8'hC7);

        @(negedge clk);

        payload_data  = 8'hC7;
        payload_valid = 1'b1;

        // Wait until PAYLOAD is reached.
        while (!payload_ready) begin
            @(negedge clk);
        end

        @(negedge clk);
        frame_ready = 1'b0;

        repeat (3) begin
            @(negedge clk);
            #1;

            assert (frame_valid)
                else $fatal(
                    1,
                    "Payload frame_valid dropped under backpressure"
                );

            assert (frame_data === 8'hC7)
                else $fatal(
                    1,
                    "Payload data changed under backpressure"
                );

            assert (!payload_ready)
                else $fatal(
                    1,
                    "Payload accepted while downstream stalled"
                );
        end

        @(negedge clk);
        frame_ready = 1'b1;

        @(posedge clk);

        @(negedge clk);
        payload_valid = 1'b0;

        wait_for_idle(50);


        // ------------------------------------------------------------
        // 6. Metadata must be latched
        //
        // Change all live descriptor inputs immediately after the
        // descriptor handshake. Current frame must remain unchanged.
        // ------------------------------------------------------------

        $display("TEST 6: latched metadata");

        frame_ready = 1'b1;

        start_frame(
            FRAME_TYPE_DATA,
            8'h55,
            8'd2
        );

        @(negedge clk);

        frame_type     = 8'hEE;
        seq            = 8'hDD;
        payload_length = 8'hCC;

        send_payload_byte(8'h81);
        send_payload_byte(8'h82);

        wait_for_idle(50);


        // ------------------------------------------------------------
        // 7. Zero-length frame
        //
        // Payload interface is deliberately valid with garbage.
        // No payload byte may be consumed or transmitted.
        // ------------------------------------------------------------

        $display("TEST 7: zero-length frame");

        frame_ready   = 1'b1;
        payload_data  = 8'hDE;
        payload_valid = 1'b1;

        start_frame(
            FRAME_TYPE_ACK,
            8'h61,
            8'd0
        );

        wait_for_idle(50);

        assert (!payload_ready)
            else $fatal(
                1,
                "Zero-length frame consumed payload"
            );

        @(negedge clk);
        payload_valid = 1'b0;


        // ------------------------------------------------------------
        // 8. Extra payload must not be consumed
        //
        // Declared length is one. Producer keeps valid asserted after
        // the only legal byte has transferred.
        // ------------------------------------------------------------

        $display("TEST 8: payload length enforcement");

        frame_ready = 1'b1;

        start_frame(
            FRAME_TYPE_DATA,
            8'h70,
            8'd1
        );

        expected_queue.push_back(8'hA1);

        @(negedge clk);

        payload_data  = 8'hA1;
        payload_valid = 1'b1;

        while (!payload_ready) begin
            @(negedge clk);
        end

        @(posedge clk);

        // Keep payload_valid high with an additional byte that is NOT
        // part of this frame.
        @(negedge clk);

        payload_data = 8'hA2;

        #1;

        assert (!payload_ready)
            else $fatal(
                1,
                "Framer accepted payload beyond declared length"
            );

        assert (!frame_valid)
            else $fatal(
                1,
                "Framer emitted payload beyond declared length"
            );

        payload_valid = 1'b0;

        wait_for_idle(50);


        // ------------------------------------------------------------
        // 9. Same-cycle next-frame descriptor acceptance
        //
        // Final payload transfer of frame A and descriptor transfer
        // for frame B occur on exactly the same clock edge.
        // ------------------------------------------------------------

        $display("TEST 9: same-cycle frame turnover");

        frame_ready = 1'b1;

        start_frame(
            FRAME_TYPE_DATA,
            8'h80,
            8'd2
        );

        send_payload_byte(8'hA0);

        // Last byte of first frame.
        expected_queue.push_back(8'hA1);

        // Complete expected header for the frame that should be
        // accepted on the same edge.
        enqueue_header(
            FRAME_TYPE_DATA,
            8'h81,
            8'd1
        );

        @(negedge clk);

        payload_data  = 8'hA1;
        payload_valid = 1'b1;

        frame_type     = FRAME_TYPE_DATA;
        seq            = 8'h81;
        payload_length = 8'd1;
        frame_start    = 1'b1;

        // First stall the final payload byte.
        frame_ready = 1'b0;

        repeat (2) begin
            @(negedge clk);
            #1;

            assert (frame_valid)
                else $fatal(
                    1,
                    "Final payload byte not valid while stalled"
                );

            assert (frame_data === 8'hA1)
                else $fatal(
                    1,
                    "Final payload byte changed while stalled"
                );

            assert (!payload_ready)
                else $fatal(
                    1,
                    "Final payload accepted during downstream stall"
                );

            assert (!frame_start_ready)
                else $fatal(
                    1,
                    "Next descriptor accepted while final byte stalled"
                );
        end

        // Release downstream. Both interfaces should now handshake.
        @(negedge clk);
        frame_ready = 1'b1;

        #1;

        assert (payload_ready)
            else $fatal(
                1,
                "Final payload was not ready to transfer"
            );

        assert (frame_start_ready)
            else $fatal(
                1,
                "Next descriptor not accepted on final payload cycle"
            );

        @(posedge clk);

        @(negedge clk);

        payload_valid = 1'b0;
        frame_start   = 1'b0;

        // This payload belongs to the descriptor accepted above.
        send_payload_byte(8'hB0);

        wait_for_idle(100);


        // ------------------------------------------------------------
        // 10. Arbitrary / unknown frame type
        //
        // The current framer treats TYPE as opaque data. Validation
        // will belong in the eventual deframer.
        // ------------------------------------------------------------

        $display("TEST 10: opaque frame type");

        frame_ready = 1'b1;

        start_frame(
            8'hE7,
            8'h91,
            8'd0
        );

        wait_for_idle(50);


        // ------------------------------------------------------------
        // 11. Reset while a frame is active
        //
        // Reset aborts the partially-transmitted frame and returns the
        // framer to IDLE.
        // ------------------------------------------------------------

        $display("TEST 11: reset during frame");

        frame_ready = 1'b0;

        start_frame(
            FRAME_TYPE_DATA,
            8'hA0,
            8'd3
        );

        // Ensure we are actively stalled on the preamble.
        check_stalled_byte(PREAMBLE, 2);

        // Remaining expected bytes belong to the aborted frame.
        expected_queue.delete();

        @(negedge clk);
        reset = 1'b1;

        @(posedge clk);

        @(negedge clk);
        #1;

        assert (frame_start_ready)
            else $fatal(
                1,
                "Framer did not return to IDLE after reset"
            );

        assert (!frame_valid)
            else $fatal(
                1,
                "frame_valid remained asserted after reset"
            );

        assert (!payload_ready)
            else $fatal(
                1,
                "payload_ready remained asserted after reset"
            );

        reset = 1'b0;


        // Verify normal operation after recovery.
        frame_ready = 1'b1;

        start_frame(
            FRAME_TYPE_DATA,
            8'hA1,
            8'd1
        );

        send_payload_byte(8'hBC);

        wait_for_idle(50);


        // ------------------------------------------------------------
        // 12. Maximum 8-bit payload length
        //
        // Exercises counter boundary / off-by-one behavior at 255.
        // ------------------------------------------------------------

        $display("TEST 12: 255-byte payload");

        frame_ready = 1'b1;

        start_frame(
            FRAME_TYPE_DATA,
            8'hB0,
            8'hFF
        );

        for (integer i = 0; i < 255; i = i + 1) begin
            send_payload_byte(i[7:0] ^ 8'hA5);
        end

        wait_for_idle(100);


        // ------------------------------------------------------------
        // 13. Randomized ready/valid stress
        //
        // Multiple small frames with random:
        // - payload sizes
        // - payload producer gaps
        // - downstream backpressure
        // - frame types
        // ------------------------------------------------------------

        $display("TEST 13: randomized stress");

        for (integer frame_index = 0;
             frame_index < 25;
             frame_index = frame_index + 1) begin

            logic [7:0] random_type;
            logic [7:0] random_seq;
            logic [7:0] random_length;

            random_type   = 8'($urandom_range(1, 4));
            random_seq    = 8'(frame_index[7:0]);
            random_length = 8'($urandom_range(0, 12));

            start_frame(
                random_type,
                random_seq,
                random_length
            );

            if (random_length == 0) begin
                finish_zero_length_random();
            end
            else begin
                for (integer byte_index = 0;
                     byte_index < random_length;
                     byte_index = byte_index + 1) begin

                    send_payload_byte_random(
                        random_seq ^
                        byte_index[7:0] ^
                        8'h5A
                    );
                end
            end

            wait_for_idle(200);
        end


        // ------------------------------------------------------------
        // Finished
        // ------------------------------------------------------------

        assert (expected_queue.size() == 0)
            else $fatal(
                1,
                "Simulation ended with %0d expected bytes remaining",
                expected_queue.size()
            );

        $display("PASS: all framer tests completed successfully.");

        $finish;
    end

endmodule
