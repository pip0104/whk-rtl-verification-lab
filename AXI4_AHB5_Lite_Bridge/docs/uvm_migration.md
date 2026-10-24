# 合法 UVM 1.2 环境迁移说明

当前项目的可执行验证使用 cocotb，实现了与 UVM 相同的 agent/reference-model/scoreboard/coverage 分层职责，并已完成端到端功能回归。由于本机没有可用的合法 UVM 商业仿真器，UVM 代码和 URG 结果不应伪造。

取得学校/企业的有效授权后，按下表迁移，而不是改变 DUT 或规格。

| UVM 组件 | 直接复用的当前资产 | 职责 |
|---|---|---|
| `axi_master_agent` | `BridgeTestbench.send_aw/send_w/send_ar/get_b/get_r` | sequence 驱动与 AXI monitor transaction 重组 |
| `ahb_slave_agent` | `AhbMemorySlave` | HREADY/HRESP 注入、前门 memory、AHB monitor |
| `bridge_reference_model` | `tools/reference_model.py` | 地址、lane、非法请求 oracle；应移植而非重写规则 |
| `bridge_scoreboard` | `expected_memory`、`check_ahb_beats` | AXI 输入、AHB 访问、AXI 输出三向关联 |
| `bridge_coverage` | `FunctionalCoverage` | 用同一 bin 迁移到 covergroup/cross |
| `bridge_assertions` | `rtl/axi4_ahb5_lite_bridge_assert.sv` | SVA 编译、assertion cover、failure log |

迁移后的验收条件：先让 UVM 重现 `results/full_regression.log` 的每一个场景；再开启 `-cm line+cond+fsm+branch+tgl+assert`（具体开关取决于获得授权的工具版本），最后由实际 URG 数据填写覆盖率，而不是沿用任何示例数字。
