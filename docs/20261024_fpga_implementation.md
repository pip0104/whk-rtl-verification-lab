# 当前 RTL 的 FPGA 实现报告 2026年10月24日

本报告对应本日修复后的 RTL，源快照为 `7c67af9849252aada3904c013f83538d561d0772`。使用已安装的 OSS CAD Suite 在 Windows 本地实际运行，不使用旧 RTL 的资源或频率。

## 实际结果

| 项目 | FPGA 器件与封装 | 本次资源 | 内部时钟目标 | 布局布线结果 | 估算内部 Fmax |
|---|---|---|---|---|---|
| WHK APB3 SPI Master Controller | iCE40 HX8K / CT256 | 804/7680 LC；108/206 IO | PCLK 50 MHz | exit 0；1 条自动 IO 警告、0 errors | 73.9809 MHz |
| WHK AXI4-to-AHB5-Lite Bridge | ECP5-85F / CABGA554 | 2038 COMB、157 FF、25 RAMW、14 DSP；305/365 IO | clk 25 MHz | exit 0；无 PNR warning/error 条目 | 37.3260 MHz |

两项目的 100 MHz 尝试均 exit 1、时序未满足，完整失败报告同时保留。随后使用相同综合网表、seed 1，在以上较低目标下完成布局布线；没有使用 `--timing-allow-fail`。降低目标是如实选择可实现频率，不代表 RTL 经优化达到 100 MHz。

SPI 已由 icepack 生成 135100 字节位流；桥接器已由 ecppack 生成位流，两次打包均 exit 0。二进制与完整构建目录不纳入源码树；[summary.json](../evidence/fpga/20261024/summary.json)记录位流大小和 SHA256，可重新生成。

SPI 的 804 是打包后的 LC，不是 804 LUT；Yosys 映射统计为 632 LUT4、236 个触发器。桥接器的 RAMW 为分布式存储资源，不能写成使用了 25 个块 RAM；DP16KD 为 0。

## 约束和解释范围

- 使用 `--freq` 指定内部时钟目标。nextpnr 的该选项为没有更具体约束的时钟设置默认频率，见[官方约束说明](https://github.com/YosysHQ/nextpnr/blob/main/docs/constraints.md)。
- 未提供板级 PCF/LPF，IO 引脚由工具自动分配；未给出外部器件输入输出延迟及 SPI 源同步时序约束。本次只能说所列内部时钟目标通过，不能说整个外部接口或板级时序闭合。
- SPI SCLK 是输出信号。73.98 MHz 是内部 PCLK 寄存器路径的时序估算，不是 SPI SCLK 最高速率，也不是实测运行频率。
- 位流生成不代表适配某块真实开发板，更不代表已下载运行。没有实物上板、ILA/示波器测试或完整 Vivado/Quartus 工程经历的新增声明。
- 仿真 PASS、形式性质 PASS 与 FPGA 实现 PASS 分别回答不同问题；本报告不是 CPU/ISS 验证、ASIC STA 签核或桥接器全部功能的证明。
- 以下旧 `scripts/run_synth_timing.ps1` 默认尝试 100 MHz，且历史脚本会把非零 PNR 退出码打印成说明。不要用该脚本外层返回成功判定时序通过。本次以原始 PNR 退出码、最终时序 JSON 和失败日志共同验收。

## 工具与源文件

- Yosys `0.67+94`，git `7defa5186-dirty`。
- nextpnr-ice40 / nextpnr-ecp5 `0.10-100-gfb95bb8e`。
- SPI RTL SHA256：`65C6D4C608C4C92643B61FD2CAB62A4B4F1C74E2F5E7CA7DD550CA1FCE53B2B4`。
- Bridge RTL SHA256：`721248B6C2B17AFD2C4A5E53A1172D90FE38409BF2273678B57931D66860AF9B`。
- Bridge 默认参数：地址/数据 32 bit、ID 4 bit、FIFO_DEPTH=16、MAX_BURST_BEATS=16。
- Yosys 的 bridge ABC 日志有 combinational-network 提示；不声称整个工具链零 warning。

## PowerShell 复现

以下从仓库根目录开始；将本机 OSS CAD Suite 路径改成自己的安装路径。每一步检查原始退出码，避免失败被外层脚本吞掉。输出是新建的 `build/fpga-reproduce/`，不依赖冻结报告。

```powershell
. 'F:\EDA\oss-cad-suite\environment.ps1'
Set-Location WHK_APB3_SPI_Master_Controller
New-Item -ItemType Directory -Force build/fpga-reproduce | Out-Null
yosys -p 'read_slang rtl/apb3_spi_master.sv; hierarchy -check -top apb3_spi_master; synth_ice40 -top apb3_spi_master -json build/fpga-reproduce/mapped.json; stat' -l build/fpga-reproduce/yosys.log
if ($LASTEXITCODE -ne 0) { throw 'SPI synthesis failed' }
nextpnr-ice40 --hx8k --package ct256 --json build/fpga-reproduce/mapped.json --freq 50 --seed 1 --pcf-allow-unconstrained --asc build/fpga-reproduce/routed.asc --log build/fpga-reproduce/nextpnr.log --report build/fpga-reproduce/report.json
if ($LASTEXITCODE -ne 0) { throw 'SPI placement/routing or timing failed' }
icepack build/fpga-reproduce/routed.asc build/fpga-reproduce/spi.bin
if ($LASTEXITCODE -ne 0) { throw 'SPI bitstream generation failed' }
Set-Location ..
```

```powershell
Set-Location WHK_AXI4_AHB5_Lite_Bridge
New-Item -ItemType Directory -Force build/fpga-reproduce | Out-Null
yosys -p 'read_slang rtl/axi4_ahb5_lite_bridge_pkg.sv rtl/axi4_ahb5_lite_bridge.sv; hierarchy -check -top axi4_ahb5_lite_bridge; synth_ecp5 -top axi4_ahb5_lite_bridge -json build/fpga-reproduce/mapped.json; stat' -l build/fpga-reproduce/yosys.log
if ($LASTEXITCODE -ne 0) { throw 'Bridge synthesis failed' }
nextpnr-ecp5 --85k --package CABGA554 --json build/fpga-reproduce/mapped.json --freq 25 --seed 1 --lpf-allow-unconstrained --textcfg build/fpga-reproduce/routed.config --log build/fpga-reproduce/nextpnr.log --report build/fpga-reproduce/report.json
if ($LASTEXITCODE -ne 0) { throw 'Bridge placement/routing or timing failed' }
ecppack build/fpga-reproduce/routed.config build/fpga-reproduce/bridge.bit
if ($LASTEXITCODE -ne 0) { throw 'Bridge bitstream generation failed' }
Set-Location ..
```

100 MHz 失败重现：把上述相应 `--freq` 改为 `100`，并使用独立输出目录，保留其非零退出码。结果不得标成 PASS。

## 冻结证据索引

- [总结果与位流哈希](../evidence/fpga/20261024/summary.json)
- [证据文件清单及哈希](../evidence/fpga/20261024/manifest.json)
- [SPI 50 MHz 日志](../evidence/fpga/20261024/spi/nextpnr_ice40_50mhz.log)、[时序 JSON](../evidence/fpga/20261024/spi/nextpnr_ice40_50mhz_timing.json)、[100 MHz 失败日志](../evidence/fpga/20261024/spi/nextpnr_ice40.log)
- [桥 25 MHz 日志](../evidence/fpga/20261024/bridge/25mhz/nextpnr.log)、[时序 JSON](../evidence/fpga/20261024/bridge/25mhz/report.json)、[100 MHz 失败日志](../evidence/fpga/20261024/bridge/nextpnr_ecp5.log)

GitHub Actions 当前运行仿真与限定范围形式验证。本报告是本地 FPGA 结果，二者执行位置与范围分开记录。
