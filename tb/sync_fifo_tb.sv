`timescale 1ns/1ps

module sync_fifo_tb #(
    parameter int DATA_WIDTH = 8,
    parameter int DATA_DEPTH = 32
);

    logic clk;
    logic reset;

    logic [DATA_WIDTH-1:0] input_data;
    logic                  input_valid;
    logic                  input_ready;

    logic [DATA_WIDTH-1:0] output_data;
    logic                  output_valid;
    logic                  output_ready;


    // ============================================================
    // Reference model
    // ============================================================

    logic [DATA_WIDTH-1:0] model_queue[$];

    integer model_read_ptr;
    integer model_write_ptr;

    integer input_transfer_count;
    integer output_transfer_count;


    // ============================================================
    // DUT
    // ============================================================

    sync_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DATA_DEPTH (DATA_DEPTH)
    ) dut (
        .*
    );


    // ============================================================
    // Clock
    // ============================================================

    initial clk = 1'b0;

    always #5 clk <= ~clk;


    // ============================================================
    // Model pointer wrap
    // ============================================================

    function automatic integer next_model_ptr(
        input integer ptr
    );
        begin
            if (ptr == DATA_DEPTH - 1)
                next_model_ptr = 0;
            else
                next_model_ptr = ptr + 1;
        end
    endfunction


    // ============================================================
    // Main scoreboard
    //
    // Model semantics match the FIFO:
    //
    // EMPTY + push only:
    //     store byte
    //
    // EMPTY + push/pop:
    //     fall-through/bypass; nothing stored
    //
    // NONEMPTY + push/pop:
    //     consume head and store new tail
    // ============================================================

    always @(posedge clk) begin : scoreboard

        logic in_hs;
        logic out_hs;
        logic was_empty;

        logic [DATA_WIDTH-1:0] expected_output;

        if (reset) begin
            model_queue.delete();

            model_read_ptr  <= 0;
            model_write_ptr <= 0;

            input_transfer_count  <= 0;
            output_transfer_count <= 0;
        end
        else begin

            was_empty = (model_queue.size() == 0);

            in_hs  = input_valid  && input_ready;
            out_hs = output_valid && output_ready;


            // ----------------------------------------------------
            // Check combinational interface behavior against model
            // ----------------------------------------------------

            assert (
                output_valid ===
                ((model_queue.size() != 0) || input_valid)
            )
                else $fatal(
                    1,
                    "output_valid mismatch: model_size=%0d input_valid=%b output_valid=%b",
                    model_queue.size(),
                    input_valid,
                    output_valid
                );


            assert (
                input_ready ===
                (
                    (model_queue.size() < DATA_DEPTH) ||
                    (output_valid && output_ready)
                )
            )
                else $fatal(
                    1,
                    "input_ready mismatch: model_size=%0d output_valid=%b output_ready=%b input_ready=%b",
                    model_queue.size(),
                    output_valid,
                    output_ready,
                    input_ready
                );


            // Whenever output is valid, it must be the model head
            // or, when empty, the current fall-through input.
            if (output_valid) begin

                if (was_empty)
                    expected_output = input_data;
                else
                    expected_output = model_queue[0];

                assert (output_data === expected_output)
                    else $fatal(
                        1,
                        "Output mismatch: expected %0h, got %0h",
                        expected_output,
                        output_data
                    );
            end


            // ----------------------------------------------------
            // Process output transaction
            // ----------------------------------------------------

            if (out_hs) begin

                output_transfer_count <=
                    output_transfer_count + 1;

                if (was_empty) begin

                    // An empty FIFO cannot produce an output unless
                    // a new input is simultaneously bypassing it.
                    assert (in_hs)
                        else $fatal(
                            1,
                            "Output handshake occurred while model FIFO was empty without input bypass"
                        );

                end
                else begin

                    model_queue.pop_front();

                end
            end


            // ----------------------------------------------------
            // Process input transaction
            // ----------------------------------------------------

            if (in_hs) begin

                input_transfer_count <=
                    input_transfer_count + 1;

                // Empty simultaneous input/output is pure bypass.
                // Do not store it in the queue.
                if (!(was_empty && out_hs)) begin
                    model_queue.push_back(input_data);
                end
            end


            // ----------------------------------------------------
            // Reference pointer behavior
            // ----------------------------------------------------

            case ({out_hs, in_hs})

                // Push only
                2'b01: begin
                    model_write_ptr <=
                        next_model_ptr(model_write_ptr);
                end

                // Pop only
                2'b10: begin
                    model_read_ptr <=
                        next_model_ptr(model_read_ptr);
                end

                // Simultaneous
                2'b11: begin

                    if (!was_empty) begin
                        model_read_ptr <=
                            next_model_ptr(model_read_ptr);

                        model_write_ptr <=
                            next_model_ptr(model_write_ptr);
                    end

                    // Empty bypass:
                    // neither pointer changes.
                end

                default: begin
                    ;
                end

            endcase


            assert (model_queue.size() <= DATA_DEPTH)
                else $fatal(
                    1,
                    "Reference FIFO overflowed: size=%0d depth=%0d",
                    model_queue.size(),
                    DATA_DEPTH
                );
        end
    end


    // ============================================================
    // Internal-state checks
    //
    // Run after the positive-edge updates have settled.
    // ============================================================

    always @(negedge clk) begin
        #1;

        if (!reset) begin

            assert (32'($unsigned(dut.counter)) == model_queue.size())
                else $fatal(
                    1,
                    "Occupancy mismatch: DUT=%0d model=%0d",
                    dut.counter,
                    model_queue.size()
                );

            assert (32'($unsigned(dut.read_ptr)) == model_read_ptr)
                else $fatal(
                    1,
                    "Read pointer mismatch: DUT=%0d model=%0d",
                    dut.read_ptr,
                    model_read_ptr
                );

            assert (32'($unsigned(dut.write_ptr)) == model_write_ptr)
                else $fatal(
                    1,
                    "Write pointer mismatch: DUT=%0d model=%0d",
                    dut.write_ptr,
                    model_write_ptr
                );

            assert (dut.empty == (model_queue.size() == 0))
                else $fatal(
                    1,
                    "EMPTY flag mismatch"
                );

            assert (dut.full == (model_queue.size() == DATA_DEPTH))
                else $fatal(
                    1,
                    "FULL flag mismatch"
                );

            assert (32'($unsigned(dut.read_ptr)) < DATA_DEPTH)
                else $fatal(
                    1,
                    "Read pointer out of range: %0d",
                    dut.read_ptr
                );

            assert (32'($unsigned(dut.write_ptr)) < DATA_DEPTH)
                else $fatal(
                    1,
                    "Write pointer out of range: %0d",
                    dut.write_ptr
                );
        end
    end


    // ============================================================
    // Output ready/valid stability
    //
    // If the consumer stalls a valid output, the FIFO must keep
    // valid asserted and keep the oldest byte unchanged.
    // ============================================================

    logic                  output_stalled_last_cycle;
    logic [DATA_WIDTH-1:0] stalled_output_data;

    always_ff @(posedge clk) begin
        if (reset) begin
            output_stalled_last_cycle <= 1'b0;
            stalled_output_data       <= '0;
        end
        else begin

            if (output_stalled_last_cycle) begin

                assert (output_valid)
                    else $fatal(
                        1,
                        "output_valid dropped while output was stalled"
                    );

                assert (output_data === stalled_output_data)
                    else $fatal(
                        1,
                        "output_data changed while output was stalled"
                    );
            end

            output_stalled_last_cycle <=
                output_valid && !output_ready;

            if (output_valid && !output_ready) begin
                stalled_output_data <= output_data;
            end
        end
    end


    // ============================================================
    // Verify that the TB itself obeys the input ready/valid contract
    // ============================================================

    logic                  input_stalled_last_cycle;
    logic [DATA_WIDTH-1:0] stalled_input_data;

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
                        "TB dropped input_valid while input was stalled"
                    );

                assert (input_data === stalled_input_data)
                    else $fatal(
                        1,
                        "TB changed input_data while input was stalled"
                    );
            end

            input_stalled_last_cycle <=
                input_valid && !input_ready;

            if (input_valid && !input_ready) begin
                stalled_input_data <= input_data;
            end
        end
    end


    // ============================================================
    // Helper tasks
    // ============================================================

    task automatic apply_reset;
        begin
            @(negedge clk);

            reset       = 1'b1;
            input_valid = 1'b0;
            output_ready = 1'b0;

            repeat (2) @(posedge clk);

            @(negedge clk);

            reset = 1'b0;

            #1;

            assert (input_ready)
                else $fatal(
                    1,
                    "FIFO not input-ready after reset"
                );

            assert (!output_valid)
                else $fatal(
                    1,
                    "FIFO output_valid asserted after reset"
                );

            assert (model_queue.size() == 0)
                else $fatal(
                    1,
                    "Reference queue not empty after reset"
                );
        end
    endtask


    // Store exactly one byte without consuming output.
    task automatic push_only(
        input logic [DATA_WIDTH-1:0] value
    );
        begin
            @(negedge clk);

            input_data   = value;
            input_valid  = 1'b1;
            output_ready = 1'b0;

            #1;

            assert (input_ready)
                else $fatal(
                    1,
                    "push_only called while FIFO could not accept input"
                );

            @(posedge clk);

            @(negedge clk);

            input_valid = 1'b0;
        end
    endtask


    // Consume exactly one stored byte without inserting anything.
    task automatic pop_only;
        begin
            @(negedge clk);

            input_valid  = 1'b0;
            output_ready = 1'b1;

            #1;

            assert (output_valid)
                else $fatal(
                    1,
                    "pop_only called while FIFO empty"
                );

            @(posedge clk);

            @(negedge clk);

            output_ready = 1'b0;
        end
    endtask


    task automatic drain_fifo;
        begin
            while (model_queue.size() != 0) begin
                pop_only();
            end
        end
    endtask


    // ============================================================
    // Test sequence
    // ============================================================

    initial begin : tests

        integer i;
        integer round;
        integer cycle;

        logic [DATA_WIDTH-1:0] blocked_value;


        // --------------------------------------------------------
        // Initial values
        // --------------------------------------------------------

        reset = 1'b0;

        input_data   = '0;
        input_valid  = 1'b0;
        output_ready = 1'b0;


        // --------------------------------------------------------
        // 1. Reset / empty behavior
        // --------------------------------------------------------

        $display(
            "TEST 1: reset / empty behavior, depth=%0d width=%0d",
            DATA_DEPTH,
            DATA_WIDTH
        );

        apply_reset();

        repeat (3) begin
            @(negedge clk);
            #1;

            assert (input_ready)
                else $fatal(
                    1,
                    "Empty FIFO should accept input"
                );

            assert (!output_valid)
                else $fatal(
                    1,
                    "Empty FIFO unexpectedly has valid output"
                );
        end


        // --------------------------------------------------------
        // 2. Empty simultaneous fall-through
        //
        // Input and output transfer on the same cycle.
        // FIFO remains empty; pointers do not advance.
        // --------------------------------------------------------

        $display("TEST 2: empty fall-through transaction");

        @(negedge clk);

        input_data   = DATA_WIDTH'(8'hA5);
        input_valid  = 1'b1;
        output_ready = 1'b1;

        #1;

        assert (input_ready)
            else $fatal(
                1,
                "Fall-through input was not ready"
            );

        assert (output_valid)
            else $fatal(
                1,
                "Fall-through output was not valid"
            );

        assert (output_data === DATA_WIDTH'(8'hA5))
            else $fatal(
                1,
                "Fall-through output mismatch"
            );

        @(posedge clk);

        @(negedge clk);

        input_valid  = 1'b0;
        output_ready = 1'b0;

        #1;

        assert (model_queue.size() == 0)
            else $fatal(
                1,
                "Empty fall-through transaction incorrectly occupied FIFO"
            );

        assert (!output_valid)
            else $fatal(
                1,
                "FIFO not empty after pure bypass"
            );


        // --------------------------------------------------------
        // 3. Empty input with stalled consumer
        //
        // Byte initially appears through fall-through path, but since
        // consumer does not take it, the FIFO must store it.
        // --------------------------------------------------------

        $display("TEST 3: empty fall-through with output stall");

        @(negedge clk);

        input_data   = DATA_WIDTH'(8'h3C);
        input_valid  = 1'b1;
        output_ready = 1'b0;

        #1;

        assert (input_ready)
            else $fatal(
                1,
                "Empty FIFO did not accept stalled fall-through input"
            );

        assert (output_valid)
            else $fatal(
                1,
                "Fall-through output not valid"
            );

        assert (output_data === DATA_WIDTH'(8'h3C))
            else $fatal(
                1,
                "Wrong fall-through value"
            );

        @(posedge clk);

        @(negedge clk);

        input_valid = 1'b0;

        repeat (3) begin
            #1;

            assert (output_valid)
                else $fatal(
                    1,
                    "Stored fall-through byte disappeared"
                );

            assert (output_data === DATA_WIDTH'(8'h3C))
                else $fatal(
                    1,
                    "Stored fall-through byte changed"
                );

            @(posedge clk);
            @(negedge clk);
        end

        pop_only();

        assert (model_queue.size() == 0)
            else $fatal(
                1,
                "FIFO not empty after consuming stored byte"
            );


        // --------------------------------------------------------
        // 4. Basic push / pop
        // --------------------------------------------------------

        $display("TEST 4: basic push / pop");

        push_only(DATA_WIDTH'(8'h11));
        push_only(DATA_WIDTH'(8'h22));
        push_only(DATA_WIDTH'(8'h33));

        pop_only();
        pop_only();
        pop_only();

        assert (model_queue.size() == 0)
            else $fatal(
                1,
                "Basic push/pop did not return FIFO to empty"
            );


        // --------------------------------------------------------
        // 5. Fill completely
        // --------------------------------------------------------

        $display("TEST 5: fill to full");

        for (i = 0; i < DATA_DEPTH; i = i + 1) begin
            push_only(
                DATA_WIDTH'(i + 1)
            );
        end

        #1;

        assert (dut.full)
            else $fatal(
                1,
                "FIFO did not assert full"
            );

        assert (!input_ready)
            else $fatal(
                1,
                "Full FIFO accepted input without simultaneous pop"
            );


        // --------------------------------------------------------
        // 6. Attempt blocked push while full
        // --------------------------------------------------------

        $display("TEST 6: blocked input while full");

        blocked_value = DATA_WIDTH'(8'hE7);

        @(negedge clk);

        input_data   = blocked_value;
        input_valid  = 1'b1;
        output_ready = 1'b0;

        repeat (3) begin
            #1;

            assert (!input_ready)
                else $fatal(
                    1,
                    "Full FIFO asserted input_ready without a pop"
                );

            assert (output_valid)
                else $fatal(
                    1,
                    "Full FIFO lost output_valid"
                );

            @(posedge clk);
            @(negedge clk);
        end


        // --------------------------------------------------------
        // 7. Full simultaneous pop + push
        //
        // The previously-blocked E7 is accepted exactly when the
        // oldest stored byte leaves. Occupancy remains DATA_DEPTH.
        // --------------------------------------------------------

        $display("TEST 7: full simultaneous pop / push");

        output_ready = 1'b1;

        #1;

        assert (input_ready)
            else $fatal(
                1,
                "Full FIFO did not allow replacement during pop"
            );

        assert (output_valid)
            else $fatal(
                1,
                "Full FIFO had no valid output"
            );

        @(posedge clk);

        @(negedge clk);

        input_valid  = 1'b0;
        output_ready = 1'b0;

        #1;

        assert (dut.full)
            else $fatal(
                1,
                "FIFO should remain full after simultaneous replacement"
            );

        assert (model_queue.size() == DATA_DEPTH)
            else $fatal(
                1,
                "Model occupancy changed during full replacement"
            );


        // Drain it. The scoreboard verifies that E7 appears after
        // all of the surviving original entries.
        drain_fifo();

        assert (model_queue.size() == 0)
            else $fatal(
                1,
                "FIFO failed to drain"
            );


        // --------------------------------------------------------
        // 8. Continuous simultaneous transfers
        //
        // Keep one item resident. Every cycle consumes the current
        // head and inserts a replacement. This repeatedly advances
        // both pointers and forces wraparound.
        // --------------------------------------------------------

        $display("TEST 8: continuous simultaneous transfers");

        push_only(DATA_WIDTH'(8'h40));

        for (
            i = 0;
            i < (DATA_DEPTH * 3 + 5);
            i = i + 1
        ) begin

            @(negedge clk);

            input_data   = DATA_WIDTH'(8'h50 + i);
            input_valid  = 1'b1;
            output_ready = 1'b1;

            #1;

            assert (input_ready)
                else $fatal(
                    1,
                    "FIFO unexpectedly blocked simultaneous transfer"
                );

            assert (output_valid)
                else $fatal(
                    1,
                    "FIFO unexpectedly lacked output during simultaneous transfer"
                );

            @(posedge clk);
        end

        @(negedge clk);

        input_valid  = 1'b0;
        output_ready = 1'b0;

        #1;

        assert (model_queue.size() == 1)
            else $fatal(
                1,
                "Continuous simultaneous traffic changed occupancy: %0d",
                model_queue.size()
            );

        pop_only();


        // --------------------------------------------------------
        // 9. Repeated fill/drain wraparound
        //
        // Particularly important for non-power-of-two DATA_DEPTH.
        // --------------------------------------------------------

        $display("TEST 9: repeated pointer wraparound");

        for (round = 0; round < 4; round = round + 1) begin

            for (i = 0; i < DATA_DEPTH; i = i + 1) begin

                push_only(
                    DATA_WIDTH'(
                        (round * DATA_DEPTH) + i + 1
                    )
                );

            end

            assert (dut.full)
                else $fatal(
                    1,
                    "FIFO did not become full in wraparound round %0d",
                    round
                );

            drain_fifo();

            assert (model_queue.size() == 0)
                else $fatal(
                    1,
                    "FIFO not empty after wraparound round %0d",
                    round
                );
        end


        // --------------------------------------------------------
        // 10. Reset while occupied
        // --------------------------------------------------------

        $display("TEST 10: reset while occupied");

        for (
            i = 0;
            i < ((DATA_DEPTH < 3) ? DATA_DEPTH : 3);
            i = i + 1
        ) begin
            push_only(
                DATA_WIDTH'(8'h90 + i)
            );
        end

        assert (model_queue.size() != 0)
            else $fatal(
                1,
                "Failed to create occupied FIFO before reset"
            );

        apply_reset();

        #1;

        assert (dut.empty)
            else $fatal(
                1,
                "FIFO not empty after reset"
            );

        assert ($unsigned(dut.read_ptr) == 0)
            else $fatal(
                1,
                "Read pointer did not reset"
            );

        assert ($unsigned(dut.write_ptr) == 0)
            else $fatal(
                1,
                "Write pointer did not reset"
            );


        // --------------------------------------------------------
        // 11. Randomized stress
        //
        // The source obeys ready/valid: if blocked, input_valid and
        // input_data remain unchanged until accepted.
        //
        // output_ready may change independently every cycle.
        // --------------------------------------------------------

        $display("TEST 11: randomized stress");

        input_valid  = 1'b0;
        output_ready = 1'b0;

        for (cycle = 0; cycle < 5000; cycle = cycle + 1) begin

            @(negedge clk);

            // Only change producer signals if the previous offered
            // input is not currently stalled.
            if (!(input_valid && !input_ready)) begin

                if ($urandom_range(0, 99) < 70) begin
                    input_valid = 1'b1;
                    input_data =
                        DATA_WIDTH'($urandom());
                end
                else begin
                    input_valid = 1'b0;
                end
            end

            // Consumer is independently ready ~60% of cycles.
            output_ready =
                ($urandom_range(0, 99) < 60);
        end


        // --------------------------------------------------------
        // Finish any currently-offered input
        // --------------------------------------------------------

        @(negedge clk);

        output_ready = 1'b1;

        if (input_valid) begin

            #1;

            assert (input_ready)
                else $fatal(
                    1,
                    "FIFO could not accept pending input while consumer ready"
                );

            @(posedge clk);

            @(negedge clk);

            input_valid = 1'b0;
        end


        // --------------------------------------------------------
        // Drain everything remaining
        // --------------------------------------------------------

        output_ready = 1'b1;

        while (model_queue.size() != 0) begin
            @(posedge clk);
        end

        @(negedge clk);

        output_ready = 1'b0;

        #1;

        assert (dut.empty)
            else $fatal(
                1,
                "FIFO not empty after randomized stress drain"
            );

        assert (!output_valid)
            else $fatal(
                1,
                "output_valid remained asserted after final drain"
            );


        // --------------------------------------------------------
        // Finished
        // --------------------------------------------------------

        $display(
            "PASS: sync_fifo depth=%0d width=%0d, input transfers=%0d, output transfers=%0d",
            DATA_DEPTH,
            DATA_WIDTH,
            input_transfer_count,
            output_transfer_count
        );

        $finish;
    end

endmodule
