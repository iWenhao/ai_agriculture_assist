# AI 农作物图像诊断功能说明

> 适配项目：ai_agriculture_assist (HarmonyOS Stage 模式，targetSdk 6.1.1)
> 新增入口：底部 Tab「AI 诊断」(`Diagnose.ets`)

---

## 1. 功能概述

用户在「AI 诊断」页面上传一张农作物照片后，系统调用 Agines 多模态大模型进行四方面分析，并以结构化卡片呈现：

| # | 维度 | 数据来源（模型返回字段） |
|---|---|---|
| 1 | 作物识别 | `cropName` / `growthStage` / `confidence` |
| 2 | 生长状态分析 | `growthStatus` |
| 3 | 病虫害风险分析 | `diseaseRisk.level` / `diseaseRisk.summary` / `diseaseRisk.keySymptoms[]` |
| 4 | 管理建议生成 | `suggestions[].title` / `suggestions[].content`（4 条） |

---

## 2. 页面布局

```
┌─────────────────────────────────────┐
│  ┌─ 卡片：图片选择 / 预览 ────────┐ │
│  │  AI 图像诊断                     │ │
│  │                                  │ │
│  │  ┌────────────────────────┐     │ │
│  │  │  选中态：Image 预览    │     │ │
│  │  │  (220 高)        [重选]│     │ │
│  │  └────────────────────────┘     │ │
│  │  或                              │ │
│  │  ┌────────────────────────┐     │ │
│  │  │  未选：虚线占位 + 提示 │     │ │
│  │  └────────────────────────┘     │ │
│  │                                  │ │
│  │  [🖼 从相册选择] [📷 拍照(占位)]│ │
│  └──────────────────────────────────┘ │
│                                       │
│  ━━  开始 AI 诊断  ━━                │ ← 加载时显示 LoadingProgress
│                                       │
│  ⚠ 错误提示（条件渲染）               │
│                                       │
│  ┌─ 卡片 1：诊断结果总览 ──────────┐ │
│  │  识别作物          置信度       │ │
│  │  番茄              高            │ │
│  │  生长阶段：开花期                │ │
│  └──────────────────────────────────┘ │
│  ┌─ 卡片 2：生长状态分析 ──────────┐ │
│  │  叶片浓绿，株型健壮…             │ │
│  └──────────────────────────────────┘ │
│  ┌─ 卡片 3：病虫害风险分析 ────────┐ │
│  │  风险等级：中                    │ │
│  │  疑似早期白粉病…                 │ │
│  │  关键症状                       │ │
│  │   • 叶背有白色粉状物            │ │
│  │   • 嫩叶卷曲                    │ │
│  └──────────────────────────────────┘ │
│  ┌─ 卡片 4：管理建议 ──────────────┐ │
│  │  ① 田间管理建议  …              │ │
│  │  ② 水肥管理建议  …              │ │
│  │  ③ 病虫害防治建议 …             │ │
│  │  ④ 后续管理建议  …              │ │
│  └──────────────────────────────────┘ │
└─────────────────────────────────────┘
```

---

## 3. 关键状态变量

```typescript
@State imageUri:       string            // 已选图片 URI（Image 组件预览用）
@State imageBase64:    string            // 图片 base64（接口入参用）
@State imageMimeType:  string            // image/jpeg | image/png | image/webp | image/gif
@State loading:        boolean           // 是否正在调用大模型
@State result:         DiagnoseResult | null   // 解析后的结构化结果
@State errorText:      string            // 错误提示
```

按钮可用态 = `imageBase64.length > 0 && !loading`

---

## 4. 业务流程（时序）

```
用户点击「从相册选择」
    └─► photoAccessHelper.PhotoViewPicker.select()
            └─► PhotoSelectResult.photoUris[0]
                    └─► handleSelectedUri(uri)
                            ├─ fileIo.openSync(uri)        // 打开文件
                            ├─ fileIo.statSync(fd)         // 拿 size
                            ├─ 循环 readSync 直到读完      // 避开 4KB 限制
                            ├─ size > 30MB ? 报错返回
                            ├─ util.Base64Helper.encodeToStringSync(buffer)
                            └─ 写入 imageUri / imageBase64 / imageMimeType

用户点击「开始 AI 诊断」
    └─► onDiagnose()
            ├─ 构造 dataURL = `data:${mime};base64,${base64}`
            ├─ 构造 messages = [
            │     {role:'system', content: DIAGNOSE_PROMPT},
            │     {role:'user',   content: [
            │         {type:'text', text:'请诊断…'},
            │         {type:'image_url', image_url:{url: dataURL}}
            │     ]}
            │   ]
            ├─ http.createHttp().request(AGINES_API_URL, …)
            ├─ responseCode === 200 ?
            │     ├─ tryExtractJson(text) 成功 → normalizeResult() → this.result
            │     └─ 失败 → this.errorText
            └─ finally: this.loading = false
```

---

## 5. JSON 数据流

### 5.1 请求体

```json
POST https://apihub.agnes-ai.com/v1/chat/completions
Content-Type: application/json
Authorization: Bearer <AGINES_API_KEY>

{
  "model": "agnes-2.0-flash",
  "stream": false,
  "messages": [
    {
      "role": "system",
      "content": "<DIAGNOSE_PROMPT，约束 JSON 输出结构>"
    },
    {
      "role": "user",
      "content": [
        { "type": "text",      "text": "请对这张农作物照片进行专业诊断…" },
        { "type": "image_url", "image_url": { "url": "data:image/jpeg;base64,/9j/4AAQ…" } }
      ]
    }
  ]
}
```

### 5.2 响应体（OpenAI/Agines 兼容）

```json
{
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "{\"cropName\":\"番茄\",\"growthStage\":\"开花期\",\"confidence\":\"高\",…}"
      }
    }
  ]
}
```

`content` 字段是一个 JSON 字符串，需用 `Utils.tryExtractJson()` 二次解析。

### 5.3 期望的 JSON 结构（`DIAGNOSE_PROMPT` 强制约束）

```json
{
  "cropName":     "番茄",
  "growthStage":  "开花期",
  "confidence":   "高",
  "growthStatus": "叶片浓绿，株型健壮，果实尚未膨大，整体处于开花前期。",
  "diseaseRisk": {
    "level":       "中",
    "summary":     "疑似早期白粉病，建议及时处理。",
    "keySymptoms": [
      "叶背有白色粉状物",
      "嫩叶轻度卷曲",
      "下部老叶有少量黄斑"
    ]
  },
  "suggestions": [
    { "title": "田间管理建议",     "content": "…" },
    { "title": "水肥管理建议",     "content": "…" },
    { "title": "病虫害防治建议",   "content": "…" },
    { "title": "后续管理建议",     "content": "…" }
  ]
}
```

`normalizeResult()` 会对模型返回做容错处理：缺字段填空字符串 / 空数组，避免 UI 崩溃。

---

## 6. 关键文件

| 文件 | 变更 | 作用 |
|---|---|---|
| `entry/src/main/ets/components/Diagnose.ets` | **新增** | 诊断页面组件（604 行，含完整注释） |
| `entry/src/main/ets/common/Constants.ets` | 修改 | 新增 `DIAGNOSE_PROMPT` 提示词 |
| `entry/src/main/ets/pages/Index.ets` | 修改 | tabList 加入「AI 诊断」第 4 项 |
| `entry/src/main/resources/base/media/diagnose.png` | **新增** | TabBar 未激活图标（灰，96×96） |
| `entry/src/main/resources/base/media/diagnose_active.png` | **新增** | TabBar 激活图标（绿，96×96） |
| `entry/src/main/module.json5` | 修改 | 新增 `ohos.permission.READ_MEDIA` |

---

## 7. 后续可扩展点

- **拍照功能**：`Diagnose.ets` 中已留"📷 拍照"按钮占位（默认禁用），启用时需：
  1. 在 `module.json5` 增加 `ohos.permission.CAMERA`
  2. 引入 `import { cameraPicker } from '@kit.CameraKit'`
  3. 拍照得到 URI 后复用 `handleSelectedUri()` 即可
- **图片压缩**：当前限制 30MB；如需更大兼容，引入 `image.createImageSource` + `createImagePacker` 在 `handleSelectedUri` 中加一道 1080p 压缩
- **多图诊断**：把 `imageBase64` 改成数组，循环拼接到 `visionContent` 即可
- **历史记录**：把 `result` 持久化到 PreferencesStorage 或 relational DB
- **置信度细化**：`confidence` 字段当前约束为「高/中/低」中文，可改成 0~1 浮点 + 阈值映射，更利于 UI 分级着色

---

## 8. 测试用例（手测 checklist）

- [ ] 选 1 张 < 5MB 番茄叶片照片，3 秒内显示四张结果卡片
- [ ] 选 1 张 > 30MB 照片，提示「图片过大」并禁止诊断
- [ ] 选非农作物照片（风景、人物），置信度为「低」且 cropName 提示「未能识别」
- [ ] 断网情况下点「开始 AI 诊断」，按钮 loading 状态正确退出 + 错误条显示「请检查网络」
- [ ] 已选图片后点「重选」，能正常重新打开相册选择器
- [ ] 诊断过程中重复点「开始 AI 诊断」，按钮 disabled 不会重复触发请求
- [ ] 切到其他 Tab 再切回「AI 诊断」，图片预览和结果不丢失
