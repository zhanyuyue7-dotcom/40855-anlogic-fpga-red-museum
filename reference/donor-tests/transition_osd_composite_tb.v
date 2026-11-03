`timescale 1ns/1ps
module transition_osd_composite_tb;
    reg de=1'b1;
    reg [23:0] rgb=24'd0;
    reg [5:0] scale=6'd32;
    reg bypass=1'b0;
    wire [23:0] faded_rgb;
    wire [23:0] disabled_rgb;

    transition_rgb_scale #(.SMOOTH(1),.ENABLE(1)) dut(
        .de(de),.rgb_in(rgb),.scale(scale),.bypass(bypass),.rgb_out(faded_rgb)
    );
    transition_rgb_scale #(.SMOOTH(1),.ENABLE(0)) disabled(
        .de(de),.rgb_in(rgb),.scale(scale),.bypass(bypass),.rgb_out(disabled_rgb)
    );

    function [7:0] scaled_channel;
        input [7:0] channel;
        input [5:0] gain;
        reg [12:0] product;
        begin
            product = channel * gain;
            scaled_channel = gain[5] ? channel : product[12:5];
        end
    endfunction

    function [23:0] expected_rgb;
        input [23:0] color;
        input [5:0] gain;
        begin
            expected_rgb = {scaled_channel(color[23:16],gain),
                            scaled_channel(color[15:8],gain),
                            scaled_channel(color[7:0],gain)};
        end
    endfunction

    task expect_scaled;
        input [23:0] color;
        input [5:0] gain;
        begin
            rgb=color; scale=gain; bypass=0; de=1; #1;
            if(faded_rgb!==expected_rgb(color,gain))
                $fatal(1,"composite fade mismatch rgb=%h level=%0d got=%h expected=%h",
                    color,gain,faded_rgb,expected_rgb(color,gain));
        end
    endtask

    initial begin
        // Exercise a BMP pixel, the OSD panel, its accent border and white text.
        expect_scaled(24'hc04020,32);
        expect_scaled(24'h101820,16);
        expect_scaled(24'h45b8ac,1);
        expect_scaled(24'hffffff,0);
        if(faded_rgb!==24'h000000)
            $fatal(1,"OSD text remained visible at the black fade level");

        // Notice/emergency scenes are intentionally presented at full strength.
        rgb=24'hc82020; scale=0; bypass=1; de=1; #1;
        if(faded_rgb!==rgb)
            $fatal(1,"event scene was incorrectly dimmed by ordinary-image fade");

        // Blanking remains black when fade is enabled; compile-time disable is
        // an exact RGB bypass, matching the existing E2 diagnostic contract.
        rgb=24'habcdef; bypass=0; de=0; #1;
        if(faded_rgb!==24'h000000)
            $fatal(1,"enabled compositor leaked RGB during blanking");
        if(disabled_rgb!==rgb)
            $fatal(1,"disabled compositor was not an exact RGB bypass");

        $display("PASS: BMP, OSD panel/border/text fade together; black is clean and event scenes bypass ordinary fade");
        $finish;
    end
endmodule
