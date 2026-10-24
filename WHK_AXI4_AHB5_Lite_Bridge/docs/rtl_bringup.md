# RTL Bring-up 指南：第一条可验证链路

## 本阶段目标

先不用 UVM，跑通一个最小端到端路径：AXI 写 -> bridge -> AHB memory model -> AXI 读回。这样能先证明 FIFO、地址对齐、AHB wait 状态机和 AXI B/R 响应的基础骨架不是空的。

## 已实现模块

| 文件 | 初学者应重点阅读 | 职责 |
|---|---|---|
| `rtl/axi4_ahb5_lite_bridge_pkg.sv` | 协议编码常量 | AXI RESP/BURST 与 AHB HTRANS/HBURST 名称。 |
| `rtl/axi4_ahb5_lite_bridge.sv` | `ST_*` 状态机、`cmd_mem`、`wdata_mem`、三个 function | 可参数化 bridge RTL。 |
| `rtl/axi4_ahb5_lite_bridge_assert.sv` | `ap_*` 属性 | AXI 背压稳定性、AHB 等待稳定性、复位后无陈旧响应。 |
| `tb/ahb5_lite_memory_model.sv` | `always_ff` 写入逻辑 | 零等待、OKAY 响应的 AHB 从属存储模型。 |
| `tb/tb_top_smoke.sv` | `send_aw/send_w/send_ar/wait_*` task | 定向非 UVM smoke test 和 VCD 波形导出。 |

## 当前 FSM

```text
IDLE -> VALIDATE_CMD -> PREPARE_BEAT -> AHB_WAIT -> READ_RESPONSE -> IDLE
                                           |             ^
                                           |             |
                                           +-> WRITE_RESPONSE -> IDLE

非法写：VALIDATE_CMD/PREPARE_BEAT -> INVALID_WRITE_DRAIN -> WRITE_RESPONSE
```

- `IDLE`：只从命令 FIFO 头部取事务；写命令必须已经缓存完整个 burst 的 W beat。
- `VALIDATE_CMD`：处理非法 LEN/SIZE/BURST/alignment，读请求直接准备 DECERR，写请求进入 drain。
- `PREPARE_BEAT`：在驱动 AHB 前检查当前 WSTRB 和 WLAST，因此非法写不会在 AHB 上留下半笔访问。
- `AHB_WAIT`：有效 HTRANS 保持到 HREADY=1；AHB ERROR 被映射为 AXI SLVERR。
- `READ_RESPONSE` / `WRITE_RESPONSE`：应对 AXI 的 RREADY/BREADY 背压。

## 虚拟机运行步骤

1. 将 `WHK_AXI4_AHB5_Lite_Bridge` 目录放到 Linux 虚拟机可写路径。
2. 确认可执行文件：`which vcs` 和 `which verdi`；若找不到，记录实际路径。
3. 在项目根目录执行 `VCS_BIN=/实际/vcs路径 scripts/run_smoke_vcs.sh`。
4. 查看 `build/smoke/compile.log`。若编译失败，保留完整日志，不要先改代码。
5. 编译成功后检查 `build/smoke/simulate.log` 含有 `SMOKE_TEST_PASS`。
6. 执行 `VERDI_BIN=/实际/verdi路径 scripts/open_smoke_verdi.sh`，在 Verdi 打开 `smoke.vcd`。

## Verdi 首次看波形的信号顺序

1. `clk`、`rst_n`：确认三拍复位后正常释放。
2. `s_aw*`、`s_w*`、`s_b*`：确认写地址、写数据和写响应各有一次 VALID/READY 握手。
3. `s_ar*`、`s_r*`：确认读地址和读数据握手。
4. `haddr/hwrite/hsize/htrans/hready/hresp/hwdata/hrdata`：确认每个 AXI beat 对应一个 AHB 有效传输。
5. `dut.state_q`、`dut.cmd_count_q`、`dut.wdata_count_q`、`dut.active_beat_q`：用于解释 bridge 内部为何停在某个状态。

## 通过标准与下一阶段

这一步通过的唯一标准是：VCS 编译无错误、仿真日志有 `SMOKE_TEST_PASS`、Verdi 波形与 `tb_top_smoke.sv` 两次写/读的预期一致。它不代表 burst/UVM/coverage 已验证；通过后才依次扩展 INCR/WRAP/FIXED、HREADY wait、HRESP ERROR、FIFO 压力和 UVM 平台。
