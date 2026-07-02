import { http } from '@kit.NetworkKit';
import { AGINES_API_URL, AGINES_API_KEY } from './Constants';

// ==================== 以下为原有工具函数 ====================

// 获取当前时间格式化字符串 (HH:mm)
export function nowTime(): string {
  return new Date().toLocaleTimeString('zh-CN', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false, // 24 小时制
  });
}

// 从API响应JSON中提取文本内容
export function extractDelta(jsonStr: string): string {
  try {
    // 把字符串变成真正的对象，外面套了一个 try...catch，因为如果服务器返回的不是合法的 JSON，程序会崩溃，catch 就是用来兜底报错的
    // Record<string, Object> 一个不限定具体内部结构的万能字典 ，当 AI 服务器返回数据时，我们只知道它最外层是一个 JSON 对象，但里面具体有哪些属性、嵌套了多少层，ArkTS 编译器是不知道的
    // Record：代表这是一个键值对（Key-Value）的集合对象。
    // <string, Object>：定义了储物柜的规则。
    // string（键）：表示储物柜外面的标签必须是字符串（比如 "choices"、"message"）。
    // Object（值）：表示柜子里装的东西可以是任何复杂类型（可以是字符串、数字、数组，甚至是另一个嵌套的对象
    const obj = JSON.parse(jsonStr) as Record<string, Object>;
    // 在对象里找 choices 属性，并判断它是不是一个非空数组
    const choices = obj['choices'];
    if (Array.isArray(choices) && choices.length > 0) {
      // 数组里可能有多个结果，我们只取第一个
      const first = choices[0] as Record<string, Object>;
      // 进入第一条消息的内部
      const message = first['message'] as Record<string, Object>;
      // 拿到真正的文字，判断它确实是字符串后，return 返回
      if (message) {
        const content = message['content'];
        if (typeof content === 'string') {
          return content;
        }
      }
    }
  } catch (err) {
    console.error('JSON 解析失败:', err);
  }
  return '';
}


// 轻量级Markdown转纯文本（去除**加粗*等格式）
export function stripMarkdown(md: string): string {
  let text = md;
  text = text.replace(/\*\*(.*?)\*\*/g, '$1'); // 去除加粗
  text = text.replace(/\*(.*?)\*/g, '$1'); // 去除斜体
  text = text.replace(/^#{1,3}\s*/gm, ''); // 去除标题
  text = text.replace(/^[-*]\s+/gm, '• '); // 列表符号转圆点
  return text;
}

// ==================== 以下为新增工具函数（种植顾问模块） ====================

// 适配后端API的消息结构
export interface AginesMessage {
  role: string;
  content: string;
}

// 请求体结构
export interface AginesRequestBody {
  model: string;
  messages: AginesMessage[];
  stream?: boolean; // 是否开启流式
}

// 将 DatePicker 选中的年月日格式化为 YYYY-MM-DD
// DatePickerResult.month 为 0-indexed,直接交给 Date 构造器即可
// 使用 en-CA locale 使标准库原生输出 YYYY-MM-DD,无需手动补零
export function formatDate(year: number, month: number, day: number): string {
  return new Intl.DateTimeFormat('en-CA', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date(year, month, day));
}

// 按"【...】"将整段建议切分为多个小节字符串（含标题）
export function splitSections(text: string): string[] {
  const result: string[] = [];
  try {
    // 用正则匹配所有"【标题】"的位置，记录每个标题的起始下标
    const reg = /【[^【】]+】/g;
    const positions: number[] = [];
    let m: RegExpExecArray | null;
    while ((m = reg.exec(text)) !== null) {
      if (m.index !== undefined) {
        positions.push(m.index);
      }
    }
    if (positions.length === 0) {
      return result;
    }
    // 按相邻标题下标切分字符串
    for (let i = 0; i < positions.length; i++) {
      const start = positions[i];
      const end = i + 1 < positions.length ? positions[i + 1] : text.length;
      result.push(text.substring(start, end));
    }
  } catch (err) {
    console.error('切分建议小节失败', err);
  }
  return result;
}

// 从小节字符串中提取"【标题】"
export function extractTitle(section: string): string {
  const start = section.indexOf('【');
  const end = section.indexOf('】');
  if (start >= 0 && end > start) {
    return section.substring(start, end + 1);
  }
  return '【建议】';
}

// 从小节字符串中去掉标题，得到正文
export function extractBody(section: string): string {
  const end = section.indexOf('】');
  if (end >= 0) {
    return section.substring(end + 1).trim();
  }
  return section.trim();
}

// 统一的 Agines 大模型非流式请求：发送请求体并返回解析后的文本内容
// 返回值约定：成功返回正文；失败返回以 "[错误]" 开头的提示字符串
export async function requestAgines(requestBody: AginesRequestBody): Promise<string> {
  const httpRequest = http.createHttp();
  try {
    const normalBody: AginesRequestBody = {
      model: requestBody.model,
      messages: requestBody.messages,
      stream: false  // 强制非流式
    };

    const response = await httpRequest.request(AGINES_API_URL, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${AGINES_API_KEY}`
      },
      extraData: JSON.stringify(normalBody),
      expectDataType: http.HttpDataType.STRING
    });

    if (response.responseCode === 200) {
      let resultStr: string = '';
      if (typeof response.result === 'string') {
        resultStr = response.result;
      } else if (response.result) {
        resultStr = JSON.stringify(response.result);
      }
      const content = extractDelta(resultStr);
      return content.length > 0 ? content : '[错误]未获取到有效回答';
    }
    return `[错误]请求失败，状态码: ${response.responseCode}`;
  } catch (err) {
    console.error('Agines 请求失败', err);
    return '[错误]请求失败，请检查网络或 API Key 配置';
  } finally {
    httpRequest.destroy();
  }
}

// ==================== AI农技问答的工具函数 ====================

// 消息角色类型定义
export type MsgRole = 'user' | 'ai';

// 单条消息的数据结构
export interface ChatMessage {
  role: MsgRole; // 角色
  text: string; // 消息内容
  time: string // 时间戳
}

// 追加AI文字（核心：UI刷新）
export function appendAiText(messageList: ChatMessage[], delta: string): ChatMessage[] {
  if (messageList.length === 0) {
    return messageList;
  }
  const last = messageList[messageList.length - 1];
  if (last.role === 'ai') {
    // ArkTS状态更新机制：必须创建新对象并重新赋值数组才能触发UI刷新
    const newMsg: ChatMessage = {
      role: 'ai',
      text: last.text + delta,
      time: last.time
    };
    const newList: ChatMessage[] = messageList.slice(0, -1);
    newList.push(newMsg);
    return newList; // 触发UI重绘
  }
  return messageList;
}

// 滚动到底部
export function qnaScrollToBottom(scroller: Scroller): void {
  setTimeout(() => {
    scroller.scrollEdge(Edge.Bottom);
  }, 50);
}

// ==================== JSON 解析辅助（种植顾问模块） ====================

/**
 * 从大模型返回的文本中尝试提取并解析 JSON 对象
 *
 * 兼容以下几种"脏"返回：
 * - 头尾有 ```json ``` 或 ``` 围栏
 * - JSON 前后夹杂了少量说明文字（取首个 { 到末个 } 的子串）
 * - 多余的空白与换行
 *
 * 解析失败返回 null，调用方应降级到原有的【】分段方案
 */
export function tryExtractJson(text: string): Record<string, Object> | null {
  try {
    let cleaned: string = text.trim();
    // 去除 ```json / ``` 围栏
    cleaned = cleaned.replace(/^```(?:json)?\s*/i, '');
    cleaned = cleaned.replace(/\s*```\s*$/i, '');
    cleaned = cleaned.trim();
    // 找首个 { 与末个 }，把中间内容作为 JSON 候选
    const first: number = cleaned.indexOf('{');
    const last: number = cleaned.lastIndexOf('}');
    if (first < 0 || last <= first) {
      return null;
    }
    const candidate: string = cleaned.substring(first, last + 1);
    const obj: Record<string, Object> = JSON.parse(candidate) as Record<string, Object>;
    return obj;
  } catch (err) {
    console.error('JSON 提取/解析失败:', err);
    return null;
  }
}