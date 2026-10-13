## Parent

[[SPEC-13] v0.2：受支持文本内容搜索与匹配片段](https://github.com/wynnok/fsearch-desktop/issues/14)。

Ticket ID：T30。切片粒度与阻塞边已由用户确认；本票不编辑或关闭父 Spec。

## What to build

v0.2 用户从明确的文本内容入口输入普通文字，通过 Fsearch 找到受支持文件及其匹配行，并沿用已有文件动作。

## Acceptance criteria

- [ ] 同一引擎服务调用公开 Grep，不复制内容索引或匹配算法。
- [ ] 一文件一结果，文件数量与内容匹配分开，来源/限制准确，基础片段可见。
- [ ] 真实文本、Unicode、CRLF、无匹配、修改正文与现有打开/预览动作验证通过。
- [ ] 说明只支持上游合规文本，PDF/Office/OCR、压缩包和云端缺失不冒充可搜；片段不默认进诊断。

