# 第三方组件声明 / Third-Party Notices

Formulens 自身的代码以 MIT 许可证发布（见 [LICENSE](LICENSE)）。
发布的安装包（DMG）还包含以下第三方组件，它们各自遵循原有的许可证。
每个 Python 包的完整许可证文本都随安装包附带，位于
`Formulens.app/Contents/Resources/python/lib/python3.12/site-packages/<包名>.dist-info/`。

## 模型

| 组件 | 版本 | 许可证 | 来源 |
|---|---|---|---|
| PaddleOCR-VL-1.6（PaddlePaddle） | 1.6 | Apache-2.0 | https://www.modelscope.cn/models/PaddlePaddle/PaddleOCR-VL-1.6 |

模型文件未经修改，按原样分发。许可证全文随模型一起附带（`models/PaddleOCR-VL-1.6/LICENSE`）。

## 应用内嵌组件

| 组件 | 版本 | 许可证 | 来源 |
|---|---|---|---|
| KaTeX | 0.16.11 | MIT；部分代码与字体素材为 OFL-1.1 / Apache-2.0（见下） | https://katex.org |
| CPython（python-build-standalone 构建） | 3.12.15 | PSF-2.0 及其附带组件的许可证 | https://github.com/astral-sh/python-build-standalone |

KaTeX 主体以 MIT 许可证发布（`macapp/Resources/katex/LICENSE`）。其中伸缩符号的 SVG 路径数据
（Copyright 2009-2010 Design Science, Inc.；2014-2017 Khan Academy）及部分源自 AMS 字体的素材
（Copyright 1995, 2009 American Mathematical Society）以 SIL Open Font License 1.1 发布；
部分字体生成脚本源自 MathJax（Apache-2.0）。OFL 1.1 全文：https://openfontlicense.org

CPython 及其附带的 OpenSSL、SQLite、libffi、zlib、xz、bzip2、mpdecimal 等组件的许可证见
`python/lib/python3.12/LICENSE.txt`。

## Python 包

| 包 | 版本 | 许可证 |
|---|---|---|
| annotated-doc | 0.0.5 | MIT |
| annotated-types | 0.8.0 | MIT |
| anyio | 4.15.1 | MIT |
| certifi | 2026.7.22 | Mozilla Public License 2.0 (MPL 2.0) |
| cffi | 2.1.1 | MIT-0 |
| charset-normalizer | 3.5.2 | MIT |
| click | 8.5.0 | BSD-3-Clause |
| cryptography | 50.0.2 | Apache-2.0 OR BSD-3-Clause |
| fastapi | 0.143.0 | MIT |
| filelock | 4.1.1 | MIT |
| fsspec | 2026.9.0 | BSD-3-Clause |
| h11 | 0.16.0 | MIT License |
| hf-xet | 1.7.0 | Apache-2.0 |
| httpcore2 | 2.13.1 | BSD-3-Clause |
| httpx2 | 2.13.1 | BSD-3-Clause |
| huggingface_hub | 2.2.0 | Apache Software License |
| idna | 3.20 | BSD-3-Clause |
| Jinja2 | 3.1.6 | BSD License |
| llguidance | 1.9.1 | MIT |
| markdown-it-py | 4.2.0 | MIT License |
| MarkupSafe | 3.0.4 | BSD-3-Clause |
| mdurl | 0.1.2 | MIT License |
| miniaudio | 1.71 | MIT License |
| mlx | 0.32.3 | MIT |
| mlx-audio | 0.5.8 | MIT |
| mlx-metal | 0.32.3 | MIT |
| mlx-vlm | 0.7.6 | MIT License |
| numpy | 2.5.4 | BSD-3-Clause AND 0BSD AND MIT AND Zlib AND CC0-1.0 |
| opentelemetry-api | 1.45.1 | Apache-2.0 |
| packaging | 26.3 | Apache-2.0 OR BSD-2-Clause |
| pillow | 12.3.0 | MIT-CMU |
| pip | 26.2.1 | MIT |
| pycparser | 3.11 | BSD-3-Clause |
| pydantic | 2.14.1 | MIT |
| pydantic_core | 2.50.1 | MIT |
| Pygments | 2.21.0 | BSD-2-Clause |
| python-multipart | 0.0.32 | Apache-2.0 |
| PyYAML | 6.0.3 | MIT License |
| regex | 2026.9.29 | Apache-2.0 AND CNRI-Python |
| requests | 2.34.2 | Apache Software License |
| rich | 15.0.0 | MIT License |
| safetensors | 0.8.0 | Apache Software License |
| scipy | 1.18.1 | BSD License |
| sentencepiece | 0.2.2 | Apache-2.0 |
| shellingham | 1.5.4 | ISC License (ISCL) |
| sounddevice | 0.5.6 | MIT |
| starlette | 1.7.0 | BSD-3-Clause |
| tokenizers | 0.23.3 | Apache Software License |
| tqdm | 4.70.1 | MPL-2.0 AND MIT |
| transformers | 5.19.0 | Apache 2.0 License |
| truststore | 0.10.5 | MIT |
| typer | 0.27.3 | MIT |
| typing-inspection | 0.4.4 | MIT |
| typing_extensions | 4.16.0 | PSF-2.0 |
| urllib3 | 2.8.0 | MIT |
| uvicorn | 0.54.0 | BSD-3-Clause |
| websockets | 17.2 | BSD-3-Clause |

### 补充说明

- **scipy** 内含 libgfortran、libquadmath、libgcc_s，许可证为 GPL-3.0 附 GCC 运行库例外（GCC Runtime Library Exception 3.1），允许作为运行库随程序分发。
- **certifi**、**tqdm** 部分代码为 MPL-2.0。本安装包按原样分发，未作修改，源代码可从 PyPI 获取。
- **opencv-python** 是 mlx-vlm 的依赖，但它内置的 ffmpeg 含 GPL 组件，且识别图片用不到，因此已从安装包中移除（见 `macapp/setup_runtime.sh`）。

## 商标

本项目与 Mathpix、百度飞桨（PaddlePaddle）、Apple 均无关联，也未获得它们的认可。
相关名称和商标归各自所有者所有。
