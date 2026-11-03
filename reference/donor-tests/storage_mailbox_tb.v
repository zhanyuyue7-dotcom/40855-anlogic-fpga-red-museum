`timescale 1ns/1ps
module storage_mailbox_tb;
    reg source_clk=0,pixel_clk=0,rst=1;
    reg [227:0] input_word=0;
    wire [227:0] output_word;
    integer i,observed=0;
    reg [31:0] token;
    osd_status_cdc #(.WIDTH(228),.ONLY_ON_CHANGE(0)) dut(source_clk,pixel_clk,rst,input_word,output_word);
    always #5 source_clk=~source_clk;
    always #13 pixel_clk=~pixel_clk;
    function [227:0] make_word;
        input [31:0] value;
        begin make_word={value[3:0],value,~value,value^32'h5a5aa5a5,value+32'd17,value,~value,value}; end
    endfunction
    always @(posedge pixel_clk) begin
        #1;
        if(!rst && output_word!=0) begin
            token=output_word[223:192];
            if(output_word!==make_word(token)) $fatal(1,"Wide status mailbox produced a torn snapshot");
            observed=observed+1;
        end
    end
    initial begin
        repeat(5) @(negedge pixel_clk); rst=0;
        for(i=1;i<150;i=i+1) begin
            @(negedge source_clk); input_word=make_word(i*32'h01010307);
        end
        repeat(30) @(negedge pixel_clk);
        if(output_word!==input_word || observed<20) $fatal(1,"Mailbox failed to converge to latest complete snapshot");
        rst=1; repeat(4) @(negedge pixel_clk);
        if(output_word!==0) $fatal(1,"Mailbox reset failed");
        $display("PASS: continuously sampled 228-bit storage+E3/audio mailbox, atomic fields, unrelated clocks, rapid changes, latest convergence and reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"Mailbox timeout"); end
endmodule
