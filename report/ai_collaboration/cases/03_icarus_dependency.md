# C03 — VS Code / Icarus 仿真中 include 与源码编译依赖混淆

**状态：** 部分原始用户日志与反馈可恢复；完整 E1 待导出。

## 问题链

2026-10-11 的 `tb_difi_data_parser.v` 一键仿真首先报告：

```text
Include file difi_v1_1_defs.vh not found
```

增加 `-I` 搜索目录后，头文件问题解决；此时下一轮错误可恢复为：

```text
Unknown module type: difi_data_parser
```

说明 testbench 源码已经被编译器读取，但待实例化的 RTL 模块未成为编译输入。`-I` 仅影响 `` `include`` 搜索，不等于自动收集 `.v` 源文件。

## AI 协作要点（不是完整对话原文）

- 先增加头文件搜索路径，例如 `rtl/include`。
- 根据新的错误识别缺少 `rtl/data/difi_data_parser.v` 的编译文件输入，而不是继续增加 `-I`。
- 用户随后反馈仅增加该模块 `.v` 路径便可仿真。

真实项目配置位于 `D:\Study\project\DIFI\.vscode\property.json`；上方路径用于描述当时环境，移植到其他电脑应使用相对路径而非固定硬盘绝对路径。

## 可核查的代码

- `sim/data/tb_difi_data_parser.v`
- `rtl/data/difi_data_parser.v`
- `rtl/include/difi_v1_1_defs.vh`

## Skill 提炼

分三层排错：**找不到头文件**→检查 `-I`；**找不到模块定义**→检查文件列表/编译顺序；**无法 elaboration**→检查顶层模块 `-s`、参数和语言标准。不同错误不能被一句“配置 include”笼统解决。关联 `axis-rtl-verification`。

## 待补

- [ ] 原始 VS Code / Icarus 两轮完整日志、property.json 前后 Diff。
- [ ] 初版 AI 建议、用户纠错反馈、第二版建议的逐字导出。
- [ ] 最后成功仿真日志及其对应时间。
