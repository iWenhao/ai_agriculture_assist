// 全局常量配置

// 智谱 GLM 大模型接口配置
// 1. 注册并获取 API Key：https://bigmodel.cn -> 控制台 -> API Keys
// 2. 将下方 GLM_API_KEY 替换为你自己的 Key
export const GLM_API_URL: string = 'https://open.bigmodel.cn/api/paas/v4/chat/completions'
export const GLM_MODEL: string = 'glm-4-flash' // 免费模型，适合课程项目
export const GLM_API_KEY: string = '在此填入你的智谱 API Key'

// 系统提示词：约束 AI 扮演农技专家，直接返回纯文本回答
export const SYSTEM_PROMPT: string =
  '你是一位资深的农业技术专家，擅长作物种植管理、水肥管理、病虫害防治、农业生产技术咨询和农业基础知识问答。' +
  '请针对用户的农业问题，给出专业的分析结果、产生原因、处理建议及注意事项。' +
  '用简洁清晰的中文回答，可以适当分点描述。只返回回答内容，不要返回JSON。'
