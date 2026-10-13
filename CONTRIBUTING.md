# Contributing · 参与贡献

Thanks for your interest in Formulens! · 感谢你对 Formulens 的关注！

## Ways to help · 参与方式

- **Bug reports and ideas**: open an [issue](../../issues) using the templates. · 通过 Issue 模板报告问题或提出建议
- **Windows / Linux versions**: the biggest open items on the [roadmap](README.md#roadmap). Please open an issue to discuss the approach before starting. · Windows / Linux 版本是路线图中最主要的工作，开始前请先开 Issue 讨论方案
- **Translations**: add a `<language>.lproj/Localizable.strings` under `macapp/Resources/`. · 在 `macapp/Resources/` 下新增翻译文件

## Development · 开发

See "Build from source" in the [README](README.md#build-from-source-macos). · 构建方法见 README「从源码构建」。

Before opening a pull request · 提交 Pull Request 前请：

1. Keep UI strings in English inside `L("...")` and add Chinese translations, then run `macapp/tools/check_l10n.sh` · 界面文字用 `L("...")` 写英文并补充中文翻译，运行检查脚本
2. Make sure `macapp/build.sh` succeeds · 确认 `macapp/build.sh` 编译通过
3. Never commit models, build outputs, screenshots of personal content or keys (see `.gitignore`) · 不要提交模型、构建产物、个人截图或密钥
4. Describe what you changed and how you tested it · 说明改了什么、如何测试

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
提交贡献即表示你同意以 MIT 许可证发布你的贡献。
