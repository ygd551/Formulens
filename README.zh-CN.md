# Formulens · 公式镜

[English](README.md) | **简体中文**

**完全离线**的截图转 LaTeX / Markdown 工具。
按下快捷键框选屏幕上的公式、文字或表格，几秒内得到可以直接粘贴的 LaTeX 或 Markdown。

识别由 [PaddleOCR-VL-1.6](https://www.modelscope.cn/models/PaddlePaddle/PaddleOCR-VL-1.6) 模型在本机完成，截图不会上传到任何服务器。

## 平台支持

| 平台 | 状态 | 推理后端 |
|---|---|---|
| macOS（Apple Silicon） | ✅ 已发布 v1.0.0 | [MLX](https://github.com/ml-explore/mlx)，在 Apple GPU 上运行 |
| Windows | 🚧 计划中 | 待定（NVIDIA GPU / CPU） |
| Linux | 🚧 计划中 | 待定（NVIDIA GPU / CPU） |

开发计划见下方[路线图](#路线图)。

## 功能（macOS 版）

- **⌃⌘M** 框选截图，识别后自动复制到剪贴板
- 自动判断内容类型：单个公式 → LaTeX；文字与行内公式混排 → Markdown（`$...$`）；表格 → Markdown 表格
- 结果窗口：原图、公式渲染预览、可编辑的 LaTeX / Markdown 源码、历史记录
- 支持 ⌘V 粘贴图片、拖入图片，以及按指定模式重新识别
- 界面支持简体中文和英文：默认跟随系统语言，也可以在菜单栏 ∑ →「语言 / Language」或窗口左上角的 🌐 中切换
- 速度（M4 实测）：单个公式约 1–2 秒，一段文字公式混排约 2 秒

## 系统要求（macOS 版）

- Apple Silicon（M1 及以后）的 Mac，不支持 Intel 芯片
- macOS 14 或更新版本
- 约 3GB 可用磁盘空间；运行时约占 2.1GB 内存（建议 16GB 内存，8GB 可以运行）

## 安装（macOS）

1. 从 [Releases](../../releases) 下载 `Formulens-<版本>.dmg` 和对应的 `.sha256` 文件
2. **校验安装包**（建议）：
   ```bash
   shasum -a 256 -c Formulens-1.0.0.dmg.sha256
   ```
   输出 `OK` 才说明文件完整、未被篡改。请只从本仓库的 Releases 下载。
3. 双击 DMG，把 **Formulens** 拖进「应用程序」
4. 首次打开：本应用没有经过 Apple 公证，系统会提示无法验证开发者。
   打开 系统设置 → 隐私与安全性，在页面底部点「仍要打开」。
   如果应用能打开但一直显示「模型启动失败」，在终端运行一次下面的命令，然后重新打开：
   ```bash
   xattr -dr com.apple.quarantine "/Applications/Formulens.app"
   ```
5. 首次截图时授权：系统设置 → 隐私与安全性 → **录屏与系统录音** → 打开 Formulens，然后在菜单栏 ∑ 中选择「重新启动 Formulens」

## 使用（macOS）

| 操作 | 说明 |
|---|---|
| ⌃⌘M | 框选截图并识别，Esc 取消 |
| ⌘V / 拖入图片 | 在结果窗口中识别剪贴板或文件中的图片 |
| ⇧⌘C | 复制当前显示的 LaTeX / Markdown |
| 菜单栏 ∑ | 识别模式、复制格式、登录时自动启动、重新启动、退出 |

菜单栏图标显示 `∑·` 表示模型正在加载，显示 `∑…` 表示正在识别。

## 隐私与安全

- **完全离线**：截图只在本机识别。推理服务开启了离线模式，不会联网下载任何内容。
- **录屏权限**：只在你按下快捷键时调用系统截图工具 `screencapture` 截取你框选的区域，不会在后台录屏。
- **本机推理服务受保护**：
  - 后台推理服务（mlx-vlm）只监听 `127.0.0.1`，外部网络无法访问
  - 每次请求都必须带上随机访问密钥。密钥在首次启动时生成，保存在 `~/Library/Application Support/Formulens/server.key`，仅当前用户可读
  - 浏览器里的网页和本机其他程序拿不到这个密钥，无法调用推理服务
  - 连接前会确认端口上的服务「必须带本应用密钥才能访问」，不会把截图发给碰巧占用该端口的其他程序
  - 模型自带的 Python 代码不会被执行（`trust_remote_code` 关闭）
  - 应用退出（包括崩溃、强制退出）后，推理服务会自动退出，不会残留在后台占用内存
- **识别结果预览**：截图内容可能是任意文字，因此预览页禁止加载任何网络资源、禁止跳转，并关闭了 KaTeX 的链接等命令（`trust: false`）
- **图片大小限制**：超过 50MB 或 1 亿像素的图片会在解码前被拒绝，防止恶意构造的图片耗尽内存
- **数据位置**：识别历史和日志保存在 `~/Library/Application Support/Formulens/`，只有当前用户可以访问；删除这个文件夹即可清除。
- **可校验的构建**：模型、Python 运行环境和全部 Python 依赖在下载后都会校验 SHA-256，任何文件被替换都会导致构建失败。
- 发现安全问题请按照 [SECURITY.md](SECURITY.md) 私下报告（仓库 Security 页面 → Report a vulnerability），不要在公开的 Issue 中披露。

## 卸载（macOS）

退出应用 → 删除「应用程序」中的 Formulens → 删除 `~/Library/Application Support/Formulens`。

---

## 路线图

### ✅ 已完成

- [x] macOS 原生应用（Swift / SwiftUI）：菜单栏常驻、全局快捷键截图、结果窗口、历史记录
- [x] 识别模式：自动 / 公式 / 文本与行内公式 / 表格
- [x] 输出 LaTeX 与 Markdown，应用内用 KaTeX 离线渲染预览
- [x] 本地推理：PaddleOCR-VL-1.6 通过 MLX 在 Apple GPU 上运行
- [x] 推理服务安全加固：只监听本机，并要求随机访问密钥
- [x] 简体中文 / 英文界面，可在应用内切换
- [x] 独立安装包（DMG）：内置 Python 运行环境和模型，不依赖任何外部环境
- [x] 可复现构建：依赖版本锁定，模型和运行环境下载后校验 SHA-256
- [x] 命令行识别工具

### 🚧 未完成

**跨平台**

- [ ] 把识别逻辑（提示词、自动模式判断、表格转换、格式整理）抽成各平台共用的核心模块
- [ ] Windows 版：截图与全局快捷键、托盘图标、安装程序
- [ ] Linux 版：X11 / Wayland 截图、托盘图标、打包发布
- [ ] Windows / Linux 的推理后端：评估 NVIDIA GPU 和纯 CPU 方案（如 vLLM、Transformers、llama.cpp）
- [ ] 跨平台界面方案选型（如 Tauri、Qt，或各平台分别使用原生界面）

**macOS 版**

- [ ] 自定义全局快捷键
- [ ] 空闲时自动卸载模型，释放内存
- [ ] 整页文档 / PDF 解析（版面分析、多栏阅读顺序）
- [ ] Apple 开发者签名与公证，安装时不再需要手动「仍要打开」
- [ ] 应用内检查更新
- [ ] 在 macOS 14 / 15 和 8GB 内存机型上验证兼容性

**识别与体验**

- [ ] 手写公式的识别效果评估与优化
- [ ] 更多输出格式：MathML、Word 公式、纯文本
- [ ] 更多界面语言
- [ ] 历史记录搜索

欢迎通过 Issues 提出建议，或通过 Pull Request 参与开发，尤其是 Windows 和 Linux 版本。参与方式见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 从源码构建（macOS）

需要 Xcode 命令行工具（`xcode-select --install`），不需要完整的 Xcode。

```bash
# 1. 下载模型（约 1.9GB，来自 ModelScope，逐个文件校验 SHA-256）
./download_model.sh

# 2. 准备打包用的独立 Python 运行环境（约 650MB；依赖按 macapp/runtime-requirements.lock 安装并校验 SHA-256）
macapp/setup_runtime.sh

# 3. 生成安装包 macapp/dist/Formulens-<版本>.dmg 及其 .sha256
macapp/package.sh
```

可选：运行 `macapp/make_cert.sh`，在钥匙串中创建本机代码签名证书。用它签名后，重新编译时不需要重新授权录屏权限。没有证书时使用 ad-hoc 签名。

### 项目结构

```
macapp/Sources/                  应用源码（Swift / SwiftUI）
  main.swift                     菜单栏、全局快捷键、截图、窗口
  AppModel.swift                 应用状态、识别流程、历史记录
  Recognizer.swift               调用推理服务，把输出整理成 LaTeX / Markdown；图片大小检查
  Services.swift                 推理服务的启动、访问密钥与端口选择、历史记录存储
  Views.swift                    结果窗口界面
  Localization.swift             界面语言（跟随系统或手动选择）
macapp/Resources/                公式预览页、KaTeX、界面翻译（en.lproj / zh-Hans.lproj）
macapp/tools/check_l10n.sh       检查每条界面文字都有中文翻译
macapp/build.sh                  只编译应用本体
macapp/install.sh                开发版安装：使用本仓库的 models/ 和 Python 环境
macapp/package.sh                生成独立安装包（检查翻译与最低系统版本、清除本机路径、签名、生成 DMG 与 SHA-256）
macapp/setup_runtime.sh          准备独立 Python 运行环境
macapp/runtime-constraints.txt   依赖的精确版本
macapp/runtime-requirements.lock 依赖锁定文件：版本 + SHA-256（macOS 14 arm64）
download_model.sh                下载并校验模型
checksums/                       模型和 Python 运行环境的 SHA-256 清单
cli/recognizer.py                命令行识别工具
env.sh / start_server.sh         命令行和开发版使用的推理服务
```

### 更新依赖

1. 修改 `macapp/runtime-constraints.txt` 中的版本
2. 重新生成锁定文件（按 macOS 14 解析，保证旧系统可用；排除 opencv-python）：
   ```bash
   cd macapp
   runtime/python/bin/python3 -I -m pip install --dry-run --ignore-installed --report /tmp/r.json \
     --only-binary=:all: --platform macosx_14_0_arm64 --python-version 3.12 --implementation cp \
     --target /tmp/t -c runtime-constraints.txt mlx-vlm mlx mlx-metal transformers
   ```
   用 `/tmp/r.json` 中每个包的 `version` 与 `download_info.archive_info.hashes.sha256` 更新 `runtime-requirements.lock`
3. 运行 `./setup_runtime.sh`，测试识别后再运行 `./package.sh`

### 界面翻译

界面文字在代码中统一写英文（`L("...")`），中文翻译在 `macapp/Resources/zh-Hans.lproj/Localizable.strings`。
新增文字后运行 `macapp/tools/check_l10n.sh` 检查。添加其他语言：新建 `<语言代码>.lproj/Localizable.strings`，
并在 `Localization.swift` 的 `AppLanguage` 和 `build.sh` 的 `CFBundleLocalizations` 中加入该语言。

### 命令行

```bash
./start_server.sh &                         # 启动推理服务
source env.sh
$PY cli/recognizer.py 图片.png auto         # auto / formula / text / table
```

`env.sh` 默认使用 `macapp/runtime` 中的 Python，也可以用 `FORMULENS_PYTHON` 指定其他已安装 mlx-vlm 的环境。
如果 Formulens 应用正在运行，命令行会自动读取它的访问密钥，复用同一个推理服务。

### 识别流程

1. 截图预处理：过小的图放大，过大的图缩小
2. 自动模式先用 `OCR:` 提示词识别；如果结果里除公式外没有正常文字，再用 `Formula Recognition:` 重新识别，精度更高；如果输出的是表格结构（OTSL），再用 `Table Recognition:` 识别
3. 把 `\( \)`、`\[ \]` 转成 Markdown 的 `$ $`、`$$ $$`，把 OTSL 表格转成 Markdown 表格

## 致谢

- [PaddleOCR-VL](https://github.com/PaddlePaddle/PaddleOCR)：百度飞桨的文档解析视觉语言模型
- [MLX](https://github.com/ml-explore/mlx) 与 [mlx-vlm](https://github.com/Blaizzy/mlx-vlm)：在 Apple Silicon 上运行模型
- [KaTeX](https://katex.org)：公式渲染
- [python-build-standalone](https://github.com/astral-sh/python-build-standalone)：可随应用分发的独立 Python

## 许可证

本项目代码以 [MIT](LICENSE) 许可证发布。
安装包中包含的模型、Python 运行环境等第三方组件遵循各自的许可证，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

本项目与 Mathpix、百度飞桨（PaddlePaddle）、Apple 均无关联。
