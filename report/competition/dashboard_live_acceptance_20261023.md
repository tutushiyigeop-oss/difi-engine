# DIFI Dashboard：B5 / B6 实机联调阶段确认（2026-10-23）

> 记录类型：开发者本人实机测试结果的后续确认（E3 级别需依赖原始运行产物时，请按原始证据实际可用情况引用）。本文件为事后状态说明，不是模拟生成的串口/网络日志，也不假定这些截图或日志已经公开入库。

## 确认结果

2026-10-23，开发者明确表示 **DIFI ENGINE CONTROL CENTER 中的 B5 UDP TX 与 B6 UDP RX 两种 Live / Hardware 模式均在实体 Zynq 开发板上成功运行，界面可以正常使用**。因此将“Dashboard 与现有 B5/B6 固定验证流程的实机集成”判定为**本阶段完成**。

| 项目 | 本阶段结论 | 证据层次 |
|---|---|---|
| Dashboard 原生 Windows GUI + Replay | Codex 本机测试记录有 101 tests PASS、原生 Qt 冒烟 PASS | `dashboard/VALIDATION.md` 中原始交付记录 |
| Dashboard → B5 UDP TX 真实板级联调 | 开发者确认运行成功 | 开发者后续确认，不以 Replay 冒充 |
| Dashboard → B6 UDP RX 真实板级联调 | 开发者确认运行成功 | 开发者后续确认，不以 Replay 冒充 |
| Dashboard 并发全双工 UDP | **不在本阶段支持范围** | B5/B6 是不同 XSA/Bitstream 与 Vitis 程序 |
| 任意自定义 IQ / Packet 构造并由板端处理返回 | **不在当前 Dashboard 功能范围** | 目前 Live 沿用固定的 B5/B6 CLI 验证流程 |

## 证据与展示边界

- B5：原脚本 `scripts/verify/tools/difi_udp_receiver.py` 通过 UDP 接收并验证完整 Packet 和 IQ；UI 可从验证过的捕获文件显示 PC 真正收到的 IQ。
- B6：原脚本 `scripts/verify/tools/difi_b6_three_types.py` 以板卡 STATUS 和 ACK 作为确认依据；B6 GUI 波形是明确标注的 **Golden Reference**，不是从 FPGA 经 UDP 返回的完整 IQ。
- 此次开发者报告的是**两种 Live 模式均成功运行**。未另行逐项报告连续多次 Stop/Restart、各种故障恢复、任意运行时长或特定屏幕分辨率的实测结果，不据此宣称这些场景全部 PASS。
- 独立 Vivado 工程复现和原始 B5/B6 固定测试已经另有工程证据；本文件只补记新增 **GUI 与实体硬件的联调结果**，不重新要求补交已明确不作为本阶段验收条件的额外文件。
- 正式比赛现场应重新录像并保留画面素材，确保能明确分辨 `LIVE / HARDWARE` 和 `REPLAY / OFFLINE`，且不把两块不同硬件配置称为同一 XSA 的同时全双工。

## 后续方向 A：作品展示与交付

1. 以 `report/competition/demo_plan.md` 为执行依据，先拍 B5 Live 和 B6 Live 的真实画面，再补工程架构、RTL 数据与第三方工具静态素材。
2. 录制状态和画面素材完成之后，再按实际镜头调整 `report/competition/demo_narration.md` 的口播。
3. 设计报告与四套 Skill 的统一验收是**独立交付事项**；不要把 Dashboard 通过等价成 Skill 全部验收成功。
4. 正式许可证、公开仓库、Tag 和比赛平台提交仍须独立审核，当前不自动进行。
