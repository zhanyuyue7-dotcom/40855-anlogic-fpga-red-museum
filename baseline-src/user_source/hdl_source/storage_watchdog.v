// M5 bounded storage recovery controller. It observes the public scheduler
// status and requests a local TF/frame-path reset without resetting HDMI,
// scene arbitration, on-chip alert graphics, or audio generation.
module storage_watchdog #(
    parameter integer INIT_TIMEOUT_CYCLES  = 300_000_000,   // 3 s @ 100 MHz
    parameter integer SCAN_TIMEOUT_CYCLES  = 2_000_000_000, // 20 s
    parameter integer LOAD_TIMEOUT_CYCLES  = 500_000_000,   // 5 s
    parameter integer EMPTY_TIMEOUT_CYCLES = 100_000_000    // 1 s
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        sd_init_done,
    input  wire        scan_done,
    input  wire [2:0]  found_count,
    input  wire        load_busy,
    input  wire        source_done,
    input  wire        write_done,
    output reg         recovery_pulse,
    output reg         recovery_toggle,
    output reg         fault_active,
    output reg  [2:0]  fault_code,
    output reg  [31:0] recovery_count,
    output reg  [31:0] last_timeout_cycles
);
    localparam [2:0] FAULT_NONE   = 3'd0;
    localparam [2:0] FAULT_INIT   = 3'd1;
    localparam [2:0] FAULT_SCAN   = 3'd2;
    localparam [2:0] FAULT_SOURCE = 3'd3;
    localparam [2:0] FAULT_WRITE  = 3'd4;
    localparam [2:0] FAULT_IMAGE  = 3'd5;
    localparam [2:0] FAULT_RETIRE = 3'd6;

    reg [31:0] elapsed_cycles;
    reg [2:0] active_code;
    wire [2:0] monitored_code = !sd_init_done ? FAULT_INIT :
        !scan_done ? FAULT_SCAN :
        found_count == 0 ? FAULT_IMAGE :
        !load_busy ? FAULT_NONE :
        !source_done ? FAULT_SOURCE :
        !write_done ? FAULT_WRITE : FAULT_RETIRE;
    wire [31:0] monitored_limit = !sd_init_done ? INIT_TIMEOUT_CYCLES :
        !scan_done ? SCAN_TIMEOUT_CYCLES :
        found_count == 0 ? EMPTY_TIMEOUT_CYCLES :
        load_busy ? LOAD_TIMEOUT_CYCLES : 32'd1;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            elapsed_cycles <= 0;
            active_code <= monitored_code;
            recovery_pulse <= 0;
            recovery_toggle <= 0;
            fault_active <= 0;
            fault_code <= FAULT_NONE;
            recovery_count <= 0;
            last_timeout_cycles <= 0;
        end else begin
            recovery_pulse <= 1'b0;
            if (monitored_code == FAULT_NONE) begin
                elapsed_cycles <= 0;
                active_code <= FAULT_NONE;
                fault_active <= 1'b0;
                fault_code <= FAULT_NONE;
            end else if (monitored_code != active_code) begin
                // A new storage phase gets its own timeout budget. Do not
                // charge initialization time against scan/load/retire.
                elapsed_cycles <= 0;
                active_code <= monitored_code;
                fault_active <= 1'b0;
                fault_code <= FAULT_NONE;
            end else if (elapsed_cycles >= monitored_limit - 1'b1) begin
                elapsed_cycles <= 0;
                recovery_pulse <= 1'b1;
                recovery_toggle <= ~recovery_toggle;
                fault_active <= 1'b1;
                fault_code <= monitored_code;
                recovery_count <= recovery_count + 1'b1;
                last_timeout_cycles <= elapsed_cycles + 1'b1;
            end else begin
                elapsed_cycles <= elapsed_cycles + 1'b1;
            end
        end
    end
endmodule
