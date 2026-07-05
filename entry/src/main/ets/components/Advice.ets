/**
 * @file Advice.ets
 * @description 智能种植顾问模块
 *
 * 功能概述：
 * 用户填写作物种类、生长阶段、种植时间及当前问题四个必填字段，
 * 调用 Agines 大模型生成个性化种植管理建议，并将模型返回的 JSON 解析为分栏卡片渲染。
 *
 * 依赖项：
 * - Constants: 模型名称(AGINES_MODEL)与系统提示词(ADVICE_PROMPT)
 * - Utils: 时间格式化、Markdown清洗、API请求封装、JSON容错解析等工具函数
 */
import {
  formatDate,
} from '../common/Utils'


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
  /**
   * 作物类型下拉选项
   * SelectOption 结构：{ value?: string | Resource, icon?: Resource }
   *   - value：选项显示的文本（必填）
   *   - icon：选项前的图标资源（可选，如 $r('app.media.xxx')）
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
   * SelectOption 结构：{ value?: string | Resource, icon?: Resource }
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
   * 6. 记录时间戳并解析JSON为分栏数据
   */
  private async onGenerate(): Promise<void> {
    // 防呆：加载中禁止重复触发
    if (this.loading) {
      return;
    }

    // 校验：四个字段任一为空则静默返回（按钮已通过enabled属性做了视觉反馈）
    /* 为什么加trim?
      在表单输入场景（尤其是移动端）中，用户很容易误触空格键或复制粘贴时带入不可见字符。
      防止“假值”通过校验,ArkTS 中，字符串 ' '（纯空格）的 length > 0 为 true，且布尔值为 true。
      不加 trim： 用户只输入了几个空格，系统会认为“已填写”，按钮变亮可点击，但实际提交的是无效数据。
      加了 trim： ' '.trim().length === 0，系统正确识别为空值，保持按钮禁用态。*/
    if (this.cropTypeIndex < 0 || this.growthStageIndex < 0
      || this.plantDate.trim().length === 0 || this.problemText.trim().length === 0) {
      return;
    }

    // 进入加载态
    this.loading = true;

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
    console.log('作物状况信息', userContent);
    // 退出加载态
    // this.loading = false;
  }

  /**
   * 弹出系统原生日期选择器
   * 选择范围：2020-01-01 至 今天
   * 确认后通过 formatDate 格式化为 YYYY-MM-DD 写入 plantDate
   */
  private showDatePicker(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date('2020-01-01'), // 可选日期范围的起始值
      end: new Date(), // 可选日期范围的结束值（当天）
      selected: new Date(), // 弹窗打开时默认选中的日期
      onAccept: (value: DatePickerResult) => { // 用户点击"确定"后的回调
        this.plantDate = formatDate(value.year, value.month, value.day); // 格式化为 YYYY-MM-DD 并写入状态
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
        .fontSize(12)
        .fontColor('#4C5549')
      if (required) {
        Text(' *')
          .fontSize(14)
          .fontColor('#E53935')
      }
    }
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
            .width('100%')

          // 作物类型 + 生长阶段：横向排列节省纵向空间
          Row({ space: 12 }) {
            // 作物类型选择器（必填）
            Column({ space: 8 }) {
              this.FieldLabel('作物类型', true)
              Select(this.cropTypeOptions)          // 传入下拉选项数组
                .selected(this.cropTypeIndex)       // 当前选中项的下标，-1 表示未选择
                // 未选择时显示灰色提示文案，选中后显示加粗的值
                .value(this.cropTypeIndex >= 0
                  ? this.cropTypeOptions[this.cropTypeIndex].value as string
                  : '请选择作物类型')
                .width('100%')                      // 选择器整体宽度
                .font({ size: 14 })                 // 触发区域的文字大小
                .fontColor('#1a1c1c')               // 触发区域的文字颜色
                .selectedOptionFont({ size: 14, weight: FontWeight.Bold })  // 下拉列表中选中项的字体样式
                .optionFont({ size: 14 })           // 下拉列表中未选中项的字体大小
                .backgroundColor('#f7f8f5')         // 选择器背景色（浅灰绿）
                .borderRadius(8)                    // 选择器圆角
                .divider({ strokeWidth: 0 })        // 取消选项之间的下划线分隔
                .onSelect((index: number) => { // 用户选中某项后的回调，index 为选中项在数组中的下标
                  this.cropTypeIndex = index; // 更新选中下标状态，触发 UI 刷新
                })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            // 生长阶段选择器（必填）
            Column({ space: 8 }) {
              this.FieldLabel('生长阶段', true)
              Select(this.growthStageOptions)       // 传入生长阶段下拉选项数组
                .selected(this.growthStageIndex)    // 当前选中项的下标，-1 表示未选择
                .value(this.growthStageIndex >= 0    // 触发区域显示的文本：已选则显示选项值，未选则显示占位提示
                  ? this.growthStageOptions[this.growthStageIndex].value as string
                  : '请选择生长阶段')
                .width('100%')                      // 选择器整体宽度
                .font({ size: 14 })                 // 触发区域的文字大小
                .fontColor('#1a1c1c')               // 触发区域的文字颜色
                .selectedOptionFont({ size: 14, weight: FontWeight.Bold })  // 下拉列表中选中项的字体样式
                .optionFont({ size: 14 })           // 下拉列表中未选中项的字体大小
                .backgroundColor('#f7f8f5')         // 选择器背景色
                .borderRadius(8)                    // 选择器圆角
                .divider({ strokeWidth: 0 })        // 取消选项之间的下划线分隔
                .onSelect((index: number) => { // 用户选中某项后的回调
                  this.growthStageIndex = index; // 更新选中下标状态
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