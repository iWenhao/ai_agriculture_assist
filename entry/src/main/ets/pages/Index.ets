// 导入子组件
import { Home } from '../components/Home'
import { Qna } from '../components/Qna'
import { Advice } from '../components/Advice'

interface TabItem {
  title: string,
  icon: Resource,
  activeIcon: Resource
}

@Entry
@Component
struct Index {
  @State message: string = 'Hello World';
  private tabList: TabItem[] = [
    { title: '首页', icon: $r('app.media.home'), activeIcon: $r('app.media.home_active') },
    { title: 'AI问答', icon: $r('app.media.flower'), activeIcon: $r('app.media.flower_active') },
    { title: '种植建议', icon: $r('app.media.advice'), activeIcon: $r('app.media.advice_active') },
  ]
  @State currentIdx: number = 0

  // 自定义构建函数推荐使用大写开头，为了和 UI 组件保持一致
  @Builder
  CustomTabBar(icon: Resource, activeIcon: Resource, title: string, idx: number) {
    Column() {
      Image(this.currentIdx === idx ? activeIcon : icon).width(26)
      Text(title).fontColor(this.currentIdx === idx ? '#fff' : undefined)
    }
    .backgroundColor(this.currentIdx === idx ? '#0D631B' : undefined)
    .width(82)
    .height(56)
    .borderRadius(30)
    // 垂直居中
    .justifyContent(FlexAlign.Center)
    .padding({ left: 6, right: 6 })
    // 与下方的barHeight 一起，营造divider 呼吸感
    .margin({ top: 10 })
  }

  build() {
    Column() {
      // barPosition设置选项卡位置
      Tabs({ barPosition: BarPosition.End }) {
        ForEach(this.tabList, (item: TabItem, idx: number) => {
          TabContent() {
            // 条件判断显示对应的子组件
            if (idx === 0) {
              Home()
            } else if (idx === 1) {
              Qna()
            } else if (idx === 2) {
              Advice()
            }
          }
          // 选项卡样式，是一个函数
          // 选择1：传统样式
          /* .tabBar(BottomTabBarStyle
           // BottomTabBarStyle.of两个参数：分别是图标和名称
             .of(this.currentIdx === idx ? item.activeIcon : item.icon, item.title)
             // 设置字体颜色
             .labelStyle({ selectedColor: '#0D631B' })
           )*/
          // 选择2: 自定义构建
          .tabBar(this.CustomTabBar(item.icon, item.activeIcon, item.title, idx))
        })
      }
      //
      .onChange((idx: number) => this.currentIdx = idx)
      // 选项卡与上方内容分割线
      .divider({
        strokeWidth: 1,
        color: '#e5e5e5'
      })
      .barHeight(66)
    }
  }
}