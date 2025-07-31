module DummyModule (
    input clk,
    input rst,
    input inPort,
    output reg outPort
  );

    always @ (posedge clk) begin
        if (rst)
            outPort <= 1'b0;
        else
            outPort <= inPort;
    end

endmodule // DummyModule
