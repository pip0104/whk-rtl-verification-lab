# 免费代码覆盖率报告

## 结论

已使用本机 Verilator 5.051 和 SV `tb_top_smoke` 产生真实 coverage database。覆盖对象为 `apb3_spi_master`，不是 cocotb 主回归，也不包含商业 condition/assertion/URG 合并结果。

| DUT 指标 | 命中 | 实际比例 |
|---|---:|---:|
| Line | 21 / 24 | 87.5% |
| Toggle | 191 / 678 | 28.2% |
| Branch | 35 / 40 | 87.5% |
| Expression | 58 / 74 | 78.4% |

全 testbench 汇总为 line 94.0%（47/50）、toggle 26.6%（308/1158）、branch 90.0%（54/60）、expression 74.8%（80/107）。FSM 为 0/0，不能据此宣称 FSM coverage。

## 可复核产物

- 原始数据库：`build/verilator_smoke_coverage/obj_dir/coverage.dat`
- 文本汇总：`results/verilator_code_coverage_summary.txt`
- LCOV 导出：`results/verilator_code_coverage.info`
- 重现实验：`scripts/run_verilator_coverage.ps1`

## 分析与下一步

高 line/branch 只说明 smoke 经过了大多数当前控制路径；28.2% toggle 表明寄存器和数据位的组合仍明显不足。TX double-write、RX unread 和 busy 中清 ENABLE 已在 cocotb 主回归实际验证，但当前 Verilator smoke 尚未覆盖这些分支。优先为 smoke 补 1-bit/32-bit 帧、CLKDIV=0/最大值、连续 CS 下第二帧和非法 START（无 TXDATA）。任何新数字必须来自重新生成的 `coverage.dat`；不能把 23/23 cocotb 功能 bin 写成代码覆盖率。
