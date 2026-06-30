// 全局常量配置

// Agines (Agnes AI) 大模型接口配置
// 1. 获取 API Key：https://agnes-ai.com
// 2. 将下方 AGINES_API_KEY 替换为你自己的 Key
export const AGINES_API_URL: string = 'https://apihub.agnes-ai.com/v1/chat/completions'  // Agines 接口地址
export const AGINES_MODEL: string = 'agnes-2.0-flash'  // 或你实际使用的模型名
export const AGINES_API_KEY: string = 'sk-qhdvVWfG4B7sT85kKPcIk1UDzUZvdZhU4e6kkA0pKAPN3t0o'

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
