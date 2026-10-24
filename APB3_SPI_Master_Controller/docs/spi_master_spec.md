# APB3 SPI Master Controller 规格书

## 1 目的与范围

本 IP 是单时钟、单片选的 SPI 主控制器。SoC 中的软件通过 APB3 配置控制寄存器和数据寄存器；控制器以主机身份驱动 SPI 时钟、MOSI 和低有效 CS，并在规定采样沿读取 MISO。此规格是 RTL、参考模型、UVM scoreboarding 和测试的唯一行为基线。

本版本强调可验证的控制面，不实现 DMA、FIFO、多个从机选择、dual/quad I/O 或时钟域转换。

## 2 时钟复位和接口

| 接口 | 信号 | 约定 |
|---|---|---|
| PCLK | `pclk` | APB3 与串行控制状态机的唯一时钟。 |
| PRESETn | `presetn` | 异步低有效复位；复位后控制器禁用、CS=1、SCLK=0、MOSI=0。 |
| APB3 | `PADDR/PSEL/PENABLE/PWRITE/PWDATA/PRDATA/PREADY/PSLVERR` | 32-bit 数据、无 wait state；合法访问时 PREADY=1。 |
| SPI | `spi_sclk/spi_mosi/spi_miso/spi_cs_n` | Mode 0/1/2/3 的四线主机接口，CS 低有效。 |
| IRQ | `irq` | `IRQ_ENABLE & IRQ_STATUS` 的按位 OR。 |

APB3 主机必须遵守 setup/access 两相：setup 周期 `PSEL=1, PENABLE=0`，下一个 access 周期 `PSEL=1, PENABLE=1`。地址范围外的 access 保持 `PREADY=1` 并置 `PSLVERR=1`。

## 3 寄存器映射

| 偏移 | 名称 | 访问 | 说明 |
|---:|---|---|---|
| 0x00 | CTRL | RW + command | 工作模式、位序、帧长及 START/CS_RELEASE 命令。 |
| 0x04 | CLKDIV | RW | SCLK 半周期减一；实际半周期为 `(CLKDIV+1) * PCLK`。 |
| 0x08 | TXDATA | RW | 下一帧的 32-bit 发送字；未消费时再次写入产生 OVERRUN。 |
| 0x0c | RXDATA | RO | 最近一帧接收字；读操作清 `RX_VALID`，不清中断 pending。 |
| 0x10 | STATUS | RO | 状态字段。 |
| 0x14 | IRQ_ENABLE | RW | 中断掩码。 |
| 0x18 | IRQ_STATUS | RW1C | 粘滞 pending 状态，写 1 清对应位。 |

### CTRL 0x00

| 位 | 名称 | 说明 |
|---:|---|---|
| 0 | ENABLE | 1 允许 START；清零会在 PCLK 边界中止 busy 帧并置 ABORT。 |
| 1 | START | 写 1 命令。仅在 ENABLE=1、BUSY=0 且 TXDATA 有效时消费 TXDATA 并启动一帧。读回恒为 0。 |
| 2 | CPOL | 空闲 SCLK 电平。 |
| 3 | CPHA | 0：leading edge 采样、trailing edge 改变 MOSI；1：leading edge 改变 MOSI、trailing edge 采样。 |
| 4 | CONTINUOUS | 该帧完成时保持 CS 为低，方便下一帧使用同一片选继续传输。 |
| 5 | LSB_FIRST | 0 为 MSB first，1 为 LSB first。 |
| 12:8 | BITS_MINUS_1 | 帧长编码；实际 bit 数为该值加 1，范围 1 至 32。复位为 7，即 8 bit。 |
| 13 | Reserved | 读写保留，必须写 0。 |
| 16 | CS_RELEASE | 写 1 命令；仅在 BUSY=0 时将保持中的 CS 拉高。读回恒为 0。 |

START 将 CPOL、CPHA、CONTINUOUS、位序和帧长锁存到活动帧；帧中写 CTRL 或 CLKDIV 不会改变已经在输出的波形。推荐流程是先写静态 CTRL，使新的 CPOL 在 CS 高电平时稳定，再写 TXDATA，最后写同一 CTRL 值加 START。

### STATUS 0x10

| 位 | 字段 | 含义 |
|---:|---|---|
| 0 | BUSY | 有活动帧。 |
| 1 | TX_READY | `!TX_VALID`，可写入 TXDATA。 |
| 2 | RX_VALID | 有未读 RXDATA。 |
| 3 | CS_ACTIVE | `CS_n=0`，包括连续帧之间的保持期。 |
| 4 | ENABLED | CTRL.ENABLE 的当前值。 |
| 5 | OVERRUN | IRQ_STATUS.OVERRUN 的镜像。 |
| 6 | ABORT | IRQ_STATUS.ABORT 的镜像。 |

### 中断位

| 位 | 事件 | 置位条件 |
|---:|---|---|
| 0 | DONE | 每帧在最后一个采样沿后、SCLK 回到 CPOL 时结束。 |
| 1 | RX_AVAIL | 成功将 RXDATA 写入空的 RX 寄存器。 |
| 2 | OVERRUN | TXDATA 已有效时再次写入，或上一帧 RXDATA 未读而新帧完成。 |
| 3 | ABORT | ENABLE 被清零时有活动帧。 |

## 4 SPI 时序与数据规则

`CLKDIV=N` 表示 SCLK 每维持一个电平 `(N+1)` 个 PCLK 周期后翻转。一个 B bit 帧有 `2*B` 个 SCLK 翻转，最后一条 trailing edge 总使时钟回到 CPOL。

| Mode | CPOL | CPHA | Leading edge | Trailing edge |
|---|---:|---:|---|---|
| 0 | 0 | 0 | 采样 | 更新下一位 |
| 1 | 0 | 1 | 输出新位 | 采样 |
| 2 | 1 | 0 | 采样 | 更新下一位 |
| 3 | 1 | 1 | 输出新位 | 采样 |

MSB first 以 `TXDATA[B-1]` 为第一位；LSB first 以 `TXDATA[0]` 为第一位。接收数据以同一位序重新装配在 RXDATA 的低 B bit。未使用的高位为零。

## 5 单帧、连续帧和软件流程

单帧：静态配置 -> 写 TXDATA -> START -> 轮询 BUSY/DONE -> 读 RXDATA。完成后 CS 自动拉高。

连续帧：第一帧以 CONTINUOUS=1 启动；其结束后 BUSY=0、CS 仍低。软件读 RXDATA 并写第二帧 TXDATA，再以相同 CPOL/CPHA/位序启动下一帧。最后一帧用 CONTINUOUS=0，或在空闲保持期写 CS_RELEASE。此定义保证单 RX 寄存器不会因自动连发而不可见地覆盖数据。

连续保持期间不能切换 CPOL、CPHA、帧宽或位序；否则 CS 已低时改变时钟定义会让从机无法可靠界定帧。

## 6 不变量和未支持范围

1. BUSY 帧内 CPOL/CPHA/位序/帧长均采用 START 时锁存值。
2. 每一帧恰好产生 `2*BITS` 条 SCLK 边沿，并在结束时恢复 CPOL。
3. CPHA=0 的第一位必须在第一条 leading edge 前稳定；CPHA=1 仅在 leading edge 后被采样。
4. CS 非连续帧结束时释放；连续帧之间保持有效。
5. RXDATA 未读不得悄悄替换，必须报告 OVERRUN。

不支持事项：多 CS、帧间无软件干预的 FIFO streaming、DMA、从机模式、三态 MISO 控制、dual/quad SPI、CRC、CS setup/hold 延迟寄存器和 CDC。扩展任何一项时需同步更新规格、reference model、UVM coverage 与回归。
