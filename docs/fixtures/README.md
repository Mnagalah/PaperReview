# 受控测试图片

`synthetic-essay.png` 由项目脚本 `script/make_test_fixture.swift` 使用系统 Helvetica 字体绘制，原文为同目录 `synthetic-essay.md`。这是带已知拼写、语法错误的合成印刷文本，用于检查系统是否保留错词、批注能否定位；不是学生手写照片，也不代表手写识别效果。

另使用 OpenBMB 官方仓库的英文手写电场笔记进行冒烟测试，来源：
https://raw.githubusercontent.com/OpenBMB/MiniCPM-OCR/main/webdemo/frontend/src/pages/playground/assets/ocr-examples/electric-field.png

`synthetic-essay-tight-crop.png` 是同一合成作文的紧裁切增强版，来自早期处理管线，用于验证上下文变化时的自动词级保真复识；不是真实手写。
