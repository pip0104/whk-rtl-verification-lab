# AXI4 to AHB5-Lite Bridge 验证追踪表

> 本表是旧实现的历史追踪基线。2026-10-24 修正了 AHB 分相位、非法后续写拍与 4KB 边界；当前 fresh 仿真结果和行为取舍见 [修复报告](20261024_bridge_fix.md)，旧代码覆盖百分比不适用于新 RTL。

本文将规格需求、可执行验证和实际证据对应起来。状态只表示当前项目已使用的免费工具链实际执行的结果，不引用或推测商业仿真器结果。

## 回归基线

- RTL：`rtl/axi4_ahb5_lite_bridge.sv`
- 参考模型单元测试：11/11 通过
- 主回归：`tests/cocotb/test_bridge_regression.py::full_protocol_regression`
- 主回归结果：1/1 通过，仿真时间 10,525 ns
- 事务级功能覆盖：36/36 个本项目定义的必达 bin 命中（100%）；原始数据见 `results/functional_coverage.json`。
- 参数展开：`FIFO_DEPTH=8/16/32/64/128` 均由 Icarus 成功展开。
- Verilator 代码覆盖 smoke：实际通过；DUT `line=73.9% (34/46)`、`toggle=38.3% (436/1138)`、`branch=59.4% (38/64)`、`expr=67.6% (50/74)`。原始数据库及报告见 `docs/code_coverage_report.md`。

“100%”仅指本表中明确列出的、由可执行 cocotb 覆盖模型统计的 36 个功能 bin；它不能和上方的 Verilator 代码覆盖基线混合为一个百分比，更不是商业工具的 line/condition/FSM/branch/toggle/assertion coverage。

## 需求追踪

| ID | 规格风险 | 可执行场景 | 检查方法 | 状态 |
|---|---|---|---|---|
| RQ-01 | 五个 AXI 通道在背压时 payload 稳定 | B/R 各 3 周期背压、W FIFO 满压 | `ProtocolMonitor` 在相邻握手边沿检查 AW/W/AR/B/R；`get_b/get_r` 再检查响应 payload | PASS |
| RQ-02 | 单拍地址、数据、B/R 响应 | 32-bit 单拍读写、所有窄传输 lane | 独立 memory scoreboard 与 AHB monitor | PASS |
| RQ-03 | INCR 地址、HTRANS/HBURST、RLAST | INCR2/4/16 写读，固定种子随机混合 | Python `burst_addresses`、逐 beat AHB 比对 | PASS |
| RQ-04 | WRAP 边界和编码 | WRAP2/4/8/16，从 wrap 块末尾开始 | 逐 beat 地址、NONSEQ/SEQ、HBURST 比对 | PASS |
| RQ-05 | FIXED 不可错误映射为递增 AHB burst | FIXED4 写读 | 每 beat 同地址、`SINGLE+NONSEQ` 比对 | PASS |
| RQ-06 | 窄传输 lane/WSTRB/读数据掩码 | 1B lane 0..3、2B lane 0/2、4B | 独立 byte-mask scoreboard | PASS |
| RQ-07 | AHB HREADY wait 期间稳定 | 1、2、4 个 HREADY wait | AHB BFM 比对地址/控制/写数据的冻结快照 | PASS |
| RQ-08 | AHB ERROR 到 AXI SLVERR 的映射 | 读首拍 ERROR；写中拍/末拍 ERROR | 逐 beat RRESP、写 B、停止 AHB 访问与 memory 状态 | PASS |
| RQ-09 | 非法请求必须 DECERR 且不可触达 AHB | 保留 burst、未对齐、过大 size、错误 WSTRB/WLAST、17-beat 超容量写 | 零 AHB beat 断言、DECERR 比对、非法写流式 drain 不死锁 | PASS |
| RQ-10 | FIFO 满压、背压和恢复 | 16 项 W FIFO 预填充，再按 AW 顺序消耗 | WREADY=0、16 次 B 和 memory 记分板 | PASS（16 深度）；其余深度完成参数展开检查 |
| RQ-11 | 复位清理陈旧事务/响应 | idle、AW 已收、W 已收、AHB wait、B stall、R stall | reset 后无 B/R；后续新读写可完成 | PASS |
| RQ-12 | 混合流量、顺序和无丢失 | W 先于 AW、未收齐 W 的 AW/AR 严格排序、固定种子 12 笔混合流量 | AHB transaction log、AXI response、memory scoreboard | PASS |

## 验证环境对应关系

| 标准验证角色 | 当前可执行实现 | 文件 |
|---|---|---|
| AXI Master Agent | pin-level AXI driver | `tests/cocotb/bridge_bfm.py` 的 `BridgeTestbench` |
| AHB Slave Agent + memory model | 可配置 wait/error 的 AHB memory responder | `AhbMemorySlave` |
| Reference model | burst 地址及 byte lane 独立 oracle | `tools/reference_model.py` |
| Scoreboard | 独立 expected-memory + AHB beat checker | `BridgeTestbench.check_*` |
| Assertion monitor | AXI stalled-payload、AHB wait-stability、reset checks | `ProtocolMonitor`、`AhbMemorySlave`、`rtl/*_assert.sv` |
| Functional coverage | 命令、响应、wait、错误、FIFO、reset bin 计数 | `FunctionalCoverage`、`results/functional_coverage.json` |

## 工具边界与后续迁移

Icarus + cocotb 已真实执行上述回归；另外 Verilator + MSYS2 已真实生成 smoke 场景的 line/toggle/branch/expression 代码覆盖数据。免费工具的能力边界仍然如下：

- `rtl/axi4_ahb5_lite_bridge_assert.sv` 保留为合法商业仿真器可用的 SVA 源码，未纳入 Icarus 编译。
- Verilator 当前报告不含 condition coverage；其 FSM 统计为 `0/0`，不构成 FSM 覆盖结论；也不产生 SVA assertion coverage 或 URG 合并数据库。
- 代码覆盖的实际数值是 smoke 基线，而不是完整 cocotb 回归的结果，不能写成 99.7% 或 80%。
- 若取得学校或公司合法 VCS/Verdi 授权，应复用同一规格、reference model、测试矩阵与脚本接口，再以 UVM agent/scoreboard/covergroup 落地并重新出具实际报告。
