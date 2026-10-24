# APB3 SPI Master 验证计划

## 1 验证目标

证明 DUT 按 `spi_master_spec.md` 完成合法 APB3 配置、四种 SPI 模式的数据交换、可编程分频、单帧与 CS 保持连续帧，并在中断、溢出、非法寄存器访问和中止场景下给出规定的状态。最终商业流程以 SystemVerilog UVM、covergroup、SVA 和代码覆盖率构成闭环；当前免费工具实际运行 cocotb 等价分层回归并单独记录结果。

## 2 环境架构

```text
APB sequence / cocotb driver -> APB3 slave pins -> DUT -> SCLK MOSI CS_n -> SPI slave model
            |                    |                  |                         |
            +-> APB monitor -----+-> scoreboard <---+-> SPI monitor ----------+
                                          |
                                  reference model + functional coverage
```

- APB driver：生成 setup/access 两阶段读写，检查 `PREADY/PSLVERR`。
- SPI slave：按 CPOL/CPHA 在非采样沿驱动 MISO，独立捕获 MOSI。
- Reference model：独立计算位序、采样沿、边沿数量和 divider 编码。
- Scoreboard：以 APB 可见的 CTRL/TXDATA/START 建立期望，和原始 SPI 波形以及 RXDATA 对比。
- Coverage：订阅事务，不从 DUT 内部寄存器取样。

## 3 需求追踪

| ID | 规格风险 | 场景 | 检查 | 覆盖点 |
|---|---|---|---|---|
| RQ01 | APB setup/access 和合法响应 | 读写 CTRL/CLKDIV/TX/RX | PREADY、无 PSLVERR、读回值 | read/write |
| RQ02 | 非法地址处理 | 访问 0x20 | PREADY=1、PSLVERR=1 | invalid register |
| RQ03 | Mode 0/1/2/3 | 4 个 CPOLxCPHA case | 独立 slave MOSI/RXDATA | mode cross |
| RQ04 | MSB/LSB 位序 | 非回文 8/16-bit 数据 | 逐位比较 | bit order x width |
| RQ05 | divider | 1/2/3/4 编码 | SCLK phase 时长与 edge count | divider bins |
| RQ06 | 帧长 | 8 和 16 bit；后续 UVM 补 1/32 和随机 | 数据、2B 边沿数 | width bins |
| RQ07 | 单帧收尾 | CONTINUOUS=0 | CS 高、BUSY=0、SCLK=CPOL | single frame |
| RQ08 | 多帧 CS 保持 | 连续第一帧和最终帧 | 帧间 CS=0、最终 CS=1 | continuous bins |
| RQ09 | RX/DONE/IRQ | enable、W1C | pending/IRQ 置清 | interrupt path |
| RQ10 | 单项缓冲边界 | 未读 RX 或重复 TX | OVERRUN 粘滞 | overrun |
| RQ11 | abort | busy 时 ENABLE=0 | CS 释放、ABORT | abort |

## 4 覆盖率计划

UVM `spi_coverage` 定义 CPOL、CPHA、mode cross、LSB、continuous、1/8/16/32 bit 和 divider 分类。cocotb 当前实际统计了 23 个必达事务 bin：4 mode + 2 bit-order + 2 width + 4 divider + 3 continuous + 4 interrupt + 2 overrun + 1 abort + 1 illegal-APB。其 23/23 只说明当前已执行场景是否覆盖，不替代 UVM covergroup 百分比。

闭环顺序：先执行 directed smoke -> 加随机合法 mode/width/divider -> 收集 UVM functional/code/assertion coverage -> 针对 hole 增加最小测试 -> 对结构不可达项以规格和 RTL 证明作 waiver。不得用 cocotb 的 100% 或 Verilator smoke 的代码数字替代商业覆盖报告。
