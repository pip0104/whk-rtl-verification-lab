# APB3 SPI Master 回归报告

## 实际结果

| 层级 | 命令入口 | 结果 |
|---|---|---|
| 帧级 oracle | `run_reference_model_tests.ps1` | 12/12 通过。 |
| RTL smoke | `run_smoke_iverilog.ps1` | 通过，验证 4 mode、LSB、divider、连续 CS、IRQ W1C。 |
| 端到端 | `run_spi_regression.ps1` | cocotb 1/1 通过，仿真 8070 ns。 |
| 功能覆盖 | `results/functional_coverage.json` | 23/23 必达 bin，100%。 |
| Verilator 代码覆盖 | `run_verilator_coverage.ps1` | DUT line 87.5%、toggle 28.2%、branch 87.5%、expr 78.4%。 |

## 解释边界

这是 Icarus + cocotb 的真实可复现基线。它不包含商业 UVM run、SVA assertion coverage 或 URG 合并 coverage；`uvm/` 仅是待合法授权工具执行的迁移源。Verilator 的代码覆盖来自 SV smoke，而不是 cocotb 主回归，不能与 23/23 混成一个百分比。
