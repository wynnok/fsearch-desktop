## Parent

[[SPEC-08] v0.1：本地设置、主动诊断导出与手动更新入口](https://github.com/wynnok/fsearch-desktop/issues/9)。

Ticket ID：T20。切片粒度与阻塞边已由用户确认；本票不编辑或关闭父 Spec。

## What to build

用户主动导出诊断前知道包含什么，生成可排障但默认不含完整文件路径或内容的报告。

## Acceptance criteria

- [ ] 导出为用户显式动作，保留可用版本、架构、系统和错误类别。
- [ ] 上游 stderr、Unicode、多行和标点路径样本经过脱敏，不原样打包。
- [ ] 检查最终导出文件而非仅检查脱敏函数，完整路径/正文不会泄露。
- [ ] 失败说明不被脱敏掩盖，无自动上传或默认查询历史记录。

