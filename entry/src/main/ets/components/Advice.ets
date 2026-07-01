// 智能种植顾问
import { http } from '@kit.NetworkKit';
import { AGINES_API_URL, AGINES_MODEL, AGINES_API_KEY, ADVICE_PROMPT } from '../common/Constants';
import { nowTime, extractDelta, stripMarkdown } from '../common/Utils'

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

// 建议结果项（四类建议）
interface AdviceResult {
  content: string;  // 建议正文
  time: string      // 生成时间
}

@Component
export struct Advice {
  // --- 表单状态 ---
  @State cropTypeIndex: number = -1;          // 作物类型选中下标
  @State growthStageIndex: number = -1;       // 生长阶段选中下标
  @State plantDate: string = '';              // 种植时间
  @State problemText: string = '';            // 当前问题描述

  // --- 结果状态 ---
  @State loading: boolean = false;            // 是否正在生成
  @State adviceResult: AdviceResult | null = null;  // 生成的建议

  // 作物类型选项（使用 ArkUI 内置 SelectOption 类型，避免结构化类型报错）
  private cropTypeOptions: SelectOption[] = [
    { value: '小麦' }, { value: '玉米' }, { value: '水稻' },
    { value: '大豆' }, { value: '棉花' }, { value: '番茄' },
    { value: '黄瓜' }, { value: '苹果' }, { value: '柑橘' },
    { value: '草莓' }, { value: '辣椒' }, { value: '其他' }
  ];

  // 生长阶段选项
  private growthStageOptions: SelectOption[] = [
    { value: '萌芽期' }, { value: '苗期' }, { value: '分蘖/分枝期' },
    { value: '拔节/抽蔓期' }, { value: '开花期' }, { value: '结果/灌浆期' },
    { value: '成熟期' }
  ];

  // --- 业务逻辑：生成种植建议 ---
  private async onGenerate(): Promise<void> {
    // 防呆：加载中直接返回
    if (this.loading) {
      return;
    }

    // 校验：作物类型、生长阶段、种植时间、当前问题均为必填
    if (this.cropTypeIndex < 0 || this.growthStageIndex < 0
      || this.plantDate.trim().length === 0 || this.problemText.trim().length === 0) {
      return;
    }

    this.loading = true;
    this.adviceResult = null;

    // 1. 拼装用户输入信息
    const cropName = this.cropTypeOptions[this.cropTypeIndex].value as string;
    const stageName = this.growthStageOptions[this.growthStageIndex].value as string;
    const date = this.plantDate.trim();
    const problem = this.problemText.trim();

    const userContent: string =
      `作物种类：${cropName}\n` +
      `生长阶段：${stageName}\n` +
      `种植时间：${date}\n` +
      `当前问题：${problem}`;

    // 2. 构造请求体（前置专属系统提示词）
    const messages: AginesMessage[] = [
      { role: 'system', content: ADVICE_PROMPT },
      { role: 'user', content: userContent }
    ];
    const requestBody: AginesRequestBody = {
      model: AGINES_MODEL,
      messages
    };

    try {
      await this.sendNormalRequest(requestBody);
    } catch (err) {
      console.error('=====种植建议生成失败=====', err);
      this.loading = false;
    }
  }

  // --- 网络请求：非流式（与 Qna 组件保持一致，预览器兼容） ---
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
        if (typeof response.result === 'string') {
          resultStr = response.result;
        } else if (response.result) {
          resultStr = JSON.stringify(response.result);
        }

        const content = extractDelta(resultStr);
        this.adviceResult = {
          content: content.length > 0 ? stripMarkdown(content) : '（未获取到有效建议）',
          time: nowTime()
        };
      } else {
        this.adviceResult = {
          content: `生成失败，状态码: ${response.responseCode}`,
          time: nowTime()
        };
      }
    } catch (err) {
      console.error('种植建议请求失败', err);
      this.adviceResult = {
        content: '生成失败，请检查网络或 API Key 配置',
        time: nowTime()
      };
    } finally {
      httpRequest.destroy();
      this.loading = false;
    }
  }

  // --- UI 组件定义 ---

  // 表单字段标题行（左侧标题，右侧必填星号）
  @Builder
  FieldLabel(title: string, required: boolean) {
    Row() {
      Text(title)
        .fontSize(14)
        .fontColor('#333333')
      if (required) {
        Text(' *')
          .fontSize(14)
          .fontColor('#E53935')
      }
    }
  }

  // 结果中按"【】"标题切分渲染为分段卡片
  @Builder
  ResultSection(title: string, body: string) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#2e7d32')
        .width('100%')

      Text(body)
        .fontSize(14)
        .fontColor('#444444')
        .lineHeight(22)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 建议结果卡片
  @Builder
  AdviceResultCard() {
    Column({ space: 12 }) {
      // 卡片标题
      Row() {
        Text('🌱 个性化种植管理建议')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1a1c1c')
          .width('100%')
        Text(this.adviceResult!.time)
          .fontSize(11)
          .fontColor('#bfcaba')
          .width('100%')
          .margin({ top: -6 })
      }

      // 分割线
      Divider()
        .color('#eeeeee')
        .strokeWidth(1)
        .width('100%')

      // 正文：尝试按【】标题切分，渲染为四段；若格式不匹配则整体展示
      if (this.adviceResult!.content.length === 0) {
        Text('（暂无内容）')
          .fontSize(14)
          .fontColor('#999999')
          .width('100%')
      } else if (this.splitSections(this.adviceResult!.content).length > 0) {
        ForEach(this.splitSections(this.adviceResult!.content), (sec: string) => {
          this.ResultSection(this.extractTitle(sec), this.extractBody(sec))
        })
      } else {
        Text(this.adviceResult!.content)
          .fontSize(14)
          .fontColor('#444444')
          .lineHeight(22)
          .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .shadow({ radius: 6, color: 'rgba(0,0,0,0.06)', offsetY: 2 })
  }

  // --- 文本切分工具方法 ---
  // 按"【...】"将整段建议切分为多个小节字符串（含标题）
  private splitSections(text: string): string[] {
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
  private extractTitle(section: string): string {
    const start = section.indexOf('【');
    const end = section.indexOf('】');
    if (start >= 0 && end > start) {
      return section.substring(start, end + 1);
    }
    return '【建议】';
  }

  // 从小节字符串中去掉标题，得到正文
  private extractBody(section: string): string {
    const end = section.indexOf('】');
    if (end >= 0) {
      return section.substring(end + 1).trim();
    }
    return section.trim();
  }

  // 将 DatePicker 选中的年月日格式化为 YYYY-MM-DD
  private formatDate(year: number, month: number, day: number): string {
    const m = (month + 1).toString().padStart(2, '0');
    const d = day.toString().padStart(2, '0');
    return `${year}-${m}-${d}`;
  }

  // 弹出系统日期选择器
  private showDatePicker(): void {
    DatePickerDialog.show({
      start: new Date('2020-01-01'),
      end: new Date(),
      selected: new Date(),
      onAccept: (value: DatePickerResult) => {
        this.plantDate = this.formatDate(value.year, value.month, value.day);
      }
    });
  }

  // --- 页面主结构 ---
  build() {
      // 可滚动表单区域
      Scroll() {
        Column({ space: 16 }) {

          // 作物状况信息卡片
          Column({ space: 16 }) {
            Text('作物状况信息')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor('#2e7d32')
              .width('100%')

            // 作物类型 + 生长阶段（同一行）
            Row({ space: 12 }) {
              // 作物类型（必填）
              Column({ space: 8 }) {
                this.FieldLabel('作物类型', true)
                Select(this.cropTypeOptions)
                  .selected(this.cropTypeIndex)
                  .value(this.cropTypeIndex >= 0
                    ? this.cropTypeOptions[this.cropTypeIndex].value as string
                    : '请选择作物类型')
                  .width('100%')
                  .font({ size: 14 })
                  .fontColor('#1a1c1c')
                  .selectedOptionFont({ size: 14, weight: FontWeight.Bold })
                  .optionFont({ size: 14 })
                  .backgroundColor('#f7f8f5')
                  .borderRadius(8)
                  .divider({ strokeWidth: 0 })
                  .onSelect((index: number) => {
                    this.cropTypeIndex = index;
                  })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              // 生长阶段（必填）
              Column({ space: 8 }) {
                this.FieldLabel('生长阶段', true)
                Select(this.growthStageOptions)
                  .selected(this.growthStageIndex)
                  .value(this.growthStageIndex >= 0
                    ? this.growthStageOptions[this.growthStageIndex].value as string
                    : '请选择生长阶段')
                  .width('100%')
                  .font({ size: 14 })
                  .fontColor('#1a1c1c')
                  .selectedOptionFont({ size: 14, weight: FontWeight.Bold })
                  .optionFont({ size: 14 })
                  .backgroundColor('#f7f8f5')
                  .borderRadius(8)
                  .divider({ strokeWidth: 0 })
                  .onSelect((index: number) => {
                    this.growthStageIndex = index;
                  })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')

            // 种植时间（必填，点击弹出日期选择器）
            Column({ space: 8 }) {
              this.FieldLabel('种植时间', true)
              Row() {
                Text(this.plantDate.length > 0 ? this.plantDate : '点击选择播种日期')
                  .fontSize(14)
                  .fontColor(this.plantDate.length > 0 ? '#1a1c1c' : '#AAAAAA')
                  .layoutWeight(1)
              }
              .width('100%')
              .height(44)
              .padding({ left: 12, right: 12 })
              .backgroundColor('#f7f8f5')
              .borderRadius(8)
              .alignItems(VerticalAlign.Center)
              .onClick(() => this.showDatePicker())
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            // 当前问题（必填，多行）
            Column({ space: 8 }) {
              this.FieldLabel('当前问题', true)
              TextArea({ placeholder: '描述作物当前表现，如叶片发黄、长势缓慢、疑似病害等...', text: this.problemText })
                .width('100%')
                .height(96)
                .fontSize(14)
                .fontColor('#1a1c1c')
                .placeholderColor('#AAAAAA')
                .placeholderFont({ size: 14 })
                .backgroundColor('#f7f8f5')
                .borderRadius(8)
                .onChange((value: string) => {
                  this.problemText = value;
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .shadow({ radius: 4, color: 'rgba(0,0,0,0.04)', offsetY: 1 })

          // 生成按钮（必填项校验通过且非加载态时可点击）
          Button(this.loading ? '正在生成建议...' : '生成种植管理建议')
            .type(ButtonType.Capsule)
            .width('100%')
            .height(48)
            .fontSize(15)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Bold)
            .backgroundColor('#2e7d32')
            .opacity((this.cropTypeIndex >= 0 && this.growthStageIndex >= 0
              && this.plantDate.trim().length > 0 && this.problemText.trim().length > 0
              && !this.loading) ? 1 : 0.5)
            .enabled(this.cropTypeIndex >= 0 && this.growthStageIndex >= 0
              && this.plantDate.trim().length > 0 && this.problemText.trim().length > 0
              && !this.loading)
            .onClick(() => this.onGenerate())

          // 加载中提示
          if (this.loading) {
            Row({ space: 8 }) {
              LoadingProgress()
                .width(20)
                .height(20)
                .color('#2e7d32')
              Text('AI 农技专家正在生成专属建议…')
                .fontSize(14)
                .fontColor('#40493d')
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 4, bottom: 4 })
          }

          // 结果卡片
          if (this.adviceResult !== null && !this.loading) {
            this.AdviceResultCard()
          }

          // 底部留白
          Blank().height(8)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 20 })
      }
      .layoutWeight(1)
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
  }
}
