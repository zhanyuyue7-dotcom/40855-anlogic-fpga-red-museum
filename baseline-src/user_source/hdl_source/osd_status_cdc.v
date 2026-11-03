// Stable-data mailbox for the BMP state nibble: SD clock -> pixel clock.
module osd_status_cdc #(parameter integer WIDTH=4, parameter integer ONLY_ON_CHANGE=1)(input wire source_clk, pixel_clk, rst,
    input wire [WIDTH-1:0] source_state, output reg [WIDTH-1:0] pixel_state);
    reg [WIDTH-1:0] held_state;
    reg request_toggle, ack_toggle;
    (* async_reg = "true" *) reg [1:0] request_sync, ack_sync;
    (* async_reg = "true" *) reg [1:0] source_reset, pixel_reset;
    always @(posedge source_clk or posedge rst) begin
        if (rst) source_reset <= 2'b11;
        else source_reset <= {source_reset[0], 1'b0};
    end
    always @(posedge pixel_clk or posedge rst) begin
        if (rst) pixel_reset <= 2'b11;
        else pixel_reset <= {pixel_reset[0], 1'b0};
    end
    always @(posedge source_clk or posedge source_reset[1]) begin
        if (source_reset[1]) begin held_state<=0; request_toggle<=0; ack_sync<=0; end
        else begin
            ack_sync <= {ack_sync[0], ack_toggle};
            if (ack_sync[1] == request_toggle && (!ONLY_ON_CHANGE || source_state != held_state)) begin
                held_state <= source_state;
                request_toggle <= ~request_toggle;
            end
        end
    end
    always @(posedge pixel_clk or posedge pixel_reset[1]) begin
        if (pixel_reset[1]) begin request_sync<=0; ack_toggle<=0; pixel_state<=0; end
        else begin
            request_sync <= {request_sync[0], request_toggle};
            if (request_sync[1] != ack_toggle) begin
                pixel_state <= held_state;
                ack_toggle <= request_sync[1];
            end
        end
    end
endmodule
