// AI农技问答（聊天对话式 + SSE 流式打字机效果）

import { http } from '@kit.NetworkKit';
import { AGINES_API_URL, AGINES_MODEL, AGINES_API_KEY, SYSTEM_PROMPT } from '../common/Constants';
import { util } from '@kit.ArkTS';

// 消息角色
type MsgRole = 'user' | 'ai';

// 单条消息
interface ChatMessage {
  role: MsgRole;
  text: string;
  time: string
}

// Agines 请求消息
interface AginesMessage {
  role: string;
  content: string;
}

// Agines 请求体
interface AginesRequestBody {
  model: string;
  messages: AginesMessage[];
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
  // 是否在预览器环境（预览器不支持流式网络，需要降级到非流式）
  private isPreviewer: boolean = false;

  aboutToAppear(): void {
    // 检测运行环境：预览器中 TextDecoder.decodeToString 是 mock 实现，返回空字符串
    try {
      const decoder = util.TextDecoder.create('utf-8');
      const testData = new Uint8Array([72, 101, 108, 108, 111]); // "Hello" ASCII
      const result = decoder.decodeToString(testData, { stream: false });
      this.isPreviewer = (result.length === 0);
    } catch (e) {
      this.isPreviewer = true;
    }
    console.log('=====运行环境=====', this.isPreviewer ? '预览器' : '真机/模拟器');

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

    // 构造 Agines 请求体
    const messages: AginesMessage[] = [{ role: 'system', content: SYSTEM_PROMPT }];
    const recent = this.messageList.slice(-6);
    for (const msg of recent) {
      if (msg.role === 'user') {
        messages.push({ role: 'user', content: msg.text });
      } else {
        messages.push({ role: 'assistant', content: msg.text });
      }
    }

    const requestBody: AginesRequestBody = {
      model: AGINES_MODEL,
      messages: messages,
      stream: true  // 开启 SSE 流式输出
    };

    try {
      if (this.isPreviewer) {
        // 预览器直接走非流式（预览器 mock 的流式数据为空）
        console.log('=====预览器环境：直接走非流式请求=====');
        await this.sendNormalRequest(requestBody);
      } else {
        // 真机/模拟器：尝试流式，失败再降级
        await this.sendStreamRequest(requestBody);
      }
    } catch (err) {
      console.error('=====请求失败，降级为非流式请求=====', err);
      try {
        await this.sendNormalRequest(requestBody);
      } catch (err2) {
        console.error('=====非流式请求也失败=====', err2);
        this.loading = false;
      }
    }
  }

  // 流式请求：真机/模拟器使用 requestInStream
  private async sendStreamRequest(requestBody: AginesRequestBody): Promise<void> {
    this.sseBuffer = '';
    const httpRequest = http.createHttp();

    // 监听 HTTP 响应头
    httpRequest.on('headersReceive', (header) => {
      console.log('=====HTTP headersReceive=====', JSON.stringify(header));
    });

    // SSE 流式接收
    httpRequest.on('dataReceive', (data: ArrayBuffer) => {
      const chunk = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(data), { stream: false });
      console.log('=====收到数据块=====', chunk);
      console.log('=====数据块长度=====', chunk.length);
      this.sseBuffer += chunk;
      this.processSSELines();
    });

    // 流式结束
    httpRequest.on('dataEnd', () => {
      console.log('=====SSE 流式结束======');
      console.log('=====残留缓冲=====', this.sseBuffer);
      if (this.sseBuffer.trim().length > 0) {
        this.processSSELines();
      }
      httpRequest.destroy();
      this.loading = false;
    });

    console.log('=====SSE 流式请求开始======');
    try {
      const responseCode = await httpRequest.requestInStream(AGINES_API_URL, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${AGINES_API_KEY}`,
          'Accept': 'text/event-stream'
        },
        extraData: JSON.stringify(requestBody),
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      console.log('=====HTTP requestInStream 返回状态码=====', responseCode);
      if (responseCode !== 200) {
        console.error('=====HTTP 请求失败，状态码=====', responseCode);
        this.appendAiText(`请求失败，状态码: ${responseCode}`);
        httpRequest.destroy();
        this.loading = false;
      }
    } catch (err) {
      httpRequest.destroy();
      throw new Error(String(err));
    }
  }

  // 非流式请求：预览器 fallback（普通 request，一次性返回完整 JSON）
  private async sendNormalRequest(requestBody: AginesRequestBody): Promise<void> {
    const httpRequest = http.createHttp();
    try {
      // 非流式：stream 设为 false
      const normalBody: AginesRequestBody = {
        model: requestBody.model,
        messages: requestBody.messages,
        stream: false
      };
      console.log('=====非流式请求开始======');
      const response = await httpRequest.request(AGINES_API_URL, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${AGINES_API_KEY}`
        },
        extraData: JSON.stringify(normalBody),
        expectDataType: http.HttpDataType.STRING
      });
      console.log('=====非流式响应状态码=====', response.responseCode);
      console.log('=====非流式响应 result 类型=====', typeof response.result);
      if (response.responseCode === 200) {
        let resultStr: string = '';
        if (typeof response.result === 'string') {
          resultStr = response.result as string;
        } else if (response.result) {
          resultStr = JSON.stringify(response.result);
        }
        console.log('=====非流式响应内容=====', resultStr);
        const content = this.extractDelta(resultStr);
        if (content.length > 0) {
          this.appendAiText(content);
        } else {
          this.appendAiText('（未获取到有效回答）');
        }
      } else {
        console.error('=====非流式请求失败=====', response.result);
        this.appendAiText(`请求失败，状态码: ${response.responseCode}`);
      }
    } catch (err) {
      console.error('非流式请求失败', err);
      this.appendAiText('请求失败，请检查网络或 API Key 配置');
    } finally {
      httpRequest.destroy();
      this.loading = false;
    }
  }

  // 处理 SSE 缓冲中的完整行，同时兼容普通 JSON 响应
  private processSSELines(): void {
    // 检查是否是 SSE 格式（包含 data: 行）
    const hasSSEFormat = this.sseBuffer.includes('data: ');

    if (hasSSEFormat) {
      const lines = this.sseBuffer.split('\n');
      this.sseBuffer = lines.pop() ?? '';

      for (const line of lines) {
        const trimmed = line.trim();
        if (trimmed.startsWith('data: ')) {
          const payload = trimmed.substring(6);
          if (payload === '[DONE]') {
            return;
          }
          const delta = this.extractDelta(payload);
          if (delta.length > 0) {
            this.appendAiText(delta);
          }
        }
      }
    } else {
      // 尝试作为普通 JSON 解析（非 SSE 流式响应）
      const trimmed = this.sseBuffer.trim();
      if (trimmed.length > 0) {
        const content = this.extractDelta(trimmed);
        if (content.length > 0) {
          this.appendAiText(content);
        }
        this.sseBuffer = '';
      }
    }
  }

  // 从单条 SSE data 或普通 JSON 中提取文本内容
  private extractDelta(jsonStr: string): string {
    try {
      const obj = JSON.parse(jsonStr) as Record<string, Object>;
      const choices = obj['choices'];
      if (Array.isArray(choices) && choices.length > 0) {
        const first = choices[0] as Record<string, Object>;
        // SSE 流式格式：delta.content
        const delta = first['delta'] as Record<string, Object>;
        if (delta) {
          const content = delta['content'];
          if (typeof content === 'string') {
            return content;
          }
        }
        // 普通 JSON 格式：message.content
        const message = first['message'] as Record<string, Object>;
        if (message) {
          const content = message['content'];
          if (typeof content === 'string') {
            return content;
          }
        }
      }
      // 错误响应
      if (obj['error']) {
        const error = obj['error'] as Record<string, Object>;
        const errMsg = error['message'];
        if (typeof errMsg === 'string') {
          return `【API 错误】${errMsg}`;
        }
      }
    } catch (err) {
      console.error('JSON 解析失败:', err);
      console.error('原始字符串:', jsonStr);
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
      // ArkTS 中直接修改数组元素不会触发 UI 刷新，必须重新赋值数组
      const newMsg: ChatMessage = { role: 'ai', text: last.text + delta, time: last.time };
      const newList: ChatMessage[] = this.messageList.slice(0, -1);
      newList.push(newMsg);
      this.messageList = newList;
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
        // 加载中状态：转圈 + 提示文字
        Row({ space: 8 }) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color('#2e7d32')
          Text('AI 正在思考…')
            .fontSize(14)
            .fontColor('#40493d')
        }
        .aiBubbleStyle()
        .justifyContent(FlexAlign.Start)
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
      // placeholder居中 使用 padding 撑开高度，上下各留 15vp，总高度即为 14(字号) + 15*2 = 44vp（可根据需要微调）
        .padding({
          top: 15,
          bottom: 15,
          left: 12,
          right: 12
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
