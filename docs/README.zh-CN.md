# miaotty 文档

[English](README.md) · [中文](README.zh-CN.md)

项目文档以英文撰写、中文镜像；本目录下的每篇文档顶部都链接到其对应版本。

| 文档 | 内容 |
|---|---|
| [**架构**](ARCHITECTURE.zh-CN.md) · [English](ARCHITECTURE.md) | **耐久决策与已实现的内容**：加法式 Ghostty fork、MTP 契约、性能纪律，以及 fork 如何接线（构建、app 集成、身份、侧面板） |
| [Overlay](../miaotty/overlay/README.md) | 施加到 Ghostty checkout 的受版本管理 patch 系列，以及 Xcode 26 / macOS 26 的构建 quirk |
| [README](../README.zh-CN.md) · [English](../README.md) | 一页纸介绍与快速开始 |

## 阅读顺序

初来者：先读 [README](../README.zh-CN.md) 看一页纸介绍，再读
[架构](ARCHITECTURE.zh-CN.md) 了解各部件如何拼合。要复现 app 构建，从
[Overlay](../miaotty/overlay/README.md) 开始。

## 文档状态

| 文档 | 描述的是 |
|---|---|
| 架构 | fork 中的**设计决策与已实现内容** |
| Overlay | **向 Ghostty checkout 打了什么 patch**，以及为什么 |
