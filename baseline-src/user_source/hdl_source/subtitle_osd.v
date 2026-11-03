// v3 ordinary-scene OSD. Control/storage/audio/brightness algorithms are unchanged.
// One synchronous ROM stage aligned with pixel, mask, foreground, and sync signals.
// Layout authority: UI_V3_IMPLEMENTATION.md; glyph maps: assets/osd-font-{20,24}.
module subtitle_osd(
    input wire clk, rst, hs, vs, de,
    input wire [23:0] rgb,
    input wire [1:0] scene_id,
    input wire [3:0] run_state,
    input wire [1:0] brightness_level,
    input wire adjust_mode,
    output reg hs_out, vs_out, de_out,
    output wire [23:0] rgb_out,
    input wire [5:0] ui_fade_level
);
    localparam [23:0] CREAM=24'hf5e6d3, RED=24'h8b0000,
                      INK=24'h3e2723, GOLD=24'hd4af37;
    reg vs_prev,de_prev,frame_started;
    reg [9:0] x,y;
    reg [1:0] frame_scene,frame_brightness;
    reg [3:0] frame_state;
    reg frame_adjust;
    wire boundary=vs_prev && !vs && !de;
    wire ordinary=frame_scene==0;
    wire [23:0] legacy_rgb;
    wire legacy_hs,legacy_vs,legacy_de;
    subtitle_osd_legacy u_legacy_overlay(
        .clk(clk),.rst(rst),.hs(hs),.vs(vs),.de(de),.rgb(rgb),
        .scene_id(scene_id),.run_state(run_state),.brightness_level(brightness_level),
        .adjust_mode(adjust_mode),.hs_out(legacy_hs),.vs_out(legacy_vs),
        .de_out(legacy_de),.rgb_out(legacy_rgb));

    reg [5:0] state_first,state_second;
    always @* begin
        case(frame_state)
            0,3: begin state_first=6'd11;state_second=6'd21;end
            1: begin state_first=6'd22;state_second=6'd23;end
            2: begin state_first=6'd24;state_second=6'd25;end
            4: begin state_first=6'd26;state_second=6'd27;end
            default: begin state_first=6'd28;state_second=6'd29;end
        endcase
    end
    reg [5:0] glyph24,glyph20;
    reg [4:0] row24,row20,col24,col20;
    reg text24,text20;
    reg [23:0] ink;
    wire [23:0] bits24;
    wire [19:0] bits20;
    always @* begin
        glyph24=0;glyph20=0;row24=0;row20=0;col24=0;col20=0;
        text24=0;text20=0;ink=INK;
        if(ordinary && x>=10'd20 && x<10'd44 && y>=10'd8 && y<10'd32) begin
            text24=1;glyph24=6'd1;row24=y-10'd8;col24=x-10'd20+5'd0;
        end
        if(ordinary && x>=10'd44 && x<10'd68 && y>=10'd8 && y<10'd32) begin
            text24=1;glyph24=6'd2;row24=y-10'd8;col24=x-10'd44+5'd0;
        end
        if(ordinary && x>=10'd76 && x<10'd100 && y>=10'd8 && y<10'd32) begin
            text24=1;glyph24=6'd37;row24=y-10'd8;col24=x-10'd76+5'd0;
        end
        if(ordinary && x>=10'd100 && x<10'd124 && y>=10'd8 && y<10'd32) begin
            text24=1;glyph24=6'd38;row24=y-10'd8;col24=x-10'd100+5'd0;
        end
        if(ordinary && x>=10'd124 && x<10'd148 && y>=10'd8 && y<10'd32) begin
            text24=1;glyph24=6'd39;row24=y-10'd8;col24=x-10'd124+5'd0;
        end
        if(ordinary && x>=10'd148 && x<10'd172 && y>=10'd8 && y<10'd32) begin
            text24=1;glyph24=6'd40;row24=y-10'd8;col24=x-10'd148+5'd0;
        end
        if(ordinary && x>=10'd200 && x<10'd224 && y>=10'd8 && y<10'd32) begin
            text24=1;glyph24=6'd11;row24=y-10'd8;col24=x-10'd200+5'd0;
        end
        if(ordinary && x>=10'd224 && x<10'd248 && y>=10'd8 && y<10'd32) begin
            text24=1;glyph24=6'd12;row24=y-10'd8;col24=x-10'd224+5'd0;
        end
        if(ordinary && x>=10'd256 && x<10'd280 && y>=10'd8 && y<10'd32) begin
            text24=1;glyph24=6'd13;row24=y-10'd8;col24=x-10'd256+5'd0;
        end
        if(ordinary && x>=10'd220 && x<10'd244 && y>=10'd414 && y<10'd438) begin
            text24=1;glyph24=6'd41;row24=y-10'd414;col24=x-10'd220+5'd0;ink=GOLD;
        end
        if(ordinary && x>=10'd244 && x<10'd268 && y>=10'd414 && y<10'd438) begin
            text24=1;glyph24=6'd42;row24=y-10'd414;col24=x-10'd244+5'd0;ink=GOLD;
        end
        if(ordinary && x>=10'd268 && x<10'd292 && y>=10'd414 && y<10'd438) begin
            text24=1;glyph24=6'd43;row24=y-10'd414;col24=x-10'd268+5'd0;ink=GOLD;
        end
        if(ordinary && x>=10'd292 && x<10'd316 && y>=10'd414 && y<10'd438) begin
            text24=1;glyph24=6'd44;row24=y-10'd414;col24=x-10'd292+5'd0;ink=GOLD;
        end
        if(ordinary && x>=10'd324 && x<10'd348 && y>=10'd414 && y<10'd438) begin
            text24=1;glyph24=6'd45;row24=y-10'd414;col24=x-10'd324+5'd0;ink=GOLD;
        end
        if(ordinary && x>=10'd348 && x<10'd372 && y>=10'd414 && y<10'd438) begin
            text24=1;glyph24=6'd46;row24=y-10'd414;col24=x-10'd348+5'd0;ink=GOLD;
        end
        if(ordinary && x>=10'd372 && x<10'd396 && y>=10'd414 && y<10'd438) begin
            text24=1;glyph24=6'd47;row24=y-10'd414;col24=x-10'd372+5'd0;ink=GOLD;
        end
        if(ordinary && x>=10'd396 && x<10'd420 && y>=10'd414 && y<10'd438) begin
            text24=1;glyph24=6'd48;row24=y-10'd414;col24=x-10'd396+5'd0;ink=GOLD;
        end
        if(ordinary && x>=10'd20 && x<10'd40 && y>=10'd452 && y<10'd472) begin
            text20=1;glyph20=6'd19;row20=y-10'd452;col20=x-10'd20+5'd0;
        end
        if(ordinary && x>=10'd40 && x<10'd60 && y>=10'd452 && y<10'd472) begin
            text20=1;glyph20=6'd20;row20=y-10'd452;col20=x-10'd40+5'd0;
        end
        if(ordinary && x>=10'd60 && x<10'd80 && y>=10'd452 && y<10'd472) begin
            text20=1;glyph20=6'd56;row20=y-10'd452;col20=x-10'd60+5'd0;
        end
        if(ordinary && x>=10'd80 && x<10'd100 && y>=10'd452 && y<10'd472) begin
            text20=1;glyph20=6'd57;row20=y-10'd452;col20=x-10'd80+5'd0;
        end
        if(ordinary && x>=10'd100 && x<10'd110 && y>=10'd452 && y<10'd472) begin
            text20=1;glyph20=6'd52;row20=y-10'd452;col20=x-10'd100+5'd5;
        end
        if(ordinary && x>=10'd110 && x<10'd130 && y>=10'd452 && y<10'd472) begin
            text20=1;glyph20=state_first;row20=y-10'd452;col20=x-10'd110+5'd0;
        end
        if(ordinary && x>=10'd130 && x<10'd150 && y>=10'd452 && y<10'd472) begin
            text20=1;glyph20=state_second;row20=y-10'd452;col20=x-10'd130+5'd0;
        end
        if(ordinary && x>=10'd212 && x<10'd232 && y>=10'd452 && y<10'd472) begin
            text20=1;glyph20=6'd30;row20=y-10'd452;col20=x-10'd212+5'd0;
        end
        if(ordinary && x>=10'd232 && x<10'd252 && y>=10'd452 && y<10'd472) begin
            text20=1;glyph20=6'd31;row20=y-10'd452;col20=x-10'd232+5'd0;
        end
        if(ordinary && x>=10'd450 && x<10'd470 && y>=10'd452 && y<10'd472) begin
            text20=1;glyph20=frame_adjust ? 6'd35 : 6'd19;row20=y-10'd452;col20=x-10'd450+5'd0;
        end
        if(ordinary && x>=10'd470 && x<10'd490 && y>=10'd452 && y<10'd472) begin
            text20=1;glyph20=frame_adjust ? 6'd36 : 6'd20;row20=y-10'd452;col20=x-10'd470+5'd0;
        end
    end
    osd_glyph_rom_24 u_24(.clk(clk),.glyph_id(glyph24),.row(row24),.row_bits(bits24));
    osd_glyph_rom_20 u_20(.clk(clk),.glyph_id(glyph20),.row(row20),.row_bits(bits20));
    wire [9:0] fill_width=frame_brightness==0 ? 10'd29 :
                          frame_brightness==1 ? 10'd58 :
                          frame_brightness==2 ? 10'd87 : 10'd116;
    wire bar=x>=260 && x<380 && y>=456 && y<464;
    wire bar_border=bar && (x<262 || x>=378 || y<458 || y>=462);
    wire bar_fill=bar && x>=262 && x<262+fill_width && y>=458 && y<462;
    reg [23:0] base;
    always @* begin
        base=rgb;
        if(y<36 || y>=408) base=CREAM;
        // Footer (including slogan and bar) moved down 12px; shared line at y=440.
        if(y==35 || y==408 || y==440 ||
           ((x==155 || x==410) && y>=450 && y<474) || bar_border || bar_fill) base=RED;
    end
    reg [23:0] base_d,ink_d,rgb_d;
    reg text24_d,text20_d,ordinary_d,ui_active_d;
    reg [4:0] col24_d,col20_d;
    wire ui_active = ordinary && (y < 10'd36 || y >= 10'd408 || text24 || text20);
    function [7:0] blend_channel;
        input [7:0] under;
        input [7:0] over;
        input [5:0] gain;
        reg [12:0] sum;
        reg [5:0] inverse_gain;
        integer bit_index;
        begin
            if (gain[5]) blend_channel = over;
            else if (gain == 6'd0) blend_channel = under;
            else begin
                inverse_gain = 6'd32 - gain;
                sum = 13'd0;
                for (bit_index=0; bit_index<5; bit_index=bit_index+1) begin
                    if (inverse_gain[bit_index]) sum = sum + ({5'd0,under} << bit_index);
                    if (gain[bit_index]) sum = sum + ({5'd0,over} << bit_index);
                end
                blend_channel = sum[12:5];
            end
        end
    endfunction
    function [23:0] blend_ui;
        input [23:0] under;
        input [23:0] over;
        input [5:0] gain;
        begin
            blend_ui = {blend_channel(under[23:16],over[23:16],gain),
                        blend_channel(under[15:8],over[15:8],gain),
                        blend_channel(under[7:0],over[7:0],gain)};
        end
    endfunction
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            vs_prev<=0;de_prev<=0;frame_started<=0;x<=0;y<=0;
            frame_scene<=0;frame_state<=0;frame_brightness<=3;frame_adjust<=0;
            hs_out<=0;vs_out<=0;de_out<=0;base_d<=0;ink_d<=INK;rgb_d<=0;
            text24_d<=0;text20_d<=0;col24_d<=0;col20_d<=0;ordinary_d<=1;ui_active_d<=0;
        end else begin
            vs_prev<=vs;de_prev<=de;
            if(boundary) begin x<=0;y<=0;frame_started<=0;end
            else if(de) begin x<=x+1'b1;frame_started<=1;end
            else if(de_prev) begin x<=0;y<=y+1'b1;end
            if(!de && !frame_started) begin
                frame_scene<=scene_id;frame_state<=run_state;
                frame_brightness<=brightness_level;frame_adjust<=adjust_mode;
            end
            hs_out<=hs;vs_out<=vs;de_out<=de;
            base_d<=base;ink_d<=ink;rgb_d<=rgb;ordinary_d<=ordinary;ui_active_d<=ui_active;
            text24_d<=text24;text20_d<=text20;col24_d<=col24;col20_d<=col20;
        end
    end
    wire glyph_on=(text24_d && bits24[23-col24_d]) || (text20_d && bits20[19-col20_d]);
    wire [23:0] ui_color = glyph_on ? ink_d : base_d;
    wire [23:0] ui_faded_color = blend_ui(rgb_d, ui_color, ui_fade_level);
    assign rgb_out=!de_out ? 24'd0 : ordinary_d ? (ui_active_d ? ui_faded_color : rgb_d) : legacy_rgb;
endmodule
