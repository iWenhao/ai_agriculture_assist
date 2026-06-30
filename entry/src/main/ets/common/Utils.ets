// 获取当前时间格式化字符串 (HH:mm)
export function nowTime(): string {
  const d = new Date();
  const h = d.getHours().toString().padStart(2, '0'); // 获取小时数，变字符串，强制补齐两位
  const m = d.getMinutes().toString().padStart(2, '0');
  return `${h}:${m}`;
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