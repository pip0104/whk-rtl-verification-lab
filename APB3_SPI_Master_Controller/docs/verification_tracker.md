# APB3 SPI Master 验证追踪表

本表区分“已真实执行的免费回归”和“已编写、等待商业工具执行的 UVM”。所有状态只引用当前项目实际产物。

| ID | 需求 | 当前实证 | 状态 |
|---|---|---|---|
| RQ01 | APB3 setup/access | SV smoke + cocotb APB driver | PASS |
| RQ02 | 非法 APB 地址 PSLVERR | cocotb 0x20 access | PASS |
| RQ03 | 4 SPI mode | 00/01/10/11 独立 slave | PASS |
| RQ04 | MSB/LSB 位序 | 8-bit + 16-bit 非回文 word | PASS |
| RQ05 | divider | smoke 检查 CLKDIV=1 的 20 ns edge delta；cocotb 命中 1/2/3/4 | PASS |
| RQ06 | 单帧 | CS release、RX 和 busy 返回 idle | PASS |
| RQ07 | 连续 CS hold | 两帧、帧间 CS 保持、末帧释放 | PASS |
| RQ08 | DONE/RX IRQ W1C | cocotb enable/mask/clear | PASS |
| RQ09 | TX/RX overrun | cocotb 检查 TX double-write 保留原字、RX unread 保留旧字 | PASS |
| RQ10 | busy abort | cocotb 在 16-bit 长帧中清 ENABLE，检查 CS/busy/ABORT | PASS |
| RQ11 | UVM covergroup/SVA | 环境和 checker 源码存在；没有商用 run | TOOL BLOCKED |

回归基线：reference model 12/12 通过，Icarus smoke 通过，cocotb 端到端回归 1/1 通过（8070 ns），`functional_coverage.json` 为 23/23 必达事务 bin。UVM/商业 coverage 仍没有实际授权工具 run，不能被该 23/23 覆盖率掩盖。
