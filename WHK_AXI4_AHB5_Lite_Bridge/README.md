# AXI4 to AHB5-Lite Bridge - RTL and cocotb Verification

**2026-10-24 当前实现：**已修正 AHB 地址/数据相位、两周期 ERROR、后续拍非法写的整笔预检、AXI 4KB 边界，并新增必达功能 bin 门槛与独立 JUnit 文件。[本次实际 RED/GREEN 报告](docs/20261024_bridge_fix.md)。每个 AXI beat 现在独立映射为 AHB SINGLE/NONSEQ，保留 FIXED/INCR/WRAP 地址语义，不再输出 AHB 多拍 burst。

下文 2026-09/10 的代码覆盖、综合、布局布线和 STA 数值是旧 RTL 的历史基线，不能归属本次修改后的 RTL。本次只重跑仿真与参数展开，不声称 UVM、整桥形式证明、上板或新时序收敛。

这是一个学习型芯片验证项目。桥接器在上游是 AXI4 Slave，在下游是 AHB5-Lite Master；可执行验证使用 SystemVerilog + cocotb，检查正常、背压、错误、FIFO 满和复位条件下的协议转换。UVM 是后续迁移计划。

## 当前进度

| 阶段 | 状态 | 产物 |
|---|---|---|
| 项目全景与学习基础 | 已完成 | `docs/1_项目总体介绍.docx`、`docs/2_基本知识与技能.docx` |
| 规格与验证计划 | 已完成 v0.1 | `docs/bridge_spec.md`、`docs/verification_plan.md` |
| 地址参考模型 | 已完成基础版 | `tools/reference_model.py`、`tools/test_reference_model.py` |
| RTL 与可移植端到端回归 | 已完成并实际执行 | `rtl/`、`tb/tb_cocotb_bridge.sv`、`tests/cocotb/` |
| 需求追踪与功能覆盖 | 已完成（事务级） | `docs/verification_tracker.md`、`results/functional_coverage.json` |
| 免费代码覆盖 smoke 基线 | 已完成并实际执行 | `scripts/run_verilator_coverage.ps1`、`docs/code_coverage_report.md` |
| 商业 UVM/SVA/覆盖率闭环 | 待合法授权工具 | `docs/uvm_migration.md` |

## 快速检查

### Windows 免费工具链（已配置）

项目可使用位于 `F:\EDA\oss-cad-suite` 的开源工具链运行基础验证：

```powershell
cd .\WHK_AXI4_AHB5_Lite_Bridge
.\scripts\run_reference_model_tests.ps1
.\scripts\run_smoke_iverilog.ps1
.\scripts\run_parameter_sweep_iverilog.ps1
.\scripts\run_bridge_regression.ps1
.\scripts\run_full_regression.ps1
.\scripts\run_cocotb_environment_probe.ps1
.\scripts\open_smoke_gtkwave.ps1
.\scripts\run_verilator_coverage.ps1
```

其中 `run_full_regression.ps1` 是功能验证交付入口：它依次运行 reference model、RTL smoke、FIFO 参数展开和 cocotb 端到端回归，并把日志写入 `results/full_regression.log`。主回归实现 AXI driver、可控 AHB memory/slave、独立 scoreboard、协议 monitor、错误/等待注入及事务级功能覆盖。

`run_verilator_coverage.ps1` 是独立的免费代码覆盖入口。它以已通过的 smoke 场景运行 Verilator，并实际导出 line/toggle/branch/expression 的统计、原始 `coverage.dat` 与 LCOV 文件。当前 DUT 基线和适用边界见 `docs/code_coverage_report.md`。该免费路径仍不包含完整 UVM、covergroup 或并发 SVA 支持；因此 `rtl/axi4_ahb5_lite_bridge_assert.sv` 会在 Icarus 路径中被有意排除，商业 UVM/SVA/URG 的真实闭环需要学校/公司提供合法授权。详见 `docs/verification_tracker.md`。

### Python 地址参考模型

也可直接运行：

```powershell
.\scripts\run_reference_model_tests.ps1
```

### 在 Linux 虚拟机中运行 RTL smoke test

将整个项目目录复制或挂载到已安装 VCS 和 Verdi 的 Linux 虚拟机中，然后在项目根目录执行：

```bash
chmod +x scripts/run_smoke_vcs.sh scripts/open_smoke_verdi.sh
VCS_BIN=/path/to/vcs scripts/run_smoke_vcs.sh
VERDI_BIN=/path/to/verdi scripts/open_smoke_verdi.sh
```

若 `vcs` 与 `verdi` 已在 `PATH` 中，直接运行两个脚本即可。第一个脚本生成 `build/smoke/smoke.vcd`、`compile.log` 和 `simulate.log`；第二个脚本在 Verdi 中打开源码和 VCD 波形。

首个 smoke test 检查两件事：32-bit 单拍写/读，以及地址 `0x22` 的 8-bit 窄传输。通过后再进入 burst、等待状态、错误注入和 UVM。

## 目录约定

```text
docs/       规格、验证计划、学习文档与覆盖率闭环记录
rtl/        Bridge RTL 与 RTL assertion
tb/         directed testbench、cocotb top、parameter-sweep top 与 memory model
tests/      cocotb driver/slave/scoreboard/coverage 与回归用例
scripts/    仿真与回归脚本
tools/      与 RTL 独立的参考模型和文档构建程序
results/    可再生的运行结果（不提交大体积覆盖率数据库）
```

## 规格基线

当前学习版的可执行边界、错误策略和参数约束以 [`docs/bridge_spec.md`](docs/bridge_spec.md) 为准。任何 RTL/UVM 实现都不得绕过或暗中改变这份规格；变更要先修改规格和验证计划。

## 性能参数与综合估算（2026-10-02 新增）

- `docs/performance_notes.md`：性能参数口径汇总——验证环境时钟假设（10 ns / 100 MHz，含源码行号）、设计级参数、FPGA 实测估算、ASIC 面积估算、面试话术与"不能说的话"。
- `constraints/bridge_100mhz.sdc`：时序约束草稿（单时钟域 100 MHz 假设；非签核约束，占位 IO 延迟）。
- `scripts/run_synth_timing.ps1`：yosys（`read_slang`）+ nextpnr-ecp5 实际综合与布局布线，输出资源与 Fmax 到 `build/synth/`。
- `scripts/run_asic_estimate.ps1`：sky130 标准单元映射与面积估算，输出门级网表与统计到 `build/asic_estimate/`。
- `scripts/run_sta.ps1`：**OpenSTA 真实静态时序分析**（sky130 库 + SDC + 门级网表）→ `build/sta/sta_report.log`。
- `constraints/sta_sky130.tcl`：等价的 OpenSTA TCL 模板（本机已通过 `run_sta.ps1` 实际执行；模板保留给 Linux/Mac 上的 OpenSTA）。

实测摘要（FPGA）：iCE40 HX8K 与 ECP5-45F **装不下**（IO 需 305 个，分别只有 206/245 个）；ECP5-85F 装得下，整体 Fmax ≈40.4–40.9 MHz，内部寄存器→寄存器路径 24.42 ns。

实测摘要（ASIC，sky130 tt + OpenSTA）：面积 ≈7,905 µm²（1756 个单元，FIFO 按触发器展开）；**100 MHz 下 setup slack -3.39 ns（不满足）**，hold +0.38 ns；周期扫描在 13.4 ns 归零，**Fmax ≈74.6 MHz**。关键路径 13.06 ns，其中起点触发器 `clk→Q` 就占 **7.84 ns**（扇出/负载异常大），是下一步优化方向。

边界：FPGA 数字不是 ASIC 频率；这次 STA 用理想时钟、无寄生参数、单 corner，属于**乐观的签核式估算**，不是流片保证。
