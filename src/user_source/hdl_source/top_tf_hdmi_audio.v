
module top(
    input                       clk,
    input                       rst_n,
    input                       key1,           // 手动下一张
    input                       key2,           // 自动播放 开/关
    input                       key_event_n,    // physical KEY3 / B1, active low
    input                       sw_emergency,   // physical SW1 / C8: up = emergency
    input                       sw_clear,       // physical SW2 / C7: rising edge = clear
    input                       sw_audio_enable,// physical SW4 / C5: up = audio on, down = mute
    input       [3:0]           keypad_rows_n,   // keypad R1..R4, active low with pull-ups
    output      [3:0]           keypad_cols_n,   // keypad C1..C4, one low / others high-Z

    output [5:0]                seg_sel,
    output [7:0]                seg_data,
    output                      uart_tx,        // CH340 RX / FPGA D12, M3 telemetry

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso,

    // External W5500 module, first local UDP-control demonstrator.
    output                      w5500_sclk,
    output                      w5500_cs_n,
    output                      w5500_mosi,
    input                       w5500_miso,
    output                      w5500_rst_n,
    input                       w5500_int_n
);

parameter integer E2_TRANSITION_ENABLE = 1;
parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 24'd307200;   // 640*480
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;

// ===================== 上电开屏动画（一次性播放） =====================
// 物料由 tools/pack_boot_video.py 生成，写入 TF 卡固定 LBA。
// 两个专用帧缓冲直接落在两个 BMP 缓冲之上：器件是 2M x 32 = 8 MiB，
// ADDR_BITS=21 正好用满，索引 2/3 是仅剩的空间，且都放得下。
parameter BOOT_VIDEO_ENABLE            = 1;
parameter [31:0] BOOT_VIDEO_START_SECTOR = 32'd262144;   // 128 MiB 处
parameter [20:0] BOOT_BUF0_ADDR        = 21'd614400;     // 2 * FRAME_PIXELS
parameter [20:0] BOOT_BUF1_ADDR        = 21'd921600;     // 3 * FRAME_PIXELS

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;
wire rst_all;


// HXFP register port is queued beside the legacy command client.
wire image_reg_start,image_reg_write,image_reg_done;
wire [15:0] image_reg_addr;
wire [4:0] image_reg_block;
wire [7:0] image_reg_wdata,image_reg_rdata;
wire merged_reg_start,merged_reg_write,merged_reg_done;
wire [15:0] merged_reg_addr;
wire [4:0] merged_reg_block;
wire [7:0] merged_reg_wdata,merged_reg_rdata;
wire image_rx_ready,image_rx_start,image_rx_valid,image_rx_end;
wire [7:0] image_rx_data;
wire [47:0] image_rx_peer,image_tx_peer;
wire image_tx_valid,image_tx_ready,image_tx_last;
wire [7:0] image_tx_data;
wire image_begin,image_begin_ready,image_commit,image_commit_ready,image_abort,image_fault;
wire image_pixel_valid,image_pixel_ready;
wire [15:0] image_pixel_rgb;
wire image_write_owner,image_write_req,image_write_en,image_scheduler_hold;
wire image_write_cancel;
wire [31:0] image_write_data;
wire [1:0] image_write_index;
wire image_display_valid;
wire [1:0] image_display_index;
wire shared_write_ready;
wire image_network_error;
wire bmp_load_busy;
(* async_reg="true" *) reg [1:0] image_owner_pixel;
(* async_reg="true" *) reg [1:0] image_boot_sync,image_boot_sd_sync,image_mem_ready_sync;
(* async_reg="true" *) reg [1:0] image_bmp_busy_sync;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire        display_valid;

wire [3:0]  state_code;
wire [6:0]  seg_data_0;
wire [6:0]  seg_scene_data;
wire [1:0] scene_id, requested_scene_id, last_event_scene, audio_scene;
wire event_trigger, scene_request, scene_commit, request_pending, latency_valid;
reg ui_visibility_toggle;
reg ui_s4_prev;
wire [31:0] latency_cycles, request_count, ignored_count, commit_count;
wire [23:0] background_rgb;
wire [23:0] osd_rgb;
wire osd_hs, osd_vs, osd_de;
wire [23:0] spectrum_rgb;
wire spectrum_hs, spectrum_vs, spectrum_de;
(* async_reg = "true" *) reg [1:0] spectrum_toggle_sync;
wire spectrum_toggle_video = spectrum_toggle_sync[1];
wire spectrum_sample_valid;
wire signed [15:0] spectrum_sample_left;
wire signed [15:0] spectrum_sample_right;
wire spectrum_sample_ready;
wire spectrum_snapshot_valid;
wire [511:0] spectrum_snapshot_heights;
wire spectrum_busy;
wire spectrum_enabled;
wire spectrum_s8_event;
wire [23:0] parameter_rgb;
wire parameter_hs, parameter_vs, parameter_de;
wire [3:0] osd_state;
wire adjust_mode_sd;
wire audio_enable_sd;
wire [1:0] brightness_level_sd;
wire [5:0] ui_fade_level;
wire scheduler_key_next, scheduler_key_auto;
wire [15:0] keypad_keys_pressed;
wire net_key_next_n, net_key_auto_n, net_key_event_n, net_sw_clear;
wire net_key_brightness_up_n, net_key_brightness_down_n;
wire net_sw_emergency;
wire sw_emergency_mux = sw_emergency;
wire key1_mux_n = key1 & ~keypad_keys_pressed[0] & net_key_next_n;
wire key2_mux_n = key2 & ~keypad_keys_pressed[1] & net_key_auto_n;
wire key_event_mux_n = key_event_n & ~keypad_keys_pressed[2] & net_key_event_n;
wire sw_clear_mux = sw_clear;
wire storage_recovery_pulse, storage_recovery_toggle;
wire storage_fault_active;
wire [2:0] storage_fault_code;
wire [31:0] storage_recovery_count, storage_last_timeout_cycles;
wire [223:0] sd_monitor;
wire [227:0] pixel_sd_monitor_bundle;
wire [223:0] pixel_sd_monitor = pixel_sd_monitor_bundle[223:0];
wire [2:0] parameter_state_pixel = pixel_sd_monitor_bundle[226:224];
wire audio_enable_pixel = pixel_sd_monitor_bundle[227];
wire [227:0] sd_parameter_bundle = {audio_enable_sd,adjust_mode_sd,brightness_level_sd,sd_monitor};
wire [71:0] memory_monitor, pixel_memory_monitor;
wire        pixel_storage_fault_active;
wire [2:0]  pixel_storage_fault_code;
wire [7:0]  pixel_storage_recovery_count;
wire [7:0] parameter_monitor = {4'd0,audio_enable_pixel,parameter_state_pixel[2],parameter_state_pixel[1:0]};
wire [7:0] fault_monitor = {4'd0,pixel_storage_fault_active,pixel_storage_fault_code};
wire [319:0] storage_monitor = {pixel_storage_recovery_count,fault_monitor,parameter_monitor,
    pixel_sd_monitor[223:192], pixel_sd_monitor[191:160], pixel_sd_monitor[63:56],
    pixel_memory_monitor[71:48], pixel_sd_monitor[159:128], pixel_sd_monitor[127:96],
    pixel_sd_monitor[95:64], pixel_memory_monitor[47:16], pixel_memory_monitor[15:0],
    pixel_sd_monitor[55:0]};

wire        w5500_udp_xfer_start, w5500_udp_xfer_write, w5500_udp_xfer_done;
wire [15:0] w5500_udp_xfer_addr;
wire [4:0]  w5500_udp_xfer_block;
wire [7:0]  w5500_udp_xfer_wdata, w5500_udp_xfer_rdata;
wire        w5500_http_xfer_start, w5500_http_xfer_write, w5500_http_xfer_done;
wire [15:0] w5500_http_xfer_addr;
wire [4:0]  w5500_http_xfer_block;
wire [7:0]  w5500_http_xfer_wdata, w5500_http_xfer_rdata;
wire        w5500_http_burst_start, w5500_http_burst_write;
wire [15:0] w5500_http_burst_addr;
wire [4:0]  w5500_http_burst_block;
wire [7:0]  w5500_http_burst_len, w5500_http_burst_tx_data;
wire        w5500_http_burst_tx_valid, w5500_http_burst_tx_ready;
wire        w5500_http_burst_done;
wire        w5500_http_burst_rx_valid;
wire [7:0]  w5500_http_burst_rx_data;
wire        w5500_spi_start, w5500_spi_write, w5500_spi_done;
wire [15:0] w5500_spi_addr;
wire [4:0]  w5500_spi_block;
wire [7:0]  w5500_spi_wdata, w5500_spi_rdata;
wire        w5500_burst_spi_start, w5500_burst_spi_write;
wire [15:0] w5500_burst_spi_addr;
wire [4:0]  w5500_burst_spi_block;
wire [7:0]  w5500_burst_spi_len, w5500_burst_spi_tx_data;
wire        w5500_burst_spi_tx_valid, w5500_burst_spi_tx_ready;
wire        w5500_burst_spi_done, w5500_burst_spi_rx_valid;
wire [7:0]  w5500_burst_spi_rx_data;
wire w5500_rx_packet_start, w5500_rx_data_valid, w5500_rx_packet_done;
wire [7:0] w5500_rx_data;
wire w5500_link_up, w5500_init_done, w5500_init_error;
wire [7:0] w5500_version;
wire w5500_cmd_next, w5500_cmd_auto_toggle, w5500_cmd_notice, w5500_cmd_emergency;
wire w5500_cmd_clear;
wire w5500_cmd_brightness_up, w5500_cmd_brightness_down;
wire w5500_cmd_audio_toggle, w5500_cmd_ui_toggle;
wire http_cmd_next, http_cmd_auto_toggle, http_cmd_notice, http_cmd_emergency;
wire http_cmd_clear;
wire http_cmd_brightness_up, http_cmd_brightness_down;
wire http_cmd_audio_toggle, http_cmd_ui_toggle;
wire w5500_command_valid, w5500_command_error;
wire [7:0] w5500_command_seq;
reg [1:0] network_event_scene_clk;
reg network_event_toggle_clk, network_clear_toggle_clk;
reg network_next_toggle_clk, network_auto_toggle_clk;
reg network_brightness_up_toggle_clk, network_brightness_down_toggle_clk;
(* async_reg = "true" *) reg [1:0] network_next_toggle_sd;
(* async_reg = "true" *) reg [1:0] network_auto_toggle_sd;
(* async_reg = "true" *) reg [1:0] network_brightness_up_toggle_sd;
(* async_reg = "true" *) reg [1:0] network_brightness_down_toggle_sd;
reg network_next_toggle_sd_d, network_auto_toggle_sd_d;
reg network_brightness_up_toggle_sd_d, network_brightness_down_toggle_sd_d;
reg network_next_event_sd, network_auto_event_sd;
reg network_brightness_up_event_sd, network_brightness_down_event_sd;
(* async_reg = "true" *) reg [1:0] network_event_toggle_video;
(* async_reg = "true" *) reg [1:0] network_clear_toggle_video;
(* async_reg = "true" *) reg [1:0] network_event_scene_video_sync;
reg network_event_toggle_video_d, network_clear_toggle_video_d;
reg network_event_valid_video, network_clear_request_video;

wire net_cmd_next            = w5500_cmd_next | http_cmd_next;
wire net_cmd_auto_toggle    = w5500_cmd_auto_toggle | http_cmd_auto_toggle;
wire net_cmd_notice         = w5500_cmd_notice | http_cmd_notice;
wire net_cmd_emergency      = w5500_cmd_emergency | http_cmd_emergency;
wire net_cmd_clear          = w5500_cmd_clear | http_cmd_clear;
wire net_cmd_brightness_up  = w5500_cmd_brightness_up | http_cmd_brightness_up;
wire net_cmd_brightness_down= w5500_cmd_brightness_down | http_cmd_brightness_down;
wire net_cmd_audio_toggle   = w5500_cmd_audio_toggle | http_cmd_audio_toggle;
wire net_cmd_ui_toggle      = w5500_cmd_ui_toggle | http_cmd_ui_toggle;

reg network_audio_enable;
wire sw_audio_enable_mux = sw_audio_enable & network_audio_enable;

w5500_spi_master #(.CLK_DIV(4)) u_w5500_spi(
    .clk(clk), .rst(rst_all), .start(w5500_spi_start),
    .write(w5500_spi_write), .address(w5500_spi_addr),
    .block(w5500_spi_block), .write_data(w5500_spi_wdata),
    .busy(), .done(w5500_spi_done), .read_data(w5500_spi_rdata),
    .w5500_cs_n(w5500_cs_n), .w5500_sclk(w5500_sclk),
    .w5500_mosi(w5500_mosi), .w5500_miso(w5500_miso),
    .burst_start(w5500_burst_spi_start), .burst_write(w5500_burst_spi_write),
    .burst_address(w5500_burst_spi_addr), .burst_block(w5500_burst_spi_block),
    .burst_length(w5500_burst_spi_len), .burst_tx_valid(w5500_burst_spi_tx_valid),
    .burst_tx_data(w5500_burst_spi_tx_data), .burst_tx_ready(w5500_burst_spi_tx_ready),
    .burst_rx_valid(w5500_burst_spi_rx_valid), .burst_rx_data(w5500_burst_spi_rx_data),
    .burst_done(w5500_burst_spi_done)
);

w5500_spi_arbiter u_w5500_spi_arbiter(
    .clk(clk), .rst(rst_all),
    .udp_start(merged_reg_start), .udp_write(merged_reg_write),
    .udp_addr(merged_reg_addr), .udp_block(merged_reg_block),
    .udp_wdata(merged_reg_wdata), .udp_done(merged_reg_done),
    .udp_rdata(merged_reg_rdata),
    .http_start(w5500_http_xfer_start), .http_write(w5500_http_xfer_write),
    .http_addr(w5500_http_xfer_addr), .http_block(w5500_http_xfer_block),
    .http_wdata(w5500_http_xfer_wdata), .http_done(w5500_http_xfer_done),
    .http_rdata(w5500_http_xfer_rdata),
    .spi_start(w5500_spi_start), .spi_write(w5500_spi_write),
    .spi_addr(w5500_spi_addr), .spi_block(w5500_spi_block),
    .spi_wdata(w5500_spi_wdata), .spi_done(w5500_spi_done),
    .spi_rdata(w5500_spi_rdata),
    .http_burst_start(w5500_http_burst_start), .http_burst_write(w5500_http_burst_write),
    .http_burst_addr(w5500_http_burst_addr), .http_burst_block(w5500_http_burst_block),
    .http_burst_len(w5500_http_burst_len), .http_burst_tx_valid(w5500_http_burst_tx_valid),
    .http_burst_tx_data(w5500_http_burst_tx_data), .http_burst_tx_ready(w5500_http_burst_tx_ready),
    .http_burst_rx_valid(w5500_http_burst_rx_valid), .http_burst_rx_data(w5500_http_burst_rx_data),
    .http_burst_done(w5500_http_burst_done),
    .burst_spi_start(w5500_burst_spi_start), .burst_spi_write(w5500_burst_spi_write),
    .burst_spi_addr(w5500_burst_spi_addr), .burst_spi_block(w5500_burst_spi_block),
    .burst_spi_len(w5500_burst_spi_len), .burst_spi_tx_valid(w5500_burst_spi_tx_valid),
    .burst_spi_tx_data(w5500_burst_spi_tx_data), .burst_spi_tx_ready(w5500_burst_spi_tx_ready),
    .burst_spi_rx_valid(w5500_burst_spi_rx_valid), .burst_spi_rx_data(w5500_burst_spi_rx_data),
    .burst_spi_done(w5500_burst_spi_done)
);

w5500_udp_ctrl #(
    .GATEWAY_IP (32'hc0a8_0001), .SUBNET_MASK(32'hffff_ff00),
    .LOCAL_MAC  (48'h02_55_00_00_00_01), .LOCAL_IP(32'hc0a8_0014),
    .LOCAL_PORT (16'd5000)
) u_w5500_ctrl(
    .clk(clk), .rst_n(~rst_all), .w5500_int_n(w5500_int_n),
    .w5500_rst_n(w5500_rst_n), .xfer_start(w5500_udp_xfer_start),
    .xfer_write(w5500_udp_xfer_write), .xfer_addr(w5500_udp_xfer_addr),
    .xfer_block(w5500_udp_xfer_block), .xfer_wdata(w5500_udp_xfer_wdata),
    .xfer_done(w5500_udp_xfer_done), .xfer_rdata(w5500_udp_xfer_rdata),
    .rx_packet_start(w5500_rx_packet_start),
    .rx_data_valid(w5500_rx_data_valid), .rx_data(w5500_rx_data),
    .rx_packet_done(w5500_rx_packet_done), .link_up(w5500_link_up),
    .init_done(w5500_init_done), .init_error(w5500_init_error),
    .version(w5500_version)
);

w5500_http_ctrl #(.WEB_INIT_FILE("w5500_web_response.hex")) u_w5500_http(
    .clk(clk), .rst_n(~rst_all),
    .xfer_start(w5500_http_xfer_start), .xfer_write(w5500_http_xfer_write),
    .xfer_addr(w5500_http_xfer_addr), .xfer_block(w5500_http_xfer_block),
    .xfer_wdata(w5500_http_xfer_wdata), .xfer_done(w5500_http_xfer_done),
    .xfer_rdata(w5500_http_xfer_rdata),
    .burst_start(w5500_http_burst_start), .burst_write(w5500_http_burst_write),
    .burst_addr(w5500_http_burst_addr), .burst_block(w5500_http_burst_block),
    .burst_len(w5500_http_burst_len), .burst_tx_valid(w5500_http_burst_tx_valid),
    .burst_tx_data(w5500_http_burst_tx_data), .burst_tx_ready(w5500_http_burst_tx_ready),
    .burst_done(w5500_http_burst_done),
    .cmd_next(http_cmd_next), .cmd_auto_toggle(http_cmd_auto_toggle),
    .cmd_notice(http_cmd_notice), .cmd_emergency(http_cmd_emergency),
    .cmd_clear(http_cmd_clear),
    .cmd_brightness_up(http_cmd_brightness_up),
    .cmd_brightness_down(http_cmd_brightness_down),
    .cmd_audio_toggle(http_cmd_audio_toggle), .cmd_ui_toggle(http_cmd_ui_toggle)
);

w5500_command_decoder u_w5500_decoder(
    .clk(clk), .rst(rst_all), .packet_start(w5500_rx_packet_start),
    .data_valid(w5500_rx_data_valid), .data(w5500_rx_data),
    .cmd_next(w5500_cmd_next), .cmd_auto_toggle(w5500_cmd_auto_toggle),
    .cmd_notice(w5500_cmd_notice), .cmd_emergency(w5500_cmd_emergency),
    .cmd_clear(w5500_cmd_clear),
    .cmd_brightness_up(w5500_cmd_brightness_up),
    .cmd_brightness_down(w5500_cmd_brightness_down),
    .cmd_audio_toggle(w5500_cmd_audio_toggle), .cmd_ui_toggle(w5500_cmd_ui_toggle),
    .command_valid(w5500_command_valid), .command_error(w5500_command_error),
    .command_seq(w5500_command_seq)
);

w5500_virtual_inputs #(.HOLD_CYCLES(100_000)) u_w5500_virtual_inputs(
    .clk(clk), .rst(rst_all), .cmd_next(1'b0),
    .cmd_auto_toggle(1'b0), .cmd_notice(1'b0),
    .cmd_emergency(1'b0),
    .cmd_clear(1'b0), .cmd_brightness_up(1'b0),
    .cmd_brightness_down(1'b0),
    .key_next_n(net_key_next_n), .key_auto_n(net_key_auto_n),
    .key_event_n(net_key_event_n), .sw_emergency(net_sw_emergency),
    .sw_clear(net_sw_clear),
    .key_brightness_up_n(net_key_brightness_up_n),
    .key_brightness_down_n(net_key_brightness_down_n)
);

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

// frame_read_write 写端口：上电动画与 BMP 轮播共用一个物理端口，
// sd_card_write_* 是最终送到 frame_read_write 的多路选择结果。
wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;

// sd_card_bmp 侧原始请求
wire        bmp_write_req;
wire        bmp_write_en;
wire [31:0] bmp_write_data;
wire [1:0]  ffrw_write_index;
wire [1:0]  ffrw_read_index;

// 开屏动画链路
wire        boot_sd_ncs, boot_sd_dclk, boot_sd_mosi;
wire        bmp_sd_ncs,  bmp_sd_dclk,  bmp_sd_mosi;
wire        boot_owns_sd;
wire        boot_stream_done, boot_stream_abort;
wire [15:0] boot_frames_written, boot_frames_shown, boot_underrun;
wire [3:0]  boot_status_code;
wire [1:0]  boot_ready_toggle, boot_consumed_toggle;
wire [1:0]  boot_write_index;
wire        boot_write_req, boot_write_en;
wire [31:0] boot_write_data;
wire        boot_read_sel, boot_active, boot_has_frame;
wire        boot_video_on    = (BOOT_VIDEO_ENABLE != 0);
wire        boot_sd_owner    = boot_video_on & boot_owns_sd;
wire        boot_active_on   = boot_video_on & boot_active;
wire [1:0]  boot_read_index  = boot_read_sel ? 2'd3 : 2'd2;
// 只有真的提交过一帧才允许开屏接管黑屏门控
wire        boot_pixel_shown = boot_active_on && boot_has_frame;

// 开屏动画独立的 TF 主机接口（与 sd_card_bmp 的实例在引脚上做 2:1 选择，
// 而不是在同一控制器里加第三个仲裁者，这样已验证的 BMP 通路完全不动）
wire        boot_sd_init_done;
wire        boot_sd_sec_read;
wire [31:0] boot_sd_sec_read_addr;
wire [7:0]  boot_sd_sec_read_data;
wire        boot_sd_sec_read_data_valid;
wire        boot_sd_sec_read_end;

// 开屏期间把 OSD 淡入等级压到 0，让开屏画面不带状态字幕；
// 交权（boot_active 落）后自动恢复原有 UI 行为。
wire [5:0]  ui_fade_effective = boot_active_on ? 6'd0 : ui_fade_level;
reg         frame_write_toggle_mem;
reg [2:0]   storage_recovery_sync_mem;
reg [3:0]   storage_recovery_hold_mem;
wire        storage_recovery_mem_pulse = storage_recovery_sync_mem[2] ^ storage_recovery_sync_mem[1];
wire        storage_reset_mem = rst_all | (storage_recovery_hold_mem != 0);
(* async_reg = "true" *) reg [1:0] transition_active_sd_sync;
wire        transition_block_sd = transition_active_sd_sync[1];

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;
wire        transition_start_toggle;
wire        display_commit_toggle;
wire        transition_commit_ready_toggle;
wire [1:0]  disp_buf_idx_video;
wire [5:0]  transition_level;
wire        transition_active;
wire        transition_recovery_reset;
reg         emergency_active_pixel;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关
wire        audio_pll_lock;
wire        audio_mclk;
wire        audio_i2s_bclk;
wire        audio_i2s_lrck;
wire        audio_i2s_dout;
wire        tone_audio_valid;
wire [23:0] tone_audio_left_data;
wire [23:0] tone_audio_right_data;
wire        pcm_fifo_wr_en;
wire [31:0] pcm_fifo_wr_data;
wire        pcm_fifo_full;
wire        pcm_fifo_almost_full;
wire        pcm_fifo_empty;
wire        pcm_fifo_rd_en;
wire [31:0] pcm_fifo_rd_data;
wire        pcm_audio_valid;
wire [23:0] pcm_audio_left_data;
wire [23:0] pcm_audio_right_data;
wire        pcm_stream_started;
wire        audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire        audio_valid_tx;
wire [23:0] audio_left_tx, audio_right_tx;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// Prefer a valid PCM package when one has started; otherwise retain the
// original internal test tone so an empty/unprepared TF card is harmless.
assign audio_valid      = pcm_stream_started ? pcm_audio_valid : tone_audio_valid;
assign audio_left_data  = pcm_stream_started ? pcm_audio_left_data : tone_audio_left_data;
assign audio_right_data = pcm_stream_started ? pcm_audio_right_data : tone_audio_right_data;
assign spectrum_sample_valid = audio_valid;
assign spectrum_sample_left  = $signed(audio_left_data[23:8]);
assign spectrum_sample_right = $signed(audio_right_data[23:8]);

// 统一复位：TF 图像链路 + HDMI 音频链路
assign rst_all = ~rst_n | ~audio_pll_lock;

// SW4 remains the hardware master; the web command provides a reversible
// software mute/unmute while SW4 is enabled.
always @(posedge clk or posedge rst_all) begin
    if (rst_all)
        network_audio_enable <= 1'b1;
    else if (net_cmd_audio_toggle)
        network_audio_enable <= ~network_audio_enable;
end

// Network scene/clear commands are explicit events. Hold the scene code in
// the command clock domain, transfer a toggle into video_clk, and emit a
// one-cycle pulse there. This removes the 20 ms mechanical debounce from the
// network path while preserving the debounced local KEY3/SW1/SW2 path.
always @(posedge clk or posedge rst_all) begin
    if (rst_all) begin
        network_event_scene_clk  <= 2'd0;
        network_event_toggle_clk <= 1'b0;
        network_clear_toggle_clk <= 1'b0;
        network_next_toggle_clk <= 1'b0;
        network_auto_toggle_clk <= 1'b0;
        network_brightness_up_toggle_clk <= 1'b0;
        network_brightness_down_toggle_clk <= 1'b0;
    end else begin
        if (net_cmd_emergency) begin
            network_event_scene_clk  <= 2'd2;
            network_event_toggle_clk <= ~network_event_toggle_clk;
        end else if (net_cmd_notice) begin
            network_event_scene_clk  <= 2'd1;
            network_event_toggle_clk <= ~network_event_toggle_clk;
        end
        if (net_cmd_clear)
            network_clear_toggle_clk <= ~network_clear_toggle_clk;
        if (net_cmd_next)
            network_next_toggle_clk <= ~network_next_toggle_clk;
        if (net_cmd_auto_toggle)
            network_auto_toggle_clk <= ~network_auto_toggle_clk;
        if (net_cmd_brightness_up)
            network_brightness_up_toggle_clk <= ~network_brightness_up_toggle_clk;
        if (net_cmd_brightness_down)
            network_brightness_down_toggle_clk <= ~network_brightness_down_toggle_clk;
    end
end

// Register the decoded scene before the two-flop SD-domain synchronizer.
// scene_id changes only in VS blanking; no asynchronous multi-bit decode
// is allowed to stop/start the SD scheduler.
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) emergency_active_pixel <= 1'b0;
    else emergency_active_pixel <= (scene_id == 2'd2);
end

// Non-scene network controls use the same toggle crossing into sd_card_clk.
// The pulse is consumed directly by the scheduler/brightness controller, so
// it does not spend another 20 ms in the mechanical-key debouncer.
always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all) begin
        network_next_toggle_sd <= 2'b00;
        network_auto_toggle_sd <= 2'b00;
        network_brightness_up_toggle_sd <= 2'b00;
        network_brightness_down_toggle_sd <= 2'b00;
        network_next_toggle_sd_d <= 1'b0;
        network_auto_toggle_sd_d <= 1'b0;
        network_brightness_up_toggle_sd_d <= 1'b0;
        network_brightness_down_toggle_sd_d <= 1'b0;
        network_next_event_sd <= 1'b0;
        network_auto_event_sd <= 1'b0;
        network_brightness_up_event_sd <= 1'b0;
        network_brightness_down_event_sd <= 1'b0;
    end else begin
        network_next_toggle_sd <= {network_next_toggle_sd[0], network_next_toggle_clk};
        network_auto_toggle_sd <= {network_auto_toggle_sd[0], network_auto_toggle_clk};
        network_brightness_up_toggle_sd <= {network_brightness_up_toggle_sd[0], network_brightness_up_toggle_clk};
        network_brightness_down_toggle_sd <= {network_brightness_down_toggle_sd[0], network_brightness_down_toggle_clk};
        network_next_event_sd <= network_next_toggle_sd[1] ^ network_next_toggle_sd_d;
        network_auto_event_sd <= network_auto_toggle_sd[1] ^ network_auto_toggle_sd_d;
        network_brightness_up_event_sd <= network_brightness_up_toggle_sd[1] ^ network_brightness_up_toggle_sd_d;
        network_brightness_down_event_sd <= network_brightness_down_toggle_sd[1] ^ network_brightness_down_toggle_sd_d;
        network_next_toggle_sd_d <= network_next_toggle_sd[1];
        network_auto_toggle_sd_d <= network_auto_toggle_sd[1];
        network_brightness_up_toggle_sd_d <= network_brightness_up_toggle_sd[1];
        network_brightness_down_toggle_sd_d <= network_brightness_down_toggle_sd[1];
    end
end

always @(posedge video_clk or posedge rst_all) begin
    if (rst_all)
        spectrum_toggle_sync <= 2'b00;
    else
        spectrum_toggle_sync <= {spectrum_toggle_sync[0], ui_visibility_toggle};
end

always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        network_event_toggle_video <= 2'b00;
        network_clear_toggle_video <= 2'b00;
        network_event_scene_video_sync <= 2'b00;
        network_event_toggle_video_d <= 1'b0;
        network_clear_toggle_video_d <= 1'b0;
        network_event_valid_video <= 1'b0;
        network_clear_request_video <= 1'b0;
    end else begin
        network_event_toggle_video <= {network_event_toggle_video[0], network_event_toggle_clk};
        network_clear_toggle_video <= {network_clear_toggle_video[0], network_clear_toggle_clk};
        network_event_scene_video_sync <= network_event_scene_clk;
        network_event_valid_video <= network_event_toggle_video[1] ^ network_event_toggle_video_d;
        network_clear_request_video <= network_clear_toggle_video[1] ^ network_clear_toggle_video_d;
        network_event_toggle_video_d <= network_event_toggle_video[1];
        network_clear_toggle_video_d <= network_clear_toggle_video[1];
    end
end

// A faster load must not replace the old image while it is still fading out.
transition_recovery_reset u_transition_recovery_reset(
    .clk(video_clk), .rst(rst_all),
    .recovery_toggle(storage_recovery_toggle),
    .recovery_reset(transition_recovery_reset)
);

transition_buffer_select u_transition_buffer_select(
    .clk(video_clk), .rst(rst_all | transition_recovery_reset), .disp_buf_idx(disp_buf_idx),
    .transition_active(transition_active), .black(transition_level == 0),
    .read_buf_idx(disp_buf_idx_video)
);

// 保持你原来的 TF / SDRAM / video 时钟
sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .reset      (1'b0)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .reset      (1'b0)
);


w5500_reg_mux2 u_image_reg_mux(
 .clk(clk),.rst(rst_all),
 .a_start(w5500_udp_xfer_start),.a_write(w5500_udp_xfer_write),.a_addr(w5500_udp_xfer_addr),
 .a_block(w5500_udp_xfer_block),.a_wdata(w5500_udp_xfer_wdata),.a_done(w5500_udp_xfer_done),.a_rdata(w5500_udp_xfer_rdata),
 .b_start(image_reg_start),.b_write(image_reg_write),.b_addr(image_reg_addr),
 .b_block(image_reg_block),.b_wdata(image_reg_wdata),.b_done(image_reg_done),.b_rdata(image_reg_rdata),
 .out_start(merged_reg_start),.out_write(merged_reg_write),.out_addr(merged_reg_addr),
 .out_block(merged_reg_block),.out_wdata(merged_reg_wdata),.out_done(merged_reg_done),.out_rdata(merged_reg_rdata));
w5500_image_udp u_image_transport(
 .clk(clk),.rst(rst_all),.enable(w5500_init_done),
 .xfer_start(image_reg_start),.xfer_write(image_reg_write),.xfer_addr(image_reg_addr),
 .xfer_block(image_reg_block),.xfer_wdata(image_reg_wdata),.xfer_done(image_reg_done),.xfer_rdata(image_reg_rdata),
 .rx_ready(image_rx_ready),.rx_start(image_rx_start),.rx_valid(image_rx_valid),.rx_end(image_rx_end),
 .rx_data(image_rx_data),.rx_peer(image_rx_peer),
 .tx_valid(image_tx_valid),.tx_ready(image_tx_ready),.tx_last(image_tx_last),.tx_data(image_tx_data),.tx_peer(image_tx_peer),
 .packets_received(),.packets_sent(),.error(image_network_error));
hxfp_receiver u_image_receiver(
 .clk(clk),.rst(rst_all),.rx_ready(image_rx_ready),.rx_start(image_rx_start),.rx_valid(image_rx_valid),
 .rx_data(image_rx_data),.rx_end(image_rx_end),.rx_peer(image_rx_peer),
 .tx_valid(image_tx_valid),.tx_ready(image_tx_ready),.tx_data(image_tx_data),.tx_last(image_tx_last),.tx_peer(image_tx_peer),
 .frame_begin(image_begin),.frame_begin_ready(image_begin_ready),
 .pixel_valid(image_pixel_valid),.pixel_ready(image_pixel_ready),.pixel_address(),.pixel_rgb565(image_pixel_rgb),
 .frame_commit(image_commit),.frame_commit_ready(image_commit_ready),.frame_abort(image_abort),.frame_error(image_fault),
 .transfer_active(),.received_bytes(),.displayed_frames());
hxfp_frame_bridge u_image_bridge(
 .net_clk(clk),.sd_clk(sd_card_clk),.video_clk(video_clk),.rst(rst_all),
 .begin_request(image_begin),.begin_ready(image_begin_ready),.commit_request(image_commit),.commit_ready(image_commit_ready),
 .abort_request(image_abort),.pixel_valid(image_pixel_valid),.pixel_ready(image_pixel_ready),.pixel_rgb565(image_pixel_rgb),
 .storage_error(storage_fault_active),.frame_error(image_fault),
 .boot_active(image_boot_sync[1]),.boot_owns_sd(boot_sd_owner),.bmp_busy(bmp_load_busy),
 .transition_busy(transition_block_sd),.mem_ready(image_mem_ready_sync[1]),.hold_scheduler(image_scheduler_hold),
 .write_cancel(image_write_cancel),.write_owner(image_write_owner),.write_request(image_write_req),.write_enable(image_write_en),
 .write_data(image_write_data),.write_index(image_write_index),
 .write_ack(sd_card_write_req_ack),.write_fifo_ready(shared_write_ready),.write_finish_toggle(frame_write_toggle_mem),
 .vs(vs),.de(de),.read_req_ack(video_read_req_ack),.tf_commit_toggle(display_commit_toggle),
 .display_valid(image_display_valid),.display_index(image_display_index),.displayed_count());
always @(posedge sd_card_clk or posedge rst_all)begin
 if(rst_all)begin image_boot_sync<=0;image_mem_ready_sync<=0;end
 else begin image_boot_sync<={image_boot_sync[0],boot_active_on};image_mem_ready_sync<={image_mem_ready_sync[0],Sdr_init_done};end
end

// Slideshow controls are independent of dedicated S5(up)/S6(down) brightness keys.
assign scheduler_key_next = key1_mux_n;
assign scheduler_key_auto = key2_mux_n;

display_parameter_ctrl u_display_parameter_ctrl(
    .clk(sd_card_clk), .rst(rst_all),
    .sw_audio_enable(sw_audio_enable_mux),
    .key_down_n(~keypad_keys_pressed[5] & net_key_brightness_down_n),
    .key_up_n(~keypad_keys_pressed[4] & net_key_brightness_up_n),
    .network_down_event(network_brightness_down_event_sd),
    .network_up_event(network_brightness_up_event_sd),
    .adjust_mode(adjust_mode_sd), .brightness_level(brightness_level_sd),
    .audio_enable(audio_enable_sd)
);

matrix_keypad u_matrix_keypad(
    .clk(clk), .rst(rst_all), .rows_n(keypad_rows_n),
    .cols_n(keypad_cols_n), .keys_pressed(keypad_keys_pressed)
);

// Matrix S4 is a persistent OSD visibility toggle. The matrix scanner is
// already debounced in the board-clock domain; only the event toggle crosses
// into the independent video clock domain.
always @(posedge clk or posedge rst_all) begin
    if (rst_all) begin
        ui_s4_prev <= 1'b0;
        ui_visibility_toggle <= 1'b0;
    end else begin
        ui_s4_prev <= keypad_keys_pressed[3];
        if ((keypad_keys_pressed[3] && !ui_s4_prev) || net_cmd_ui_toggle)
            ui_visibility_toggle <= ~ui_visibility_toggle;
    end
end

// 复用你 I2S->HDMI 工程里的 PLL，只取 12.288MHz 音频主时钟
PLL_HDMI_AUDIO u_audio_pll(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (audio_pll_lock),
    .clk0_out   (),
    .clk1_out   (),
    .clk2_out   (audio_mclk)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all || storage_reset_mem)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all) begin
        storage_recovery_sync_mem <= 3'b000;
        storage_recovery_hold_mem <= 4'd0;
    end else begin
        storage_recovery_sync_mem <= {storage_recovery_sync_mem[1:0],storage_recovery_toggle};
        if (storage_recovery_mem_pulse)
            storage_recovery_hold_mem <= 4'd8;
        else if (storage_recovery_hold_mem != 0)
            storage_recovery_hold_mem <= storage_recovery_hold_mem - 1'b1;
    end
end

// A transition keeps reading the old buffer until the black guard.  Keep the
// SD scheduler informed across the clock boundary so a queued KEY2 is held
// instead of starting a write into that still-visible buffer.
always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all)
        transition_active_sd_sync <= 2'b00;
    else
        transition_active_sd_sync <= {transition_active_sd_sync[0], transition_active};
end

storage_watchdog u_storage_watchdog(
    // Held in reset during the power-on animation: sd_card_bmp is also held in
    // reset then, so sd_init_done would read 0 and the 3 s init timeout would
    // fire in the middle of playback and reset frame_read_write.
    .clk(sd_card_clk), .rst(rst_all | boot_sd_owner),
    .sd_init_done(sd_monitor[37]), .scan_done(sd_monitor[38]),
    .found_count(sd_monitor[10:8]), .load_busy(sd_monitor[33]),
    .source_done(sd_monitor[35]), .write_done(sd_monitor[36]),
    .recovery_pulse(storage_recovery_pulse),
    .recovery_toggle(storage_recovery_toggle),
    .fault_active(storage_fault_active), .fault_code(storage_fault_code),
    .recovery_count(storage_recovery_count),
    .last_timeout_cycles(storage_last_timeout_cycles)
);

// ===================== TF 多图扫描与缓存（双缓冲） =====================
sd_card_bmp #(
    .CLK_FREQ_HZ       (100_000_000),
    .SCAN_START_SECTOR (32'd0),
    .SCAN_MAX_SECTOR   (32'd131071),
    .SCAN_TARGET_COUNT  (3'd4),
    .AUDIO_ENABLE       (1'b1),
    // Physical card LBA: partition start 8192 + volume-relative file sector 40064.
    .AUDIO_START_SECTOR (32'd48256)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (rst_all | storage_recovery_pulse | boot_sd_owner),
    .key_next          (scheduler_key_next),
    .key_auto          (scheduler_key_auto),
    .network_next_event(network_next_event_sd),
    .network_auto_event(network_auto_event_sd),
    .emergency_active  (emergency_active_pixel),
    .transition_block  (transition_block_sd | image_scheduler_hold),
    .state_code        (state_code),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .display_valid     (display_valid),
    .load_busy         (bmp_load_busy),
    .monitor_status    (sd_monitor),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),
    .transition_start_toggle(transition_start_toggle),
    .display_commit_toggle(display_commit_toggle),

    .write_req         (bmp_write_req),
    .write_req_ack     (sd_card_write_req_ack & ~image_write_owner),
    .write_en          (bmp_write_en),
    .write_data        (bmp_write_data),
    .SD_nCS            (bmp_sd_ncs),
    .SD_DCLK           (bmp_sd_dclk),
    .SD_MOSI           (bmp_sd_mosi),
    .SD_MISO           (sd_miso),
    .audio_start       (display_valid),
    .audio_fifo_wr_en  (pcm_fifo_wr_en),
    .audio_fifo_wr_data(pcm_fifo_wr_data),
    .audio_fifo_full   (pcm_fifo_full),
    .audio_fifo_almost_full(pcm_fifo_almost_full)
);

// ===================== 上电开屏动画：TF 流式读取 + 双缓冲 =====================
// 该块从上电起独占 TF 总线，把动画帧写进 SDRAM 索引 2/3；最后一帧写入完成后
// 立刻交还总线，BMP 扫描可与最后一帧的显示并行完成，因此交接处不会黑屏。
// 卡上无动画块（magic 不符）或读卡超时会自行放弃，正常功能完全不受影响。
boot_video_stream #(
    .START_SECTOR (BOOT_VIDEO_START_SECTOR),
    .BUF_ADDR0    (BOOT_BUF0_ADDR),
    .BUF_ADDR1    (BOOT_BUF1_ADDR)
) u_boot_video_stream (
    .clk                    (sd_card_clk),
    .rst                    (rst_all),
    .SD_nCS                 (boot_sd_ncs),
    .SD_DCLK                (boot_sd_dclk),
    .SD_MOSI                (boot_sd_mosi),
    .SD_MISO                (sd_miso),
    .sd_init_done           (boot_sd_init_done),
    .sd_sec_read            (boot_sd_sec_read),
    .sd_sec_read_addr       (boot_sd_sec_read_addr),
    .sd_sec_read_data       (boot_sd_sec_read_data),
    .sd_sec_read_data_valid (boot_sd_sec_read_data_valid),
    .sd_sec_read_end        (boot_sd_sec_read_end),
    .write_req              (boot_write_req),
    .write_req_ack          (sd_card_write_req_ack),
    .write_en               (boot_write_en),
    .write_data             (boot_write_data),
    .write_finish_toggle    (frame_write_toggle_mem),
    .write_addr_index       (boot_write_index),
    .owns_sd                (boot_owns_sd),
    .ready_toggle           (boot_ready_toggle),
    .consumed_toggle        (boot_consumed_toggle),
    .stream_done            (boot_stream_done),
    .stream_abort           (boot_stream_abort),
    .frames_written         (boot_frames_written),
    .status_code            (boot_status_code)
);

boot_video_play #(
    .FRAME_VS_HOLD   (4),       // 60 Hz / 4 = 15 fps 下限
    .HANDOVER_MAX_VS (3600)     // 60 s 硬上限：bmp_read 逐扇区扫描最坏可达
                                // 131071 扇区，宁可停在末帧也不要切黑屏
) u_boot_video_play (
    .clk               (video_clk),
    .rst               (rst_all),
    .vs                (vs),
    .de                (de),
    .bmp_display_valid (pixel_sd_monitor[56]),
    .ready_toggle      (boot_ready_toggle),
    .consumed_toggle   (boot_consumed_toggle),
    .stream_done       (boot_stream_done),
    .stream_abort      (boot_stream_abort),
    .read_sel          (boot_read_sel),
    .boot_active       (boot_active),
    .boot_has_frame    (boot_has_frame),
    .frames_shown      (boot_frames_shown),
    .underrun_count    (boot_underrun)
);

// TF 引脚 2:1 选择：上电给开屏动画，播完永久交回 BMP 通路。
// sd_card_bmp 在 boot_sd_owner 期间保持复位，所以同一时刻只有一个 SPI 主机。
assign sd_ncs  = boot_sd_owner ? boot_sd_ncs  : bmp_sd_ncs;
assign sd_dclk = boot_sd_owner ? boot_sd_dclk : bmp_sd_dclk;
assign sd_mosi = boot_sd_owner ? boot_sd_mosi : bmp_sd_mosi;

// SDRAM 写端口 2:1 选择（开屏写入期间 sd_card_bmp 处于复位，不存在并发写）
assign sd_card_write_req = image_write_owner ? image_write_req : (boot_sd_owner ? boot_write_req : bmp_write_req);
assign sd_card_write_en = image_write_owner ? image_write_en : (boot_sd_owner ? boot_write_en : bmp_write_en);
assign sd_card_write_data = image_write_owner ? image_write_data : (boot_sd_owner ? boot_write_data : bmp_write_data);
assign ffrw_write_index = image_write_owner ? image_write_index : (boot_sd_owner ? boot_write_index : write_buf_idx);

// 显示缓冲读索引：开屏期间用 2/3，交权后回到 BMP 的 0/1
assign ffrw_read_index = boot_active_on ? boot_read_index : (image_display_valid ? image_display_index : disp_buf_idx_video);

seg_decoder seg_decoder_m0(
    .bin_data          (state_code),
    .seg_data          (seg_data_0)
);
seg_decoder u_scene_seg_decoder(
    .bin_data          ({2'b00, scene_id}),
    .seg_data          (seg_scene_data)
);

seg_scan seg_scan_m0(
    .clk               (clk),
    .rst_n             (rst_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,7'b1111_111}),
    .seg_data_1        ({1'b1,7'b1111_111}),
    .seg_data_2        ({1'b1,7'b1111_111}),
    .seg_data_3        ({1'b1,7'b1111_111}),
    .seg_data_4        ({1'b1,seg_scene_data}),
    .seg_data_5        ({1'b1,seg_data_0})
);

// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// 首图提交前黑屏；提交后一直显示当前显示缓冲区内容
// sd_monitor[56] is display_valid, already transferred atomically into the
// pixel domain by the existing storage mailbox. Do not gate the RGB arithmetic
// directly from the asynchronous SD-domain display_valid signal.
// 开屏期间 display_valid 仍是 0（BMP 通路还没提交首图），必须由开屏自己放行
assign background_rgb = (boot_pixel_shown | pixel_sd_monitor[56] | image_display_valid) ? vout_data_raw : 24'd0;
wire [23:0] transition_rgb;
transition_commit_guard u_transition_commit_guard(
    .clk(video_clk),
    .rst(rst_all | transition_recovery_reset),
    .commit_toggle(display_commit_toggle),
    .disp_buf_idx(disp_buf_idx_video),
    .read_req_ack(video_read_req_ack),
    .vs(vs), .de(de),
    .ready_toggle(transition_commit_ready_toggle)
);
transition_fade #(
    .FRAME_HOLD(1),
    .LEVEL_HOLD(1),
    .ENABLE(E2_TRANSITION_ENABLE)
) u_transition_fade(
    .clk(video_clk), .rst(rst_all | transition_recovery_reset), .vs(vs), .de(de),
    .rgb_in(background_rgb),
    .start_toggle(transition_start_toggle),
    .commit_toggle(transition_commit_ready_toggle),
    .abort_transition(scene_id == 2'd2),
    .rgb_out(transition_rgb),
    .fade_level(transition_level),
    .transition_active(transition_active)
);
scene_video u_scene_video(
    .clk(video_clk), .rst(rst_all), .vs(vs), .de(de),
    .background_rgb(transition_rgb), .key_event_n(key_event_mux_n),
    .sw_emergency(sw_emergency_mux), .sw_clear(sw_clear_mux),
    .network_event_valid(network_event_valid_video),
    .network_event_scene(network_event_scene_video_sync),
    .network_clear_request(network_clear_request_video),
    .rgb(vout_data),
    .scene_id(scene_id), .requested_scene_id(requested_scene_id),
    .last_event_scene(last_event_scene), .event_trigger(event_trigger),
    .scene_request(scene_request), .scene_commit(scene_commit),
    .request_pending(request_pending), .latency_valid(latency_valid),
    .latency_cycles(latency_cycles), .request_count(request_count),
    .ignored_count(ignored_count), .commit_count(commit_count)
);
spectrum_1024_realtime_rgb #(
    .FRAME_WIDTH (640), .FRAME_HEIGHT(480),
    .X0          (32),  .Y0         (280),
    .WIDTH       (576), .HEIGHT     (160)
) u_spectrum_1024_realtime_rgb(
    .clk                    (video_clk),
    .rst                    (rst_all),
    .sample_valid           (spectrum_sample_valid),
    .sample_left            (spectrum_sample_left),
    .sample_right           (spectrum_sample_right),
    .sample_ready           (spectrum_sample_ready),
    .spectrum_snapshot_valid(spectrum_snapshot_valid),
    .spectrum_snapshot_heights(spectrum_snapshot_heights),
    .spectrum_busy          (spectrum_busy),
    .hs                     (hs),
    .vs                     (vs),
    .de                     (de),
    .rgb_in                 (vout_data),
    .scene_id               (scene_id),
    .ui_fade_level          (ui_fade_effective),
    .s8_pressed             (spectrum_toggle_video),
    .hs_out                 (spectrum_hs),
    .vs_out                 (spectrum_vs),
    .de_out                 (spectrum_de),
    .rgb_out                (spectrum_rgb),
    .spectrum_enabled       (spectrum_enabled),
    .s8_event               (spectrum_s8_event)
);
scene_status_uart #(.INCLUDE_STORAGE(1),.STATUS_VERSION(3)) u_scene_status_uart(
    .clk(video_clk), .rst(rst_all), .scene_id(scene_id),
    .request_pending(request_pending), .latency_valid(latency_valid),
    .requested_scene_id(requested_scene_id), .last_event_scene(last_event_scene),
    .request_count(request_count), .ignored_count(ignored_count),
    .commit_count(commit_count), .latency_cycles(latency_cycles),
    .storage_status(storage_monitor), .tx(uart_tx)
);
osd_status_cdc #(.WIDTH(228),.ONLY_ON_CHANGE(0)) u_storage_sd_mailbox(
    .source_clk(sd_card_clk), .pixel_clk(video_clk), .rst(rst_all),
    .source_state(sd_parameter_bundle), .pixel_state(pixel_sd_monitor_bundle)
);
storage_fault_cdc u_storage_fault_cdc(
    .source_clk(sd_card_clk), .pixel_clk(video_clk), .rst(rst_all),
    .source_fault(storage_fault_active), .source_code(storage_fault_code),
    .source_recovery(storage_recovery_count[7:0]),
    .pixel_fault(pixel_storage_fault_active), .pixel_code(pixel_storage_fault_code),
    .pixel_recovery(pixel_storage_recovery_count)
);
osd_status_cdc #(.WIDTH(72),.ONLY_ON_CHANGE(0)) u_storage_memory_mailbox(
    .source_clk(ext_mem_clk), .pixel_clk(video_clk), .rst(rst_all),
    .source_state(memory_monitor), .pixel_state(pixel_memory_monitor)
);
osd_status_cdc u_osd_status_cdc(
    .source_clk(sd_card_clk), .pixel_clk(video_clk), .rst(rst_all),
    .source_state(state_code), .pixel_state(osd_state)
);
ui_visibility_fade u_ui_visibility_fade(
    .clk(video_clk), .rst(rst_all), .vs(vs), .de(de),
    .trigger_toggle(ui_visibility_toggle), .fade_level(ui_fade_level),
    .visible(), .transition_active()
);
subtitle_osd u_subtitle_osd(
    .clk(video_clk), .rst(rst_all), .hs(spectrum_hs), .vs(spectrum_vs),
    .de(spectrum_de), .rgb(spectrum_rgb),
    .scene_id(scene_id), .run_state(osd_state),
    .brightness_level(parameter_state_pixel[1:0]),
    .adjust_mode(parameter_state_pixel[2]), .hs_out(osd_hs),
    .vs_out(osd_vs), .de_out(osd_de), .rgb_out(osd_rgb),
    .ui_fade_level(ui_fade_effective)
);
video_brightness u_video_brightness(
    .clk(video_clk), .rst(rst_all), .hs(osd_hs), .vs(osd_vs), .de(osd_de),
    .rgb(osd_rgb), .brightness_level(parameter_state_pixel[1:0]),
    .hs_out(parameter_hs), .vs_out(parameter_vs), .de_out(parameter_de),
    .rgb_out(parameter_rgb)
);

frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (storage_reset_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (BOOT_BUF0_ADDR),
    .read_addr_3       (BOOT_BUF1_ADDR),
    .read_addr_index   (ffrw_read_index),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_top_down    (image_write_owner),
    .write_cancel      (image_write_cancel),
    .write_ready       (shared_write_ready),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .monitor_status    (memory_monitor),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (BOOT_BUF0_ADDR),
    .write_addr_3      (BOOT_BUF1_ADDR),
    .write_addr_index  (ffrw_write_index),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// ===================== 音频：内部 I2S 测试音 =====================
scene_audio_cdc u_scene_audio_cdc(
    .video_clk(video_clk), .audio_clk(audio_mclk), .rst(rst_all),
    .scene_id(scene_id), .audio_scene(audio_scene)
);
hdmi_audio_tone_i2s_64fs #(
    .PHASE_INC (32'd39370534),
    .AMP       (24'sd2000000)
) u_hdmi_audio_tone_i2s_64fs (
    .I_mclk      (audio_mclk),
    .I_rst       (rst_all),
    .I_scene     (audio_scene),
    .O_i2s_BCLK  (audio_i2s_bclk),
    .O_i2s_LRCK  (audio_i2s_lrck),
    .O_i2s_DOUT  (audio_i2s_dout)
);

I2S_receiver u_I2S_receiver(
    .I_clk              (video_clk),
    .I_rst              (rst_all),
    .I_i2s_BCLK         (audio_i2s_bclk),
    .I_i2s_LRCK         (audio_i2s_lrck),
    .I_i2s_DOUT         (audio_i2s_dout),
    .O_audio_valid      (tone_audio_valid),
    .O_audio_left_data  (tone_audio_left_data),
    .O_audio_right_data (tone_audio_right_data)
);

// Use the existing Anlogic asynchronous FIFO IP for the SD-to-video CDC.
// It is already part of the TD project and has device-specific RAM timing.
wfifo_32_32_512 #(.AL_FULL_NUM(384)) u_audio_sample_fifo(
    .rst        (rst_all),
    .clkw       (sd_card_clk),
    .clkr       (video_clk),
    .we         (pcm_fifo_wr_en),
    .di         (pcm_fifo_wr_data),
    .re         (pcm_fifo_rd_en),
    .dout       (pcm_fifo_rd_data),
    .valid      (),
    .full_flag  (pcm_fifo_full),
    .empty_flag (pcm_fifo_empty),
    .afull      (pcm_fifo_almost_full),
    .aempty     (),
    .wrusedw    (),
    .rdusedw    ()
);

audio_pcm_fifo_player #(
    .VIDEO_CLK_HZ   (25_000_000),
    .SAMPLE_RATE_HZ (48_000)
) u_audio_pcm_fifo_player(
    .clk            (video_clk),
    .rst            (rst_all),
    .fifo_empty     (pcm_fifo_empty),
    .fifo_data      (pcm_fifo_rd_data),
    .fifo_rd_en     (pcm_fifo_rd_en),
    .audio_valid    (pcm_audio_valid),
    .audio_left     (pcm_audio_left_data),
    .audio_right    (pcm_audio_right_data),
    .stream_started (pcm_stream_started)
);

audio_sample_gate u_audio_sample_gate(
    .enable(audio_enable_pixel), .valid_in(audio_valid),
    .left_in(audio_left_data), .right_in(audio_right_data),
    .valid_out(audio_valid_tx), .left_out(audio_left_tx),
    .right_out(audio_right_tx)
);

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_vs          (parameter_vs),
    .I_de          (parameter_de),
    .I_rgb         (parameter_rgb),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_all),
    .O_pulse (edid_trig)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_all),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid_tx),
    .I_audio_left_data  (audio_left_tx),
    .I_audio_right_data (audio_right_tx),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_all),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
