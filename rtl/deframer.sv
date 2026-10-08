`timescale 1ns/1ps

module deframer (
    input logic clk,
    input logic reset,

    input logic [7:0] input_data,
    input logic input_valid,
    output logic input_ready,

    output logic frame_start,
    input logic frame_start_ready,
    output logic [7:0] frame_type,
    output logic [7:0] seq,
    output logic [7:0] payload_length,

    output logic [7:0] payload_data,
    output logic payload_valid,
    input logic payload_ready
);

    typedef enum logic [2:0] {
        FIND_PREAMBLE,
        TYPE,
        SEQ,
        LENGTH,
        DESCRIPTOR,
        PAYLOAD
        // , CRC
    } state_t;

    localparam logic [7:0] preamble = 8'h55;
//    localparam logic [7:0] FRAME_TYPE_DATA = 8'd01;
  //  localparam logic [7:0] FRAME_TYPE_ACK = 8'd02;
    //localparam logic [7:0] FRAME_TYPE_DATA_ACK = 8'd03;
    //localparam logic [7:0] FRAME_TYPE_CONTROL = 8'd04;

    state_t state;

    logic [7:0] frame_type_ff;
    logic [7:0] seq_ff;
    logic [7:0] payload_length_ff;
    logic [7:0] payload_counter;
    
    always_comb begin
        payload_data = '0;
        payload_valid = 1'b0;

        input_ready = 1'b0;

        frame_start = 1'b0;
        frame_type = frame_type_ff;
        seq = seq_ff;
        payload_length = payload_length_ff;

        case (state)
            FIND_PREAMBLE: begin
                input_ready = 1'b1;
            end
            TYPE: begin
                input_ready = 1'b1;
            end
            SEQ: begin
                input_ready = 1'b1;
            end
            LENGTH: begin
                input_ready = 1'b1;
            end
            DESCRIPTOR: begin
                input_ready = 1'b1;
            end
            PAYLOAD: begin
                payload_data = input_data;
                payload_valid = input_valid;
                input_ready = payload_ready;
            end
            default: begin
                ;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            payload_counter <= '0;
            state <= FIND_PREAMBLE;
        end
        else begin
            case (state)
                FIND_PREAMBLE: begin
                    if (input_valid && input_ready) begin // input_ready should be implied
                        if (input_data === preamble) begin
                            state <= TYPE;
                        end
                        payload_counter <= '0;
                    end
                end
                TYPE: begin
                    if (input_valid && input_ready) begin // don't really need to check input valid here
                        state <= SEQ;
                        frame_type_ff <= input_data;
                        // do we check if it's valid here?
                    end
                end
                SEQ: begin
                    if (input_valid && input_ready) begin // don't really need to check input valid here
                        state <= LENGTH;
                        seq_ff <= input_data;
                    end
                end
                LENGTH: begin
                    if (input_valid && input_ready) begin // don't really need to check input valid here
                        state <= DESCRIPTOR;
                        payload_length_ff <= input_data;
                    end
                end
                DESCRIPTOR: begin
                    if (frame_start && frame_start_ready) begin // don't really need to check input valid here
                        if (payload_length_ff === 8'd0) begin
                            state <= FIND_PREAMBLE;
                        end
                        else begin
                            state <= PAYLOAD;
                        end
                    end
                end
                PAYLOAD: begin
                    if (payload_valid && payload_ready) begin
                        if (payload_counter == payload_length_ff - 8'd1) begin
                            payload_counter <= '0;
                            state <= FIND_PREAMBLE;
                        end
                        else begin
                            payload_counter <= payload_counter + 8'd1;
                        end
                    end
                end
                default: begin
                    state <= FIND_PREAMBLE;
                end
            endcase
        end
    end
endmodule
