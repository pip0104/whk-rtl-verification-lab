# 可复现回归报告

> 2026-10-24 更新：本文以下为旧 RTL 历史记录。当前修复版的实际回归及主/自检 XML 路径见 [20261024_bridge_fix.md](20261024_bridge_fix.md)。不要将旧 10,525 ns 或旧 smoke 代码覆盖数字用于当前 RTL。

## 结论

2026-09-08 在 Windows 本机的免费合法工具链上，项目完整回归通过。该回归覆盖 RTL 编译、基础 smoke、参数展开、Python 参考模型和事务级 AXI/AHB 端到端验证。

执行入口：

```powershell
cd 'C:\Users\Pip\Documents\总线验证\AXI4_AHB5_Lite_Bridge'
.\scripts\run_full_regression.ps1
```

完整终端记录会写入 `results/full_regression.log`；JUnit 结果为 `tests/cocotb/results.xml`；功能覆盖原始数据为 `results/functional_coverage.json`。独立的 Verilator 代码覆盖基线见 `docs/code_coverage_report.md`。

## 实际通过项

| 项目 | 实际结果 |
|---|---|
| Reference model | 11/11 Python 单元测试通过 |
| Icarus RTL smoke | PASS：32-bit 单拍与 8-bit 窄传输 |
| 参数展开 | PASS：FIFO 8、16、32、64、128 |
| cocotb 主回归 | PASS：1/1，10,525 ns |
| 功能 bin | 36/36 必达 bin 命中，644 次事务级采样 |
| Verilator 代码覆盖 smoke | PASS；DUT line 73.9%、toggle 38.3%、branch 59.4%、expr 67.6% |
| 波形 | smoke VCD：`build/iverilog_smoke/smoke.vcd` |

主回归的固定随机 seed 位于 `test_bridge_regression.py`，因此随机混合流量可复现。

## 验证内容

- AXI `FIXED`、`INCR`、`WRAP`，包括 WRAP2/4/8/16 与 INCR16。
- 1/2/4 byte 的窄传输、所有合法 32-bit byte lane。
- AHB `HREADY` 0/1/2-3/4+ wait；wait 期间 AHB 控制/写数据稳定。
- AHB read/write ERROR，及 AXI `SLVERR`、`DECERR` 映射。
- AXI B/R 背压、W 早于 AW、未收齐 W 时读请求不可超越写请求。
- FIFO 满压、恢复和复位在六个外部可见阶段的清理。

## 限制

代码覆盖基线来自免费 Verilator 对 smoke 场景的一次实际运行，并非完整 cocotb 回归，因此不能将其外推为项目覆盖率闭环。当前不含 condition、有效 FSM 或 SVA assertion coverage，也不含商业工具 URG 合并报告。详情和需求证据见 `docs/verification_tracker.md` 与 `docs/code_coverage_report.md`。
