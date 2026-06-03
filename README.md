<p align="center">
  <img src="doc/maestro-icon.png" width="128" alt="Maestro">
</p>

<h1 align="center">Maestro</h1>

<p align="center">
  并行编排多个 AI 编码 agent 的原生 macOS 终端。
</p>

<p align="center">
  中文 · <a href="README.en.md">English</a>
</p>

---

Maestro 是 [Prowl](https://github.com/onevcat/Prowl) 的个人 fork（Prowl 本身 fork 自 [Supacode](https://github.com/supabitapp/supacode)），平时主要满足我自己的需求，在此基础上持续做自己的定制。基于 [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) 和 [libghostty](https://github.com/ghostty-org/ghostty) 构建。

> 功能简介待补充。

## 安装

暂无预编译下载，请从源码构建（见下方「开发与构建」）。要求 macOS 26.0+。

## 开发与构建

需要 [mise](https://mise.jdx.dev/) 提供 zig / swiftlint 等工具链。

```bash
make build-ghostty-xcframework   # 从 Zig 源码构建 GhosttyKit
make build-app                   # 构建 macOS app（Debug）
make run-app                     # 构建、启动并流式查看日志
make install-dev-build           # 构建 Debug 并安装到 /Applications
make install-release             # 构建 Release，本地签名并安装到 /Applications
```

```bash
make check                       # 格式化改动文件 + swift-format lint + SwiftLint
make test                        # 运行单元测试
make build-cli                   # 构建 maestro CLI
```

## 致谢

站在 [Prowl](https://github.com/onevcat/Prowl) 与 [Supacode](https://github.com/supabitapp/supacode) 的肩膀上。

## License

[FSL-1.1-ALv2](LICENSE)
