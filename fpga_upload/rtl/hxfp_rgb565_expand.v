// Combinational adapter. Pixel stream is top-down; do NOT apply BMP vertical flip.
module hxfp_rgb565_expand(input wire [15:0] rgb565, output wire [31:0] rgb888_word);
    assign rgb888_word = {8'd0,
        rgb565[15:11],rgb565[15:13],
        rgb565[10:5],rgb565[10:9],
        rgb565[4:0],rgb565[4:2]};
endmodule
