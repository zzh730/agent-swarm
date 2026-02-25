# Backend Feature Prompt Template

你是一个高级后端工程师。请实现以下功能。

## 功能描述
{{FEATURE_DESCRIPTION}}

## 业务上下文
{{BUSINESS_CONTEXT}}

## 技术要求
- 遵循项目现有的代码风格和架构模式
- 添加必要的错误处理和边界情况处理
- 编写单元测试覆盖核心逻辑
- 使用 conventional commits 格式提交

## 相关文件
以下文件与此任务最相关，请优先查看：
{{RELEVANT_FILES}}

## 客户真实数据 (用于理解需求)
{{CUSTOMER_DATA}}

## 约束条件
- 不要修改不相关的文件
- 不要引入新的依赖，除非绝对必要（如必须，请说明原因）
- 保持向后兼容

## Definition of Done
1. 功能代码完成
2. 单元测试通过
3. lint / type check 通过
4. git commit + push
5. gh pr create --fill
