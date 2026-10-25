# 2026-10-26 最新完成版本核对与复跑

本次核对和复跑对象为本仓库 `7658315b5a86a5621a221e5bc8af42ed4ecb5e90`，没有改动 RTL、测试或形式性质。最新完成的功能仍是 2026-10-24 的 SPI 分频修复、限定范围形式验证、桥接器协议修复，以及同日完成的 FPGA 实现。本次新增的是版本核对与本地复跑记录。

## 本地版本核对

核对了本仓库、`CPU-DV-Portfolio-20261024` 完成包，以及原 `APB3_SPI_Master_Controller`、`AXI4_AHB5_Lite_Bridge` 项目目录：

- 完成包的 186 个受 Git 跟踪路径，在替换两个子项目的 `WHK_` 命名后，均能在本仓库找到。
- 本仓库 204 个跟踪文件中，173 个与完成包字节相同，5 个只涉及子项目命名，8 个为后续发布说明或文档更新，另有 18 个为 FPGA 报告与证据文件。
- 两份完成包中的 5 个 RTL 文件与本仓库逐字节相同；原项目副本没有发现晚于 2026-10-24 的已完成源码、测试或报告。
- 因此应继续以本仓库的两个 `WHK_` 子目录作为当前版本，不把旧目录覆盖回来，也不把本次复跑描述为新增 RTL 功能。

## 2026-10-26 本地实际复跑

运行时间为北京时间 **00:12:01–00:12:59**，统一入口返回 **exit 0 / PASS**。机器可读结果的 UTC 时间为 `2026-10-25T16:12:01.281393+00:00` 至 `2026-10-25T16:12:59.333186+00:00`。

本机通过仓库统一 PowerShell 入口实际执行，使用已安装的 Python 3.12 与 OSS CAD Suite。以下为等价复现命令，路径用占位符表示，需按安装位置替换：

```powershell
.\run_checks.ps1 -OssCadRoot 'C:\path\to\oss-cad-suite' -Python 'C:\path\to\python.exe' -Formal
```

其他机器可使用安装了 `requirements.txt` 依赖的 Python，并先激活 Icarus/Yosys/SBY 工具链：

```sh
python scripts/verify.py --project all --formal
```

| 检查 | 本次结果 |
|---|---|
| 结果验收门槛单元测试 | 6/6 PASS |
| SPI 独立参考模型 | 12/12 PASS |
| SPI SystemVerilog smoke | `SMOKE_TEST_PASS` |
| SPI 原 cocotb 回归 | 1/1 PASS，8070 ns；0 FAIL / ERROR / SKIP |
| SPI 分频与边界定向用例 | 24/24 PASS，23360 ns；0 FAIL / ERROR / SKIP |
| SPI 事务级功能覆盖 | 23/23 必达分类 bin |
| 桥接器独立参考模型 | 16/16 PASS |
| 桥接器 SystemVerilog smoke | `SMOKE_TEST_PASS` |
| 桥接器 cocotb 原回归与新增用例 | 5/5 PASS，14725 ns；0 FAIL / ERROR / SKIP |
| 桥接器事务级功能覆盖 | 36/36 必达分类 bin，缺失列表为空 |
| FIFO 参数展开 | 深度 8/16/32/64/128 均 `PARAMETER_SWEEP_PASS`；仅为 elaboration |
| SPI 旧版形式反例 | baseline BMC 返回 FAIL / exit 2，符合预期 |
| SPI 修复版限定范围证明 | reset / config / timing / rx 四组 prove PASS，共 18 条安全断言（含辅助不变量） |
| SPI 可达性检查 | 3 条 cover PASS，分别在 step 6 / 8 / 8 达到 |

工具版本：Python 3.12.14、cocotb 2.1.0、Icarus Verilog 14.0 devel、Yosys 0.67+94（`7defa5186`）、SBY v0.67-4-gfea6e46、Boolector 3.2.4。本地运行日志中的已知 Icarus/GPI 提示仍保留，不声称日志零 warning。

本次生成的详细结果位于被 Git 忽略的 `results/verification_summary.json`、`results/{spi,bridge}/`，形式任务清单位于 `WHK_APB3_SPI_Master_Controller/results/formal/20261025T161211073211Z/manifest.json`。该统一结果 JSON 的 SHA256 为 `90f0d17a3d1504d9b5d09d8a953c273f4da5ebc0c8b2d8e4c925012634b0e1b2`。这些路径是本次本地输出，重新运行会生成新报告；2026-10-24 的冻结证据保留原样。

## 当前源码与已有 FPGA 证据

| 源文件 | 当前 SHA256 |
|---|---|
| `WHK_APB3_SPI_Master_Controller/rtl/apb3_spi_master.sv` | `65c6d4c608c4c92643b61fd2cab62a4b4f1c74e2f5e7ca7dd550ca1fce53b2b4` |
| `WHK_AXI4_AHB5_Lite_Bridge/rtl/axi4_ahb5_lite_bridge.sv` | `721248b6c2b17afd2c4a5e53a1172d90fe38409bf2273678b57931d66860af9b` |
| `WHK_AXI4_AHB5_Lite_Bridge/rtl/axi4_ahb5_lite_bridge_pkg.sv` | `55331627f5f8129b1746836cf0865ef6e4912ed7b0899564cc2f0a4b2b70d4d0` |

两个主 RTL 的哈希均与 [2026-10-24 FPGA 结果](../evidence/fpga/20261024/summary.json)记录的源码哈希一致；本次还逐项核对了 [FPGA manifest](../evidence/fpga/20261024/manifest.json) 的 16 个证据文件，长度与 SHA256 全部匹配。

FPGA 综合、布局布线的执行日期仍是 **2026-10-24**，本次没有重跑 FPGA 流程。该次 SPI 在 iCE40 HX8K 上通过 50 MHz 内部 PCLK 目标（804 LC），桥接器在 ECP5-85F 上通过 25 MHz 内部时钟目标；两者尝试 100 MHz 均失败。外部 IO 时序和板级约束未闭合，没有上板实测。详见[原始实现报告](20261024_fpga_implementation.md)。

## 解释范围

23/23 与 36/36 均为事务级功能分类覆盖，不是代码覆盖或完整协议证明。形式结果只覆盖 [SPI 报告](../WHK_APB3_SPI_Master_Controller/docs/20261024_formal.md)列明的性质和假设；桥接器没有新增形式证明。UVM 迁移、CPU/ISS 接入、非默认 FIFO 深度的完整功能矩阵、代码覆盖与 ASIC STA 重跑仍未完成。本地复跑记录不代表新一次 GitHub Actions 运行。
