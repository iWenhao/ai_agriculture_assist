// AI农技问答（聊天对话式，参照设计稿还原）

// http 1: 先导入
import { http } from '@kit.NetworkKit';
import { GLM_API_URL, GLM_MODEL, GLM_API_KEY, SYSTEM_PROMPT } from '../common/Constants';

// 消息角色
type MsgRole = 'user' | 'ai';

// 单条消息：用户消息用 text；AI 消息用 answer
interface ChatMessage {
  role: MsgRole;
  text: string;          // 用户消息文本（AI 消息为空）
  answer: AIAnswer | null; // AI 回答（用户消息为空）
  time: string;          // 显示时间
}

// AI 回答结构（对应设计稿：初步诊断 / 主要诱因 / 专家建议）
interface AIAnswer {
  diagnosis: string;     // 初步诊断
  detail: string;        // 诊断详细说明
  causes: string[];      // 主要诱因列表
  suggestions: string[]; // 专家建议列表
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
}

@Component
export struct Qna {
  // --- 设计稿配色（来自 DESIGN.md） ---
  private readonly C_PRIMARY: string = '#0d631b';          // 主色：农业深绿
  private readonly C_PRIMARY_CONTAINER: string = '#2e7d32';// 绿色气泡
  private readonly C_SECONDARY: string = '#f89c00';        // 金色：高价值AI洞察
  private readonly C_BG: string = '#f9f9f9';               // 背景冷灰
  private readonly C_GREEN_TINT: string = '#f1f8e9';       // AI卡片渐变浅绿
  private readonly C_CARD: string = '#f3f3f3';             // 小卡片背景
  private readonly C_TEXT: string = '#1a1c1c';             // 主文本
  private readonly C_TEXT_SUB: string = '#40493d';         // 次级文本
  private readonly C_OUTLINE: string = '#bfcaba';          // 分割线/时间

  // 底部推荐追问 chip（参照设计稿）
  private suggestChips: string[] = [
    '如何具体施药？',
    '预防下季感染？',
    '查看周边疫情'
  ];

  // --- 状态变量 ---
  @State messageList: ChatMessage[] = []; // 对话消息列表
  @State inputText: string = '';          // 输入框文本
  @State loading: boolean = false;        // 是否正在请求
  private scroller: Scroller = new Scroller();

  // 组件即将出现：放入欢迎语
  aboutToAppear(): void {
    this.messageList = [
      {
        role: 'ai',
        text: '',
        answer: {
          diagnosis: '您好，我是 AI 农技专家',
          detail: '无论是作物种植、水肥管理、病虫害防治还是农业技术咨询，都可以向我提问，我会为您提供专业的诊断与建议。',
          causes: ['支持病虫害症状识别与分析', '提供科学的田间管理建议'],
          suggestions: ['可直接输入您遇到的农技问题', '或点击下方推荐问题快速提问']
        },
        time: this.nowTime()
      }
    ];
  }

  // 获取当前时间字符串 HH:MM
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

    // 追加用户消息并清空输入框
    this.messageList.push({
      role: 'user',
      text: q,
      answer: null,
      time: this.nowTime()
    });
    this.inputText = '';
    this.loading = true;
    this.scrollToBottom();

    // 构造 GLM 请求体（带显式类型，符合 ArkTS 严格模式）
    const messages: GlmMessage[] = [{ role: 'system', content: SYSTEM_PROMPT }];
    // 把近几轮对话作为上下文带上（最多 6 条，避免超长）
    const recent = this.messageList.slice(-6);
    for (const msg of recent) {
      if (msg.role === 'user') {
        messages.push({ role: 'user', content: msg.text });
      } else if (msg.answer !== null) {
        messages.push({
          role: 'assistant',
          content: this.answerToText(msg.answer)
        });
      }
    }

    const requestBody: GlmRequestBody = {
      model: GLM_MODEL,
      messages: messages
    };

    // http 2: http.createHttp()创建连接
    const httpRequest = http.createHttp();
    let aiAnswer: AIAnswer;
    let errMsg = '';
    try {
      console.log('=====AI问答请求开始======');
      // http 3: 使用request 方法请求
      const response = await httpRequest.request(GLM_API_URL, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${GLM_API_KEY}`
        },
        extraData: JSON.stringify(requestBody)
      });
      console.log('AI问答结果>>>>>>', JSON.stringify(response));

      if (response.responseCode === 200) {
        const content = this.extractContent(response.result as string);
        if (content.length > 0) {
          aiAnswer = this.parseAnswer(content);
        } else {
          errMsg = 'AI 返回内容为空，请重试';
          aiAnswer = this.errorAnswer(errMsg);
        }
      } else {
        errMsg = `服务异常（${response.responseCode}），请稍后重试`;
        aiAnswer = this.errorAnswer(errMsg);
      }
    } catch (err) {
      console.error('AI问答请求失败', err);
      errMsg = '请求失败，请检查网络或 API Key 配置';
      aiAnswer = this.errorAnswer(errMsg);
    } finally {
      // 一定要销毁，减少内存开销
      httpRequest.destroy();
      this.loading = false;
    }

    // 追加 AI 消息
    this.messageList.push({
      role: 'ai',
      text: '',
      answer: aiAnswer,
      time: this.nowTime()
    });
    this.scrollToBottom();
  }

  // 把 AIAnswer 转成纯文本，用于多轮上下文
  private answerToText(a: AIAnswer): string {
    let s = `初步诊断：${a.diagnosis}。${a.detail}`;
    if (a.causes.length > 0) {
      s += '主要诱因：' + a.causes.join('；') + '。';
    }
    if (a.suggestions.length > 0) {
      s += '专家建议：' + a.suggestions.join('；') + '。';
    }
    return s;
  }

  // 错误兜底回答
  private errorAnswer(msg: string): AIAnswer {
    return {
      diagnosis: '暂时无法回答',
      detail: msg,
      causes: [],
      suggestions: []
    };
  }

  // 从智谱返回的 JSON 字符串中提取 message.content
  private extractContent(resultStr: string): string {
    try {
      const outer = JSON.parse(resultStr) as Record<string, Object>;
      const choices = outer['choices'];
      if (Array.isArray(choices) && choices.length > 0) {
        const first = choices[0] as Record<string, Object>;
        const message = first['message'] as Record<string, Object>;
        const content = message['content'];
        if (typeof content === 'string') {
          return content;
        }
      }
    } catch (err) {
      console.error('提取 content 失败', err);
    }
    return '';
  }

  // 从 AI 返回的 content 中解析出回答结构
  private parseAnswer(content: string): AIAnswer {
    try {
      // 去除可能存在的 ```json 或 ``` 代码块包裹
      const cleaned = content.replace(/```json/gi, '').replace(/```/g, '').trim();
      const obj = JSON.parse(cleaned) as Record<string, Object>;
      return {
        diagnosis: this.readStr(obj, 'diagnosis') || this.readStr(obj, 'analysis'),
        detail: this.readStr(obj, 'detail'),
        causes: this.readStrArray(obj, 'causes'),
        suggestions: this.readStrArray(obj, 'suggestions')
      };
    } catch (err) {
      console.error('回答JSON解析失败，使用原文兜底', err);
      // 解析失败时把原文整体放进诊断说明，保证不白屏
      return {
        diagnosis: 'AI 回复',
        detail: content,
        causes: [],
        suggestions: []
      };
    }
  }

  // 安全读取字符串字段
  private readStr(obj: Record<string, Object>, key: string): string {
    const val = obj[key];
    return typeof val === 'string' ? val : '';
  }

  // 安全读取字符串数组字段
  private readStrArray(obj: Record<string, Object>, key: string): string[] {
    const val = obj[key];
    if (Array.isArray(val)) {
      // 显式断言为对象数组，避免遍历 Object 时元素被推断为 any
      const items = val as Object[];
      const arr: string[] = [];
      for (const item of items) {
        if (typeof item === 'string') {
          arr.push(item);
        }
      }
      return arr;
    }
    // 兼容个别模型把数组返回成字符串的情况
    if (typeof val === 'string' && val.length > 0) {
      return [val];
    }
    return [];
  }

  // 滚动到底部
  private scrollToBottom(): void {
    // 延迟一帧，等列表刷新后再滚
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 50);
  }

  // ===== 顶部 Header =====
  @Builder
  Header() {
    Row({ space: 10 }) {
      // 左侧：圆形头像 + 标题
      Row({ space: 8 }) {
        // 头像（圆形绿色背景 + 叶子图标）
        Stack() {
          Text('🌾')
            .fontSize(18)
        }
        .width(32)
        .height(32)
        .borderRadius(16)
        .backgroundColor(this.C_PRIMARY_CONTAINER)
        .alignContent(Alignment.Center)

        Text('AI农技问答')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.C_PRIMARY)
      }

      Blank() // 中间撑开

      // 右侧：通知铃铛
      Text('🔔')
        .fontSize(22)
        .padding(6)
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 12 })
    .backgroundColor(this.C_BG)
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: 1 }, color: '#EEEEEE' })
  }

  // ===== 用户消息气泡（绿色，靠右） =====
  @Builder
  UserBubble(msg: ChatMessage) {
    Column({ space: 4 }) {
      Text(msg.text)
        .fontSize(15)
        .fontColor('#FFFFFF')
        .lineHeight(22)
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(this.C_PRIMARY_CONTAINER)
        .borderRadius({ topLeft: 12, topRight: 12, bottomLeft: 12, bottomRight: 0 })
        .constraintSize({ maxWidth: '80%' })
      Text(msg.time)
        .fontSize(11)
        .fontColor(this.C_OUTLINE)
    }
    .alignItems(HorizontalAlign.End)
  }

  // ===== AI 消息卡片（渐变白，靠左，三段式） =====
  @Builder
  AiCard(msg: ChatMessage) {
    Column({ space: 4 }) {
      // “AI 农技专家” 标签
      Row({ space: 6 }) {
        Stack() {
          Text('✦')
            .fontSize(13)
            .fontColor('#FFFFFF')
        }
        .width(20)
        .height(20)
        .borderRadius(6)
        .backgroundColor(this.C_SECONDARY)
        .alignContent(Alignment.Center)

        Text('AI 农技专家')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.C_PRIMARY)
      }

      // 卡片主体
      Column({ space: 12 }) {
        // 第一段：初步诊断（verified 图标 + 标题 + 说明）
        Row({ space: 10 }) {
          Text('✔')
            .fontSize(16)
            .fontColor(this.C_PRIMARY)
          Column({ space: 4 }) {
            Text(`初步诊断：${msg.answer!.diagnosis}`)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.C_PRIMARY)
            if (msg.answer!.detail.length > 0) {
              Text(msg.answer!.detail)
                .fontSize(13)
                .fontColor(this.C_TEXT_SUB)
                .lineHeight(20)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .alignItems(VerticalAlign.Top)

        // 第二段：主要诱因（左橙色边框小卡）
        if (msg.answer!.causes.length > 0) {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text('⚠')
                .fontSize(13)
                .fontColor(this.C_SECONDARY)
              Text('主要诱因')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.C_TEXT)
            }
            ForEach(msg.answer!.causes, (c: string) => {
              Row({ space: 8 }) {
                Text('•')
                  .fontSize(13)
                  .fontColor(this.C_SECONDARY)
                Text(c)
                  .fontSize(13)
                  .fontColor(this.C_TEXT_SUB)
                  .lineHeight(20)
                  .layoutWeight(1)
              }
              .alignItems(VerticalAlign.Top)
            })
          }
          .width('100%')
          .padding(10)
          .backgroundColor(this.C_CARD)
          .borderRadius(8)
          .border({ width: { left: 4 }, color: this.C_SECONDARY })
        }

        // 第三段：专家建议（左绿色边框小卡）
        if (msg.answer!.suggestions.length > 0) {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text('★')
                .fontSize(13)
                .fontColor(this.C_PRIMARY)
              Text('专家建议')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.C_TEXT)
            }
            ForEach(msg.answer!.suggestions, (s: string) => {
              Row({ space: 8 }) {
                Text('✓')
                  .fontSize(13)
                  .fontColor(this.C_PRIMARY)
                Text(s)
                  .fontSize(13)
                  .fontColor(this.C_TEXT_SUB)
                  .lineHeight(20)
                  .layoutWeight(1)
              }
              .alignItems(VerticalAlign.Top)
            })
          }
          .width('100%')
          .padding(10)
          .backgroundColor(this.C_CARD)
          .borderRadius(8)
          .border({ width: { left: 4 }, color: this.C_PRIMARY })
        }
      }
      .width('100%')
      .padding(14)
      .backgroundColor(this.C_GREEN_TINT)
      .borderRadius({ topLeft: 0, topRight: 12, bottomLeft: 12, bottomRight: 12 })

      Text(msg.time)
        .fontSize(11)
        .fontColor(this.C_OUTLINE)
    }
    .alignItems(HorizontalAlign.Start)
    .constraintSize({ maxWidth: '88%' })
  }

  // ===== 单条消息：根据角色选择气泡 =====
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
        this.AiCard(msg)
        Blank()
      }
      .width('100%')
    }
  }

  // ===== 底部输入栏 =====
  @Builder
  InputBar() {
    Column() {
      // 推荐追问 chip（横向滚动）
      Scroll() {
        Row({ space: 10 }) {
          ForEach(this.suggestChips, (chip: string) => {
            Text(chip)
              .fontSize(12)
              .fontColor(this.C_TEXT_SUB)
              .backgroundColor('#e8e8e8')
              .border({ width: 1, color: this.C_OUTLINE })
              .borderRadius(16)
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .onClick(() => {
                this.inputText = chip;
                this.onSend();
              })
          })
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .padding({ top: 8, bottom: 8 })

      // 输入框 + 发送按钮
      Row({ space: 10 }) {
        Row({ space: 8 }) {
          TextArea({
            placeholder: '咨询农技难题...',
            text: this.inputText
          })
            .layoutWeight(1)
            .fontSize(14)
            .fontColor(this.C_TEXT)
            .placeholderColor('#AAAAAA')
            .backgroundColor(this.C_CARD)
            .borderRadius(12)
            .onChange((value: string) => {
              this.inputText = value;
            })

          // 麦克风（占位装饰）
          Text('🎤')
            .fontSize(20)
            .padding(6)
        }
        .layoutWeight(1)
        .height(48)
        .padding({ left: 12, right: 8 })
        .backgroundColor(this.C_CARD)
        .borderRadius(12)
        .alignItems(VerticalAlign.Center)

        // 发送按钮（绿色）
        Stack() {
          Text('➤')
            .fontSize(20)
            .fontColor('#FFFFFF')
        }
        .width(48)
        .height(48)
        .backgroundColor(this.C_PRIMARY_CONTAINER)
        .borderRadius(12)
        .alignContent(Alignment.Center)
        .opacity((this.inputText.trim().length > 0 && !this.loading) ? 1 : 0.5)
        .onClick(() => this.onSend())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 12 })
      .alignItems(VerticalAlign.Center)
    }
    .backgroundColor(this.C_BG)
    .border({ width: { top: 1 }, color: '#EEEEEE' })
  }

  build() {
    Column() {
      // 顶部标题栏
      this.Header()

      // 消息列表（可滚动）
      List({ space: 16, scroller: this.scroller }) {
        ForEach(this.messageList, (msg: ChatMessage) => {
          ListItem() {
            this.MessageItem(msg)
          }
        })

        // 加载中：追加一条 AI 占位消息
        if (this.loading) {
          ListItem() {
            Row() {
              Column({ space: 4 }) {
                Row({ space: 6 }) {
                  Stack() {
                    Text('✦')
                      .fontSize(13)
                      .fontColor('#FFFFFF')
                  }
                  .width(20)
                  .height(20)
                  .borderRadius(6)
                  .backgroundColor(this.C_SECONDARY)
                  .alignContent(Alignment.Center)
                  Text('AI 农技专家')
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.C_PRIMARY)
                }
                Row({ space: 8 }) {
                  LoadingProgress()
                    .width(20)
                    .height(20)
                    .color(this.C_PRIMARY)
                  Text('AI 正在分析中…')
                    .fontSize(13)
                    .fontColor(this.C_TEXT_SUB)
                }
                .width('100%')
                .padding(16)
                .backgroundColor(this.C_GREEN_TINT)
                .borderRadius({ topLeft: 0, topRight: 12, bottomLeft: 12, bottomRight: 12 })
              }
              .alignItems(HorizontalAlign.Start)
              .constraintSize({ maxWidth: '88%' })
              Blank()
            }
            .width('100%')
          }
        }
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 12, right: 12, top: 14, bottom: 14 })
      .scrollBar(BarState.Auto)

      // 底部输入栏
      this.InputBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.C_BG)
  }
}
