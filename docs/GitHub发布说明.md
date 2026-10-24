# GitHub 发布说明

目标账号：`pip0104`。

仓库：[whk-rtl-verification-lab](https://github.com/pip0104/whk-rtl-verification-lab)。[实际云端验证记录](https://github.com/pip0104/whk-rtl-verification-lab/actions)。

发布内容是本地已验收的源码、测试、限定范围形式验证与精简红绿证据；虚拟环境和构建缓存未上传。本机原开发仓库与原始 ZIP 保留。

2026-10-24 后续补充了当前修复版 RTL 的 FPGA 实现报告与冻结日志：`evidence/fpga/20261024/`。[报告、结果边界和复现命令](20261024_fpga_implementation.md)。SPI 的内部 50 MHz 目标、桥接器内部 25 MHz 目标在 Windows 本地通过；100 MHz 失败记录同时保留。该 FPGA 结果是本地执行记录，与 Actions 的仿真/形式验证结果分开，不代表已运行 FPGA 云端流程、板级 I/O 时序闭合或实物上板。

本公开仓库从已验收快照起始，使用 GitHub noreply 提交邮箱。冻结证据中的历史 commit 标识来自保留的本地开发仓库；旧 RTL 源文件随仓库携带，重现反例不依赖那些本地 commit。

本地 PASS 与 GitHub Actions 的托管结果分别记录，云端结果以实际工作流为准。本仓库属于个人可复现项目展示，不是上游开源 CPU 的贡献记录。


完整仿真与限定范围形式验证已在 Ubuntu 22.04 云端通过：[实际通过记录](https://github.com/pip0104/whk-rtl-verification-lab/actions/runs/40084460034)。

原仓库名在两个其他账号下完全重名，现已改为 `whk-rtl-verification-lab`；本次公开搜索未发现新名的完全同名仓库。
