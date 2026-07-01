// AI农技问答组件
import { http } from '@kit.NetworkKit';
import { AGINES_API_URL, AGINES_MODEL, AGINES_API_KEY, SYSTEM_PROMPT } from '../common/Constants';
import { nowTime, extractDelta, stripMarkdown } from '../common/Utils'

// 消息角色类型定义
type MsgRole = 'user' | 'ai';

// 单条消息的数据结构
interface ChatMessage {
  role: MsgRole;  // 角色
  text: string; // 消息内容
  time: string // 时间戳
}

// 适配后端API的消息结构
interface AginesMessage {
  role: string;
  content: string;
}

// 请求体结构
interface AginesRequestBody {
  model: string;
  messages: AginesMessage[];
  stream?: boolean; // 是否开启流式
}

@Component
export struct Qna {
  // --- 状态变量与控制器 ---
  @State messageList: ChatMessage[] = []; // 聊天消息列表
  @State inputText: string = ''; // 输入框内容
  @State loading: boolean = false; // 加载状态（防止重复提交）
  private scroller: Scroller = new Scroller(); // 列表滚动控制器

  // 组件即将出现时的生命周期
  aboutToAppear(): void {
    // 初始化：推入一条AI的欢迎语
    this.messageList.push({
      role: 'ai',
      text: '您好，我是 AI 农技专家。无论是作物种植、水肥管理、病虫害防治还是农业技术咨询，都可以向我提问。',
      time: nowTime()
    });
  }

  // --- 业务逻辑：发送请求 ---
  private async onSend(): Promise<void> {  // 无返回值的异步执行网络请求
    const q = this.inputText.trim();
    // 防呆处理：内容为空或正在加载时直接返回
    if (q.length === 0 || this.loading) {
      return;
    }

    // 1. 更新UI：添加用户消息
    this.messageList.push({ role: 'user', text: q, time: nowTime() });
    this.inputText = '';
    this.loading = true;

    // 2. 更新UI：添加一条空的AI消息
    // 为什么？
    /*   解决“状态管理”的痛点（最核心原因）
    在 ArkUI中，如果我们不提前创建这条消息，而是等网络数据第一次返回时再往列表里 push 一条新消息，会引发严重的 UI 刷新问题：
    如果不提前占坑：每次收到一小块数据（比如一个字），你都需要执行 push 操作。这会导致列表频繁地新增节点，不仅性能极差，还会导致列表闪烁或滚动卡顿。
    提前占坑的好处：我们在发送请求前，就 push 了一条 text: '' 的空消息。这样列表的结构就已经固定了。后续网络返回数据时，我们只需要修改最后一条数据的 text 属性（即 appendAiText 方法），而不会触发列表的增删操作，UI 刷新会非常丝滑。
         提供即时的“加载反馈”（用户体验）
    网络请求是需要时间的（哪怕只有 0.5 秒）。
    如果等数据返回了才显示气泡，用户点击发送后，界面会“僵死”半秒钟，体验很差。
    提前推入一条空消息，我们的 UI 可以立刻判断：如果 msg.text.length === 0，就显示一个 LoadingProgress（转圈圈）和“AI 正在思考…”的提示。这能给用户一个即时的视觉反馈，让他们知道系统正在工作。*/
    const aiTime = nowTime();
    this.messageList.push({ role: 'ai', text: '', time: aiTime });
    this.scrollToBottom(); // 滚动到聊天底部
    // 3. 构造请求体 (只保留最近6条消息，防止上下文过长)
     const messages: AginesMessage[] = [{ role: 'system', content: SYSTEM_PROMPT }];
     const recent = this.messageList.slice(-6); // 取最后6条
     for (const msg of recent) {
       // 将 'ai' 角色映射为 'assistant' 以符合OpenAI/Agines格式
       messages.push({ role: msg.role === 'ai' ? 'assistant' : msg.role, content: msg.text });
     }

     const requestBody: AginesRequestBody = {
       model: AGINES_MODEL,
       messages
     };

     try {
       // 调用非流式请求方法（为了解决预览器兼容性及类型报错）
       await this.sendNormalRequest(requestBody);
     } catch (err) {
       console.error('=====请求失败=====', err);
       this.loading = false;
     }
  }

  // --- 网络请求：非流式 ---
  private async sendNormalRequest(requestBody: AginesRequestBody): Promise<void> {
    const httpRequest = http.createHttp();
    try {
      const normalBody: AginesRequestBody = {
        model: requestBody.model,
        messages: requestBody.messages,
        stream: false  // 强制设为非流式请求
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
        // 处理响应数据类型
        if (typeof response.result === 'string') {
          resultStr = response.result;
        } else if (response.result) {
          resultStr = JSON.stringify(response.result);
        }

        // 提取文本内容
        const content = extractDelta(resultStr);
        if (content.length > 0) {
          this.appendAiText(content);
        } else {
          this.appendAiText('（未获取到有效回答）');
        }
      } else {
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

  // --- 工具方法 ---

  // 追加AI文字（核心：UI刷新）
  private appendAiText(delta: string): void {
    if (this.messageList.length === 0) {
      return;
    }
    const last = this.messageList[this.messageList.length - 1];
    if (last.role === 'ai') {
      // ArkTS状态更新机制：必须创建新对象并重新赋值数组才能触发UI刷新
      const newMsg: ChatMessage = {
        role: 'ai',
        text: last.text + delta,
        time: last.time
      };
      const newList: ChatMessage[] = this.messageList.slice(0, -1);
      newList.push(newMsg);
      this.messageList = newList; // 触发UI重绘
      this.scrollToBottom();
    }
  }

  // 滚动到底部
  private scrollToBottom(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 50);
  }

  // --- UI 组件定义 ---
  // 用户气泡 (绿色，靠右)
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
    .alignItems(HorizontalAlign.End) // 靠右对齐
  }

  // AI气泡公共样式
  @Styles  // 定义组件重用样式的装饰器
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
    .constraintSize({ maxWidth: '88%' }) //为组件设置一个约束尺寸，规定它的最大宽度不能超过其父容器宽度的 88%
    .shadow({ radius: 4, color: 'rgba(0,0,0,0.05)', offsetY: 2 })
  }

  // AI 气泡 (白色，靠左)
  @Builder
  AiBubble(msg: ChatMessage) {
    Column({ space: 4 }) {
      // 根据文本是否为空显示加载状态或正常内容
      if (msg.text.length === 0) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color('#2e7d32')
          Text('AI 农技专家正在思考…')
            .fontSize(14)
            .fontColor('#40493d')
        }
        .aiBubbleStyle()
        .justifyContent(FlexAlign.Start)
      } else {
        Text(stripMarkdown(msg.text))
          .fontSize(15)
          .fontColor('#1a1c1c')
          .lineHeight(22)
          .aiBubbleStyle()
      }

      Text(msg.time)
        .fontSize(11)
        .fontColor('#bfcaba')
    }
    .alignItems(HorizontalAlign.Start) // 靠左对齐
  }

  // 消息项（根据角色分发）
  @Builder
  MessageItem(msg: ChatMessage) {
    if (msg.role === 'user') {
      Row() {
        // Blank() 是一个特殊的弹性间隔组件，它本身不显示任何内容，但它的核心作用是自动撑满父容器内未被其他子组件占用的剩余空间
        Blank() // 占位符，推到右侧
        this.UserBubble(msg)
      }
      .width('100%')
    } else {
      Row() {
        this.AiBubble(msg)
        Blank() // 占位符，推到左侧
      }
      .width('100%')
    }
  }

  // 底部输入栏
  @Builder
  InputBar() {
    Row({ space: 10 }) {
      // TextArea：多行输入框
      // 使用 padding 撑开高度以实现 placeholder 垂直居中
      TextArea({ placeholder: '咨询农技难题...', text: this.inputText })
        .padding({
          top: 15,
          bottom: 15,
          left: 12,
          right: 12
        })
        .layoutWeight(1) // 占满
        .fontSize(14)
        .fontColor('#1a1c1c')
        .placeholderColor('#AAAAAA')
        .backgroundColor('#f3f3f3')
        .borderRadius(12)
        .onChange((value: string) => {
          this.inputText = value;
        })

      // 发送按钮
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
      // 按钮状态：有内容且非加载态时才可点击
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

  // 页面主结构
  build() {
    Column() {
      // 消息列表
      // Scroller 控制器
      // this.scroller.scrollEdge(Edge.Bottom);
     /* Edge.Top：滚动到顶部（在垂直滚动中，Edge.Start 的效果与 Edge.Top 完全相同）。
      Edge.Bottom：滚动到底部（在垂直滚动中，Edge.End 的效果与 Edge.Bottom 完全相同）。
      Edge.Start：滚动到起始边缘（如果是横向滚动，就是最左侧）。
      Edge.End：滚动到结束边缘（如果是横向滚动，就是最右侧）。*/
      List({ space: 16, scroller: this.scroller }) {
        ForEach(this.messageList, (msg: ChatMessage) => {
          ListItem() {
            this.MessageItem(msg)
          }
        })
      }
      .layoutWeight(1) // 占满上部空间
      .height('100%')
      .width('100%')
      .padding({
        left: 12,
        right: 12,
        top: 14,
        bottom: 14
      })
      .scrollBar(BarState.Auto)

      // 输入栏
      this.InputBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#f9f9f9')
  }
}