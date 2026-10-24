# 性能参数说明（APB3-SPI Master Controller）

> 目的：把"这个 SPI 控制器的工作频率是多少"拆成三层——**验证环境假设**、**FPGA 估算**、**ASIC 估算**，并写清哪些数字有工具产物支撑。
> 本文所有数字都可用末尾命令重新生成。

## 一句话结论

这个模块的 **PCLK 在验证环境里是 10 ns（100 MHz）**，SCLK 由 `CLKDIV` 分频：半周期 = `(CLKDIV+1)` 个 PCLK，所以 **SCLK 最高 50 MHz（CLKDIV=0）、CLKDIV=1 时 25 MHz**（25 MHz 这一档在 smoke 里有实测边沿间隔印证）。

三层频率口径：FPGA（iCE40 HX8K）整体约 **73.7 MHz**（含未约束 IO 路径），内部逻辑约 102 MHz；**ASIC 侧用 sky130 标准库 + OpenSTA 做真实 STA，Fmax ≈ 182 MHz**（周期 5.5 ns 时 slack 归零，100 MHz 下 setup slack 还有 +4.54 ns 余量），标准单元面积约 **4.7k µm²**。

## 第一层：验证环境的时钟假设（有源码证据）

| 项目 | 数值 | 证据 |
| --- | --- | --- |
| PCLK 周期 | **10 ns（半周期 5 ns）→ 100 MHz** | `tb/tb_cocotb_spi.sv:21`（`always #5 pclk = ~pclk;`）；`tb/tb_top_smoke.sv:36` |
| 时间精度 | 1 ns / 1 ps | 各文件首行 `` `timescale 1ns/1ps `` |
| 时钟域 | 只有 PCLK 一个时钟；不支持跨时钟域 | `docs/spi_master_spec.md` §6 |

## 第二层：SCLK 分频与帧时间（规格里写死的公式，可现场推算）

规格原文（`docs/spi_master_spec.md` §3、§4）：

- `CLKDIV`（寄存器 `0x04`）：**SCLK 半周期 = `(CLKDIV+1)` 个 PCLK 周期**。
- 一个 B bit 帧有 `2*B` 次 SCLK 翻转，最后一条 trailing edge 使时钟回到 CPOL。

由此得到（PCLK = 100 MHz、周期 10 ns）：

| 指标 | 公式 | 算例 |
| --- | --- | --- |
| SCLK 频率 | `PCLK / (2 × (CLKDIV+1))` | CLKDIV=0 → **50 MHz**；=1 → **25 MHz**；=4 → **10 MHz** |
| SCLK 理论最低 | CLKDIV 最大 65535（16-bit 寄存器） | 100 MHz / (2×65536) ≈ **763 Hz** |
| 单帧时间 | `帧长 × SCLK 周期` | 8-bit @25 MHz → **320 ns**；16-bit @25 MHz → **640 ns**；32-bit @10 MHz → **3,200 ns** |
| 帧长范围 | `BITS_MINUS_1` 5 bit，1~32 bit | 复位值 7 → 默认 8 bit |

**实测印证**：`docs/verification_tracker.md` 的 RQ05 记录了 smoke 检查 `CLKDIV=1` 时 **20 ns 边沿间隔**（= 半周期 20 ns → SCLK 25 MHz），并且 cocotb 回归命中分频 1/2/3/4 四档。也就是说 **"CLKDIV=1 → 25 MHz" 这一档是真测过的**，其余档位是按规格公式推算。

寄存器与数据通路（影响性能的其他参数）：

| 项目 | 数值 | 来源 |
| --- | --- | --- |
| CLKDIV 位宽 | 16 bit（`reg [15:0] clkdiv_reg`） | `rtl/apb3_spi_master.sv:48` |
| 数据通路 | `TXDATA`/`RXDATA` 是**单寄存器，不是 FIFO** | 规格 §3 |
| 含义 | 帧率受软件读写速度限制：下一帧前必须读走 RXDATA，否则触发 OVERRUN | 规格 §3、README「主要能力与边界」 |
| 中断 | DONE / RX_AVAIL / OVERRUN / ABORT，`IRQ_STATUS` 写 1 清零 | 规格 §3 |

## 第三层：FPGA 估算（真实跑出来的）

工具：`yosys 0.67`（`read_slang` 前端）+ `nextpnr-ice40`；脚本 `scripts/run_synth_timing.ps1`，产物在 `build/synth/`。

### 综合与资源（iCE40 HX8K）

| 指标 | 结果 |
| --- | --- |
| yosys 映射 | 946 cells：679 `SB_LUT4`、220 个触发器（153 SB_DFFER + 62 SB_DFFR + 4 SB_DFFES + 1 SB_DFFS）、47 SB_CARRY |
| nextpnr 器件利用率 | `ICESTORM_LC 793/7680`（**10%**），IO 与 RAM 无冲突 |

### 时序

| 指标 | 结果 |
| --- | --- |
| **整体 Fmax**（`read_slang` 网表，当前脚本） | **73.68 MHz**（目标 100 MHz，未达标） |
| 内部**寄存器→寄存器**关键路径 | **9.79 ns ≈ 102 MHz** |
| 输入 pad → 寄存器 | 18.92 ns |
| 寄存器 → 输出 pad | 7.93 ns |
| 参考：早先用 `read_verilog -sv` 网表的同一流程 | 84.48 MHz（网表不同，布局不同） |

**怎么解释"两个数字差这么多"**：nextpnr 报的 73.68 MHz 里包含了 **pad → 寄存器**的 18.92 ns（未做引脚约束、pad 由工具自动摆放），这条 IO 路径把整体数字拉低了；**只看内部逻辑**（FF→FF）是 9.79 ns，约 102 MHz。所以准确的表述是："内部逻辑约 100 MHz 量级，含未约束 IO 路径的整芯片估算在 74–85 MHz 之间"。面试里主动把这两个口径分开，比报一个漂亮的数字更可信。

## 第四层：ASIC 估算（sky130 映射 + OpenSTA 真实 STA）

工具：`yosys + abc -liberty`，库为 SkyWater **SKY130 HD `tt_025C_1v80`**（`F:\EDA\liberty\`）。
脚本：`scripts/run_asic_estimate.ps1`；产物在 `build/asic_estimate/`（含门级网表 `mapped.v`）。

| 指标 | 结果 |
| --- | --- |
| 映射后实例总数 | **864** 个标准单元 |
| 估算单元总面积 | **≈4,732 µm²**（按库中每个单元的 `area` 求和；2 种单元缺面积数据，属轻微低估） |
| 面积占比最高 | `a21oi_1` 100 个（10.6%）、`nor2_1` 102 个（8.1%）、`o21ai_0` 76 个（8.0%） |

### OpenSTA 真实 STA 结果（sky130 HD tt_025C_1v80，理想时钟）

脚本：`scripts/run_sta.ps1`；产物：`build/sta/sta_report.log`。

| 指标 | 结果 |
| --- | --- |
| 约束 | 10 ns 周期（100 MHz）、clock uncertainty setup 0.15 / hold 0.05 |
| setup 最差 slack（@100 MHz） | **+4.54 ns（MET）**，TNS 0.00 |
| hold 最差 slack（@100 MHz） | **+0.39 ns（MET）** |
| 关键路径（setup） | `_4419_` → `_4323_`，数据到达 **5.19 ns** |
| 周期扫描归零点 | 5.5 ns → +0.037 ns；5.46 ns → -0.003 ns |
| **推定 Fmax** | **≈182 MHz**（1 / 5.50 ns） |

关键路径的 5.19 ns 里，有一步是 `sky130_fd_sc_hd__nor3_1` 的 **2.17 ns**，其余多级都在 0.2–0.5 ns——说明这条路也主要吃亏在**某一级的大负载**，而不是级数特别多。对 SPI 这类逻辑量小的模块，把那个大负载（大概率是分频/计数比较相关的扇出）缓一下就能再提一截。

### 这条工具链是怎么搭出来的（可复现）

1. `yosys`（`read_slang`）+ `dfflibmap -liberty` + `abc -liberty` → sky130 门级网表（`write_verilog -noattr`）。
2. OpenSTA 从源码编译（MSYS2/UCRT64）：依赖 `bison flex git cmake swig tcl eigen3` + 自行编译的 CUDD（`The-OpenROAD-Project/cudd`，装到 `F:\EDA\cudd`）；并把 OpenSTA 的 CMake 里"直接执行 `.tcl`"改成显式调用 `tclsh`，否则生成 `StaTclInitVar.cc` 会静默失败。
3. 网表必须先用 `dfflibmap` 把触发器映射到库单元，否则残留 `always/reg` 会导致 OpenSTA 解析报错。
4. SDC 里不能出现 `remove_from_collection`（PrimeTime 专有），IO 延迟以注释形式保留并附 OpenSTA 写法。
5. `sta.exe` 是 MSYS2 程序，路径含中文/反斜杠会被破坏，所以脚本先复制到纯 ASCII 暂存目录（`F:\EDA\sta-work\...`）再用正斜杠调用。

### 这次 STA 的边界（必须一起说）

- 理想时钟（无 CTS）、无寄生参数（无 SPEF）、单 corner（tt/25°C/1.80V）、无 derate/串扰。
- 结果适合判断"能不能跑 100 MHz、瓶颈在哪"，**不是流片保证**。

## 时序约束草稿（`constraints/spi_100mhz.sdc`）

- `create_clock -period 10.000 pclk`：100 MHz 主时钟假设。
- `create_generated_clock -name spi_sclk -source pclk -divide_by 2 spi_sclk`：把 **CLKDIV=0（最快档）** 作为悲观场景约束；其他档位要各建 scenario（注释里给了 `-divide_by 4`、`-divide_by 10` 的写法）。
- 输入/输出延迟 2.0 / 0.5 ns 与输出负载 0.05：**占位值**，真实项目按 SoC 集成方与外部 SPI 从器件填写。
- **不写** `set_clock_groups -asynchronous`：`spi_sclk` 是由 `pclk` 生成的同源时钟，声明异步会把真实路径藏起来。

## 面试话术（建议照这个说）

> SPI 这边的频率很好讲，因为它由规格公式决定：PCLK 在验证环境里是 100 MHz，SCLK 半周期等于 `(CLKDIV+1)` 个 PCLK，所以 CLKDIV 等于 0 时 SCLK 是 50 MHz、等于 1 时是 25 MHz——25 MHz 这一档我在 smoke 里用 20 纳秒的边沿间隔实测印证过，分频 1/2/3/4 都在 cocotb 回归里命中。帧时间也能直接算：8 位帧在 25 MHz 下一帧 320 纳秒。
>
> 需要说明的是 PCLK 的 100 MHz 是**验证环境假设**。我用开源工具做了实际综合与时序估算：iCE40 上整体约 74 MHz，其中内部寄存器到寄存器路径只有 9.8 纳秒、约 100 MHz，"整体偏低"是被未做引脚约束的 pad 路径拉下来的；FPGA 数字不等于 ASIC 频率。
>
> ASIC 侧我做了 sky130 标准单元映射，面积约 4.7k 平方微米；**因为 OpenSTA 没有 Windows 版，我自己用 MSYS2 从源码把它编译出来（还顺带编了它依赖的 CUDD），再用 sky130 库对门级网表做真实静态时序分析**。结果是 10 ns 周期下 setup slack 还有 +4.54 ns，周期扫描到 5.5 ns 才归零，也就是**约 182 MHz**。
>
> 需要说清边界：这次 STA 用理想时钟、单个 tt corner、没有寄生参数，属于乐观的签核式估算，不是流片保证；但它已经足够回答"这个模块能不能跑到 100 MHz"，并且指出了瓶颈是某一级的大负载。

## 复现命令

```powershell
cd 'C:\Users\Pip\Documents\总线验证\APB3_SPI_Master_Controller'

.\scripts\run_synth_timing.ps1      # yosys + nextpnr-ice40：资源与 Fmax 估算
.\scripts\run_asic_estimate.ps1     # sky130 映射与面积估算
.\scripts\run_sta.ps1               # OpenSTA 真实时序分析（setup/hold slack 与 Fmax）
.\scripts\run_full_regression.ps1   # 原有功能回归（不受以上流程影响）
```

## 不要说的话（边界）

- 不要说"这个 IP 的工作频率是 100 MHz"——那是验证环境假设。
- 不要把 73.68 MHz（含未约束 IO）当成设计能力上限；内部逻辑口径是 9.79 ns。
- 不要把 FPGA 频率当作 ASIC 频率：ASIC 侧口径是 STA 出的约 182 MHz（理想时钟）。
- 不要把这次 STA 说成签核：没有 CTS、没有寄生参数、只有单 corner。
- 不要说"50 MHz 的 SCLK 实测过"——实测过的是 CLKDIV=1 的 25 MHz；50 MHz 是公式推算。
