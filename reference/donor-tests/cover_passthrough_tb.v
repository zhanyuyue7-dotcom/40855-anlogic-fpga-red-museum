`timescale 1ns/1ps
module cover_passthrough_tb;
    reg clk=0, rst=1, hs=0, vs=0, de=0;
    reg [23:0] rgb=0;
    wire ohs, ovs, ode;
    wire [23:0] orgb;
    cover_passthrough dut(.clk(clk), .rst(rst), .hs(hs), .vs(vs), .de(de),
        .rgb(rgb), .hs_out(ohs), .vs_out(ovs), .de_out(ode), .rgb_out(orgb));
    always #5 clk=~clk;
    initial begin
        repeat(2) @(negedge clk);
        rst=0;
        @(negedge clk); hs=1; vs=1; de=1; rgb=24'h123456;
        @(posedge clk); #1;
        if (ohs!==1 || ovs!==1 || ode!==1 || orgb!==24'h123456)
            $fatal(1,"cover path did not preserve the one-cycle pixel stage");
        @(negedge clk); hs=0; vs=0; de=0; rgb=24'habcdef;
        @(posedge clk); #1;
        if (ohs!==0 || ovs!==0 || ode!==0 || orgb!==24'habcdef)
            $fatal(1,"cover blanking stage mismatch");
        $display("PASS: cover passthrough has no panel, border, text or fade UI");
        $finish;
    end
endmodule
