# 性能参数说明（AXI4-to-AHB5-Lite Bridge）

> 历史估算快照：2026-10-24 RTL 新增 AHB 相位与整笔写预检状态，本次未重新综合/布局布线/STA。以下资源、Fmax 与 slack 只属于旧 RTL，不能作为当前实现的 PPA 结果。

> 目的：把"这个设计的工作频率是多少"这个问题拆成三层——**验证环境假设**、**FPGA 估算**、**ASIC 估算**，并明确哪些数字有实际工具产物支撑、哪些目前拿不到。
> 全部数字都可用本文末尾的命令重新生成；没有产物支撑的数字一律不写。

## 一句话结论

分三层说：**验证环境按 10 ns（100 MHz）时钟假设搭建**；FPGA（ECP5-85F）估算约 **41 MHz**；**ASIC 侧已用 sky130 标准库 + OpenSTA 做真实静态时序分析，Fmax ≈ 74.6 MHz**（周期 13.4 ns 时 slack 归零），标准单元面积约 **7.9k µm²**。

结论很清楚：**这个设计在当前映射下跑不到 100 MHz**。关键路径 13.06 ns，其中光是起点触发器的 `clk→Q` 就占 **7.84 ns**——这是扇出/负载过大的典型信号，不是逻辑级数问题。

## 第一层：验证环境的时钟假设（有源码证据）

| 项目 | 数值 | 证据 |
| --- | --- | --- |
| 仿真时钟周期 | **10 ns（半周期 5 ns）→ 100 MHz** | `tb/tb_cocotb_bridge.sv:74`（`forever #5 clk = ~clk;`）；`tb/tb_top_smoke.sv:64` |
| 时间精度 | 1 ns / 1 ps | 各 RTL/tb 文件首行 `` `timescale 1ns/1ps `` |
| 时钟域 | **单时钟域**：AXI 与 AHB 共用 `clk` | `docs/bridge_spec.md` §2.1 |
| 复位 | `rst_n` 同步、低有效 | `docs/bridge_spec.md` §2.1 |

**关键区分**：这是"测试平台给设计加的时钟"，不是"设计能跑到的频率"。两者不能混为一谈。

## 第二层：设计级参数（规格/RTL 里本来就有）

| 参数 | 数值 | 来源 |
| --- | --- | --- |
| AXI / AHB 数据宽度 | 32-bit | `rtl/axi4_ahb5_lite_bridge.sv:16` `DATA_WIDTH=32` |
| 地址宽度 | 32-bit | 同文件 `ADDR_WIDTH=32` |
| AXI ID 宽度 | 4（范围 1~8） | 同文件 `ID_WIDTH=4` |
| 命令/写数据 FIFO 深度 | 默认 16，参数化 **8/16/32/64/128**（2 的幂） | 同文件 `FIFO_DEPTH=16`；规格 §2.2 |
| 突发长度上限 | `MAX_BURST_BEATS` 默认 = FIFO 深度，范围 2~128 | 同文件第 19 行；规格 §2.2 |
| 单次传输宽度 | 1 / 2 / 4 byte（`AxSIZE=0/1/2`） | 规格 §3.2 |
| WRAP 长度 | 2 / 4 / 8 / 16 beat | 规格 §3.2 |
| 字节通道 | 4 个 lane（32-bit÷8），最大 `AxSIZE=2` | RTL 派生参数 `BYTE_LANES=4`、`MAX_AXSIZE=2` |
| 理论带宽上限（推算） | 4 byte × 100 MHz = **400 MB/s**（单方向、零等待、连续传输） | 由上面两项推算 |

**为什么只是"理论上限"**：桥的后端是**串行执行**的（同一时刻一笔 active command、一个 active beat），每拍至少要 1 个 AHB 周期；回归里还注入了 `HREADY` 等待 0 / 1 / 2–3 / 4+ 周期（`docs/verification_tracker.md` RQ-07）。所以真实吞吐 = 400 MB/s ÷（每拍的等待周期数 + 1）。面试时主动说明这一点，比被追问强。

## 第三层：FPGA 估算（真实跑出来的，有工具产物）

工具：`yosys 0.67`（综合，`read_slang` 前端）+ `nextpnr`（布局布线 + 静态时序），来自 `F:\EDA\oss-cad-suite`。
脚本：`scripts/run_synth_timing.ps1`；产物在 `build/synth/`。

### 器件适配情况（这本身是个有意思的结论）

| 器件 | 结果 | 原因 |
| --- | --- | --- |
| iCE40 HX8K（ct256） | **装不下** | IO 需 305 个，封装只有 206 个（`SB_IO: 305/206 = 148%`）。逻辑容量其实够（LC 961/7680 = 12%） |
| ECP5-45F（CABGA381） | **装不下** | IO 需 305 个，只有 245 个（`TRELLIS_IO: 305/245 = 124%`） |
| **ECP5-85F（CABGA554）** | 装得下，已跑完时序 | `TRELLIS_IO: 305/365 (83%)` |

> 结论：这个桥暴露了 305 个 IO（几组 32-bit 数据/地址总线各占几十个 pad）。**它面向 SoC 内部集成，本来就不该有这么多 pad**；FPGA 上"装不下"是引脚问题，不是设计问题。

### ECP5-85F 时序与资源

| 指标 | 结果 |
| --- | --- |
| 组合资源 | `TRELLIS_COMB 1205/83640`（1%） |
| 触发器 | `TRELLIS_FF 139/83640`（0%） |
| IO | `TRELLIS_IO 305/365`（83%） |
| yosys 映射后资源 | 573 LUT4、206 CCU2C、139 TRELLIS_FF、23 TRELLIS_DPR16X4（分布式 RAM）、57 PFUMX、12 L6MUX21 |
| **整体 Fmax（含未约束 IO）** | **≈40.4–40.9 MHz**（目标 100 MHz，未达标） |
| **内部寄存器→寄存器关键路径** | **24.42 ns ≈ 40.9 MHz** |
| 关键路径位置 | `active_cmd_q`（FF）→ `write_resp_q` 的 CE 使能逻辑：clk-to-q 0.52 ns + 组合逻辑 24.02 ns + 布线 0.41 ns |
| 时钟→输出 pad 路径 | 30.32 ns（pad 未约束、自动摆放，偏悲观） |

**怎么读这个结果**：整体 Fmax（40.4 MHz）与内部 FF→FF 路径（40.9 MHz）几乎一致，说明**瓶颈是内部组合逻辑，不是 IO**。24 ns 的纯组合延迟在 ECP5 上约等于 50 级以上的 LUT 级联，典型来源是**大扇出的使能/比较逻辑**（FIFO 空满判断、写响应使能条件）。这正是以后要优化的点：把这类比较/使能逻辑打拍或分层。

## 第四层：ASIC 估算（sky130 映射 + OpenSTA 真实 STA）

工具：`yosys + abc -liberty`，库为 **SkyWater SKY130 HD `tt_025C_1v80`**（下载到 `F:\EDA\liberty\`，不放进仓库）。
脚本：`scripts/run_asic_estimate.ps1`；产物在 `build/asic_estimate/`（含映射后的门级网表 `mapped.v`）。

| 指标 | 结果 |
| --- | --- |
| 映射后实例总数 | **1756** 个标准单元 |
| 估算单元总面积 | **≈7,905 µm²**（按 sky130 库中每个单元的 `area` 求和；2 种单元缺面积数据，属轻微低估） |
| 面积占比最高的单元 | `nand2_1` 305 个（14.5%）、`xnor2_1` 118 个（13.1%）、`nor2_1` 124 个（5.9%） |
| FIFO 处理方式 | 当前映射把命令/数据 FIFO **展开成触发器**；真实 ASIC 会用 SRAM 宏，面积应明显下降 |

### OpenSTA 真实 STA 结果（sky130 HD tt_025C_1v80，理想时钟）

脚本：`scripts/run_sta.ps1`；产物：`build/sta/sta_report.log`。

| 指标 | 结果 |
| --- | --- |
| 约束 | 10 ns 周期（100 MHz）、clock uncertainty setup 0.15 / hold 0.05 |
| setup 最差 slack（@100 MHz） | **-3.39 ns（VIOLATED）**，TNS -189.45 ns |
| hold 最差 slack（@100 MHz） | **+0.38 ns（MET）** |
| 关键路径（setup） | `_10225_` → `_10337_`，数据到达 **13.06 ns** |
| 周期扫描归零点 | 13.4 ns → +0.006 ns；13.0 ns → -0.394 ns |
| **推定 Fmax** | **≈74.6 MHz**（1 / 13.40 ns） |

关键路径的形状很说明问题：

```text
  0.00  clock clk (rise edge)
  7.84  _10225_/Q      (sky130_fd_sc_hd__dfxtp_1)   <- clk→Q 就 7.84 ns！
  1.13  _08088_/X      (mux4_2)
  1.75  _08161_/X      (o21a_1)
  ...   起终点共 13.06 ns 到达端点 D
```

正常 sky130 触发器的 `clk→Q` 在 0.2–0.5 ns 量级；这里是 **7.84 ns**，说明该触发器输出接了**异常大的负载**（净荷电容把 NLDM 表外推到很远处）。同一条路径上还有 `mux4_2` 的 1.13 ns 与 `o21a_1` 的 1.75 ns——都是大负载/大单元的典型特征。**这就是"跑不到 100 MHz"的根因方向：不是逻辑级数太多，而是少数信号扇出/负载过大，需要缓冲、复制寄存器或改变结构（例如把 FIFO 换成 SRAM 宏）。**

### 这条工具链是怎么搭出来的（可复现）

1. `yosys`（`read_slang` 前端）+ `dfflibmap -liberty` + `abc -liberty`：把 RTL 映射成 sky130 标准单元，并用 `write_verilog -noattr` 导出干净网表。
2. **OpenSTA 源码编译**（本机无 Windows 版，MSYS2/UCRT64 从源码构建）：
   - 依赖：`bison flex git cmake swig tcl eigen3`（MSYS2 包）+ CUDD（`The-OpenROAD-Project/cudd` 源码编译安装到 `F:\EDA\cudd`）。
   - 关键修补：OpenSTA 的 CMake 用 `etc/TclEncode.tcl` 直接执行 Tcl 脚本（依赖 Unix shebang，Windows 下"成功"却不产出文件），改为显式调用 `tclsh`。
   - 产物：`F:\EDA\OpenSTA-master\build\sta.exe`（11 MB）。
3. 网表要求：必须先用 `dfflibmap` 把触发器映射成库单元，否则网表里会残留 `always`/`reg`，OpenSTA 解析失败。
4. SDC 兼容性：OpenSTA **不支持** `remove_from_collection`（PrimeTime 专有），因此 IO 延迟约束在本仓库以注释形式保留，并给出 OpenSTA 可用的显式端口写法。
5. 路径坑：`sta.exe` 是 MSYS2 程序，工作路径含中文会被破坏、反斜杠会被当转义，因此脚本先把输入复制到纯 ASCII 暂存目录（`F:\EDA\sta-work\...`）并用正斜杠传参。

### 这次 STA 的边界（必须一起说）

- **理想时钟网络**：没有 CTS，时钟延迟与偏斜为 0；真实签核要走时钟树。
- **无寄生参数**：没有 SPEF/布线，只用了库单元的 NLDM 负载模型，没有线延迟。
- **单 corner**：只有 tt / 25°C / 1.80 V，没有 SS/FF、没有 derate、没有串扰。
- **FIFO 展开成触发器**：真实 ASIC 会用 SRAM 宏，面积会下降、时序结构也会变。
- 所以这次 STA 是**乐观的"签核式估算"**，能用来判断"能不能跑 100 MHz、瓶颈在哪"，不能当作流片保证。

## 时序约束草稿（`constraints/bridge_100mhz.sdc`）

文件内容与含义：

- `create_clock -period 10.000 clk`：把"100 MHz 单时钟"这个假设写成约束。
- 时钟不确定性 0.15 ns（setup）/ 0.05 ns（hold）：给抖动与时钟树偏差留预算。
- 输入/输出延迟 2.0 ns（max）/ 0.5 ns（min）、输出负载 0.05：**占位值**，真实项目要按集成方 IO 时序填。
- 复位按**同步路径**约束（因为规格要求 `rst_n` 同步低有效），**故意不做 false path**。
- 不写 `set_clock_groups`：AXI 与 AHB 同源单时钟，不存在跨域路径。

**边界**：这份 SDC 表达"约束意图"，它本身不产生 Fmax；没有库和 STA 工具时，它只是设计意图的书面证据。

## 面试话术（建议照这个说）

> 这个桥的验证环境按 10 ns 周期搭建，也就是 100 MHz，AXI 和 AHB 共用同一个时钟，是单时钟域设计。设计参数上，数据宽度 32 位、地址 32 位、命令和写数据 FIFO 深度参数化 8 到 128，突发长度上限跟 FIFO 深度绑定。
>
> 需要区分的是：100 MHz 是**验证环境的时钟假设**，不是芯片的工作频率。我用开源工具做了一次真实的综合与时序估算：在 ECP5-85F 上布局布线后整体约 41 MHz，而且瓶颈是内部一条 24.4 纳秒的组合路径——从写命令寄存器到写响应使能逻辑，说明这条使能/比较逻辑没有打拍，这是我知道的优化方向。顺便说，这个设计在小 FPGA 上"装不下"，原因是它暴露了 305 个 IO 引脚，是引脚数限制而不是逻辑容量问题。
>
> ASIC 侧我做了 sky130 标准单元映射，面积约 7.9k 平方微米（FIFO 目前按触发器展开，真实项目会换成 SRAM 宏，面积会下降）。**因为 OpenSTA 没有 Windows 版，我自己在 MSYS2 里从源码把它编译出来，再用 sky130 库对门级网表做了真实静态时序分析**：约束 10 ns 周期时 setup slack 是 -3.39 ns，不满足；做周期扫描后 slack 在 13.4 ns 周期归零，也就是**当前映射下 Fmax 约 74.6 MHz**。
>
> 关键路径很能说明问题：起点触发器的 clk→Q 就有 7.84 ns，正常应该在 0.5 ns 以内，说明这条路径上有个信号扇出/负载异常大，不是逻辑级数的问题——这也是我下一步要优化的方向（缓冲、复制寄存器，或者把 FIFO 换成 SRAM 宏）。需要说明的是这次 STA 用理想时钟、单 corner、没有寄生参数，属于乐观的签核式估算，不是流片保证。

## 复现命令

```powershell
cd 'C:\Users\Pip\Documents\总线验证\AXI4_AHB5_Lite_Bridge'

# FPGA 综合 + 布局布线 + 时序估算（ECP5-85F）
.\scripts\run_synth_timing.ps1
# -> build\synth\yosys_synth.log / nextpnr_ecp5.log / nextpnr_ecp5_timing.json

# ASIC 侧标准单元映射与面积估算（sky130）
.\scripts\run_asic_estimate.ps1
# -> build\asic_estimate\mapped.v / mapped_stat.log / area_*.log

# ASIC 真实静态时序分析（OpenSTA + sky130 库）
.\scripts\run_sta.ps1
# -> build\sta\sta_report.log（setup/hold slack、关键路径、周期扫描）

# 原有的功能回归（不受以上流程影响）
.\scripts\run_full_regression.ps1
```

## 不要说的话（边界）

- 不要说"这个桥能跑 100 MHz"——100 MHz 是验证环境假设。
- 不要把 FPGA 的 41 MHz 说成 ASIC 频率；ASIC 侧的数字要用 STA 的 74.6 MHz。
- 不要把这次 STA 说成签核：它是理想时钟、单 corner、无寄生的乐观估算。
- 不要把 305 个 IO 引脚的兼容性问题说成"设计有问题"。
- 不要把 7.9k µm² 说成最终面积（FIFO 用 SRAM 宏、加时钟树与布线后会变）。
- 不要隐瞒"当前映射跑不到 100 MHz"这个结论——主动说结论加根因方向，比被追问强。
