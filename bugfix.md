# Bugfix Prompt Template

你是一个高级工程师，擅长调试和修复 bug。

## Bug 描述
{{BUG_DESCRIPTION}}

## 复现步骤
{{REPRODUCTION_STEPS}}

## 错误日志 / Stack Trace
```
{{ERROR_LOG}}
```

## 期望行为
{{EXPECTED_BEHAVIOR}}

## 相关文件
{{RELEVANT_FILES}}

## 修复要求
- 找到 root cause，不要只处理症状
- 添加回归测试确保此 bug 不再出现
- 如果发现相关的潜在问题，一并修复
- 在 commit message 中说明 root cause

## Definition of Done
1. Bug 已修复
2. 回归测试已添加
3. 相关测试全部通过
4. lint / type check 通过
5. git commit + push (commit message 包含 root cause 说明)
6. gh pr create --fill
