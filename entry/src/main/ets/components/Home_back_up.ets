import { http } from '@kit.NetworkKit';


// 天气数据（仅保留农事建议用到的字段）
interface WeatherNow {
  temp: string;       // 温度
  text: string;       // 天气状况
  humidity: string;   // 湿度
  windScale: string;  // 风力等级
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

  // 根据天气生成简短农事建议（10字左右）
  private getShortAdvice(): string {
    if (!this.weatherInfo) {
      return '';
    }
    const w = this.weatherInfo;
    const tempNum = parseInt(w.temp);
    const humNum = parseInt(w.humidity);
    const windNum = parseInt(w.windScale);

    // 降雨优先
    if (w.text === '暴雨' || w.text === '大雨' || w.text === '中雨' || w.text === '雨' || w.text === '小雨') {
      return '不宜施肥，注意排水';
    }
    if (w.text === '雪') {
      return '做好防冻，减少作业';
    }
    // 大风优先
    if (windNum >= 5) {
      return '暂停喷药，注意防风';
    }
    // 高温
    if (tempNum >= 35) {
      return '注意遮阳，避开正午';
    }
    // 低温
    if (tempNum < 10) {
      return '注意防冻，暂缓施肥';
    }
    // 高湿
    if (humNum >= 80) {
      return '湿度偏高，注意防病';
    }
    // 干燥
    if (humNum <= 30) {
      return '空气干燥，及时灌溉';
    }
    // 晴天/多云等正常天气
    if (w.text === '晴') {
      return '适宜施肥，注意补水';
    }
    if (w.text === '阴' || w.text === '多云') {
      return '注意补光，适宜施肥';
    }
    return '适宜田间管理作业';
  }

  // 根据天气生成右侧短标签（宜xx / 不宜xx）
  private getRightTag(): string {
    if (!this.weatherInfo) {
      return '加载中';
    }
    const w = this.weatherInfo;
    const tempNum = parseInt(w.temp);
    const windNum = parseInt(w.windScale);

    if (w.text === '暴雨' || w.text === '大雨' || w.text === '中雨' || w.text === '雨' || w.text === '小雨') {
      return '宜排涝';
    }
    if (w.text === '雪') {
      return '宜防冻';
    }
    if (windNum >= 5) {
      return '不宜喷药';
    }
    if (tempNum >= 35) {
      return '宜遮阳';
    }
    if (tempNum < 10) {
      return '不宜施肥';
    }
    return '宜施肥';
  }

  // 从纯文本中解析天气数据（只提取需要的4个字段）
  private parseWeatherText(text: string): void {
    const lines = text.split('\n');
    let temp = '';
    let weatherText = '';
    let humidity = '';
    let windScale = '';

    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.startsWith('温度：') && temp === '') {
        temp = trimmed.substring(3);
      } else if (trimmed.startsWith('天气：') && weatherText === '') {
        weatherText = trimmed.substring(3);
      } else if (trimmed.startsWith('湿度：')) {
        humidity = trimmed.substring(3);
      } else if (trimmed.startsWith('风力：') && windScale === '') {
        windScale = trimmed.substring(3);
      }
    }

    this.weatherInfo = {
      temp: temp,
      text: weatherText,
      humidity: humidity,
      windScale: windScale
    };
  }

  // 获取天气数据
  private async loadWeather() {
    const httpRequest = http.createHttp();
    const city = '杨凌';
    const targetUrl = `http://gggg.bt1.886966.xyz/API/tttt.php`;
    const requestUrl = `${targetUrl}?city=${city}&n=1`;
    try {
      console.log('=====天气请求开始');
      const response = await httpRequest.request(requestUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 8000,
        readTimeout: 8000
      });
      console.log('response>>>>>>', JSON.stringify(response));
      if (response.responseCode === 200) {
        this.parseWeatherText(response.result as string);
      }
    } catch (err) {
      console.error('天气请求失败', err);
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

            if (this.weatherInfo) {
              Text(this.getShortAdvice())
                .fontSize(13).fontColor('#333333')
              Text(`今日天气：${this.weatherInfo.text}，${this.weatherInfo.temp}℃，湿度${this.weatherInfo.humidity}%`)
                .fontSize(12).fontColor('#666666')
            } else {
              Text('正在获取天气...').fontSize(13).fontColor('#999999')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Column({ space: 5 }) {
            Image($r('app.media.sun')).width(30)
            Text(this.getRightTag())
              .fontSize(14).fontColor('#854D00').fontWeight(FontWeight.Bold)
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