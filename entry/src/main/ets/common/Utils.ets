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
 * 📚 给同学们的话
 *
 * 种植顾问模块只做两件事，建议按这个顺序读：
 *
 *   第 1 步：requestAgines        —— 怎么调 AI 大模型接口
 *   第 2 步：parseAdviceSections  —— 怎么把 AI 返回的 JSON 变成 UI 要的数据
 *
 * 中间还夹了一个小工具 getAdviceSectionStyle（标题→样式的映射），
 * 看到的时候顺便读一下就行。
 *
 * 关于"模型返回的 JSON 不合法怎么办"：
 *    模型偶尔会返回坏 JSON。这里采用最朴素的策略——信任 ADVICE_PROMPT 里的
 *    约束，让模型老实输出。万一真的返回坏 JSON，就 catch 住错误，
 *    把原文原样交给 UI 显示，UI 会自动退到"不分段、整段显示"的兜底模式。
 *    "出错就降级、绝不崩溃" 比"写一个 JSON 修复器"更适合教学。
 */

/**
 * 单个分栏的"视觉样式"：图标 + 背景色 + 边框色
 * 由 getAdviceSectionStyle 返回
 */
export interface SectionStyle {
  icon: Resource; // 分类图标（本地资源 $r('app.media.xxx')）
  bg: string; // 卡片背景色
  border: string; // 卡片边框色
}

/**
 * 一个分栏的完整渲染数据：标题 + 正文 + 视觉样式
 * parseAdviceSections 返回的就是这个数组，UI 直接遍历它来画卡片
 */
export interface SectionData {
  icon: Resource;
  title: string;
  body: string;
  bg: string;
  border: string;
}

/**
 * 大模型返回的 JSON 结构（见 Constants.ets 里的 ADVICE_PROMPT）
 *
 * 用 interface 把"JSON 长什么样"写下来，相当于给 JSON 定一个 schema：
 *   - sections 是一个数组
 *   - 数组里每一项必须有 title（标题）和 content（正文）两个字符串字段
 *
 * 这样写完后，编译器会自动帮我们检查类型，下面的 parseAdviceSections
 * 里就不再需要到处写 `as Record<string, Object>` 和 typeof 检查了。
 */
interface AdviceSection {
  title: string;   // 分栏标题（如"田间管理建议"）
  content: string; // 分栏正文（具体建议内容）
}

interface AdviceJson {
  sections: Array<AdviceSection>;
}

/**
 * 小工具：根据分栏标题查找对应的图标 + 配色
 *
 * 思路很简单：if/else 链，把标题字符串映射到一组样式数据。
 * 这里是写死的"四种固定标题"对应四种配色，万一模型返回了一个
 * 我们没预设过的标题，就落到最后那个中性灰的兜底样式上。
 *
 * 配色用的是 Material Design 50/100 这两档（最浅），看起来柔和不刺眼。
 */
export function getAdviceSectionStyle(title: string): SectionStyle {
  if (title === '田间管理建议') {
    // 田间 → 农作物图标  /  浅绿底 + 浅绿边
    return { icon: $r('app.media.flower2'), bg: '#F6FBF4', border: '#DCEDC8' };
  } else if (title === '水肥一体化指导') {
    // 水肥 → 水滴图标      /  浅蓝底 + 浅蓝边
    return { icon: $r('app.media.water'), bg: '#F2F8FD', border: '#BBDEFB' };
  } else if (title === '病虫害预警') {
    // 病虫害 → 虫子图标    /  浅橙底 + 浅橙边
    return { icon: $r('app.media.insect'), bg: '#FFF8F0', border: '#FFE0B2' };
  } else if (title === '后续生产管理建议') {
    // 后续生产             /  浅紫底 + 浅紫边
    return { icon: $r('app.media.advice2'), bg: '#F8F4FA', border: '#E1BEE7' };
  }
  // 兜底：没匹配上的标题就用中性灰
  return { icon: $r('app.media.advice'), bg: '#FAFAFA', border: '#E0E0E0' };
}

/**
 * 第 2 步：把大模型返回的 content 解析成分栏渲染数据
 *
 * 整个函数三件事：
 *   1）调 JSON.parse 把字符串变成对象（这一步最简单但最容易出错，用 try/catch 兜住）
 *   2）从对象里取出 sections 数组
 *   3）对数组每一项，调 getAdviceSectionStyle 算样式，组装成 SectionData
 *
 * 解析失败返回空数组，UI 会自动退到"不分段、整段显示"的兜底模式。
 */
export function parseAdviceSections(content: string): SectionData[] {
  // 1）把字符串解析成 AdviceJson 对象
  //    try/catch 是必须的：万一 JSON 不合法，parse 会抛异常，
  //    接住它直接返回空数组，UI 会退到"不分段、整段显示"的兜底模式
  //    "as AdviceJson" 是个承诺：我们相信模型会按 ADVICE_PROMPT 约定的结构返回
  let obj: AdviceJson;
  try {
    obj = JSON.parse(content.trim()) as AdviceJson;
  } catch (err) {
    console.error('JSON 解析失败:', err);
    return [];
  }

  // 2）遍历 sections，每一项直接用 .title / .content，
  //    因为 AdviceJson 接口已经声明了它们的类型，编译器帮我们做了类型检查
  const result: SectionData[] = [];
  for (let i: number = 0; i < obj.sections.length; i++) {
    const item = obj.sections[i];
    const style = getAdviceSectionStyle(item.title);
    result.push({
      icon: style.icon,
      title: item.title,
      body: item.content,
      bg: style.bg,
      border: style.border
    });
  }
  return result;
}

// 适配后端API的消息结构
//   - role:    'system'（系统提示词）或 'user'（用户输入）或 'assistant'（AI 回复）
//   - content: 这一条消息的文字内容
export interface AginesMessage {
  role: string;
  content: string;
}

// 请求体结构
//   - model:   用哪个模型（见 Constants.ets 里的 AGINES_MODEL）
//   - messages: 一个对话历史数组，按时间顺序排列
//   - stream:  true=流式（边生成边返回），false=一次性返回完整结果
export interface AginesRequestBody {
  model: string;
  messages: AginesMessage[];
  stream?: boolean;
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

/**
 * 第 1 步：调用 Agines 大模型接口
 *
 * 三段式流程，跟我们调用任何 HTTP 接口一样：
 *   1）发请求  → httpRequest.request(...)
 *   2）看状态  → responseCode 是否为 200
 *   3）取数据  → response.result 里就是 AI 写回来的内容
 *
 * 返回值约定（这条约定让 UI 代码变得很简单）：
 *   - 成功：返回 AI 写的正文（纯文本字符串）
 *   - 失败：返回以 "[错误]" 开头的提示字符串
 *
 * 用 "[错误]" 前缀而不是抛异常，是因为 ArkUI 里 catch 异常写起来比较啰嗦，
 * 在返回值层面区分"正常结果"和"错误信息"对前端更友好。
 */
export async function requestAgines(requestBody: AginesRequestBody): Promise<string> {
  // 创建一个 HTTP 请求对象（用完一定要 destroy，否则会内存泄漏）
  const httpRequest = http.createHttp();

  try {
    // 1）发请求：POST + JSON + Bearer Token
    const response = await httpRequest.request(AGINES_API_URL, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${AGINES_API_KEY}`
      },
      // extraData 是请求体；stream:false 表示一次性返回完整结果，不要流式
      // 注意：ArkTS 不支持对象的展开运算符（...），所以这里要显式写出三个字段
      extraData: JSON.stringify({
        model: requestBody.model,
        messages: requestBody.messages,
        stream: false
      }),
      expectDataType: http.HttpDataType.STRING
    });

    // 2）看状态：HTTP 200 = 成功
    if (response.responseCode === 200) {
      // response.result 可能是字符串也可能是对象，统一转成字符串
      const resultStr: string = typeof response.result === 'string'
        ? response.result
        : JSON.stringify(response.result);
      console.log('种植管理建议', resultStr);

      // 3）取数据：从 OpenAI 风格的响应里把真正的正文抽出来
      const content: string = extractDelta(resultStr);
      return content.length > 0 ? content : '[错误]未获取到有效回答';
    }

    // 状态码不是 200，返回错误信息
    return `[错误]请求失败，状态码: ${response.responseCode}`;
  } catch (err) {
    // 网络层抛异常（断网、DNS 失败等）会进这里
    console.error('Agines 请求失败', err);
    return '[错误]请求失败，请检查网络或 API Key 配置';
  } finally {
    // 无论成功失败都要销毁请求对象，释放底层 socket 资源
    httpRequest.destroy();
  }
}