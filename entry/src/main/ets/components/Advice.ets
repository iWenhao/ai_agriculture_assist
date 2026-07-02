/**
 * @file Advice.ets
 * @description 智能种植顾问模块
 *
 * 功能概述：
 * 用户填写作物种类、生长阶段、种植时间及当前问题四个必填字段，
 * 调用 Agines 大模型生成个性化种植管理建议，并将结果按【】标题分段渲染为卡片。
 *
 * 依赖项：
 * - Constants: 模型名称(AGINES_MODEL)与系统提示词(ADVICE_PROMPT)
 * - Utils: 时间格式化、Markdown清洗、文本分段提取、API请求封装等工具函数
 */
import { AGINES_MODEL, ADVICE_PROMPT } from '../common/Constants';
import {
  nowTime,
  stripMarkdown,
  splitSections,
  extractTitle,
  extractBody,
  formatDate,
  requestAgines,
  AginesRequestBody
} from '../common/Utils'

/**
 * 建议结果数据模型
 * 用于存储大模型返回的建议内容及生成时间戳
 */
interface AdviceResult {
  content: string; // 建议正文（已去除Markdown格式）
  time: string // 建议生成的时间（用于展示时效性）
}

/**
 * 智能种植顾问组件
 *
 * 包含表单输入区、生成按钮和结果展示区三部分。
 * 所有表单字段均为必填，校验通过后按钮才可点击。
 */
@Component
export struct Advice {
  // ==================== 表单状态 ====================

  /** 作物类型选中下标，-1表示未选择 */
  @State cropTypeIndex: number = -1;
  /** 生长阶段选中下标，-1表示未选择 */
  @State growthStageIndex: number = -1;
  /** 种植时间，格式为 YYYY-MM-DD，通过日期选择器赋值 */
  @State plantDate: string = '';
  /** 当前问题描述文本 */
  @State problemText: string = '';
  // ==================== 结果状态 ====================

  /** 是否正在调用大模型生成建议，控制加载动画与按钮禁用态 */
  @State loading: boolean = false;
  /** 生成的建议结果，null表示尚未生成或正在生成中 */
  @State adviceResult: AdviceResult | null = null;
  /**
   * 作物类型下拉选项
   * 使用 ArkUI 内置 SelectOption 类型避免结构化类型报错
   * 涵盖主要粮食、蔬菜、水果及兜底的"其他"选项
   */
  private cropTypeOptions: SelectOption[] = [
    { value: '小麦' }, { value: '玉米' }, { value: '水稻' },
    { value: '大豆' }, { value: '棉花' }, { value: '番茄' },
    { value: '黄瓜' }, { value: '苹果' }, { value: '柑橘' },
    { value: '草莓' }, { value: '辣椒' }, { value: '其他' }
  ];
  /**
   * 生长阶段下拉选项
   * 采用通用阶段划分，适配多种作物的共性生长周期
   */
  private growthStageOptions: SelectOption[] = [
    { value: '萌芽期' }, { value: '苗期' }, { value: '分蘖/分枝期' },
    { value: '拔节/抽蔓期' }, { value: '开花期' }, { value: '结果/灌浆期' },
    { value: '成熟期' }
  ];

  // ==================== 业务逻辑 ====================

  /**
   * 生成种植建议的核心方法
   *
   * 执行流程：
   * 1. 防重复提交检查
   * 2. 四项必填字段校验
   * 3. 拼装用户输入为结构化文本
   * 4. 构造含系统提示词的请求体
   * 5. 调用 Agines API 获取结果
   * 6. 清洗Markdown并记录时间戳
   */
  private async onGenerate(): Promise<void> {
    // 防呆：加载中禁止重复触发
    if (this.loading) {
      return;
    }

    // 校验：四个字段任一为空则静默返回（按钮已通过enabled属性做了视觉反馈）
    if (this.cropTypeIndex < 0 || this.growthStageIndex < 0
      || this.plantDate.trim().length === 0 || this.problemText.trim().length === 0) {
      return;
    }

    // 进入加载态，清空上一次的结果
    this.loading = true;
    this.adviceResult = null;

    // 1. 从选项数组中提取选中的文本值，拼装为用户消息内容
    const cropName = this.cropTypeOptions[this.cropTypeIndex].value as string;
    const stageName = this.growthStageOptions[this.growthStageIndex].value as string;
    const date = this.plantDate.trim();
    const problem = this.problemText.trim();

    const userContent: string =
      `作物种类：${cropName}\n` +
        `生长阶段：${stageName}\n` +
        `种植时间：${date}\n` +
        `当前问题：${problem}`;

    // 2. 构造请求体：system角色注入专属提示词，user角色传入用户输入
    const requestBody: AginesRequestBody = {
      model: AGINES_MODEL,
      messages: [
        { role: 'system', content: ADVICE_PROMPT },
        { role: 'user', content: userContent }
      ]
    };

    // 3. 发起API请求并处理响应
    const content = await requestAgines(requestBody);

    // 4. 解析结果：若以"[错误]"开头则截取错误信息，否则清洗Markdown格式
    this.adviceResult = {
      content: content.startsWith('[错误]') ? content.substring(4) : stripMarkdown(content),
      time: nowTime()
    };

    // 退出加载态
    this.loading = false;
  }

  /**
   * 弹出系统原生日期选择器
   * 选择范围：2020-01-01 至 今天
   * 确认后通过 formatDate 格式化为 YYYY-MM-DD 写入 plantDate
   *
   * 注意：DatePickerDialog.show(...) 从 API 18 起已废弃，
   * 此处改用 UIContext 上的 showDatePickerDialog(...) 入口，
   * 参数选项与 DatePickerDialogOptions 保持一致。
   */
  private showDatePicker(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date('2020-01-01'),
      end: new Date(),
      selected: new Date(),
      onAccept: (value: DatePickerResult) => {
        this.plantDate = formatDate(value.year, value.month, value.day);
      }
    });
  }

  // ==================== UI 构建器 ====================

  /**
   * 表单字段标题行构建器
   * @param title - 字段标签文字
   * @param required - 是否显示红色必填星号
   */
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

  /**
   * 结果分段卡片构建器
   * 将大模型返回的每个【标题】段落渲染为独立的图文块
   * @param title - 段落标题（如"田间管理建议"）
   * @param body - 段落正文内容
   */
  @Builder
  ResultSection(title: string, body: string) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#2e7d32')  // 绿色标题，呼应农业主题
        .width('100%')

      Text(body)
        .fontSize(14)
        .fontColor('#444444')
        .lineHeight(22)       // 增加行高提升长文可读性
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 建议结果卡片构建器
   *
   * 渲染逻辑：
   * - 内容为空时显示占位提示
   * - 内容可按【】分段时，逐段渲染为 ResultSection
   * - 无法分段时整体作为纯文本展示（兼容非标准格式的AI回复）
   */
  @Builder
  AdviceResultCard() {
    Column({ space: 12 }) {
      // 卡片头部：标题 + 生成时间
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

      // 分隔线
      Divider()
        .color('#eeeeee')
        .strokeWidth(1)
        .width('100%')

      // 正文区域：三种渲染策略
      if (this.adviceResult!.content.length === 0) {
        // 策略1：空内容占位
        Text('（暂无内容）')
          .fontSize(14)
          .fontColor('#999999')
          .width('100%')
      } else if (splitSections(this.adviceResult!.content).length > 0) {
        // 策略2：按【】标题分段渲染
        ForEach(splitSections(this.adviceResult!.content), (sec: string) => {
          this.ResultSection(extractTitle(sec), extractBody(sec))
        })
      } else {
        // 策略3：无法分段时整体展示
        Text(this.adviceResult!.content)
          .fontSize(14)
          .fontColor('#444444')
          .lineHeight(22)
          .width('100%')
      }
    }
    .width('100%')
    .padding(20)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    // 左侧橙色边框作为视觉标识，区分于表单卡片
    .border({
      width: { left: 4 },
      color: { left: '#FFA000' }
    })
    .shadow({ radius: 6, color: 'rgba(0,0,0,0.06)', offsetY: 2 })
  }

  // ==================== 页面主结构 ====================
  build() {
    // 外层可滚动容器，防止键盘弹出或小屏设备内容溢出
    Scroll() {
      Column({ space: 30 }) {

        // ========== 作物状况信息表单卡片 ==========
        Column({ space: 16 }) {
          // 卡片标题
          Text('作物状况信息')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#2e7d32')
            .width('100%')

          // 作物类型 + 生长阶段：横向排列节省纵向空间
          Row({ space: 12 }) {
            // 作物类型选择器（必填）
            Column({ space: 8 }) {
              this.FieldLabel('作物类型', true)
              Select(this.cropTypeOptions)
                .selected(this.cropTypeIndex)
                // 未选择时显示灰色提示文案，选中后显示加粗的值
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
                .divider({ strokeWidth: 0 })  // 取消下划线
                .onSelect((index: number) => {
                  this.cropTypeIndex = index;
                })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            // 生长阶段选择器（必填）
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

          // 种植时间选择器（必填，点击触发自定义日期弹窗）
          Column({ space: 8 }) {
            this.FieldLabel('种植时间', true)
            Row() {
              Text(this.plantDate.length > 0 ? this.plantDate : '点击选择播种日期')
                .fontSize(14)
                // 有值时深色，无值时灰色占位色
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

          // 当前问题输入框（必填，多行文本域）
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

          // ========== 生成按钮 ==========
          Button() {
            if (this.loading) {
              // 加载态：旋转图标 + 提示文字
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color('#FFFFFF')
                Text('正在生成建议...')
                  .fontSize(15)
                  .fontColor('#FFFFFF')
                  .fontWeight(FontWeight.Bold)
              }
            } else {
              // 正常态
              Text('生成种植管理建议')
                .fontSize(15)
                .fontColor('#FFFFFF')
                .fontWeight(FontWeight.Bold)
            }
          }
          .type(ButtonType.Capsule)
          .width('100%')
          .height(48)
          .backgroundColor('#2e7d32')
          .margin({ top: 20 })
          // 四项必填全部完成且非加载态时 opacity=1，否则半透明提示不可用
          .opacity((this.cropTypeIndex >= 0 && this.growthStageIndex >= 0
            && this.plantDate.trim().length > 0 && this.problemText.trim().length > 0
            && !this.loading) ? 1 : 0.5)
          // enabled 与 opacity 条件保持一致，双重保障防止误触
          .enabled(this.cropTypeIndex >= 0 && this.growthStageIndex >= 0
            && this.plantDate.trim().length > 0 && this.problemText.trim().length > 0
            && !this.loading)
          .onClick(() => this.onGenerate())
        }
        // 表单卡片样式：白色背景 + 圆角 + 轻阴影
        .width('100%')
        .padding(20)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .shadow({ radius: 4, color: 'rgba(0,0,0,0.04)', offsetY: 1 })

        // ========== 建议结果卡片（仅在生成完成且非加载态时显示）==========
        if (this.adviceResult !== null && !this.loading) {
          this.AdviceResultCard()
        }

        // 底部安全留白，避免最后的内容被导航栏或手势条遮挡
        Blank().height(8)
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 8,
        bottom: 20
      })
    }
    .layoutWeight(1)
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .backgroundColor('#F6F7F6') // 浅灰绿背景
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto) // 滚动条按需显示
  }
}