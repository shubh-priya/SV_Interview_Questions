/*Scenario: Your pixel-pipe testbench has 4 identical lanes, each needing its own DUT connection. Rather than writing 4 separate interface instances by hand, you use a generate block to instantiate an array of interfaces, and your driver needs to drive all 4 lanes using a valid/ready handshake with proper reset handling
interface lane_if(input logic clk);
  logic        rst_n;
  logic        valid;
  logic        ready;
  logic [15:0] data;

  clocking drv_cb @(posedge clk);
    default input #1step output #2;
    output valid, data;
    input  ready;
  endclocking

  modport DRIVER (clocking drv_cb, input rst_n);
endinterface
module tb_top;
  logic clk;
  lane_if lane_ifs[4](clk);   // array of 4 interface instances

  // ... DUT instantiation connecting each lane_ifs[i] to lane i ...
endmodule
task: 
Write a UVM driver class lane_driver that has a virtual interface array handle (not just a single virtual interface) — declare the correct type for vif such that it can reference all 4 lane interfaces, and show how you'd retrieve it via uvm_config_db in build_phase (assume the array was set() into config_db as a whole, under the key "vif_array").
Write a run_phase task that drives a single lane_txn (assume it has bit [15:0] data) onto a specific lane index lane_num, correctly implementing the valid/ready handshake:
Assert valid and place data on the bus.
Wait until ready is also observed high on the same or a later cycle (i.e., handle the case where ready isn't immediately high).
Deassert valid after the handshake completes.
All signal access must go through the clocking block, not raw interface signals.
Write a reset-handling task wait_for_reset that waits for rst_n to be asserted low then deasserted (a full reset pulse), for a specific lane, before allowing any driving to begin.
Deliberate trap to watch for: should wait_for_reset also read rst_n through the clocking block (drv_cb.rst_n), or directly (vif[lane_num].rst_n)? Justify your choice — think about whether rst_n was declared as part of the clocking block at all in the interface above, and what that implies.
*/
class lane_driver extends uvm_driver #(lane_txn);
  `uvm_component_utils(lane_driver)
  virtual lane_if vif [4];
  //function void new
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual lane_if)::get(this,"","vif_array",vif))
      `uvm_fata("DRV", "Cannot get the interface handle correctly")
  endfunction
     task run_phase(uvm_phase phase);
    fork
      wait_for_reset(0);
      wait_for_reset(1);
      wait_for_reset(2);
      wait_for_reset(3);
    join
    forever begin
      lane_txn tr;
    seq_item_port.get_next_item(tr);
    drive_intf(tr.lane_num,tr);
      seq_item_port.item_done();
    end
    endtask
      task drive_intf(int lane_num, lane_txn txn);
    @vif[lane_num].drv_cb;
    vif[lane_num].drv_cb.valid<=1;
    vif[lane_num].drv_cb.data<=txn.data;
    do
      @(vif[lane_num].drv_cb);
    while(!vif[lane_num].drv_cb.ready);
    vif[lane_num].drv_cb.valid<=0;
    endtask
    task wait_for_reset(int_lane_num);
      wait(vif[lane_num].reset_n==0);
      wait(vif[lane_num].reset_n==1);
    endtask
