`timescale 1ns/1ps

module framer (
    input logic clk,
    input logic reset,

    input logic frame_start,
    output logic frame_start_ready,

    input logic [7:0] frame_type,
    input logic [7:0] seq,
    input logic [7:0] payload_length,

    input logic [7:0] payload_data,
    input logic payload_valid,
    output logic payload_ready,

    output logic [7:0] frame_data,
    output logic frame_valid,
    input logic frame_ready
);

    typedef enum logic [2:0] {
        IDLE,
        PREAMBLE,
        TYPE,
        SEQ,
        LENGTH,
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
        frame_data = '0;
        frame_valid = 1'b0;
        frame_start_ready = 1'b0;
        payload_ready = 1'b0;

        case (state)
            IDLE: begin
                frame_valid = 1'b0;
                frame_start_ready = 1'b1;
            end
            PREAMBLE: begin
                frame_data = preamble;
                frame_valid = 1'b1;
            end
            TYPE: begin
                frame_data = frame_type_ff;
                frame_valid = 1'b1;
            end
            SEQ: begin
                frame_data = seq_ff;
                frame_valid = 1'b1;
            end
            LENGTH: begin
                frame_data = payload_length_ff;
                frame_valid = 1'b1;
            end
            PAYLOAD: begin
                frame_data = payload_data;
                frame_valid = payload_valid;
                frame_start_ready = frame_ready && (payload_counter == payload_length_ff - 8'd1) && payload_valid;
                payload_ready = frame_ready;
            end
            default: begin
                ;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            payload_counter <= '0;
            state <= IDLE;
        end
        else begin
            case (state)
                IDLE: begin
                    if (frame_start && frame_start_ready) begin
                        state <= PREAMBLE;
                        frame_type_ff <= frame_type;
                        seq_ff <= seq;
                        payload_length_ff <= payload_length;
                        payload_counter <= '0;
                    end
                end
                PREAMBLE: begin
                    if (frame_ready && frame_valid) begin // don't really need to check frame valid here
                        state <= TYPE;
                    end
                end
                TYPE: begin
                    if (frame_ready && frame_valid) begin // don't really need to check frame valid here
                        state <= SEQ;
                    end
                end
                SEQ: begin
                    if (frame_ready && frame_valid) begin // don't really need to check frame valid here
                        state <= LENGTH;
                    end
                end
                LENGTH: begin
                    if (frame_ready && frame_valid) begin // don't really need to check frame valid here
                        if (payload_length_ff == 8'd0) begin
                            state <= IDLE; // CHANGE WHEN ADDING CRC
                        end
                        else begin
                            state <= PAYLOAD;
                        end
                    end
                end
                PAYLOAD: begin
                    if (frame_ready && frame_valid) begin
                        if (payload_counter == payload_length_ff - 8'd1) begin
                            if (frame_start && frame_start_ready) begin
                                state <= PREAMBLE;
                                frame_type_ff <= frame_type;
                                seq_ff <= seq;
                                payload_length_ff <= payload_length;
                            end
                            else begin
                                state <= IDLE;

                            end
                            payload_counter <= '0;
                        end
                        else begin
                            payload_counter <= payload_counter + 8'd1;
                        end
                    end
                end
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
