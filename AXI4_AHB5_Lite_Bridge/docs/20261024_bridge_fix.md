# AXI4→AHB5-Lite 协议修复与实际回归（2026-10-24）

本次在独立仓库副本中修改并实际运行。原项目目录和 ZIP 未改动。本报告对应修复后的 RTL，旧资料中的 10,525 ns、代码覆盖百分比、综合面积和 Fmax 都是旧版本历史证据，不归属本次实现。

## 结果

| 验证 | 本次实际结果 | 证据 |
|---|---|---|
| 原 full protocol + 新增定向测试 | 5/5 PASS；原主测试 13,725 ns；合计 14,725 ns | `results/deepening/green_full_entrypoint.log`、`results/deepening/green_full.xml` |
| 地址参考模型 | 16/16 PASS（保留原 11 项，新增 5 项） | `results/deepening/green_reference.log`、完整入口日志 |
| 原 SV smoke | PASS，32-bit 与 byte lane 2 窄传输；385 ns 时结束 | `results/deepening/green_full_entrypoint.log` |
| 参数检查 | FIFO_DEPTH 8/16/32/64/128 elaboration PASS | 完整入口日志；这不是五种深度全部功能回归 |
| 主事务级功能覆盖门槛 | 36/36 必达分类 bin，缺失列表为空；644 次 coverpoint 累计命中 | `results/functional_coverage.json` |
| 覆盖率门槛负向检查 | 空覆盖产生 AssertionError，负向测试捕获后 PASS | `required_coverage_bins_fail_closed`；`results/deepening/coverage_gate_negative.json` |
| 环境自检与主报告隔离 | probe PASS；自检前后主 XML SHA256 相同 | `results/deepening/green_probe.log`、`results/deepening/junit_isolation.json` |

工具版本、基线 Git commit、当前源文件 SHA256、命令和结果摘要在 `results/deepening/manifest.json`。实际使用 Python 3.12.14、cocotb 2.1.0、Icarus 14.0 devel。Icarus 的 constant-select/elaboration 提示和本机 GPI 日志格式提示仍会出现；没有据此声称日志零 warning。

## RED：先在旧 RTL 上实际失败

先替换为只观察公共 AHB 引脚的分相位 responder，并新增测试；此时尚未修改 RTL 或参考模型。

| 反例 | 旧实现实际失败表现 | 根因 |
|---|---|---|
| 地址/数据分相位 | 读到无数据相位的毒值 `0xDEAD5A5A`，预期 `0x1234ABCD` | 旧 RTL 在地址接受的同一个沿就采样 HRDATA |
| 第二拍非法 WSTRB | 已有 1 笔 AHB 写，预期整笔 0 笔 | 旧 RTL 到每拍执行前才检查该拍，前拍已经产生副作用 |
| INCR 从 `0xFFC` 发两个 4-byte beat | RRESP 实际 OKAY，预期 DECERR | 描述符和地址模型均未检查跨 4KB |
| 参考模型 | 16 项中 3 项失败：跨 4KB、FIXED 超 16 beat、地址溢出 | 地址合法性规则缺失 |

原始失败日志为 `results/deepening/red_protocol.log`、`red_protocol.xml`、`red_reference.log`；旧 RTL 的 hash 为 `red_source_hash.txt`。三个 RTL 测试的失败均为预期行为断言，不是编译失败。测试开发时曾修正 responder 在初始复位前读取 X 的问题；正式保留的 RED 是修正测试启动问题之后的运行。

RED 还暴露了交付链问题：`cocotb runner.test()` 在本机测试失败时仍可让外层 Python 返回 0。因此主 runner 现在解析 fresh JUnit，只要 failure/error/skip 或默认测试集合不完整就明确非零退出。旧 `tests/cocotb/results.xml` 曾被 25 ns 时钟 probe 覆盖，故现改成独立输出。

## 修正后的契约

1. **真实 AHB 地址相位和后继数据相位。** 新增 `ST_AHB_ADDRESS`；地址在 HREADY 高的边沿被接受后，进入 `ST_AHB_WAIT` 数据相位。只有后继数据相位完成时才采样 HRDATA/HRESP 或 pop W FIFO。写数据等待期间始终来自未消费的 FIFO 头。
2. **每个 AXI beat 独立映射为 AHB SINGLE/NONSEQ。** 保留 AXI FIXED/INCR/WRAP 的地址和 AXI 响应行为，但本版不输出 AHB 多拍 HBURST、SEQ/BUSY，也不追求流水化吞吐量。此取舍消除了旧设计在 IDLE 气泡后恢复 SEQ 的不完整 AHB burst 控制；不能继续宣称本版保留旧 AHB burst 编码能力。
3. **两周期 ERROR。** 独立 responder 在数据相位先输出 `(HRESP,HREADY)=(1,0)`，再输出 `(1,1)`；RTL 等完成沿才转 SLVERR，停止后续真实 AHB 访问。读仍补齐错误 R beat，写 drain 剩余数据；已成功的早期 AHB 写不回滚。原 full protocol 的首/中/末错误场景都在该新 responder 下重跑。
4. **合法写整笔预检。** 既然整笔数据已缓冲，新增逐项预检状态，检查所有 beat 的 WSTRB 与 WLAST 后才发首笔 AHB。后续拍才出现非法同样实现整笔零 AHB 副作用。超容量/非法描述符继续流式 drain，不要求不可能完成的整笔缓冲。
5. **4KB 与范围检查。** INCR 检查末字节，FIXED 只检查反复访问的单拍范围，WRAP 按自然对齐 wrap block 判定；`0xFFC` 的合法 FIXED/WRAP 不会被误当线性 INCR 拒绝。FIXED 最多 16 beat，32 位地址溢出拒绝。RTL 的 32 位地址/数据契约现有显式参数检查。

AHB 时序依据：[Arm AMBA AHB Protocol Specification, IHI0033C](https://documentation-service.arm.com/static/6141bf0d674a052ae36ca811?token=)。实现是该协议的保守 SINGLE 子集，没有进行第三方 VIP 认证。

## 验证环境如何避免旧模型掩盖错误

`tests/cocotb/bridge_bfm.py::AhbMemorySlave` 在有效边沿前采样引脚：只有 HREADY 高时接受新地址；完成上一笔已登记的数据相位时使用登记的地址、方向和大小，以及当前数据相位 HWDATA。没有数据相位时 HRDATA 故意给毒值。等待状态比较控制/数据稳定性；ERROR 按标准输出两周期，并记录低/高 HREADY 两个周期。它不读取 DUT 内部 FSM，也不使用 RTL 的地址函数。

`tb/ahb5_lite_memory_model.sv` 也改为登记地址/控制，在后继数据相位写内存。原纯 SystemVerilog smoke 因而不再依赖同拍地址/数据的简化模型。

旧主回归保留所有场景；AHB 检查器按明确的新 SINGLE 契约检查逐拍地址、方向、大小、数据和编码。reset-on-wait 场景改为观察 HREADY 低的数据相位，因为 HTRANS 在此时表示下一地址并正确为 IDLE。

新增测试在 `tests/cocotb/test_bridge_deepening.py`：分相位读写；后续非法 strobe/缺失最后 WLAST 的零副作用；4KB 读写拒绝、页尾合法 FIXED/WRAP、两周期 ERROR；功能覆盖门槛负向检查。

覆盖门槛明确列出 36 个必达分类 bin；报告给出 required、covered、missing，不再只看有 JSON 文件就算通过。644 是不同 coverpoint 的累计命中数，不能写成 644 笔独立事务；36/36 也不是交叉覆盖、代码覆盖或协议完备性证明。

## 复现

从本子项目目录执行，使用已安装了 cocotb 的 Python；无需复制虚拟环境进仓库：

```powershell
. 'F:\EDA\oss-cad-suite\environment.ps1'
$py = 'C:\Users\Pip\Documents\总线验证\AXI4_AHB5_Lite_Bridge\.venv_cocotb\Scripts\python.exe'
.\scripts\run_full_regression.ps1 -PythonExe $py
.\scripts\run_cocotb_environment_probe.ps1 -PythonExe $py
```

跨平台/CI 的统一入口由仓库根 `scripts/verify.py` 提供。主 runner 默认执行原主测试加四项深化测试，写 `results/bridge_regression.xml`，运行前删除该 XML 与主覆盖 JSON。probe 单独写 `results/environment_probe.xml`，不会覆盖主结果。`BRIDGE_TEST_MODULE=test_bridge_deepening` 仅用于定向重现，不等价于完整主回归。

## 仍未完成

- 本桥没有新增 formal harness、prove/cover 结果或 UVM 实现；SVA 源码存在不代表已执行。
- 没有 CPU/LSU 接入、RISC-V 指令或 ISS 差分验证、上游开源 CPU PR、FPGA 上板。
- 没有重跑新 RTL 的代码覆盖、综合/布局布线或 STA；旧资源与频率不能直接沿用。
- 后端仍串行执行，AW 同拍优先，无公平性保证；缺失 W 数据或外部永久背压仍可永久阻塞，没有超时机制。
- 本次主功能回归为默认 FIFO 16 深度；8/32/64/128 只有参数展开，不宣称都完成相同功能矩阵。

适合面试表述：发现旧验证环境把地址和数据放在同拍，重新搭建只看公共引脚的 AHB responder，用三个真实失败反例定位问题，再修正相位、整笔写预检和边界拒绝；原主回归与新增四项均通过，事务级功能覆盖 36/36。不能把这些成果改写为已完成 CPU 验证或整桥形式收敛。
