// 获取当前时间格式化字符串 (HH:mm)
export function nowTime(): string {
  const d = new Date();
  const h = d.getHours().toString().padStart(2, '0');
  const m = d.getMinutes().toString().padStart(2, '0');
  return `${h}:${m}`;
}

// 从API响应JSON中提取文本内容
export function extractDelta(jsonStr: string): string {
  try {
    const obj = JSON.parse(jsonStr) as Record<string, Object>;
    const choices = obj['choices'];
    if (Array.isArray(choices) && choices.length > 0) {
      const first = choices[0] as Record<string, Object>;
      const message = first['message'] as Record<string, Object>;
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