// AI农技问答

// http 1: 先导入
import { http } from '@kit.NetworkKit';
import { GLM_API_URL, GLM_MODEL, GLM_API_KEY, SYSTEM_PROMPT } from '../common/Constants';

// 快捷标签项
interface QuickTag {
  label: string,
  question: string
}

// AI 回答结构（对应需求文档的四项内容）
interface AIAnswer {
  analysis: string;   // 分析结果
  cause: string;      // 产生原因
  suggestion: string; // 处理建议
  notice: string;     // 注意事项
}

// GLM 请求消息
interface ChatMessage {
  role: string;
  content: string;
}

// GLM 请求体
interface ChatRequestBody {
  model: string;
  messages: ChatMessage[];
}

@Component
export struct Qna {
  // 快捷问题标签，点击自动填入示例问题
  private quickTags: QuickTag[] = [
    { label: '种植管理', question: '玉米在拔节期应该如何进行田间管理？' },
    { label: '水肥管理', question: '番茄结果期应该怎样科学施肥和浇水？' },
    { label: '病虫害防治', question: '水稻叶片上出现黄色斑点可能是什么病害？该如何防治？' },
    { label: '技术咨询', question: '大棚蔬菜种植有哪些关键的环境调控技术？' },
    { label: '基础知识', question: '什么是作物的营养生长期和生殖生长期？' }
  ]

  // --- 状态变量 ---
  @State question: string = '';        // 用户输入的问题
  @State answer: AIAnswer | null = null; // AI 返回的回答
  @State loading: boolean = false;     // 是否正在请求
  @State errorMsg: string = '';        // 错误提示

  // 输入框控制器，提升为成员避免每次重建
  private textAreaCtrl: TextAreaController = new TextAreaController();

  // 点击快捷标签：自动填入对应示例问题
  private onTagClick(item: QuickTag): void {
    this.question = item.question;
  }

  // 提交提问
  private async onAsk(): Promise<void> {
    const q = this.question.trim();
    if (q.length === 0) {
      this.errorMsg = '请输入您要咨询的农技问题';
      return;
    }

    // 切换为加载状态，清空旧结果
    this.loading = true;
    this.errorMsg = '';
    this.answer = null;

    // 构造 GLM 请求体（带显式类型，符合 ArkTS 严格模式）
    const requestBody: ChatRequestBody = {
      model: GLM_MODEL,
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'user', content: q }
      ]
    };

    // http 2: http.createHttp()创建连接
    const httpRequest = http.createHttp();
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
        // 解析智谱返回的外层结构，取出 message.content
        const content = this.extractContent(response.result as string);
        if (content.length > 0) {
          // 解析 content 中的 JSON
          this.answer = this.parseAnswer(content);
        } else {
          this.errorMsg = 'AI 返回内容为空，请重试';
        }
      } else {
        this.errorMsg = `服务异常（${response.responseCode}），请稍后重试`;
      }
    } catch (err) {
      console.error('AI问答请求失败', err);
      this.errorMsg = '请求失败，请检查网络或 API Key 配置';
    } finally {
      // 一定要销毁，减少内存开销
      httpRequest.destroy();
      this.loading = false;
    }
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
      // 使用类型守卫逐字段安全提取
      return {
        analysis: this.readStr(obj, 'analysis'),
        cause: this.readStr(obj, 'cause'),
        suggestion: this.readStr(obj, 'suggestion'),
        notice: this.readStr(obj, 'notice')
      };
    } catch (err) {
      console.error('回答JSON解析失败，使用原文兜底', err);
      // 解析失败时把原文整体放进分析结果，保证不白屏
      return {
        analysis: content,
        cause: '',
        suggestion: '',
        notice: ''
      };
    }
  }

  // 安全读取对象中的字符串字段，非字符串一律返回空串
  private readStr(obj: Record<string, Object>, key: string): string {
    const val = obj[key];
    return typeof val === 'string' ? val : '';
  }

  // 单张回答卡片：左侧色条 + 标题 + 内容
  @Builder
  AnswerCard(title: string, content: string, barColor: ResourceColor) {
    // 空内容不展示该卡片
    if (content.length > 0) {
      Row({ space: 8 }) {
        Column({ space: 6 }) {
          Text(title)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
          Text(content)
            .fontSize(13)
            .fontColor('#555555')
            .lineHeight(22)
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({
        left: 14,
        right: 14,
        top: 12,
        bottom: 12
      })
      .backgroundColor('#FFFFFF')
      .borderRadius(10)
      // 左侧色条样式，参照首页农事建议卡片
      .border({
        width: { left: 4 },
        color: barColor
      })
    }
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        // 标题区
        Column({ space: 6 }) {
          Text('AI 农技问答')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#0D631B')
          Text('输入生产问题，获取智能分析与建议')
            .fontSize(12)
            .fontColor('#999999')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 快捷问题标签区
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.quickTags, (item: QuickTag) => {
            Text(item.label)
              .fontSize(13)
              .fontColor('#0D631B')
              .backgroundColor('#E8F5E9')
              .borderRadius(16)
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .margin({ right: 8, bottom: 8 })
              .onClick(() => this.onTagClick(item))
          })
        }
        .width('100%')

        // 输入区
        Column({ space: 10 }) {
          TextArea({
            placeholder: '请描述您遇到的农技问题，如病虫害、水肥、种植管理等…',
            controller: this.textAreaCtrl
          })
            .height(120)
            .fontSize(14)
            .borderRadius(10)
            .backgroundColor('#FFFFFF')
            .placeholderColor('#BBBBBB')
            .onChange((value: string) => {
              this.question = value;
            })

          Button('提 问')
            .width('100%')
            .height(46)
            .fontSize(16)
            .fontColor('#FFFFFF')
            .backgroundColor('#0D631B')
            .borderRadius(10)
            // 加载中或无输入时禁用，避免重复请求
            .enabled(!this.loading && this.question.trim().length > 0)
            .opacity((!this.loading && this.question.trim().length > 0) ? 1 : 0.6)
            .onClick(() => this.onAsk())
        }
        .width('100%')

        // 回答区：根据状态切换渲染
        if (this.loading) {
          // 加载中
          Row({ space: 10 }) {
            LoadingProgress()
              .width(28)
              .height(28)
              .color('#0D631B')
            Text('AI 正在分析中…')
              .fontSize(14)
              .fontColor('#666666')
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding(40)
        } else if (this.errorMsg.length > 0) {
          // 错误提示
          Text(this.errorMsg)
            .width('100%')
            .fontSize(14)
            .fontColor('#D32F2F')
            .backgroundColor('#FFEBEE')
            .borderRadius(10)
            .padding(16)
            .textAlign(TextAlign.Center)
        } else if (this.answer !== null) {
          // 回答卡片：分析结果 / 产生原因 / 处理建议 / 注意事项
          Column({ space: 12 }) {
            this.AnswerCard('分析结果', this.answer.analysis, '#0D631B')
            this.AnswerCard('产生原因', this.answer.cause, '#FF9E00')
            this.AnswerCard('处理建议', this.answer.suggestion, '#1976D2')
            this.AnswerCard('注意事项', this.answer.notice, '#D32F2F')
          }
          .width('100%')
        } else {
          // 初始空态提示
          Text('点击上方标签或输入问题，开始向 AI 提问')
            .width('100%')
            .fontSize(13)
            .fontColor('#999999')
            .textAlign(TextAlign.Center)
            .padding(30)
        }
      }
      .width('100%')
      .backgroundColor('#F5F5F5')
      .padding({
        top: 12,
        bottom: 12,
        left: 12,
        right: 12
      })
    }
    .width('100%')
    .height('100%')
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
  }
}
