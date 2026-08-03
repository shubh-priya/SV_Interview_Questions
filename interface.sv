//Add an interface with valid, ready,data and reset and a clocking blockand modport for driver, monitor 
interface pixel_if (input logic clock_in);
  logic valid_in;
  logic [7:0] data_in;
  logic ready;
  logic reset;
  clocking drv_cb @(posedge clk);
    default input #1step output #2;
    output valid_in, data;
    input ready;
  endclocking
  clocking mon_cb @(posedge clk);
    default input #1step output #2;
    input ready;
    
endinterface

