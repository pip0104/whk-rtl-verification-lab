# 免费代码覆盖率报告

> 历史基线：2026-10-24 已修改 RTL；本报告的 line/toggle/branch/expr 数值尚未对新 RTL 重跑，不能作为新版本覆盖率。当前只确认事务级必达 bin 门槛，见 [修复报告](20261024_bridge_fix.md)。

## 结论

2026-09-08 已在本机使用免费 Verilator + MSYS2 工具链，成功运行 `tb_top_smoke` 并产生真实代码覆盖率数据库。该结果与 Icarus/cocotb 的完整功能回归分开记录，不能混用或夸大为完整验证闭环。

执行入口：

```powershell
cd 'C:\Users\Pip\Documents\总线验证\AXI4_AHB5_Lite_Bridge'
.\scripts\run_verilator_coverage.ps1
```

## 实际 DUT 结果

覆盖对象是 `axi4_ahb5_lite_bridge__F8_M8`（`FIFO_DEPTH=8`、`MAX_BURST_BEATS=8`），测试场景为已通过的 32-bit 单拍读写与 8-bit 窄传输 smoke。

| 指标 | 命中 | 实际比例 |
|---|---:|---:|
| Line | 34 / 46 | 73.9% |
| Toggle | 436 / 1138 | 38.3% |
| Branch | 38 / 64 | 59.4% |
| Expression | 50 / 74 | 67.6% |

全 testbench 层级汇总为 line 77.9%（60/77）、toggle 38.4%（770/2006）、branch 61.8%（42/68）、expression 60.0%（60/100）。这些百分比来自 Verilator 的 `coverage.dat`，不是手工估计。

## 可复核产物

- 覆盖数据库：`build/verilator_smoke_coverage/obj_dir/coverage.dat`
- 文本汇总：`results/verilator_code_coverage_summary.txt`
- LCOV 导出：`results/verilator_code_coverage.info`
- 可复现脚本：`scripts/run_verilator_coverage.ps1`

## 边界与下一步

本结果证明免费代码覆盖率路径能够工作，但它只是 smoke 基线。完整 cocotb 回归目前通过 Icarus 执行，Windows 版 cocotb 包不提供 Verilator VPI 适配库，故不能把该完整 Python 回归直接合并为同一份 Verilator coverage 数据库。

要提升这组数字，应为 Verilator 增加等价的纯 SystemVerilog 定向/随机 testbench，逐步覆盖 burst、wait、ERROR、非法请求、FIFO 满压与复位分支；每次都重新运行脚本并以新产生的数据为准。不要把 36/36 的功能 bin 覆盖率写成 line/toggle 覆盖率，也不要在未取得合法授权时声称 VCS/URG 或 assertion coverage。
