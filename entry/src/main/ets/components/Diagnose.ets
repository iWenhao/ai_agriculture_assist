/**
 * @file Diagnose.ets
 * @description AI 图像诊断模块
 *
 * 功能概述：
 * 用户从相册选择一张农作物照片（本版本），系统调用 Agines 多模态大模型
 * 对图片进行四方面分析（作物识别、生长状态分析、病虫害风险分析、管理建议生成），
 * 并以结构化卡片的形式向用户呈现诊断结果与处理建议。
 *
 * 依赖项：
 * - Constants: 模型名称(AGINES_MODEL)、API Key 与诊断专用提示词(DIAGNOSE_PROMPT)
 * - photoAccessHelper: 系统相册选择器（无需运行时权限）
 * - fileIo: 读取图片二进制
 * - util.Base64Helper: Base64 编码
 * - http: 调用大模型 API
 * - Utils.tryExtractJson: 容错提取模型返回的 JSON
 */

import { http } from '@kit.NetworkKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AGINES_API_URL, AGINES_API_KEY, AGINES_MODEL, DIAGNOSE_PROMPT } from '../common/Constants';
import { tryExtractJson } from '../common/Utils';

// 单条管理建议
interface SuggestionItem {
  title: string;
  content: string;
}

// 病虫害风险评估
interface DiseaseRisk {
  level: string;
  summary: string;
  keySymptoms: string[];
}

// AI 诊断结果（与 DIAGNOSE_PROMPT 中约束的 JSON 结构对应）
interface DiagnoseResult {
  cropName: string;
  growthStage: string;
  confidence: string;
  growthStatus: string;
  diseaseRisk: DiseaseRisk;
  suggestions: SuggestionItem[];
}

// 多模态消息内容单元（OpenAI/Agines 兼容格式）
interface ImageUrlObject {
  url: string;
}

interface VisionContent {
  type: string;
  text?: string;
  image_url?: ImageUrlObject;
}

// 通用消息：content 既可以是字符串，也可以是多模态数组
interface ChatMsg {
  role: string;
  content: Object;
}

// 诊断请求体
interface DiagnoseRequestBody {
  model: string;
  messages: ChatMsg[];
  stream: boolean;
}

// readSync 读取选项
interface ReadFileOptions {
  offset?: number;
  length?: number;
}

/**
 * AI 图像诊断组件
 *
 * 流程：相册选图 → 读取并转 base64 → 调多模态大模型 → 解析 JSON → 分卡片渲染
 */
@Component
export struct Diagnose {
  // ========== 状态变量 ==========
  @State imageUri: string = '';          // 已选图片的 URI（用于 Image 组件预览）
  @State imageBase64: string = '';       // 图片的 base64 编码（用于接口入参）
  @State imageMimeType: string = 'image/jpeg';
  @State loading: boolean = false;       // 是否正在调用大模型
  @State result: DiagnoseResult | null = null;  // 解析后的结构化结果
  @State errorText: string = '';         // 错误提示

  // ========== 工具函数 ==========

  /**
   * 依据文件扩展名推断 MIME 类型
   * 默认按 JPEG 处理，覆盖相册中最常见的几种格式
   */
  private detectMime(uri: string): string {
    const lower: string = uri.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif';
    }
    return 'image/jpeg';
  }

  /**
   * 安全读取字符串字段：非字符串一律降级为 fallback
   */
  private asStr(v: Object | undefined, fallback: string): string {
    if (v !== undefined && typeof v === 'string') {
      return v;
    }
    return fallback;
  }

  /**
   * 安全读取字符串数组：非数组或元素非字符串一律降级为空数组
   */
  private asStrArr(v: Object | undefined): string[] {
    const out: string[] = [];
    if (v !== undefined && Array.isArray(v)) {
      const arr: Object[] = v as Object[];
      for (const item of arr) {
        if (typeof item === 'string') {
          out.push(item);
        }
      }
    }
    return out;
  }

  /**
   * 容错地把模型返回的对象规整为 DiagnoseResult
   * 缺失字段填空字符串或空数组，避免 UI 渲染时崩溃
   */
  private normalizeResult(obj: Record<string, Object>): DiagnoseResult {
    const diseaseRiskRaw = obj['diseaseRisk'] as Record<string, Object> | undefined;
    const diseaseRisk: DiseaseRisk = {
      level: diseaseRiskRaw !== undefined ? this.asStr(diseaseRiskRaw['level'], '未知') : '未知',
      summary: diseaseRiskRaw !== undefined ? this.asStr(diseaseRiskRaw['summary'], '暂无描述') : '暂无描述',
      keySymptoms: diseaseRiskRaw !== undefined ? this.asStrArr(diseaseRiskRaw['keySymptoms']) : []
    };

    const suggestions: SuggestionItem[] = [];
    const suggestionsRaw = obj['suggestions'] as Object;
    if (Array.isArray(suggestionsRaw)) {
      const suggestionsArr: Object[] = suggestionsRaw as Object[];
      for (const item of suggestionsArr) {
        if (item !== null && item !== undefined) {
          const it = item as Record<string, Object>;
          suggestions.push({
            title: this.asStr(it['title'], ''),
            content: this.asStr(it['content'], '')
          });
        }
      }
    }

    return {
      cropName: this.asStr(obj['cropName'], '未能识别'),
      growthStage: this.asStr(obj['growthStage'], '难以判断'),
      confidence: this.asStr(obj['confidence'], '中'),
      growthStatus: this.asStr(obj['growthStatus'], '暂无描述'),
      diseaseRisk,
      suggestions
    };
  }

  // ========== 业务逻辑 ==========

  /**
   * 处理已选中的图片 URI：读取文件 → 转 base64 → 写入状态
   * 失败时清空状态并显示错误
   */
  private async handleSelectedUri(uri: string): Promise<void> {
    // 切换图片时清空上次结果，避免误用
    this.result = null;
    this.errorText = '';
    this.imageUri = uri;
    this.imageBase64 = '';

    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      const size: number = stat.size;

      // HarmonyOS 单次 readSync 最多读 4096 字节，需要循环读到文件尾
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      let totalRead: number = 0;
      while (totalRead < size) {
        const readOpt: ReadFileOptions = { offset: totalRead };
        const once: number = fileIo.readSync(file.fd, buffer, readOpt);
        if (once <= 0) {
          break;
        }
        totalRead += once;
      }
      fileIo.closeSync(file);

      if (totalRead === 0) {
        this.errorText = '图片读取失败，请重试';
        this.imageUri = '';
        return;
      }

      // 30MB 字节（≈40MB base64）上限，超过则提示用户换张更小的图
      if (size > 30 * 1024 * 1024) {
        this.errorText = '图片过大（>30MB），请压缩后重新选择';
        this.imageUri = '';
        return;
      }

      this.imageMimeType = this.detectMime(uri);
      const helper = new util.Base64Helper();
      this.imageBase64 = helper.encodeToStringSync(new Uint8Array(buffer));
    } catch (err) {
      console.error('读取图片失败', JSON.stringify(err));
      this.errorText = '读取图片失败，请重试';
      this.imageUri = '';
      this.imageBase64 = '';
    }
  }

  /**
   * 从相册选择图片
   * PhotoViewPicker 由系统提供，不需运行时权限，调起系统选择器即可
   */
  private async pickFromAlbum(): Promise<void> {
    if (this.loading) {
      return;
    }
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await picker.select(options);
      if (result && result.photoUris && result.photoUris.length > 0) {
        await this.handleSelectedUri(result.photoUris[0]);
      }
    } catch (err) {
      console.error('相册选择失败', JSON.stringify(err));
      this.errorText = '打开相册失败，请稍后重试';
    }
  }

  /**
   * 调用大模型进行图像诊断
   * 1) 构造多模态消息（system + user[text + image]）
   * 2) POST 到 Agines Chat Completions
   * 3) 容错解析 JSON 并写入 result
   */
  private async onDiagnose(): Promise<void> {
    if (this.loading || this.imageBase64.length === 0) {
      return;
    }

    this.loading = true;
    this.errorText = '';
    this.result = null;

    const dataUrl: string = `data:${this.imageMimeType};base64,${this.imageBase64}`;
    // 显式为每个对象标注类型，避免 ArkTS 数组字面量类型推断失败
    const textPart: VisionContent = {
      type: 'text',
      text: '请对这张农作物照片进行专业诊断，按系统提示词中规定的 JSON 结构输出。'
    };
    const imagePart: VisionContent = {
      type: 'image_url',
      image_url: { url: dataUrl }
    };
    const visionContent: VisionContent[] = [textPart, imagePart];

    const messages: ChatMsg[] = [
      { role: 'system', content: DIAGNOSE_PROMPT as Object },
      { role: 'user', content: visionContent as Object }
    ];

    const requestBody: DiagnoseRequestBody = {
      model: AGINES_MODEL,
      messages: messages,
      stream: false
    };

    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(AGINES_API_URL, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${AGINES_API_KEY}`
        },
        extraData: JSON.stringify(requestBody),
        expectDataType: http.HttpDataType.STRING
      });

      if (response.responseCode === 200) {
        const text: string = typeof response.result === 'string'
          ? response.result
          : JSON.stringify(response.result);
        const parsed = tryExtractJson(text);
        if (parsed !== null) {
          this.result = this.normalizeResult(parsed);
        } else {
          this.errorText = 'AI 返回数据无法解析，请稍后重试';
        }
      } else {
        this.errorText = `请求失败，状态码: ${response.responseCode}`;
      }
    } catch (err) {
      console.error('诊断请求失败', JSON.stringify(err));
      this.errorText = '诊断请求失败，请检查网络';
    } finally {
      httpRequest.destroy();
      this.loading = false;
    }
  }

  // ========== UI 构建器 ==========

  /**
   * 卡片小节标题行：左侧色条 + 标题文字
   */
  @Builder
  SectionHeader(title: string, color: ResourceColor) {
    Row({ space: 8 }) {
      Row().width(3).height(14).backgroundColor(color).borderRadius(2)
      Text(title).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#1a1c1c')
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 单条建议卡片：序号圆点 + 标题 + 内容
   */
  @Builder
  SuggestionCard(item: SuggestionItem, idx: number) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(`${idx + 1}`)
          .fontSize(12)
          .fontColor($r('app.color.diagnose_text_inverse'))
          .fontWeight(FontWeight.Bold)
          .width(22).height(22)
          .textAlign(TextAlign.Center)
          .borderRadius(11)
          .backgroundColor($r('app.color.diagnose_brand'))
        Text(item.title).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#1a1c1c')
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(item.content)
        .fontSize(13)
        .fontColor('#40493d')
        .lineHeight(20)
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#f7f8f5')
    .borderRadius(8)
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 结果展示面板：四张结果卡片（总览、生长状态、病虫害风险、管理建议）
   */
  @Builder
  ResultPanel(r: DiagnoseResult) {
    Column({ space: 16 }) {

      // ========== 总览卡片：作物名 / 生长阶段 / 置信度 ==========
      Column({ space: 12 }) {
        this.SectionHeader('诊断结果总览', $r('app.color.diagnose_brand'))

        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Text('识别作物').fontSize(11).fontColor('#999999')
            Text(r.cropName).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#1a1c1c')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Column({ space: 4 }) {
            Text('置信度').fontSize(11).fontColor('#999999')
            Text(r.confidence).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.diagnose_brand'))
          }
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')

        Row({ space: 6 }) {
          Text('生长阶段：').fontSize(12).fontColor('#666666')
          Text(r.growthStage).fontSize(12).fontColor('#1a1c1c').fontWeight(FontWeight.Medium)
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
      .shadow({ radius: 4, color: 'rgba(0,0,0,0.04)', offsetY: 1 })
      .alignItems(HorizontalAlign.Start)

      // ========== 生长状态分析 ==========
      Column({ space: 10 }) {
        this.SectionHeader('生长状态分析', '#FF9E00')
        Text(r.growthStatus)
          .fontSize(13).fontColor('#40493d').lineHeight(20).width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
      .shadow({ radius: 4, color: 'rgba(0,0,0,0.04)', offsetY: 1 })
      .alignItems(HorizontalAlign.Start)

      // ========== 病虫害风险分析 ==========
      Column({ space: 10 }) {
        this.SectionHeader('病虫害风险分析', '#E53935')

        Row({ space: 8 }) {
          Text('风险等级：').fontSize(13).fontColor('#666666')
          Text(r.diseaseRisk.level).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#E53935')
        }
        .width('100%')

        Text(r.diseaseRisk.summary)
          .fontSize(13).fontColor('#40493d').lineHeight(20).width('100%')

        if (r.diseaseRisk.keySymptoms.length > 0) {
          Text('关键症状').fontSize(12).fontColor('#999999').margin({ top: 4 })
          Column({ space: 6 }) {
            ForEach(r.diseaseRisk.keySymptoms, (s: string) => {
              Row({ space: 6 }) {
                Text('•').fontSize(14).fontColor('#E53935')
                Text(s).fontSize(13).fontColor('#40493d').layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            })
          }
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
      .shadow({ radius: 4, color: 'rgba(0,0,0,0.04)', offsetY: 1 })
      .alignItems(HorizontalAlign.Start)

      // ========== 管理建议 ==========
      Column({ space: 12 }) {
        this.SectionHeader('管理建议', '#1976D2')
        if (r.suggestions.length > 0) {
          ForEach(r.suggestions, (item: SuggestionItem, idx: number) => {
            this.SuggestionCard(item, idx)
          })
        } else {
          Text('暂无结构化建议，请参考上方诊断信息')
            .fontSize(13).fontColor('#999999')
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
      .shadow({ radius: 4, color: 'rgba(0,0,0,0.04)', offsetY: 1 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ========== 页面主结构 ==========
  build() {
    Scroll() {
      Column({ space: 20 }) {

        // ========== 图片选择 / 预览卡片 ==========
        Column({ space: 16 }) {
          Text('AI 图像诊断')
            .fontSize(15).fontWeight(FontWeight.Bold)
            .width('100%')

          if (this.imageUri.length > 0) {
            // 已选择图片：显示预览 + 右上角"重选"按钮
            Stack({ alignContent: Alignment.TopEnd }) {
              Image(this.imageUri)
                .width('100%')
                .height(220)
                .borderRadius(10)
                .objectFit(ImageFit.Cover)
                .backgroundColor('#f3f3f3')
              Button('重选')
                .height(28)
                .fontSize(12)
                .fontColor($r('app.color.diagnose_brand'))
                .backgroundColor('#FFFFFF')
                .borderRadius(14)
                .margin({ top: 10, right: 10 })
                .padding({ left: 12, right: 12 })
                .opacity(this.loading ? 0.5 : 1)
                .enabled(!this.loading)
                .onClick(() => this.pickFromAlbum())
            }
            .width('100%')
          } else {
            // 未选择图片：占位 + 提示语
            Column({ space: 12 }) {
              Image($r('app.media.diagnose_active'))
                .width(60).height(60)
                .opacity(0.6)
              Text('上传农作物照片，让 AI 帮您诊断')
                .fontSize(14).fontColor('#666666')
              Text('支持 JPG / PNG，建议拍摄清晰的叶面、果穗或植株全景')
                .fontSize(12).fontColor('#999999')
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .height(200)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor('#fafafa')
            .borderRadius(10)
            .border({ width: 1, color: '#e5e5e5', style: BorderStyle.Dashed })
          }

          // 选择按钮组
          Row({ space: 12 }) {
            Button() {
              Row({ space: 6 }) {
                Text('🖼').fontSize(14)
                Text('从相册选择').fontSize(14).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
              }
            }
            .type(ButtonType.Capsule)
            .layoutWeight(1)
            .height(44)
            .backgroundColor($r('app.color.diagnose_brand'))
            .opacity(this.loading ? 0.5 : 1)
            .enabled(!this.loading)
            .onClick(() => this.pickFromAlbum())

            // 拍照按钮预留位（默认禁用，避免引入 CAMERA 权限；后续可接入 cameraPicker）
            Button() {
              Row({ space: 6 }) {
                Text('📷').fontSize(14)
                Text('拍照').fontSize(14).fontColor('#1a1c1c').fontWeight(FontWeight.Medium)
              }
            }
            .type(ButtonType.Capsule)
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#f0f0f0')
            .opacity(0.5)
            .enabled(false)
          }
          .width('100%')
        }
        .width('100%')
        .padding(20)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .shadow({ radius: 4, color: 'rgba(0,0,0,0.04)', offsetY: 1 })
        .alignItems(HorizontalAlign.Start)

        // ========== 开始诊断按钮 ==========
        Button() {
          if (this.loading) {
            Row({ space: 8 }) {
              LoadingProgress().width(18).height(18).color('#FFFFFF')
              Text('正在诊断中...').fontSize(15).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
            }
          } else {
            Text('开始 AI 诊断')
              .fontSize(15).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
          }
        }
        .type(ButtonType.Capsule)
        .width('100%')
        .height(48)
        .backgroundColor($r('app.color.diagnose_brand'))
        .opacity((this.imageBase64.length > 0 && !this.loading) ? 1 : 0.5)
        .enabled(this.imageBase64.length > 0 && !this.loading)
        .onClick(() => this.onDiagnose())

        // ========== 错误提示 ==========
        if (this.errorText.length > 0) {
          Row({ space: 8 }) {
            Text('⚠').fontSize(14).fontColor('#E53935')
            Text(this.errorText).fontSize(13).fontColor('#E53935').layoutWeight(1)
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#FFEBEE')
          .borderRadius(8)
          .alignItems(VerticalAlign.Top)
        }

        // ========== 诊断结果 ==========
        if (this.result !== null) {
          this.ResultPanel(this.result)
        }
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
    .backgroundColor('#F6F7F6')
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
  }
}