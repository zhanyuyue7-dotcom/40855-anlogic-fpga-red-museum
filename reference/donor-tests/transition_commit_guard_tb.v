`timescale 1ns/1ps
module transition_commit_guard_tb;
    reg clk = 0;
    reg rst = 1;
    reg commit_toggle = 0;
    reg [1:0] disp_buf_idx = 0;
    reg read_req_ack = 0;
    reg vs=1;
    wire ready_toggle;

    transition_commit_guard dut(
        .clk(clk),
        .rst(rst),
        .commit_toggle(commit_toggle),
        .disp_buf_idx(disp_buf_idx),
        .read_req_ack(read_req_ack),
        .vs(vs), .de(1'b0),
        .ready_toggle(ready_toggle)
    );

    always #5 clk = ~clk;

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task ack_once;
        reg ready_before;
        begin
            @(negedge clk);
            ready_before = ready_toggle;
            read_req_ack = 1'b1;
            tick;
            if (ready_toggle !== ready_before)
                $fatal(1, "raw asynchronous read ACK bypassed synchronizer");
            @(negedge clk);
            read_req_ack = 1'b0;
            repeat (4) tick;
        end
    endtask

    initial begin
        repeat (3) tick;
        rst = 1'b0;
        repeat (3) tick;

        // The commit notification can arrive before the reader has latched
        // the new display buffer. An early ACK must not release fade-in.
        commit_toggle = 1'b1;
        repeat (3) tick;
        ack_once;
        if (ready_toggle !== 1'b0)
            $fatal(1, "ready toggled before the display buffer changed");

        // The buffer index changes after the first ACK. The next accepted
        // frame read is the first point at which the new frame is visible.
        disp_buf_idx = 2'd1;
        repeat (5) tick;
        // An ACK before a fresh frame boundary cannot prove new-buffer use.
        ack_once;
        if (ready_toggle !== 1'b0) $fatal(1,"in-flight ACK released new buffer early");
        @(negedge clk); vs=0;
        repeat (2) tick;
        ack_once;
        if (ready_toggle !== 1'b1)
            $fatal(1, "ready did not toggle after buffer change and read ACK");

        // No duplicate release without another commit.
        ack_once;
        if (ready_toggle !== 1'b1)
            $fatal(1, "ready toggled more than once for one commit");

        $display("PASS: commit release waits for new buffer visibility");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "commit guard timeout");
    end
endmodule
