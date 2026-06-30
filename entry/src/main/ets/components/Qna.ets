// AI农技问答（聊天对话式 + SSE 流式打字机效果）

import { http } from '@kit.NetworkKit';
import { GLM_API_URL, GLM_MODEL, GLM_API_KEY, SYSTEM_PROMPT } from '../common/Constants';
import { util } from '@kit.ArkTS';

// 消息角色
type MsgRole = 'user' | 'ai';

// 单条消息
interface ChatMessage {
  role: MsgRole;
  text: string;
  time: string
}

// GLM 请求消息
interface GlmMessage {
  role: string;
  content: string;
}

// GLM 请求体
interface GlmRequestBody {
  model: string;
  messages: GlmMessage[];
  stream: boolean;
}

@Component
export struct Qna {
  // --- 状态变量 ---
  @State messageList: ChatMessage[] = [];
  @State inputText: string = '';
  @State loading: boolean = false;
  private scroller: Scroller = new Scroller();
  // SSE 行缓冲：网络数据按块到达，需要拼接成完整行再解析
  private sseBuffer: string = '';

  aboutToAppear(): void {
    this.messageList.push({
      role: 'ai',
      text: '您好，我是 AI 农技专家。无论是作物种植、水肥管理、病虫害防治还是农业技术咨询，都可以向我提问。',
      time: this.nowTime()
    });
  }

  private nowTime(): string {
    const d = new Date();
    const h = d.getHours().toString().padStart(2, '0');
    const m = d.getMinutes().toString().padStart(2, '0');
    return `${h}:${m}`;
  }

  // 提交提问
  private async onSend(): Promise<void> {
    const q = this.inputText.trim();
    if (q.length === 0 || this.loading) {
      return;
    }

    // 追加用户消息
    this.messageList.push({
      role: 'user',
      text: q,
      time: this.nowTime()
    });
    this.inputText = '';
    this.loading = true;

    // 追加一条空 AI 消息（流式填充）
    const aiTime = this.nowTime();
    this.messageList.push({
      role: 'ai',
      text: '',
      time: aiTime
    });
    this.scrollToBottom();

    // 构造 GLM 请求体
    const messages: GlmMessage[] = [{ role: 'system', content: SYSTEM_PROMPT }];
    const recent = this.messageList.slice(-6);
    for (const msg of recent) {
      if (msg.role === 'user') {
        messages.push({ role: 'user', content: msg.text });
      } else {
        messages.push({ role: 'assistant', content: msg.text });
      }
    }

    const requestBody: GlmRequestBody = {
      model: GLM_MODEL,
      messages: messages,
      stream: true  // 开启 SSE 流式输出
    };

    // 重置 SSE 缓冲
    this.sseBuffer = '';

    // http 2: http.createHttp()创建连接
    const httpRequest = http.createHttp();

    // SSE 流式接收：每收到一块数据就解析并追加文字
    httpRequest.on('dataReceive', (data: ArrayBuffer) => {
      // ArrayBuffer → 字符串（decodeToString 直接返回 string）
      const chunk = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(data), { stream: false });
      // 拼接到缓冲（数据可能跨块）
      this.sseBuffer += chunk;
      // 按行分割，处理完整的 SSE 行
      this.processSSELines();
    });

    // 流式结束
    httpRequest.on('dataEnd', () => {
      console.log('=====SSE 流式结束======');
      // 处理缓冲中可能残留的最后一行
      if (this.sseBuffer.trim().length > 0) {
        this.processSSELines();
      }
      httpRequest.destroy();
      this.loading = false;
    });

    try {
      console.log('=====SSE 流式请求开始======');
      await httpRequest.request(GLM_API_URL, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${GLM_API_KEY}`,
          'Accept': 'text/event-stream'
        },
        extraData: JSON.stringify(requestBody),
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
    } catch (err) {
      console.error('SSE 请求失败', err);
      // 失败时直接显示错误信息到 AI 消息
      this.appendAiText('请求失败，请检查网络或 API Key 配置');
      httpRequest.destroy();
      this.loading = false;
    }
  }

  // 处理 SSE 缓冲中的完整行
  private processSSELines(): void {
    // SSE 格式：每行 "data: {...}\n\n"，以双换行分隔
    const lines = this.sseBuffer.split('\n');
    // 最后一个元素可能是不完整的行，保留在缓冲中
    this.sseBuffer = lines.pop() ?? '';

    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.startsWith('data: ')) {
        const payload = trimmed.substring(6);
        // 智谱 SSE 结束标志
        if (payload === '[DONE]') {
          return;
        }
        // 解析 delta.content
        const delta = this.extractDelta(payload);
        if (delta.length > 0) {
          this.appendAiText(delta);
        }
      }
    }
  }

  // 从单条 SSE data 中提取 delta.content
  private extractDelta(jsonStr: string): string {
    try {
      const obj = JSON.parse(jsonStr) as Record<string, Object>;
      const choices = obj['choices'];
      if (Array.isArray(choices) && choices.length > 0) {
        const first = choices[0] as Record<string, Object>;
        const delta = first['delta'] as Record<string, Object>;
        const content = delta['content'];
        if (typeof content === 'string') {
          return content;
        }
      }
    } catch (err) {
      // JSON 解析失败（极少），忽略
    }
    return '';
  }

  // 追加文字到列表中最后一条 AI 消息（触发 UI 刷新 = 打字机效果）
  private appendAiText(delta: string): void {
    if (this.messageList.length === 0) {
      return;
    }
    const last = this.messageList[this.messageList.length - 1];
    if (last.role === 'ai') {
      this.messageList[this.messageList.length - 1] = {
        role: 'ai',
        text: last.text + delta,
        time: last.time
      };
      this.scrollToBottom();
    }
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 50);
  }

  // ===== 用户消息气泡（绿色，靠右） =====
  @Builder
  UserBubble(msg: ChatMessage) {
    Column({ space: 4 }) {
      Text(msg.text)
        .fontSize(15)
        .fontColor('#FFFFFF')
        .lineHeight(22)
        .padding({
          left: 14,
          right: 14,
          top: 10,
          bottom: 10
        })
        .backgroundColor('#2e7d32')
        .borderRadius({
          topLeft: 12,
          topRight: 12,
          bottomLeft: 12,
          bottomRight: 0
        })
        .constraintSize({ maxWidth: '80%' })
      Text(msg.time)
        .fontSize(11)
        .fontColor('#bfcaba')
    }
    .alignItems(HorizontalAlign.End)
  }

  // AI 气泡公共样式
  @Styles
  aiBubbleStyle() {
    .padding({
      left: 14,
      right: 14,
      top: 10,
      bottom: 10
    })
    .backgroundColor('#FFFFFF')
    .borderRadius({
      topLeft: 0,
      topRight: 12,
      bottomLeft: 12,
      bottomRight: 12
    })
    .constraintSize({ maxWidth: '88%' })
    .shadow({ radius: 4, color: 'rgba(0,0,0,0.05)', offsetY: 2 })
  }

  // ===== AI 消息气泡（白色，靠左） =====
  @Builder
  AiBubble(msg: ChatMessage) {
    Column({ space: 4 }) {
      // 公共样式
      if (msg.text.length === 0) {
        Text('AI 正在思考…')
          .fontSize(14)
          .fontColor('#40493d')
          .aiBubbleStyle()
      } else {
        Text(msg.text)
          .fontSize(15)
          .fontColor('#1a1c1c')
          .lineHeight(22)
          .aiBubbleStyle()
      }
      Text(msg.time)
        .fontSize(11)
        .fontColor('#bfcaba')
    }
    .alignItems(HorizontalAlign.Start)
  }

  // ===== 单条消息 =====
  @Builder
  MessageItem(msg: ChatMessage) {
    if (msg.role === 'user') {
      Row() {
        Blank()
        this.UserBubble(msg)
      }
      .width('100%')
    } else {
      Row() {
        this.AiBubble(msg)
        Blank()
      }
      .width('100%')
    }
  }

  // ===== 底部输入栏 =====
  @Builder
  InputBar() {
    Row({ space: 10 }) {
      TextArea({
        placeholder: '咨询农技难题...',
        text: this.inputText
      })
        .layoutWeight(1)
        .fontSize(14)
        .fontColor('#1a1c1c')
        .placeholderColor('#AAAAAA')
        .backgroundColor('#f3f3f3')
        .borderRadius(12)
        .onChange((value: string) => {
          this.inputText = value;
        })

      Stack() {
        Text('➤')
          .fontSize(20)
          .fontColor('#FFFFFF')
      }
      .width(48)
      .height(48)
      .backgroundColor('#2e7d32')
      .borderRadius(12)
      .alignContent(Alignment.Center)
      .opacity((this.inputText.trim().length > 0 && !this.loading) ? 1 : 0.5)
      .onClick(() => this.onSend())
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 4,
      bottom: 12
    })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      List({ space: 16, scroller: this.scroller }) {
        ForEach(this.messageList, (msg: ChatMessage) => {
          ListItem() {
            this.MessageItem(msg)
          }
        })
      }
      .layoutWeight(1)
      .width('100%')
      .padding({
        left: 12,
        right: 12,
        top: 14,
        bottom: 14
      })
      .scrollBar(BarState.Auto)

      this.InputBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#f9f9f9')
  }
}
