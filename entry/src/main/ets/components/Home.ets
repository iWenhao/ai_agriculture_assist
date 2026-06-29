import { http } from '@kit.NetworkKit';

// ================= 类型定义 (严格模式规范) =================

// 天气内层数据接口
interface WeatherNow {
  temp: string;
  text: string;
  humidity: string;
}

// 和风天气 API 返回的整体结构接口
interface WeatherResponse {
  code: string | number;
  now: WeatherNow;
}

interface ServiceItem {
  name: string;
  icon: Resource;
}

interface NewsItem {
  pic: Resource;
  title: string;
  channel: string;
  time: string;
}

// ================= 组件实现 =================

@Component
export struct Home {
  // --- 状态变量 ---
  @State weatherInfo: WeatherNow | null = null;
  // --- 静态数据 ---
  private serviceList: ServiceItem[] = [
    { name: "作物管理", icon: $r('app.media.corp') },
    { name: "水肥一体", icon: $r('app.media.water') },
    { name: "害虫防治", icon: $r('app.media.insect') },
    { name: "农技库", icon: $r('app.media.book') }
  ];
  private newsList: NewsItem[] = [
    {
      pic: $r('app.media.news1'),
      title: '2024年大豆玉米带状复合种植关键技术要点',
      channel: '农技频道',
      time: '2小时前'
    },
    {
      pic: $r('app.media.news2'),
      title: '智能无人机在果园精准施药中的应用案例分享',
      channel: '智慧农业',
      time: '5小时前'
    }
  ];

  // 组件生命周期：即将出现时触发网络请求
  aboutToAppear(): void {
    console.log('99999999999999999999');
    this.loadWeather();
  }

  // 获取天气数据
  private async loadWeather() {
    console.log('=====请求开始');
    const httpRequest = http.createHttp();
    // 替换为你的实际 API Key，101110101 为渭南城市 ID
    const LocationID = '101110101'
    const API_KEY = '2b5955f84f4842399f17983ee9f84264'
    // const url = `https://n967cfxv4v.re.qweatherapi.com/v7/weather/now?location=${LocationID}`;
    const url = 'https://sbtxqq.icu/api/qqtq.php?msg=%E8%A5%BF%E5%AE%89'
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'X-QW-Api-Key': API_KEY        // 3. 全新鉴权规范：将 Key 放在 Header
        }
      });
      console.log('response ====>', JSON.stringify(response))
      if (response.responseCode === 200) {
        // 使用类型断言，完美解决 arkts-no-any-unknown 警告
        const res = JSON.parse(response.result as string) as WeatherResponse;
        console.log('HTTP ====>', res)
        if (res.code === 200) {
          console.log('res==>', res);
          this.weatherInfo = {
            temp: res.now.temp,
            text: res.now.text,
            humidity: res.now.humidity
          };
        }
      }
    } catch (err) {
      // console.error('天气请求失败', err);
    } finally {
      httpRequest.destroy();
    }
  }

  build() {
    // 1. 最外层套上 Scroll 组件实现全局滚动
    Scroll() {
      // 2. 内部主容器（绝对不能写 height('100%')）
      Column({ space: 30 }) {

        // --- 顶部图片 ---
        Stack({ alignContent: Alignment.Start }) {
          Image($r('app.media.home_top'))
            .width('100%')
            .borderRadius(10)
          Text('智慧农业，触手可及')
            .fontColor('#fff')
            .fontSize(22)
            .fontWeight(600)
            .width(120)
            .margin({ left: 20 })
        }

        // --- 农事建议 ---
        Row({ space: 5 }) {
          Column({ space: 8 }) {
            Text('农事建议').fontColor('#854D00').fontSize(14).fontWeight(FontWeight.Bold)
            Text('当前是小麦追肥的最佳时期').fontSize(13)

            // 动态绑定天气数据
            Text(this.weatherInfo ?
              `今天天气：${this.weatherInfo.temp}℃，${this.weatherInfo.text}，湿度${this.weatherInfo.humidity}%` :
              '正在获取天气...')
              .fontSize(13)
              .fontColor('#666666')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1) // 自动推开右侧

          Column({ space: 5 }) {
            Image($r('app.media.sun')).width(30)
            Text('宜施肥').fontSize(14).fontColor('#854D00').fontWeight(FontWeight.Bold)
          }
        }
        .width('100%')
        .padding(20)
        .backgroundColor('#FFF')
        .borderRadius(10)
        .border({ width: { left: 4 }, color: '#FF9E00' })

        // --- 核心服务 ---
        Column() {
          Text('核心服务')
            .fontColor('#333333')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .width('100%') // 占满整行，确保靠左

          Row() {
            ForEach(this.serviceList, (item: ServiceItem) => {
              Column({ space: 8 }) {
                // 外层大白盒 60x60，内层小图标 24x24
                Stack({ alignContent: Alignment.Center }) {
                  Image(item.icon).width(24).height(24)
                }
                .width(60)
                .height(60)
                .backgroundColor('#FFFFFF')
                .borderRadius(20)

                Text(item.name).fontSize(13).fontWeight(500)
              }
            })
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween) // 均匀分布
          .margin({ top: 15 })
        }

        // --- 最新农讯 ---
        Column() {
          Text('最新农讯')
            .fontColor('#333333')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .width('100%')
            .margin({ bottom: 15 })

          Column({ space: 15 }) {
            ForEach(this.newsList, (item: NewsItem) => {
              Row({ space: 15 }) {
                // 图片单独切圆角
                Image(item.pic)
                  .width(90)
                  .height(90)
                  .borderRadius(8)

                // 右侧文字区
                Column() {
                  Text(item.title)
                    .width('100%')
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#333333')
                    .lineHeight(22) // 增加呼吸感
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .wordBreak(WordBreak.BREAK_ALL) // 防止长英文不换行

                  Blank() // 核心：像弹簧一样把频道和时间推到最下面

                  Row() {
                    Text(item.channel).fontSize(12).fontColor('#999999')
                    Text(item.time).fontSize(12).fontColor('#999999')
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.SpaceBetween) // 左右推开
                }
                .height(90) // 必须和图片一样高，Blank才能生效
                .layoutWeight(1) // 占满右侧剩余空间，让标题知道何时折行
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding(12)
              .backgroundColor('#FFFFFF')
              .borderRadius(10)
              .clip(true) // 外围裁切溢出部分
            })
          }
        }
      }
      .width('100%')
      .padding({
        top: 10,
        bottom: 20,
        left: 15,
        right: 15
      }) // 给底部留点余量
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring) // 添加高级的边缘回弹效果
  }
}