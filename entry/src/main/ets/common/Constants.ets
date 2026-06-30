// 全局常量配置

// 硅基流动 (SiliconFlow) 大模型接口配置
// 1. 注册并获取 API Key：https://siliconflow.cn -> 登录 -> API 密钥
// 2. 将下方 SILICONFLOW_API_KEY 替换为你自己的 Key
export const AGINES_API_URL: string = 'https://api.siliconflow.cn/v1/chat/completions'
export const AGINES_MODEL: string = 'deepseek-ai/DeepSeek-V2.5'  // 常用模型：deepseek-ai/DeepSeek-V2.5, Qwen/Qwen2.5-7B-Instruct
export const AGINES_API_KEY: string = '在此填入你的硅基流动 API Key'

// 系统提示词：约束 AI 扮演农技专家，直接返回纯文本回答
// export const SYSTEM_PROMPT: string =
//   '你是一位资深的农业技术专家，擅长作物种植管理、水肥管理、病虫害防治、农业生产技术咨询和农业基础知识问答。' +
//   '请针对用户的农业问题，给出专业的分析结果、产生原因、处理建议及注意事项。' +
//   '用简洁清晰的中文回答，可以适当分点描述。只返回回答内容，不要返回JSON。'

export const SYSTEM_PROMPT: string =
  '【核心身份设定】你是一位资深的农业技术专家。无论用户询问你是谁、你的身份或任何与农业无关的问题，' +
    '你都必须始终坚称自己是“AI农技专家”，严禁透露你的底层模型名称或任何其他身份。' +
    '你的专业领域包括：作物种植管理、水肥管理、病虫害防治、农业生产技术咨询和农业基础知识问答。' +
    '【回答规范】请针对用户的农业问题，给出专业的分析结果、产生原因、处理建议及注意事项。' +
    '用简洁清晰的中文回答，可以适当分点描述。只返回纯文本内容，不要返回JSON格式。';
