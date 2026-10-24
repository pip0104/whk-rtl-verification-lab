# AXI4 to AHB5-Lite Bridge 验证计划（v0.1）

## 1. 验证目标

证明 DUT 对 `docs/bridge_spec.md` 定义的合法请求完成正确 AXI-to-AHB5-Lite 转换；对非法请求和 AHB 错误产生规定响应；在 AXI/AHB 背压、FIFO 边界与复位中保持协议安全。验证采用 SystemVerilog + UVM 1.2，最终按测试、功能覆盖率、断言、代码覆盖率和不可达项分析闭环。

## 2. 环境架构

```text
AXI sequence -> AXI Master Agent -> [AXI IF] -> DUT -> [AHB IF] -> AHB Slave Agent / memory model
                              |                   |                    |
                              +-> AXI monitor -----+-> scoreboard <-----+-> AHB monitor
                                                          |
                                                     reference model + coverage
```

- AXI Master Agent：active，产生 AW/W/AR 与 BREADY/RREADY 背压，监控完整 AXI 事务。
- AHB Slave Agent：active，按配置插入 HREADY wait、OKAY/ERROR，维护前门存储模型，监控 bridge 发起的实际访问。
- Reference model：独立计算合法性、每 beat 地址、lane、memory 期望、B/R 响应。地址算法与 `tools/reference_model.py` 一致。
- Scoreboard：关联 AXI 输入、AHB 观察和 AXI 输出；逐 beat 比对地址、方向、数据、响应、ID、RLAST。
- Coverage：订阅 monitor transaction；不得从 DUT 内部状态采样。

## 3. 需求到验证手段映射

| ID | 规格点 | 定向测试 | 断言 | 功能覆盖 |
|---|---|---|---|---|
| RQ-01 | AXI 五通道握手和背压稳定性 | `axi_backpressure_test` | AW/W/AR/B/R stable-while-stalled | 通道 x stall 长度 |
| RQ-02 | 单拍读/写地址、数据、响应 | `single_rw_test` | 每写一个 B；每读一个 R | direction x response |
| RQ-03 | INCR 地址和 beat 数 | `incr_burst_test` | beat count / RLAST | LEN x SIZE x dir |
| RQ-04 | WRAP 地址回绕 | `wrap_burst_test` | 地址与 reference function 一致 | WRAP len x start position |
| RQ-05 | FIXED 地址不变 | `fixed_burst_test` | 每 beat 地址恒定 | FIXED x size x dir |
| RQ-06 | 窄传输 lane / WSTRB | `narrow_transfer_test` | HSIZE 与 size 映射 | size x addr_low x dir |
| RQ-07 | AHB HREADY 等待 | `ahb_waitstate_test` | wait 时控制稳定 | wait length x dir |
| RQ-08 | AHB ERROR 映射 | `ahb_error_test` | 响应 beat 数/最终 B | dir x error_beat |
| RQ-09 | 非法输入 DECERR | `illegal_request_test` | 无 AHB 有效传输 | illegal kind x dir |
| RQ-10 | FIFO 满压与恢复 | `fifo_stress_test` | no under/overflow | depth x occupancy band |
| RQ-11 | 复位恢复 | `reset_recovery_test` | reset 后无陈旧输出 | reset insertion point |
| RQ-12 | 混合随机流量与顺序 | `random_mix_test` | 无重复/丢失 response | dir x burst x response cross |

## 4. 测试列表与最低通过标准

| 测试 | 激励重点 | 最低检查 |
|---|---|---|
| `smoke_test` | reset 后一个 32-bit 单拍读写 | 编译、UVM topology、scoreboard 无错误。 |
| `single_rw_test` | 各地址的单拍读写 | memory 前门/后门一致，B/R 为 OKAY。 |
| `incr_burst_test` | 2/4/8/16 beat，1/2/4 byte | 每 beat 地址、数据、RLAST 正确。 |
| `wrap_burst_test` | 2/4/8/16 beat，从块内不同位置起始 | 回绕边界和 HTRANS/HBURST 正确。 |
| `fixed_burst_test` | 多 beat 相同地址 | 全部访问同一地址，顺序正确。 |
| `narrow_transfer_test` | 所有合法 address low bits x size | WSTRB/HWDATA/HRDATA lane 正确。 |
| `ahb_waitstate_test` | 随机 0~N 个 wait | HREADY=0 时信号稳定，无超时。 |
| `ahb_error_test` | 首/中/末 beat 注入 ERROR | SLVERR、剩余 beat 策略和无死锁正确。 |
| `illegal_request_test` | illegal burst/size/align/strobe/WLAST | DECERR，AHB 无实际访问。 |
| `fifo_stress_test` | 深度 8/16/32/64/128，高速 AXI + 慢 AHB | READY 降低、无溢出、恢复后完成。 |
| `reset_recovery_test` | AW 后、W 中、AHB wait、B/R stall 中复位 | flush 干净，后续新请求正常。 |
| `random_mix_test` | 合法约束随机，固定 seed 回归 | 无 scoreboard/assertion error，覆盖率增长。 |

## 5. 功能覆盖率模型

每个 covergroup 从 AXI/AHB monitor 收集，至少包含：

| Coverpoint | Bins |
|---|---|
| `direction_cp` | READ、WRITE |
| `burst_cp` | FIXED、INCR、WRAP |
| `size_cp` | 1B、2B、4B |
| `beats_cp` | 1、2、4、8、16、OTHER_SUPPORTED |
| `addr_lane_cp` | 32-bit 总线的地址低两位合法位置 |
| `response_cp` | OKAY、SLVERR、DECERR |
| `wait_cp` | 0、1、2_3、4_PLUS 个 HREADY wait |
| `fifo_level_cp` | empty、low、middle、near_full、full |
| `error_beat_cp` | first、middle、last |
| `reset_point_cp` | idle、AW/W capture、AHB wait、AXI response stall |

必要交叉：`direction x burst x size`、`direction x response`、`burst x beats`、`size x addr_lane`、`direction x wait`、`direction x error_beat`、`fifo_depth x fifo_level`。先避免全笛卡尔积；每个 cross 都要对应一个规格风险。

## 6. Assertion 计划

1. AXI AW/W/AR/B/R 通道各自的 stalled payload stability。
2. AHB active transfer 在 HREADY=0 时控制和写数据稳定。
3. FIFO count 不越界，空不 pop、满不 push。
4. 命令接受后唯一完成；读 N beat 对应 N 个 R，最后一拍 RLAST。
5. 写命令对应唯一 B，且 BID 等于 AWID。
6. 非法命令不发 AHB 有效传输。
7. reset 期间无 READY/VALID，释放 reset 后无陈旧响应。

每条 assertion 均应有：名称、意图、时钟/disable 条件、触发覆盖（cover property）和至少一个会使它失败的 mutation 思路。

## 7. 回归与覆盖率闭环

1. 每次失败记录 test、seed、参数、日志路径和首个错误事务。
2. 修复前先产生最小可复现 directed test；修复后保留为永久回归。
3. 回归合并 function/code/assertion coverage，按需求 ID 维护 Verification Tracker。
4. 未覆盖项只允许三种状态：待补测试、设计不可达、工具/配置不可达；后两种必须写出证据和批准人。
5. 项目目标是功能覆盖率 100%，代码覆盖率接近既定目标且有 waiver 说明；最终数字以实际 URG 报告为准。
