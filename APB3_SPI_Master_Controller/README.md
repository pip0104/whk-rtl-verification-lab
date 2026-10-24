# APB3 SPI Master Controller RTL and Verification

这是一个可复用的学习型 SPI Master IP：APB3 从接口完成寄存器配置，SPI 侧输出 `SCLK/MOSI/CS_n` 并采样 `MISO`。项目将 RTL、独立帧级参考模型、Icarus smoke、cocotb 端到端回归、事务级功能覆盖、可迁移 UVM 环境和 Verilator 代码覆盖入口放在同一目录中。

## 已交付的真实证据

| 范围 | 当前结果 | 证据入口 |
|---|---|---|
| Python 帧级参考模型 | 12/12 单元测试通过 | `scripts/run_reference_model_tests.ps1` |
| RTL smoke | 通过 | `scripts/run_smoke_iverilog.ps1` |
| APB3 + SPI 端到端回归 | cocotb 1/1 通过，仿真 8070 ns | `scripts/run_spi_regression.ps1` |
| 事务级功能覆盖 | 23/23 必达 bin，100% | `results/functional_coverage.json` |
| UVM agent/scoreboard/covergroup | 源码已交付，待合法 UVM 仿真器执行 | `uvm/`、`docs/uvm_migration.md` |
| Verilator 代码覆盖 | DUT smoke：line 87.5%、toggle 28.2%、branch 87.5%、expr 78.4% | `scripts/run_verilator_coverage.ps1` |

“100%”只指 `functional_coverage.json` 中定义的 23 个 cocotb 事务级必达 bin，不是商业工具的 covergroup、assertion 或代码覆盖率，也不代表签核。

## 主要能力与边界

- 兼容 APB3 的 setup/access 两阶段读写，`PREADY=1`，非法寄存器地址报 `PSLVERR`。
- 支持 CPOL/CPHA 四种 SPI 模式、1 至 32 bit 帧长、MSB/LSB first，以及 `CLKDIV + 1` 个 PCLK 的可编程 SCLK 半周期。
- 单帧模式在末尾释放 CS；连续模式让 CS 跨显式 START 的帧保持有效，最终帧以 `CONTINUOUS=0` 结束，或用 `CS_RELEASE` 命令释放。
- TXDATA/RXDATA 是单项寄存器而非 FIFO。软件在发起下一帧前必须读走 RXDATA，TXDATA 的未消费二次写和 RXDATA 覆盖会触发 OVERRUN。
- 不支持多 CS、DMA/FIFO、双线/四线 SPI、CRC、从机模式或跨时钟域。连续 CS 已保持时，后续帧必须保持相同 CPOL/CPHA/bit-order；先把静态 CTRL 写好且让 SCLK 在 CS 高电平时稳定，再发 START。

详细、可执行的接口规则见 `docs/spi_master_spec.md`。

## 快速回归

PowerShell 示例：

```powershell
cd 'C:\Users\Pip\Documents\总线验证\APB3_SPI_Master_Controller'
.\scripts\run_reference_model_tests.ps1
.\scripts\run_smoke_iverilog.ps1
.\scripts\run_spi_regression.ps1
.\scripts\run_full_regression.ps1
.\scripts\run_verilator_coverage.ps1
```

前三项使用 `F:\EDA\oss-cad-suite` 的 Icarus 和已有 cocotb 环境。若要迁移到另一台机器，先按 `requirements.txt` 创建 Python 环境并安装 cocotb；商业 UVM/covergroup 流程需要学校或公司的合法仿真器授权。

## 目录

```text
rtl/       APB3 SPI RTL 和边界断言
tb/        可移植 SV smoke top 和 cocotb top
tests/     cocotb SPI slave、APB driver、端到端检查与功能覆盖
tools/     独立帧级参考模型及单元测试
uvm/       APB agent、SPI monitor、scoreboard、covergroup 和 UVM top
docs/      规格、验证计划、追踪、报告和学习文档
scripts/   可复现回归与代码覆盖脚本
results/   实际运行生成的日志、JUnit 和 coverage JSON
```

## 性能参数与综合估算（2026-10-02 新增）

- `docs/performance_notes.md`：性能参数口径汇总——PCLK 100 MHz 假设（含源码行号）、SCLK 分频公式与算例、FPGA 实测估算、ASIC 面积估算、面试话术与"不能说的话"。
- `constraints/spi_100mhz.sdc`：时序约束草稿（PCLK 100 MHz + SCLK 生成时钟 divide_by 2；非签核约束）。
- `scripts/run_synth_timing.ps1`：yosys（`read_slang`）+ nextpnr-ice40 实际综合与布局布线，输出资源与 Fmax 到 `build/synth/`。
- `scripts/run_asic_estimate.ps1`：sky130 标准单元映射与面积估算，输出门级网表与统计到 `build/asic_estimate/`。
- `scripts/run_sta.ps1`：**OpenSTA 真实静态时序分析**（sky130 库 + SDC + 门级网表）→ `build/sta/sta_report.log`。
- `constraints/sta_sky130.tcl`：等价的 OpenSTA TCL 模板（本机已通过 `run_sta.ps1` 实际执行；模板保留给 Linux/Mac 上的 OpenSTA）。

实测摘要（FPGA）：iCE40 HX8K 利用率 793/7680 LC（10%）；整体 Fmax 73.68 MHz（含未约束 pad 路径），内部寄存器→寄存器 9.79 ns（≈102 MHz）。

实测摘要（ASIC，sky130 tt + OpenSTA）：面积 ≈4,732 µm²（864 个单元）；**100 MHz 下 setup slack +4.54 ns、hold +0.39 ns（均满足）**；周期扫描在 5.5 ns 归零，**Fmax ≈182 MHz**。

SCLK 分频：CLKDIV=0 → 50 MHz、=1 → 25 MHz（后者有 smoke 的 20 ns 边沿间隔实测印证）、=4 → 10 MHz。

边界：FPGA 数字不是 ASIC 频率；这次 STA 用理想时钟、无寄生参数、单 corner，属于**乐观的签核式估算**，不是流片保证。
