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
  tryExtractJson,
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
 * 单个分栏的视觉样式
 * 由 getSectionStyle 根据标题分发得到
 */
interface SectionStyle {
  icon: string; // 分类图标（emoji）
  bg: string; // 卡片背景色
  border: string; // 卡片边框色
}

/**
 * 一个分栏的完整渲染数据
 * 由 buildSectionsData 在生成结果时一次性算好，
 * ForEach 只需遍历此数组并调用 ResultSection，避免在 UI 上下文里写逻辑
 */
interface SectionData {
  icon: string;
  title: string;
  body: string;
  bg: string;
  border: string;
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
   * 预处理好的分栏渲染数据（图标/标题/正文/配色）
   * 在 onGenerate 拿到 content 后一次性算好，ForEach 直接遍历此数组
   * 避免在 ArkUI Builder 上下文里写中间变量和方法调用
   */
  @State sectionsData: SectionData[] = [];
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
    const finalContent: string = content.startsWith('[错误]') ? content.substring(4) : stripMarkdown(content);
    this.adviceResult = {
      content: finalContent,
      time: nowTime()
    };
    // 5. 一次性算好所有分栏的样式数据，ForEach 直接遍历，避免 Builder 内做逻辑
    this.sectionsData = this.buildSectionsData(finalContent);

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
   * 结果分段块构建器
   * 将大模型返回的每个【标题】段落渲染为"标题行 + 内容卡片"两个独立元素
   *
   * 视觉规范：
   * - 标题行：纯文字 + 图标，无背景/无边框/无圆角，字色 #166A16，正常字重
   * - 内容卡片：1px 浅边框 + 8px 圆角 + 浅色背景，仅包裹正文
   * - 标题与卡片之间留 6px 间距，各分栏之间在 ForEach 外层 Column 控制
   *
   * @param data - 单个分栏的完整渲染数据（由 buildSectionsData 预先生成）
   */
  @Builder
  ResultSection(data: SectionData) {
    Column({ space: 6 }) {
      // 标题行（卡片外）：图标 + 标题，不加粗，字号略小于正文
      Row({ space: 6 }) {
        // Text(data.icon)
        //   .fontSize(13)
        Image(data.icon)
        Text(data.title)
          .fontSize(13)
          .fontColor('#166A16')
      }
      .width('100%')

      // 内容卡片（只包正文）：浅背景 + 浅边框 + 圆角
      Text(data.body)
        .fontSize(14)
        .fontColor('#3c4a3c')
        .lineHeight(22)
        .width('100%')
        .padding(12)
        .backgroundColor(data.bg)
        .borderRadius(8)
        .border({
          width: 1,
          color: data.border
        })
    }
    .width('100%')
  }

  /**
   * 根据分栏标题查找对应的图标 / 背景色 / 边框色
   * 配色采用 Material Design 50/100 档（最浅），柔和不刺眼
   * 内部统一清洗【】书名号后再比较，兼容 JSON 路径（不带【】）和【】兜底路径（带【】）
   * 未匹配到预定义标题时使用中性灰样式兜底
   */
  private getSectionStyle(title: string): SectionStyle {
    const key: string = title.replace(/【|】/g, '');
    if (key === '田间管理建议') {
      // 田间 → 麦穗 / 极浅绿底 + 浅绿边
      const s: SectionStyle = { icon: '🌾', bg: '#F6FBF4', border: '#DCEDC8' };
      return s;
    } else if (key === '水肥一体化指导') {
      // 水肥 → 水滴 / 极浅蓝底 + 浅蓝边
      const s: SectionStyle = { icon: '💧', bg: '#F2F8FD', border: '#BBDEFB' };
      return s;
    } else if (key === '病虫害预警') {
      // 病虫害 → 警示三角 / 极浅橙底 + 浅橙边
      const s: SectionStyle = { icon: '⚠️', bg: '#FFF8F0', border: '#FFE0B2' };
      return s;
    } else if (key === '后续生产管理建议') {
      // 后续生产 → 剪贴板 / 极浅紫底 + 浅紫边
      const s: SectionStyle = { icon: '📋', bg: '#F8F4FA', border: '#E1BEE7' };
      return s;
    }
    // 兜底：未匹配的中性灰样式
    const s: SectionStyle = { icon: '•', bg: '#FAFAFA', border: '#E0E0E0' };
    return s;
  }

  /**
   * 把大模型返回的 content 拆分成"已计算好样式"的渲染数据数组
   *
   * 双轨解析：
   * 1) 优先尝试 JSON 解析（结构稳定、不依赖正则）
   * 2) 失败则降级到【】分段方案（兼容老格式输出或偶发模型抽风）
   * 3) 两条路径都失败则返回空数组，UI 退到"无法分段时整体展示"
   */
  private buildSectionsData(content: string): SectionData[] {
    // 路径 1：JSON 解析
    const jsonResult: SectionData[] = this.parseJsonSections(content);
    if (jsonResult.length > 0) {
      return jsonResult;
    }
    // 路径 2：【】兜底
    return this.parseBracketSections(content);
  }

  /**
   * JSON 路径：从 content 中提取 {"sections":[{"title":"...","content":"..."}, ...]}
   * 任一字段缺失或类型不匹配都跳过该条
   */
  private parseJsonSections(content: string): SectionData[] {
    const obj: Record<string, Object> | null = tryExtractJson(content);
    if (obj === null) {
      return [];
    }
    const raw: Object = obj['sections'];
    if (!Array.isArray(raw)) {
      return [];
    }
    const arr: Object[] = raw as Object[];
    const result: SectionData[] = [];
    for (let i: number = 0; i < arr.length; i++) {
      const item: Object = arr[i];
      if (item === null || typeof item !== 'object') {
        continue;
      }
      const rec: Record<string, Object> = item as Record<string, Object>;
      const t: Object = rec['title'];
      const b: Object = rec['content'];
      if (typeof t !== 'string' || typeof b !== 'string') {
        continue;
      }
      const titleStr: string = t as string;
      const bodyStr: string = b as string;
      const s: SectionStyle = this.getSectionStyle(titleStr);
      const d: SectionData = {
        icon: s.icon,
        title: titleStr,
        body: bodyStr,
        bg: s.bg,
        border: s.border
      };
      result.push(d);
    }
    return result;
  }

  /**
   * 【】兜底路径：按【】书名号切分文本，提取标题和正文
   * 用于兼容模型偶尔输出非 JSON 格式的退化情况
   */
  private parseBracketSections(content: string): SectionData[] {
    const secs: string[] = splitSections(content);
    const len: number = secs.length;
    const result: SectionData[] = new Array<SectionData>(len);
    let valid: number = 0;
    for (let i: number = 0; i < len; i++) {
      const sec: string = secs[i];
      const t: string = extractTitle(sec);
      const b: string = extractBody(sec);
      if (b.length === 0) {
        continue;
      }
      const s: SectionStyle = this.getSectionStyle(t);
      const cleanTitle: string = t.replace(/【|】/g, '');
      const d: SectionData = {
        icon: s.icon,
        title: cleanTitle,
        body: b,
        bg: s.bg,
        border: s.border
      };
      result[valid] = d;
      valid++;
    }
    // 裁剪到实际写入的长度（避免空槽位）
    return result.slice(0, valid);
  }

  /**
   * 获取今天的日期字符串（YYYY-MM-DD），用于结果卡片副标题
   * 使用 en-CA locale 让标准库原生输出 YYYY-MM-DD
   */
  private getTodayStr(): string {
    return new Intl.DateTimeFormat('en-CA', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(new Date());
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
      // 卡片头部：主标题 + 副标题（AI 来源 + 今天的年月日）
      Column({ space: 4 }) {
        Text('个性化种植管理建议')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#005E0F')
          .width('100%')
        Text(`由AI农技专家实时生成 · ${this.getTodayStr()}`)
          .fontSize(11)
          .fontColor('#7A8B7A')
          .width('100%')
      }

      // 正文区域：三种渲染策略
      if (this.adviceResult!.content.length === 0) {
        // 策略1：空内容占位
        Text('（暂无内容）')
          .fontSize(14)
          .fontColor('#999999')
          .width('100%')
      } else if (this.sectionsData.length > 0) {
        // 策略2：按【】标题分段渲染，数据已在 onGenerate 里预处理为 SectionData[]
        // 外层 Column space 控制各分栏之间的间距，每个分栏内部 ResultSection 自己控制标题/卡片间距
        Column({ space: 22 }) {
          ForEach(this.sectionsData, (data: SectionData) => {
            this.ResultSection(data);
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
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