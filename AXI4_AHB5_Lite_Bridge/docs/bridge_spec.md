# AXI4 to AHB5-Lite Bridge 规格书（学习版 v0.2，2026-10-24）

本版变更：真实 AHB 地址/数据分相位；每个 AXI beat 转独立 AHB SINGLE/NONSEQ；支持两周期 ERROR；合法写 burst 全部预检后才发起 AHB；增加 AXI 4KB 与地址溢出拒绝。实际 RED/GREEN 证据见 [修复报告](20261024_bridge_fix.md)。

## 1. 目的与范围

本桥接器将上游 **AXI4 memory-mapped** 请求转换为下游 **AHB5-Lite** 主机访问。设计目标是优先保证协议、数据与时序可验证，采用“前端排队、后端串行执行”的微架构；不是追求最高吞吐量的商用互连 IP。

本规格是 RTL、Python 参考模型、UVM reference model、scoreboard、assertion 和 coverage plan 的唯一行为基线。

### 1.1 术语

- AXI Master：发起上游 AW/W/AR 的组件。
- Bridge：AXI4 Slave + AHB5-Lite Master，也是 DUT。
- AHB Slave：接收 HADDR/HWRITE 等信号并返回 HREADY/HRESP/HRDATA 的组件。
- beat：burst 中的一次数据传输。
- 命令（command）：一个 AXI 读请求，或已接收 AW 的 AXI 写请求描述。

## 2. 接口与参数

### 2.1 时钟和复位

| 名称 | 方向 | 约定 |
|---|---|---|
| `clk` | 输入 | AXI 与 AHB 共用单时钟。 |
| `rst_n` | 输入 | 同步、低有效复位。在 `clk` 上升沿采样。 |

复位有效的采样沿清空所有 FIFO、状态机、待发 AXI 响应和正在执行的事务。复位期间 bridge 不宣称接收 AXI 请求（AWREADY/WREADY/ARREADY 为 0），也不宣称有效响应（BVALID/RVALID 为 0）。复位解除后的第一拍从空闲状态开始；复位前未完成事务视为被取消。

### 2.2 默认参数

| 参数 | 默认值 | 合法范围 / 约束 |
|---|---:|---|
| `AXI_ADDR_WIDTH` | 32 | 32（v0.1 固定） |
| `AXI_DATA_WIDTH` | 32 | 32（v0.1 固定） |
| `AXI_ID_WIDTH` | 4 | 1~8 |
| `AHB_ADDR_WIDTH` | 32 | 与 AXI 地址宽度相同 |
| `AHB_DATA_WIDTH` | 32 | 与 AXI 数据宽度相同 |
| `FIFO_DEPTH` | 16 | 8/16/32/64/128；必须是 2 的幂 |
| `MAX_BURST_BEATS` | `FIFO_DEPTH` | 2~128，且不大于 `FIFO_DEPTH` |

`FIFO_DEPTH` 代表命令 FIFO 和写数据 FIFO 的容量。学习版要求整笔写 burst 数据在下发 AHB 前已经缓冲完整，因此接收的 `AWLEN+1` 不得超过 `FIFO_DEPTH` 和 `MAX_BURST_BEATS`。这保证了写数据不会在 AHB burst 中途饥饿，也使 AHB burst 映射更容易验证。

## 3. AXI4 支持范围

### 3.1 支持的通道和字段

| 通道 | 支持字段 | 行为 |
|---|---|---|
| AW | `AWID/AWADDR/AWLEN/AWSIZE/AWBURST` | 描述写 burst；AW 与 W 可以独立到达。 |
| W | `WDATA/WSTRB/WLAST` | 按 AXI 写数据顺序缓冲；W 在 AW 前到达时先留在 data FIFO。 |
| B | `BID/BRESP` | 每一笔 AXI 写 burst 恰好返回一次。 |
| AR | `ARID/ARADDR/ARLEN/ARSIZE/ARBURST` | 描述读 burst。 |
| R | `RID/RDATA/RRESP/RLAST` | 每个读 beat 恰好返回一次，最后一拍 `RLAST=1`。 |

未在 v0.1 显式处理的 AXI sideband（例如 cache、lock、QoS、region、user）不参与功能决策。RTL 顶层若暴露这些端口，应以参数化常量或安全默认值映射，并在接口文档中标明。

### 3.2 突发与大小

| 字段 | 支持值 | 规则 |
|---|---|---|
| `AxBURST` | `FIXED=2'b00`、`INCR=2'b01`、`WRAP=2'b10` | 保留编码 `2'b11` 非法。 |
| `AxSIZE` | 0/1/2 | 分别表示 1/2/4 byte；不超过 32-bit 数据总线。 |
| `AxLEN` | 0 至 `MAX_BURST_BEATS-1` | 真正 beat 数为 `AxLEN+1`；FIXED 另限不超过 16 beat。 |
| 地址对齐 | 必须满足 `AxADDR % (2**AxSIZE) == 0` | v0.1 不处理 unaligned access。 |
| WRAP 长度 | 2/4/8/16 beat | 其他长度非法。 |
| WLAST | 仅在预期最后一个 W beat 为 1 | 早到、晚到或缺失均是协议错误。 |

所有请求必须位于一个 4KB 地址区间。INCR 检查 `start + beats*bytes_per_beat - 1`；FIXED 只检查一个传输的字节范围；WRAP 检查其自然对齐的 wrap block，不能把块末尾起始的合法 WRAP 当作线性 INCR 错误拒绝。超出 32 位地址范围也返回 DECERR。

### 3.3 WSTRB 约束

本版本支持由 `AxSIZE` 和当前地址决定的**连续且对齐** byte mask。例如 32-bit 总线上的 1-byte 写地址 `0x...02`，合法 WSTRB 是 `4'b0100`；2-byte 写地址 `0x...02`，合法 WSTRB 是 `4'b1100`。任意稀疏或部分 byte-enable 不可由基础 AHB 写直接表达，因此 v0.1 判为不支持请求；后续增强版若要支持，必须加入 read-modify-write（RMW）设计和相应原子性说明。

## 4. 合法性、流控与排序

### 4.1 输入接收

- 传输在相关通道的 `VALID && READY` 同时为 1 的时钟沿发生。
- 当 `VALID=1 && READY=0`，发送方必须保持 VALID 与所有 payload 稳定；bridge 以 assertion 检查该规则。
- `AWREADY` 在命令 FIFO 有空间时拉高。合法写 burst 必须能够完整缓冲；超过 `MAX_BURST_BEATS` 或 FIFO 容量的写描述符被接收后立即进入 reject-and-drain：bridge 继续接收并丢弃该笔 W 数据，最后返回一次 `DECERR`，从而不因无法整体装入 FIFO 而死锁。
- `WREADY` 在写数据 FIFO 有空间时拉高；W 数据可早于对应 AW 缓冲。
- `ARREADY` 在命令 FIFO 有空间且请求字段合法（或能被接收后返回 DECERR）时拉高。

### 4.2 排序规则

bridge 使用单一命令 FIFO 保持**已被接收命令的全局到达顺序**。只有命令 FIFO 的头部命令具备执行条件时才可调度：读命令立即具备条件，写命令需要其完整的 `AWLEN+1` 个 W beat 已缓冲且 WLAST 正确。这样 AXI 同一 ID 的顺序天然保留；不同 ID 也采用更保守的全局顺序，不实施读写重排序或响应交织优化。

当头部写命令尚未收齐 W 数据时，后续读命令不会越过它执行。该取舍降低学习版复杂度；上游若不继续发送该写 burst 的 W 数据会主动造成阻塞，属于上游违反进度假设。

### 4.3 输出背压

- 断言 `BVALID` 后，在 `BREADY` 到来前保持 `BID/BRESP/BVALID` 稳定。
- 断言 `RVALID` 后，在 `RREADY` 到来前保持 `RID/RDATA/RRESP/RLAST/RVALID` 稳定。
- AHB 后端在输出响应被背压时不启动下一命令，以便保持最小状态空间和严格全局完成顺序。

## 5. 地址与 burst 映射

令 `beats = AxLEN + 1`，`step = 2**AxSIZE`。

| AXI 类型 | 当前 beat 地址 | AHB5-Lite 映射策略 |
|---|---|---|
| FIXED | `addr[k] = start_addr` | 每个 beat 作为独立 `SINGLE + NONSEQ` 访问，避免把固定地址误表示为 AHB 递增 burst。 |
| INCR | `addr[k] = start_addr + k*step` | 每个 beat 独立 `SINGLE + NONSEQ`，不把 AXI burst 长度直接当作 AHB burst。 |
| WRAP | 在 `wrap_size=beats*step` 块内递增，到上界后回到下界 | 每个 beat 独立 `SINGLE + NONSEQ`，保持 AXI wrap 地址序列。 |

这是明确的吞吐量取舍：当前后端不输出 AHB SEQ/BUSY 或多拍 HBURST，也不重叠两笔 AHB 传输。旧版的 IDLE 气泡后继续 SEQ 以及同拍地址/数据模型不再属于本版契约。

WRAP 地址计算如下：

```text
lower_boundary = floor(start_addr / wrap_size) * wrap_size
upper_boundary = lower_boundary + wrap_size
next_linear    = curr_addr + step
next_addr      = (next_linear == upper_boundary) ? lower_boundary : next_linear
```

`tools/reference_model.py` 是这段规则的可执行版本。RTL、UVM 和文档中的任何例子都必须与其测试用例一致。

## 6. AHB5-Lite 侧行为

基础 AHB5-Lite 信号使用 `HADDR/HWRITE/HSIZE/HBURST/HPROT/HTRANS/HWDATA`，从属端返回 `HREADY/HRESP/HRDATA`。AHB5 可选 sideband（如安全、排他、user）在 v0.1 中不参与状态机：若端口存在，使用可配置的静态默认值；不实现排他访问。

### 6.1 单个 AHB beat

1. 后端从已准备命令装载当前 beat 的地址、方向、大小、数据与 burst 控制。
2. 在地址相位发出 `HTRANS=NONSEQ, HBURST=SINGLE`，在 `HREADY=1` 的边沿接受地址；该边沿不采样本笔读数据、不消费 W FIFO。
3. 进入后继数据相位，`HTRANS=IDLE` 表示不发下一地址；若 `HREADY=0`，保持当前写数据和控制。ERROR 首周期 `HRESP=1,HREADY=0`，次周期 `HRESP=1,HREADY=1`。
4. 只在数据相位的 `HREADY=1` 边沿采样 `HRESP/HRDATA` 或消费本笔 W 数据。
5. `HRESP=OKAY` 则推进 beat 计数；`HRESP=ERROR` 则执行第 7 节的错误策略。

### 6.2 窄传输数据对齐

AHB `HSIZE` 与 `AxSIZE` 相同。写数据必须放在由地址低位选中的 `HWDATA` byte lane；读数据由相同 lane 提取、其余 AXI RDATA byte 填零。32-bit 总线举例：地址低两位为 `2'b10` 的 byte 写使用 `HWDATA[23:16]`；读回时该 lane 数据放回 AXI RDATA 的对应 lane。

## 7. 错误处理策略

| 错误来源 | 对 AHB 的影响 | AXI 可见结果 |
|---|---|---|
| 非法 burst / size / alignment / WSTRB / WLAST | 不发起该命令的 AHB 访问。 | 读：产生规定 beat 数的 `RRESP=DECERR`、`RDATA=0`；写：消费该 burst W 数据后产生一次 `BRESP=DECERR`。 |
| AHB `HRESP=ERROR`（读） | 停止后续真实 AHB 访问。 | 当前及剩余读 beat 均返回 `SLVERR`；当前/剩余 RDATA 为 0；最后一个仍置 RLAST。 |
| AHB `HRESP=ERROR`（写） | 停止后续真实 AHB 写。 | 消费并丢弃本 burst 剩余已收/待收 W beat；最后产生一次 `BRESP=SLVERR`。已成功发出的早期 beat 不回滚。 |
| 复位中断 | 清空内部状态。 | 所有未完成传输取消；复位后不补发 B/R。 |

选择“读错误后仍发送剩余 R beat”的原因是保持 AXI burst 的 beat 数和 RLAST 规则可预测。选择“写错误后继续消费 W”的原因是避免上游仍在发送该 burst 数据时发生协议死锁。

合法描述符的整笔写数据收齐后，用独立预检状态逐项检查所有 WSTRB/WLAST，预检期间不 pop；任何一项非法都从首项 drain，整笔不发 AHB。非法描述符仍走流式 drain，避免超容量 burst 等待完整缓冲而死锁。若发送方实际不再提供描述符要求的 W beat，本版本不提供超时补偿。

## 8. 微架构与状态机约束

建议的 RTL 组成：命令 FIFO、W data FIFO、写 burst 完整性跟踪、地址生成器、AHB 执行 FSM、AXI 响应寄存器/FIFO、可选的读数据暂存器。后端每个时刻只拥有一个 active command 和一个 active beat。

实际 FSM 为 `IDLE -> VALIDATE_CMD -> VALIDATE_WRITE（仅写）-> PREPARE_BEAT -> AHB_ADDRESS -> AHB_WAIT（数据相位）-> READ_RESPONSE/WRITE_RESPONSE`，非法写进入 `INVALID_WRITE_DRAIN`。数据相位完成后才能推进 beat；下一 beat 重新发独立 NONSEQ 地址。

## 9. 不变量（RTL assertion 的来源）

1. FIFO count 始终处于 `[0, FIFO_DEPTH]`，且不允许 pop 空 FIFO / push 满 FIFO。
2. `HREADY=0` 时 active beat 的 AHB 控制和写数据稳定。
3. AXI 所有通道在 `VALID && !READY` 时 payload 稳定。
4. 一笔合法 N-beat 读恰好产生 N 个 R；仅第 N 个 R 的 RLAST 为 1。
5. 一笔写命令恰好产生一个 B，BID 等于 AWID。
6. 每个 AHB OKAY beat 的地址等于同一命令同一 beat 的地址参考值。
7. RESET 后不存在陈旧的 BVALID/RVALID 或 FIFO valid。

## 10. 未支持项与后续版本

v0.1 不支持 64-bit/128-bit 数据宽度、unaligned access、任意稀疏 WSTRB、排他访问、多个时钟域、读写重排序、AXI cache/QoS 语义、完整 AXI4 256-beat burst（当它超过 `MAX_BURST_BEATS` 时）。任何扩大支持范围的改动必须同时更新：本规格、reference model、verification plan、coverage model 和 test matrix。
