#!/bin/bash
# Runs every block-level and integration testbench and reports pass/fail.
set -e
mkdir -p sim
RTL=rtl
TB=tb
FAIL=0

run() {
  name=$1; shift
  echo "=== $name ==="
  iverilog -g2012 -o sim/$name.vvp "$@" -s tb_$name
  if ! timeout 250 vvp sim/$name.vvp | tee /tmp/out_$name.log | grep -q "ALL TESTS PASSED"; then
    echo "!!! $name FAILED !!!"
    FAIL=1
  fi
  echo
}

run rst_sync       $RTL/rst_sync.v $TB/tb_rst_sync.v
run regfile        $RTL/regfile.v $TB/tb_regfile.v
run alu            $RTL/alu.v $TB/tb_alu.v
run clk_gate       $RTL/clk_gate.v $TB/tb_clk_gate.v
run clk_div        $RTL/clk_div.v $TB/tb_clk_div.v
run async_fifo     $RTL/async_fifo.v $TB/tb_async_fifo.v
run data_sync      $RTL/data_sync.v $TB/tb_data_sync.v
run pulse_gen      $RTL/pulse_gen.v $TB/tb_pulse_gen.v
run uart_tx        $RTL/uart_tx.v $TB/tb_uart_tx.v
run uart_rx        $RTL/uart_rx.v $TB/tb_uart_rx.v
run sys_ctrl       $RTL/regfile.v $RTL/alu.v $RTL/sys_ctrl.v $TB/tb_sys_ctrl.v
run clkdom1_top    $RTL/regfile.v $RTL/alu.v $RTL/clk_gate.v $RTL/sys_ctrl.v $RTL/clkdom1_top.v $TB/tb_clkdom1_top.v
run uart_top       $RTL/clk_div.v $RTL/uart_tx.v $RTL/uart_rx.v $RTL/pulse_gen.v $RTL/async_fifo.v $RTL/uart_top.v $TB/tb_uart_top.v
run sys_top        $RTL/rst_sync.v $RTL/regfile.v $RTL/alu.v $RTL/clk_gate.v $RTL/sys_ctrl.v $RTL/clkdom1_top.v $RTL/clk_div.v $RTL/uart_tx.v $RTL/uart_rx.v $RTL/pulse_gen.v $RTL/async_fifo.v $RTL/data_sync.v $RTL/uart_top.v $RTL/sys_top.v $TB/tb_sys_top.v

if [ $FAIL -eq 0 ]; then
  echo "########## ALL BLOCK & INTEGRATION TESTS PASSED ##########"
else
  echo "########## SOME TESTS FAILED - see logs above ##########"
fi
