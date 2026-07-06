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

// ==================== 种植顾问模块  ====================

/**
 * 修复 JSON 字符串值内未转义的双引号
 *
 * 背景：大模型（agnes-2.0-flash 等）有时会在 content 字符串内直接写出 "
 *   例如 "...遵循"少量多次"原则..."
 * 这会令标准 JSON.parse 提前结束字符串并报 "Unexpected string in JSON"。
 *
 * 思路：逐字符扫描，进入字符串后，遇到未转义的 " 时向前看一个非空白字符：
 *   - 是 ,]}: 之一或到达末尾 → 视为字符串正常结束
 *   - 其它字符 → 视为字符串内的"裸引号"，在前面补一个反斜杠转义
 *
 * 同时把字符串里的真换行 / 真回车（JSON 规范不允许）替换成 \n / \r 转义形式，
 * 避免另一类 SyntaxError。
 */
function repairJsonQuotes(raw: string): string {
  const out: string[] = [];
  let i: number = 0;
  let inString: boolean = false;
  const len: number = raw.length;
  while (i < len) {
    const ch: string = raw[i];
    if (!inString) {
      if (ch === '"') {
        inString = true;
      }
      out.push(ch);
      i++;
      continue;
    }
    // 已经在某个 JSON 字符串值内部
    if (ch === '\\') {
      // 转义序列：保留反斜杠和下一个字符
      out.push(ch);
      if (i + 1 < len) {
        out.push(raw[i + 1]);
        i += 2;
      } else {
        i += 1;
      }
      continue;
    }
    if (ch === '"') {
      // 向前看，跳过空白，判断是不是字符串结束
      let j: number = i + 1;
      let next: string = '';
      let found: boolean = false;
      while (j < len) {
        const cj: string = raw[j];
        if (cj !== ' ' && cj !== '\t' && cj !== '\n' && cj !== '\r') {
          next = cj;
          found = true;
          break;
        }
        j++;
      }
      if (!found || next === ',' || next === ']' || next === '}' || next === ':') {
        // 真正的字符串结束
        inString = false;
        out.push(ch);
      } else {
        // 字符串内部的"裸引号"，转义
        out.push('\\"');
      }
      i++;
      continue;
    }
    // 字符串内的真换行 / 回车 → JSON 不允许，需要转义
    if (ch === '\n') {
      out.push('\\n');
      i++;
      continue;
    }
    if (ch === '\r') {
      out.push('\\r');
      i++;
      continue;
    }
    out.push(ch);
    i++;
  }
  return out.join('');
}

/**
 * 从大模型返回的文本中尝试提取并解析 JSON 对象
 *
 * 兼容以下几种"脏"返回：
 * - 头尾有 ```json ``` 或 ``` 围栏
 * - JSON 前后夹杂了少量说明文字（取首个 { 到末个 } 的子串）
 * - 多余的空白与换行
 * - content 字符串里夹了未转义的直引号 " （大模型常见毛病）
 *
 * 解析失败返回 null，调用方应降级到整体原文展示
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
    let candidate: string = cleaned.substring(first, last + 1);
    // 先按"裸引号"模式尝试解析，失败再走一次 repair 后重试
    try {
      const obj: Record<string, Object> = JSON.parse(candidate) as Record<string, Object>;
      return obj;
    } catch (firstErr) {
      const repaired: string = repairJsonQuotes(candidate);
      const obj2: Record<string, Object> = JSON.parse(repaired) as Record<string, Object>;
      console.warn('JSON 首次解析失败，已自动修复裸引号后重试成功');
      return obj2;
    }
  } catch (err) {
    console.error('JSON 提取/解析失败:', err);
    return null;
  }
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

// 获取今天的日期字符串（YYYY-MM-DD）
// 使用 en-CA locale 让标准库原生输出 YYYY-MM-DD
export function todayStr(): string {
  return new Intl.DateTimeFormat('en-CA', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date());
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
      console.log('种植管理建议', resultStr)
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