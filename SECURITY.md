# Security Policy · 安全策略

## Reporting a vulnerability · 报告漏洞

Please **do not** open a public issue for security problems.
Report them privately via GitHub: go to the **Security** tab of this repository and click **Report a vulnerability**.
Include the Formulens version, your macOS version, and steps to reproduce.

请**不要**通过公开的 Issue 报告安全问题。
请在本仓库的 **Security** 页面点击 **Report a vulnerability** 私下提交，并附上 Formulens 版本、macOS 版本和复现步骤。

## Supported versions · 支持的版本

Only the latest release receives security fixes. · 只有最新版本会获得安全修复。

## Scope · 范围

Formulens runs entirely on your machine. Its local inference service listens only on `127.0.0.1`
and requires a random access key. See "Privacy & security" in the [README](README.md) for the design.

Formulens 完全在本机运行，本地推理服务只监听 `127.0.0.1` 并要求随机访问密钥。
设计说明见 [README](README.zh-CN.md) 的「隐私与安全」一节。
