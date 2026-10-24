# UVM 执行与覆盖率闭环说明

`uvm/` 提供 UVM 1.2 迁移的基础环境：APB active agent、APB monitor、SPI 被动 monitor、由 APB 可见配置推导期望的 scoreboard，以及 SPI mode/位序/帧宽/divider/连续帧 covergroup。UVM 源码的存在不等于已在商业仿真器执行。

当前机器的 Icarus + cocotb 路径已实际执行；它不适合作为 UVM/covergroup/SVA/assertion coverage 的证据。取得学校或公司的合法 VCS、Xcelium、Questa 或同等授权后，应先确认 UVM_HOME，再从项目根目录调用相应 simulator，例如 VCS 概念命令：

```bash
vcs -sverilog -ntb_opts uvm -f uvm/files.f -top tb_top_uvm -o build/uvm/simv
build/uvm/simv +UVM_TESTNAME=apb3_spi_base_test -cm line+cond+tgl+branch+fsm+assert
```

实际迁移前还需要补齐两项：SPI slave responder sequence（按每帧 response 驱动 MISO）和 virtual test（驱动 `spi_program_frame_seq` 后等待 DONE/RX）。这两个测试层会把现有 cocotb 的模式、连续 CS、IRQ、OVERRUN、ABORT 和随机 frame 集合完整搬到 UVM，随后把每次 run 的真实 coverage database 合并。不要在这些工作真正完成前声称 UVM 回归通过或 100% commercial coverage。
