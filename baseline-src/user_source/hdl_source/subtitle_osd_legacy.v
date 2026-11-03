// E1: synchronous glyph ROM + one aligned stage for RGB/DE/HS/VS.
module subtitle_osd_legacy(
    input wire clk, rst, hs, vs, de,
    input wire [23:0] rgb,
    input wire [1:0] scene_id,
    input wire [3:0] run_state,
    input wire [1:0] brightness_level,
    input wire adjust_mode,
    output reg hs_out, vs_out, de_out,
    output wire [23:0] rgb_out
);
    reg vs_prev, de_prev, frame_started;
    reg [9:0] x, y;
    reg [1:0] frame_scene;
    reg [1:0] frame_brightness;
    reg [3:0] frame_state;
    reg frame_adjust;
    reg [23:0] background_d, accent_d;
    reg panel_d, border_d, text_d;
    reg [3:0] column_d;
    reg [5:0] glyph_id;
    wire [15:0] row_bits;
    wire boundary = vs_prev && !vs && !de;
    wire top_panel = x>=16 && x<624 && y>=16 && y<72;
    wire bottom_panel = x>=16 && x<624 && y>=408 && y<464;
    wire top_text = x>=32 && x<384 && y>=28 && y<60;
    wire bottom_text = x>=32 && x<192 && y>=420 && y<452;
    wire parameter_text = x>=224 && x<608 && y>=420 && y<452;
    wire border = (top_panel && (y<18 || y>=70)) ||
                  (bottom_panel && (y<410 || y>=462));
    wire [9:0] text_x = parameter_text ? x-10'd224 : x-10'd32;
    wire [9:0] text_y = top_text ? y-10'd28 : y-10'd420;
    wire [3:0] character_column = text_x[8:5];
    wire [23:0] accent = frame_scene==2 ? 24'hc82020 :
                        frame_scene==1 ? 24'he0a020 : 24'h45b8ac;
    always @* begin
        glyph_id=0;
        if (top_text) begin
            case (character_column)
                0: glyph_id=1; // 场
                1: glyph_id=2; // 景
                3: glyph_id=frame_scene==2 ? 9 : frame_scene==1 ? 7 : 3;
                4: glyph_id=frame_scene==2 ? 10 : frame_scene==1 ? 8 : 4;
                5: glyph_id=frame_scene==0 ? 5 : 0;
                6: glyph_id=frame_scene==0 ? 6 : 0;
                8: glyph_id=11; // 等
                9: glyph_id=12; // 级
                10: glyph_id=13+frame_scene;
                default: glyph_id=0;
            endcase
        end else if (bottom_text) begin
            case (character_column)
                0: glyph_id=18; // 运
                1: glyph_id=19; // 行
                3: begin
                    case (frame_state)
                        0,3: glyph_id=11; // 等
                        1: glyph_id=21; // 空
                        2: glyph_id=23; // 扫
                        4: glyph_id=25; // 加
                        default: glyph_id=27; // 未
                    endcase
                end
                4: begin
                    case (frame_state)
                        0,3: glyph_id=20; // 待
                        1: glyph_id=22; // 闲
                        2: glyph_id=24; // 描
                        4: glyph_id=26; // 载
                        default: glyph_id=28; // 知
                    endcase
                end
                default: glyph_id=0;
            endcase
        end else if (parameter_text) begin
            case (character_column)
                0: glyph_id=29; // 亮
                1: glyph_id=30; // 度
                3: begin
                    case (frame_brightness)
                        0: glyph_id=15; // 2
                        1: glyph_id=31; // 5
                        2: glyph_id=32; // 7
                        default: glyph_id=14; // 1
                    endcase
                end
                4: glyph_id=frame_brightness==3 ? 13 :
                            frame_brightness==1 ? 13 : 31;
                5: glyph_id=frame_brightness==3 ? 13 : 33; // 0 or %
                6: glyph_id=frame_brightness==3 ? 33 : 0;  // %
                8: glyph_id=frame_adjust ? 34 : 18; // 调 / 运
                9: glyph_id=frame_adjust ? 35 : 19; // 节 / 行
                default: glyph_id=0;
            endcase
        end
    end
    osd_glyph_rom u_glyph(.clk(clk), .glyph_id(glyph_id), .row(text_y[4:1]), .row_bits(row_bits));
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            vs_prev<=0; de_prev<=0; frame_started<=0; x<=0; y<=0;
            frame_scene<=0; frame_state<=0; frame_brightness<=3; frame_adjust<=0;
            hs_out<=0; vs_out<=0; de_out<=0; background_d<=0; accent_d<=0;
            panel_d<=0; border_d<=0; text_d<=0; column_d<=0;
        end else begin
            vs_prev<=vs; de_prev<=de;
            if (boundary) begin x<=0; y<=0; frame_started<=0; end
            else if (de) begin x<=x+1'b1; frame_started<=1; end
            else if (de_prev) begin x<=0; y<=y+1'b1; end
            // Capture through vertical blanking so an M3 commit on the VS
            // edge is included before the next active frame. Freeze mid-frame.
            if (!de && !frame_started) begin
                frame_scene<=scene_id;
                frame_state<=run_state;
                frame_brightness<=brightness_level;
                frame_adjust<=adjust_mode;
            end
            hs_out<=hs; vs_out<=vs; de_out<=de;
            background_d<=rgb; accent_d<=accent;
            panel_d<=top_panel || bottom_panel;
            border_d<=border; text_d<=top_text || bottom_text || parameter_text;
            column_d<=text_x[4:1];
        end
    end
    assign rgb_out = !de_out ? 24'd0 : text_d && row_bits[15-column_d] ?
        24'hffffff : border_d ? accent_d : panel_d ? 24'h101820 : background_d;
endmodule
