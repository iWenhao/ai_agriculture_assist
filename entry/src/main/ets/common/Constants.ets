// 全局常量配置

// 智谱 GLM 大模型接口配置
// 1. 注册并获取 API Key：https://bigmodel.cn -> 控制台 -> API Keys
// 2. 将下方 GLM_API_KEY 替换为你自己的 Key
export const GLM_API_URL: string = 'https://open.bigmodel.cn/api/paas/v4/chat/completions'
export const GLM_MODEL: string = 'glm-4-flash' // 免费模型，适合课程项目
export const GLM_API_KEY: string = '在此填入你的智谱 API Key'

// 系统提示词：约束 AI 扮演农技专家，并按固定字段返回 JSON
export const SYSTEM_PROMPT: string =
  '你是一位资深的农业技术专家。请针对用户提出的农业生产问题，用JSON格式回答。' +
  'JSON必须包含且仅包含以下四个字段：' +
  'analysis(对问题的分析结果)、' +
  'cause(问题产生的原因)、' +
  'suggestion(具体的处理或管理建议)、' +
  'notice(操作时的注意事项)。' +
  '所有字段值用简洁的中文描述。只返回JSON对象，不要包含任何额外文字或代码块标记。'
