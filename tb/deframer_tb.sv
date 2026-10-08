`timescale 1ns/1ps

module deframer_tb;

    localparam logic [7:0] PREAMBLE = 8'h55;

    localparam logic [7:0] FRAME_TYPE_DATA     = 8'h01;
    localparam logic [7:0] FRAME_TYPE_ACK      = 8'h02;
    //localparam logic [7:0] FRAME_TYPE_DATA_ACK = 8'h03;
    localparam logic [7:0] FRAME_TYPE_CONTROL  = 8'h04;


    // ================================================================
    // DUT signals
    // ================================================================

    logic clk;
    logic reset;

    logic [7:0] input_data;
    logic       input_valid;
    logic       input_ready;

    logic       frame_start;
    logic       frame_start_ready;
    logic [7:0] frame_type;
    logic [7:0] seq;
    logic [7:0] payload_length;

    logic [7:0] payload_data;
    logic       payload_valid;
    logic       payload_ready;


    // ================================================================
    // Expected-output scoreboards
    // ================================================================

    logic [7:0] expected_type_queue[$];
    logic [7:0] expected_seq_queue[$];
    logic [7:0] expected_length_queue[$];

    logic [7:0] expected_payload_queue[$];


    // ================================================================
    // Stall-monitor state
    // ================================================================

    logic       descriptor_stalled_last_cycle;
    logic [7:0] stalled_frame_type;
    logic [7:0] stalled_seq;
    logic [7:0] stalled_payload_length;

    logic       payload_stalled_last_cycle;
    logic [7:0] stalled_payload_data;

    logic       input_stalled_last_cycle;
    logic [7:0] stalled_input_data;


    // ================================================================
    // DUT
    // ================================================================

    deframer dut (
        .*
    );


    // ================================================================
    // Clock
    // ================================================================

    initial clk = 1'b0;

    always #5 clk <= ~clk;


    // ================================================================
    // Descriptor scoreboard
    //
    // Every descriptor handshake must exactly match the next expected
    // descriptor.
    // ================================================================

    always @(posedge clk) begin
        if (!reset && frame_start && frame_start_ready) begin

            assert (
                expected_type_queue.size() > 0 &&
                expected_seq_queue.size() > 0 &&
                expected_length_queue.size() > 0
            )
                else $fatal(
                    1,
                    "Unexpected descriptor: type=%02h seq=%02h length=%0d",
                    frame_type,
                    seq,
                    payload_length
                );

            assert (frame_type === expected_type_queue[0])
                else $fatal(
                    1,
                    "Descriptor TYPE mismatch: expected %02h, got %02h",
                    expected_type_queue[0],
                    frame_type
                );

            assert (seq === expected_seq_queue[0])
                else $fatal(
                    1,
                    "Descriptor SEQ mismatch: expected %02h, got %02h",
                    expected_seq_queue[0],
                    seq
                );

            assert (payload_length === expected_length_queue[0])
                else $fatal(
                    1,
                    "Descriptor LENGTH mismatch: expected %0d, got %0d",
                    expected_length_queue[0],
                    payload_length
                );

            expected_type_queue.pop_front();
            expected_seq_queue.pop_front();
            expected_length_queue.pop_front();
        end
    end


    // ================================================================
    // Payload scoreboard
    //
    // Every payload handshake must correspond exactly to the next
    // expected payload byte.
    // ================================================================

    always @(posedge clk) begin
        if (!reset && payload_valid && payload_ready) begin

            assert (expected_payload_queue.size() > 0)
                else $fatal(
                    1,
                    "Unexpected payload byte: %02h",
                    payload_data
                );

            assert (payload_data === expected_payload_queue[0])
                else $fatal(
                    1,
                    "Payload mismatch: expected %02h, got %02h",
                    expected_payload_queue[0],
                    payload_data
                );

            expected_payload_queue.pop_front();
        end
    end


    // ================================================================
    // Descriptor stability monitor
    //
    // Once frame_start is asserted and downstream is not ready,
    // frame_start must remain asserted and all descriptor metadata
    // must remain stable.
    // ================================================================

    always_ff @(posedge clk) begin
        if (reset) begin
            descriptor_stalled_last_cycle <= 1'b0;

            stalled_frame_type     <= '0;
            stalled_seq            <= '0;
            stalled_payload_length <= '0;
        end
        else begin

            if (descriptor_stalled_last_cycle) begin

                assert (frame_start)
                    else $fatal(
                        1,
                        "frame_start dropped while descriptor was stalled"
                    );

                assert (frame_type === stalled_frame_type)
                    else $fatal(
                        1,
                        "frame_type changed while descriptor was stalled"
                    );

                assert (seq === stalled_seq)
                    else $fatal(
                        1,
                        "seq changed while descriptor was stalled"
                    );

                assert (payload_length === stalled_payload_length)
                    else $fatal(
                        1,
                        "payload_length changed while descriptor was stalled"
                    );
            end

            descriptor_stalled_last_cycle <=
                frame_start && !frame_start_ready;

            if (frame_start && !frame_start_ready) begin
                stalled_frame_type     <= frame_type;
                stalled_seq            <= seq;
                stalled_payload_length <= payload_length;
            end
        end
    end


    // ================================================================
    // Payload stability monitor
    //
    // If a payload byte is valid but the consumer stalls it, the
    // payload byte must remain valid and unchanged.
    // ================================================================

    always_ff @(posedge clk) begin
        if (reset) begin
            payload_stalled_last_cycle <= 1'b0;
            stalled_payload_data       <= '0;
        end
        else begin

            if (payload_stalled_last_cycle) begin

                assert (payload_valid)
                    else $fatal(
                        1,
                        "payload_valid dropped while payload was stalled"
                    );

                assert (payload_data === stalled_payload_data)
                    else $fatal(
                        1,
                        "payload_data changed while payload was stalled"
                    );
            end

            payload_stalled_last_cycle <=
                payload_valid && !payload_ready;

            if (payload_valid && !payload_ready) begin
                stalled_payload_data <= payload_data;
            end
        end
    end


    // ================================================================
    // Input-source stability monitor
    //
    // The TB itself obeys ready/valid. This also catches accidental
    // changes to input_data while the deframer is applying
    // backpressure.
    // ================================================================

    always_ff @(posedge clk) begin
        if (reset) begin
            input_stalled_last_cycle <= 1'b0;
            stalled_input_data       <= '0;
        end
        else begin

            if (input_stalled_last_cycle) begin

                assert (input_valid)
                    else $fatal(
                        1,
                        "Testbench dropped input_valid while stalled"
                    );

                assert (input_data === stalled_input_data)
                    else $fatal(
                        1,
                        "Testbench changed input_data while stalled"
                    );
            end

            input_stalled_last_cycle <=
                input_valid && !input_ready;

            if (input_valid && !input_ready) begin
                stalled_input_data <= input_data;
            end
        end
    end


    // ================================================================
    // General interface invariants
    // ================================================================

    always @(posedge clk) begin
        if (!reset) begin

            // The deframer intentionally stops consuming bytes while
            // waiting for descriptor acceptance.
            if (frame_start) begin
                assert (!input_ready)
                    else $fatal(
                        1,
                        "input_ready asserted while descriptor was pending"
                    );
            end

            // PAYLOAD is a direct ready/valid pass-through.
            if (payload_valid) begin

                assert (input_valid)
                    else $fatal(
                        1,
                        "payload_valid asserted without input_valid"
                    );

                assert (payload_data === input_data)
                    else $fatal(
                        1,
                        "Payload output does not match input stream"
                    );

                assert (input_ready === payload_ready)
                    else $fatal(
                        1,
                        "PAYLOAD ready path is not pass-through"
                    );
            end
        end
    end


    // ================================================================
    // Helper tasks
    // ================================================================

    task automatic clear_expected;
        begin
            expected_type_queue.delete();
            expected_seq_queue.delete();
            expected_length_queue.delete();
            expected_payload_queue.delete();
        end
    endtask


    task automatic expect_descriptor(
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


    task automatic expect_payload(
        input logic [7:0] value
    );
        begin
            expected_payload_queue.push_back(value);
        end
    endtask


    task automatic apply_reset;
        begin
            clear_expected();

            @(negedge clk);

            reset             = 1'b1;
            input_valid       = 1'b0;
            frame_start_ready = 1'b0;
            payload_ready     = 1'b0;

            repeat (2) @(posedge clk);

            @(negedge clk);

            reset = 1'b0;

            #1;

            assert (input_ready)
                else $fatal(
                    1,
                    "Deframer not ready to search after reset"
                );

            assert (!frame_start)
                else $fatal(
                    1,
                    "frame_start asserted after reset"
                );

            assert (!payload_valid)
                else $fatal(
                    1,
                    "payload_valid asserted after reset"
                );
        end
    endtask


    // Presents one byte and holds it until the deframer accepts it.
    task automatic send_input_byte(
        input logic [7:0] value
    );
        begin
            @(negedge clk);

            input_data  = value;
            input_valid = 1'b1;

            while (!input_ready) begin
                @(negedge clk);
            end

            @(posedge clk);

            @(negedge clk);

            input_valid = 1'b0;
        end
    endtask


    // Same as send_input_byte, but waits a random number of cycles
    // before presenting the byte.
    task automatic send_input_byte_random(
        input logic [7:0] value
    );
        integer gap_cycles;

        begin
            gap_cycles = $urandom_range(0, 3);

            repeat (gap_cycles) begin
                @(negedge clk);
                input_valid = 1'b0;
            end

            send_input_byte(value);
        end
    endtask


    // Sends the complete fixed-format header and registers the
    // descriptor that should eventually emerge.
    task automatic send_frame_header(
        input logic [7:0] type_value,
        input logic [7:0] seq_value,
        input logic [7:0] length_value
    );
        begin
            expect_descriptor(
                type_value,
                seq_value,
                length_value
            );

            send_input_byte(PREAMBLE);
            send_input_byte(type_value);
            send_input_byte(seq_value);
            send_input_byte(length_value);
        end
    endtask


    task automatic send_frame_header_random(
        input logic [7:0] type_value,
        input logic [7:0] seq_value,
        input logic [7:0] length_value
    );
        begin
            expect_descriptor(
                type_value,
                seq_value,
                length_value
            );

            send_input_byte_random(PREAMBLE);
            send_input_byte_random(type_value);
            send_input_byte_random(seq_value);
            send_input_byte_random(length_value);
        end
    endtask


    // Accepts a pending descriptor after holding it stalled for a
    // chosen number of cycles.
    task automatic accept_descriptor(
        input integer stall_cycles
    );
        integer i;

        begin
            frame_start_ready = 1'b0;

            #1;

            assert (frame_start)
                else $fatal(
                    1,
                    "Expected descriptor was not presented"
                );

            for (i = 0; i < stall_cycles; i = i + 1) begin

                #1;

                assert (frame_start)
                    else $fatal(
                        1,
                        "frame_start dropped while descriptor stalled"
                    );

                assert (!input_ready)
                    else $fatal(
                        1,
                        "Input was consumed while descriptor stalled"
                    );

                @(posedge clk);
                @(negedge clk);
            end

            frame_start_ready = 1'b1;

            #1;

            assert (frame_start)
                else $fatal(
                    1,
                    "Descriptor disappeared before acceptance"
                );

            @(posedge clk);

            @(negedge clk);

            frame_start_ready = 1'b0;
        end
    endtask


    task automatic accept_descriptor_random;
        integer stall_cycles;

        begin
            stall_cycles = $urandom_range(0, 4);
            accept_descriptor(stall_cycles);
        end
    endtask


    task automatic send_payload_byte(
        input logic [7:0] value
    );
        begin
            expect_payload(value);
            send_input_byte(value);
        end
    endtask


    // Random producer gaps and random payload-consumer backpressure.
    task automatic send_payload_byte_random(
        input logic [7:0] value
    );
        integer source_gap;
        integer timeout;

        begin
            expect_payload(value);

            source_gap = $urandom_range(0, 3);

            repeat (source_gap) begin
                @(negedge clk);

                input_valid   = 1'b0;
                payload_ready = 1'($urandom_range(0, 1));
            end

            @(negedge clk);

            input_data  = value;
            input_valid = 1'b1;

            timeout = 0;

            while (1) begin

                payload_ready = 1'($urandom_range(0, 1));

                #1;

                if (input_ready) begin

                    assert (payload_valid)
                        else $fatal(
                            1,
                            "Input ready for payload without payload_valid"
                        );

                    @(posedge clk);

                    @(negedge clk);

                    input_valid = 1'b0;
                    payload_ready = 1'b0;

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


    task automatic check_scoreboards_empty;
        begin
            assert (expected_type_queue.size() == 0)
                else $fatal(
                    1,
                    "%0d expected descriptors remain",
                    expected_type_queue.size()
                );

            assert (expected_seq_queue.size() == 0)
                else $fatal(
                    1,
                    "Sequence scoreboard not empty"
                );

            assert (expected_length_queue.size() == 0)
                else $fatal(
                    1,
                    "Length scoreboard not empty"
                );

            assert (expected_payload_queue.size() == 0)
                else $fatal(
                    1,
                    "%0d expected payload bytes remain",
                    expected_payload_queue.size()
                );
        end
    endtask


    // ================================================================
    // Tests
    // ================================================================

    initial begin : test_sequence

        integer i;
        integer frame_index;
        integer byte_index;
        integer garbage_count;

        logic [7:0] random_type;
        logic [7:0] random_seq;
        logic [7:0] random_length;
        logic [7:0] random_data;
        logic [7:0] garbage_byte;


        // ------------------------------------------------------------
        // Initial values
        // ------------------------------------------------------------

        reset = 1'b0;

        input_data  = '0;
        input_valid = 1'b0;

        frame_start_ready = 1'b0;
        payload_ready     = 1'b0;


        // ------------------------------------------------------------
        // 1. Reset / search behavior
        // ------------------------------------------------------------

        $display("TEST 1: reset and search state");

        apply_reset();

        repeat (3) begin
            @(negedge clk);
            #1;

            assert (input_ready)
                else $fatal(
                    1,
                    "Deframer not ready while searching for preamble"
                );

            assert (!frame_start)
                else $fatal(
                    1,
                    "Unexpected descriptor while searching"
                );

            assert (!payload_valid)
                else $fatal(
                    1,
                    "Unexpected payload while searching"
                );
        end


        // ------------------------------------------------------------
        // 2. Ignore garbage before preamble
        // ------------------------------------------------------------

        $display("TEST 2: garbage before preamble");

        payload_ready = 1'b1;

        send_input_byte(8'h00);
        send_input_byte(8'hAA);
        send_input_byte(8'h54);
        send_input_byte(8'h56);
        send_input_byte(8'hFF);

        repeat (2) begin
            @(negedge clk);
            #1;

            assert (!frame_start)
                else $fatal(
                    1,
                    "Garbage generated a descriptor"
                );

            assert (!payload_valid)
                else $fatal(
                    1,
                    "Garbage generated payload"
                );
        end

        check_scoreboards_empty();


        // ------------------------------------------------------------
        // 3. Basic one-byte frame
        // ------------------------------------------------------------

        $display("TEST 3: basic one-byte frame");

        send_frame_header(
            FRAME_TYPE_DATA,
            8'h10,
            8'd1
        );

        accept_descriptor(0);

        payload_ready = 1'b1;

        send_payload_byte(8'hA5);

        check_scoreboards_empty();


        // ------------------------------------------------------------
        // 4. Multi-byte frame with input gaps
        // ------------------------------------------------------------

        $display("TEST 4: multi-byte frame with input gaps");

        expect_descriptor(
            FRAME_TYPE_DATA,
            8'h20,
            8'd4
        );

        send_input_byte(PREAMBLE);

        repeat (2) @(posedge clk);

        send_input_byte(FRAME_TYPE_DATA);

        repeat (3) @(posedge clk);

        send_input_byte(8'h20);

        repeat (2) @(posedge clk);

        send_input_byte(8'd4);

        accept_descriptor(0);

        payload_ready = 1'b1;

        send_payload_byte(8'h11);

        repeat (2) @(posedge clk);

        send_payload_byte(8'h22);
        send_payload_byte(8'h33);

        repeat (3) @(posedge clk);

        send_payload_byte(8'h44);

        check_scoreboards_empty();


        // ------------------------------------------------------------
        // 5. Descriptor backpressure
        //
        // Also presents the first payload byte while descriptor output
        // is stalled. The deframer must refuse to consume it.
        // ------------------------------------------------------------

        $display("TEST 5: descriptor backpressure");

        frame_start_ready = 1'b0;
        payload_ready     = 1'b1;

        send_frame_header(
            FRAME_TYPE_DATA,
            8'h31,
            8'd1
        );

        expect_payload(8'hC1);

        @(negedge clk);

        input_data  = 8'hC1;
        input_valid = 1'b1;

        repeat (4) begin
            #1;

            assert (frame_start)
                else $fatal(
                    1,
                    "Descriptor not held during backpressure"
                );

            assert (frame_type === FRAME_TYPE_DATA)
                else $fatal(
                    1,
                    "Descriptor type changed during stall"
                );

            assert (seq === 8'h31)
                else $fatal(
                    1,
                    "Descriptor sequence changed during stall"
                );

            assert (payload_length === 8'd1)
                else $fatal(
                    1,
                    "Descriptor length changed during stall"
                );

            assert (!input_ready)
                else $fatal(
                    1,
                    "First payload byte consumed before descriptor acceptance"
                );

            assert (!payload_valid)
                else $fatal(
                    1,
                    "Payload exposed before descriptor acceptance"
                );

            @(posedge clk);
            @(negedge clk);
        end

        // Accept descriptor.
        frame_start_ready = 1'b1;

        @(posedge clk);

        @(negedge clk);

        frame_start_ready = 1'b0;

        // Pending C1 should now be visible as payload.
        #1;

        assert (payload_valid)
            else $fatal(
                1,
                "Pending payload did not appear after descriptor acceptance"
            );

        assert (payload_data === 8'hC1)
            else $fatal(
                1,
                "Wrong pending payload byte"
            );

        assert (input_ready)
            else $fatal(
                1,
                "Payload was not ready after descriptor acceptance"
            );

        @(posedge clk);

        @(negedge clk);

        input_valid = 1'b0;

        check_scoreboards_empty();


        // ------------------------------------------------------------
        // 6. Zero-length frame
        // ------------------------------------------------------------

        $display("TEST 6: zero-length frame");

        payload_ready = 1'b1;

        send_frame_header(
            FRAME_TYPE_ACK,
            8'h42,
            8'd0
        );

        accept_descriptor(2);

        #1;

        assert (!frame_start)
            else $fatal(
                1,
                "Zero-length descriptor did not complete"
            );

        assert (!payload_valid)
            else $fatal(
                1,
                "Zero-length frame produced payload"
            );

        assert (input_ready)
            else $fatal(
                1,
                "Deframer did not return to preamble search"
            );

        // Non-preamble data after the frame must simply be discarded.
        send_input_byte(8'h99);

        check_scoreboards_empty();


        // ------------------------------------------------------------
        // 7. Delayed payload producer
        // ------------------------------------------------------------

        $display("TEST 7: delayed payload input");

        send_frame_header(
            FRAME_TYPE_DATA,
            8'h50,
            8'd2
        );

        accept_descriptor(0);

        payload_ready = 1'b1;
        input_valid   = 1'b0;

        repeat (4) begin
            @(negedge clk);
            #1;

            assert (input_ready)
                else $fatal(
                    1,
                    "Deframer not ready for delayed payload"
                );

            assert (!payload_valid)
                else $fatal(
                    1,
                    "Deframer invented payload with input_valid low"
                );
        end

        send_payload_byte(8'h71);
        send_payload_byte(8'h72);

        check_scoreboards_empty();


        // ------------------------------------------------------------
        // 8. Payload backpressure
        // ------------------------------------------------------------

        $display("TEST 8: payload backpressure");

        send_frame_header(
            FRAME_TYPE_DATA,
            8'h60,
            8'd1
        );

        accept_descriptor(0);

        payload_ready = 1'b0;

        expect_payload(8'hD4);

        @(negedge clk);

        input_data  = 8'hD4;
        input_valid = 1'b1;

        repeat (4) begin
            #1;

            assert (payload_valid)
                else $fatal(
                    1,
                    "Payload not presented during consumer stall"
                );

            assert (payload_data === 8'hD4)
                else $fatal(
                    1,
                    "Payload changed during consumer stall"
                );

            assert (!input_ready)
                else $fatal(
                    1,
                    "Input consumed while payload consumer stalled"
                );

            @(posedge clk);
            @(negedge clk);
        end

        payload_ready = 1'b1;

        #1;

        assert (input_ready)
            else $fatal(
                1,
                "Input backpressure did not release"
            );

        @(posedge clk);

        @(negedge clk);

        input_valid   = 1'b0;
        payload_ready = 1'b0;

        check_scoreboards_empty();


        // ------------------------------------------------------------
        // 9. Preamble value inside payload
        //
        // 0x55 must be ordinary data while PAYLOAD is active.
        // ------------------------------------------------------------

        $display("TEST 9: preamble byte inside payload");

        send_frame_header(
            FRAME_TYPE_DATA,
            8'h70,
            8'd3
        );

        accept_descriptor(0);

        payload_ready = 1'b1;

        send_payload_byte(8'h11);
        send_payload_byte(8'h55);
        send_payload_byte(8'h22);

        check_scoreboards_empty();


        // ------------------------------------------------------------
        // 10. Exact payload-length enforcement
        //
        // After two payload bytes, the next non-preamble input byte
        // belongs outside the frame and must be discarded.
        // ------------------------------------------------------------

        $display("TEST 10: exact payload length");

        send_frame_header(
            FRAME_TYPE_DATA,
            8'h80,
            8'd2
        );

        accept_descriptor(0);

        payload_ready = 1'b1;

        send_payload_byte(8'hA1);
        send_payload_byte(8'hA2);

        // This is NOT part of the payload.
        send_input_byte(8'hA3);

        #1;

        assert (!payload_valid)
            else $fatal(
                1,
                "Byte beyond declared payload length was emitted"
            );

        check_scoreboards_empty();


        // ------------------------------------------------------------
        // 11. Unknown / opaque frame type
        // ------------------------------------------------------------

        $display("TEST 11: opaque frame type");

        send_frame_header(
            8'hE7,
            8'h91,
            8'd0
        );

        accept_descriptor(1);

        check_scoreboards_empty();


        // ------------------------------------------------------------
        // 12. Back-to-back frames
        // ------------------------------------------------------------

        $display("TEST 12: back-to-back frames");

        payload_ready = 1'b1;

        // Frame 1
        send_frame_header(
            FRAME_TYPE_DATA,
            8'hA0,
            8'd2
        );

        accept_descriptor(0);

        send_payload_byte(8'h01);
        send_payload_byte(8'h02);

        // Frame 2: zero length
        send_frame_header(
            FRAME_TYPE_ACK,
            8'hA1,
            8'd0
        );

        accept_descriptor(0);

        // Frame 3
        send_frame_header(
            FRAME_TYPE_CONTROL,
            8'hA2,
            8'd3
        );

        accept_descriptor(0);

        send_payload_byte(8'h10);
        send_payload_byte(8'h20);
        send_payload_byte(8'h30);

        check_scoreboards_empty();


        // ------------------------------------------------------------
        // 13. Reset during header parsing
        // ------------------------------------------------------------

        $display("TEST 13: reset during header");

        expect_descriptor(
            FRAME_TYPE_DATA,
            8'hB0,
            8'd3
        );

        send_input_byte(PREAMBLE);
        send_input_byte(FRAME_TYPE_DATA);

        // Abort the partial frame.
        clear_expected();

        @(negedge clk);

        reset       = 1'b1;
        input_valid = 1'b0;

        @(posedge clk);

        @(negedge clk);

        reset = 1'b0;

        #1;

        assert (input_ready)
            else $fatal(
                1,
                "Deframer did not recover from header reset"
            );

        assert (!frame_start)
            else $fatal(
                1,
                "Partial descriptor survived reset"
            );

        assert (!payload_valid)
            else $fatal(
                1,
                "Partial payload survived reset"
            );

        // Verify recovery with a complete frame.
        send_frame_header(
            FRAME_TYPE_DATA,
            8'hB1,
            8'd1
        );

        accept_descriptor(0);

        payload_ready = 1'b1;

        send_payload_byte(8'hBC);

        check_scoreboards_empty();


        // ------------------------------------------------------------
        // 14. Reset while descriptor is stalled
        // ------------------------------------------------------------

        $display("TEST 14: reset during descriptor stall");

        frame_start_ready = 1'b0;

        send_frame_header(
            FRAME_TYPE_DATA,
            8'hC0,
            8'd2
        );

        #1;

        assert (frame_start)
            else $fatal(
                1,
                "Expected stalled descriptor before reset"
            );

        clear_expected();

        @(negedge clk);

        reset = 1'b1;

        @(posedge clk);

        @(negedge clk);

        reset = 1'b0;

        #1;

        assert (!frame_start)
            else $fatal(
                1,
                "Descriptor remained valid after reset"
            );

        assert (input_ready)
            else $fatal(
                1,
                "Deframer did not resume searching after reset"
            );


        // ------------------------------------------------------------
        // 15. Reset during payload
        // ------------------------------------------------------------

        $display("TEST 15: reset during payload");

        send_frame_header(
            FRAME_TYPE_DATA,
            8'hD0,
            8'd3
        );

        accept_descriptor(0);

        payload_ready = 1'b1;

        send_payload_byte(8'h41);

        // Present the next byte but do not let it transfer.
        payload_ready = 1'b0;

        expect_payload(8'h42);

        @(negedge clk);

        input_data  = 8'h42;
        input_valid = 1'b1;

        #1;

        assert (payload_valid)
            else $fatal(
                1,
                "Expected stalled payload before reset"
            );

        clear_expected();

        @(negedge clk);

        reset       = 1'b1;
        input_valid = 1'b0;

        @(posedge clk);

        @(negedge clk);

        reset = 1'b0;

        #1;

        assert (!payload_valid)
            else $fatal(
                1,
                "Payload survived reset"
            );

        assert (input_ready)
            else $fatal(
                1,
                "Deframer did not return to search after payload reset"
            );


        // ------------------------------------------------------------
        // 16. Maximum 8-bit payload length
        // ------------------------------------------------------------

        $display("TEST 16: 255-byte payload");

        send_frame_header(
            FRAME_TYPE_DATA,
            8'hE0,
            8'hFF
        );

        accept_descriptor(0);

        payload_ready = 1'b1;

        for (i = 0; i < 255; i = i + 1) begin
            send_payload_byte(
                i[7:0] ^ 8'hA5
            );
        end

        check_scoreboards_empty();


        // ------------------------------------------------------------
        // 17. Randomized stress
        //
        // Randomizes:
        // - garbage before frames
        // - frame type
        // - sequence
        // - payload length
        // - gaps between incoming bytes
        // - descriptor backpressure
        // - payload producer gaps
        // - payload consumer backpressure
        // ------------------------------------------------------------

        $display("TEST 17: randomized stress");

        frame_start_ready = 1'b0;
        payload_ready     = 1'b0;

        for (
            frame_index = 0;
            frame_index < 40;
            frame_index = frame_index + 1
        ) begin

            // ----------------------------------------
            // Random non-preamble garbage
            // ----------------------------------------

            garbage_count = $urandom_range(0, 4);

            for (
                i = 0;
                i < garbage_count;
                i = i + 1
            ) begin

                garbage_byte = 8'($urandom_range(
                    0,
                    255
                ));

                // 0x55 would intentionally begin a frame, so don't
                // use it as "garbage."
                if (garbage_byte == PREAMBLE) begin
                    garbage_byte = 8'h54;
                end

                send_input_byte_random(
                    garbage_byte
                );
            end


            // ----------------------------------------
            // Random descriptor
            // ----------------------------------------

            random_type   = 8'($urandom_range(0, 255));
            random_seq    = 8'($urandom_range(0, 255));
            random_length = 8'($urandom_range(0, 12));

            send_frame_header_random(
                random_type,
                random_seq,
                random_length
            );

            accept_descriptor_random();


            // ----------------------------------------
            // Random payload
            // ----------------------------------------

            for (
                byte_index = 0;
                byte_index < random_length;
                byte_index = byte_index + 1
            ) begin

                random_data = 8'($urandom_range(
                    0,
                    255
                ));

                send_payload_byte_random(
                    random_data
                );
            end

            payload_ready = 1'b0;

            check_scoreboards_empty();
        end


        // ------------------------------------------------------------
        // Final result
        // ------------------------------------------------------------

        check_scoreboards_empty();

        $display(
            "PASS: all deframer tests completed successfully."
        );

        $finish;
    end

endmodule
