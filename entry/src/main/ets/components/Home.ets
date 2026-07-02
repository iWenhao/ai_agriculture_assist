// 首页

// http 1: 先导入
import { http } from '@kit.NetworkKit';

interface ServiceItem {
  name: string,
  icon: Resource
}

interface NewsItem {
  pic: Resource,
  title: string,
  channel: string,
  time: string
}

// 天气数据
interface WeatherNow {
  temp: string; // 温度
  text: string; // 天气状况
  humidity: string; // 湿度
  windScale: string; // 风力等级
}

@Component
export struct Home {
  private serviceList: ServiceItem[] = [
    { name: "作物管理", icon: $r('app.media.corp') },
    { name: "水肥一体", icon: $r('app.media.water') },
    { name: "害虫防治", icon: $r('app.media.insect') },
    { name: "农技库", icon: $r('app.media.book') }
  ]
  private newsList: NewsItem[] = [
    {
      pic: $r('app.media.news1'),
      title: '2024年大豆玉米带状复合种植关键技术要点',
      channel: '农技频道',
      time: '2小时前'
    }, {
    pic: $r('app.media.news2'),
    title: '智能无人机在果园精准是要中的应用案例分享',
    channel: '智慧农业',
    time: '5小时前'
  }
  ]
  // --- 天气状态变量 ---
  @State weatherInfo: WeatherNow | null = null;

  // 获取天气数据
  private async loadWeather() {
    // http 2: http.createHttp()创建连接
    const httpRequest = http.createHttp();
    const city = '杨凌';
    const targetUrl = `http://gggg.bt1.886966.xyz/API/tttt.php`;
    const requestUrl = `${targetUrl}?city=${city}&n=1`;
    try {
      // console.log('=====天气请求开始======');
      // http 3: 使用request 方法请求
      const response = await httpRequest.request(requestUrl, {
        method: http.RequestMethod.GET,
        // expectDataType: http.HttpDataType.STRING
      });
      // console.log('天气请求结果>>>>>>', JSON.stringify(response));
      if (response.responseCode === 200) {
        this.parseWeatherText(response.result as string);
      }
    } catch (err) {
      console.error('天气请求失败', err);
    } finally {
      // 一定要销毁，减少内存开销
      httpRequest.destroy();
    }
  }

  // 从纯文本中解析天气数据
  private parseWeatherText(text: string): void {
    // 以换行符 \n为分隔，把字符串拆成一个字符串数组
    const lines = text.split('\n');
    // console.log('lines', lines);
    let temp = '';
    let weatherText = '';
    let humidity = '';
    let windScale = '';

    // 数组循环
    for (const line of lines) {
      // console.log('line',line)
      const trimmed = line.trim();
      if (trimmed.startsWith('温度：') && temp === '') {
        // substring(3) 字符串截取到结尾
        // 等价于
        // str.substring(3, str.length);
        temp = trimmed.substring(3);
        // console.log('temp',temp)
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

  // 组件生命周期：即将出现时触发网络请求
  aboutToAppear(): void {
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

  build() {
    Scroll() {
      Column({ space: 30 }) {
        // Text('首页')
        // 顶部图片
        // 层叠布局使文字放在图片上
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

        // 农事建议
        Row({ space: 5 }) {
          Column({ space: 8 }) {
            // 默认16vp
            Text('农事建议').fontColor('#854D00').fontSize(14)

            /*Text('当前是小麦追肥的最佳时期')
            Text('今天天气：22度，晴，湿度45%').fontSize(14)*/

            if (this.weatherInfo) {
              Text(this.getShortAdvice())
              Text(`今日天气：${this.weatherInfo.text}，${this.weatherInfo.temp}，湿度${this.weatherInfo.humidity}`)
                .fontSize(12).fontColor('#666666')
            } else {
              Text('正在获取天气...').fontSize(13).fontColor('#999999')
            }
          }
          // 纵向布局靠左对齐
          .alignItems(HorizontalAlign.Start)

          Column({ space: 5 }) {
            Image($r('app.media.sun')).width(30)
            Text(this.getRightTag()).fontSize(14).fontColor('#854D00')
          }
        }
        .width('100%')
        .padding({
          left: 20,
          right: 20,
          top: 12,
          bottom: 12
        })
        .backgroundColor('#FFF')
        // 两端对齐
        .justifyContent(FlexAlign.SpaceBetween)
        .borderRadius(10)
        // 左侧样式
        .border({
          width: { left: 4 },
          color: '#FF9E00'
        })

        // 核心服务
        Column() {
          Row() {
            Text('核心服务')
              .fontColor('#333333')
              .fontSize(14)
              .width('100%') // 关键点：让文字组件占满整行宽度,不加文字无法靠左
          }

          Row() {
            ForEach(this.serviceList, (item: ServiceItem) => {
              Column({ space: 5 }) {
                // 外层的大背景盒子（定宽定高）
                Stack({ alignContent: Alignment.Center }) {

                  //  内层的精致小图标（尺寸明显小于外层）
                  Image(item.icon)
                    .width(24)  // 【关键1】图标很小
                    .height(24) // 保持宽高一致

                }
                .width(60) // 【关键2】背景盒子很大，足足有 60vp
                .height(60) // 形成 60 vs 24 的大小对比
                .backgroundColor('#FFFFFF') // 纯白背景
                .borderRadius(20)
                .margin({ bottom: 5 })

                Text(item.name).fontSize(14).fontWeight(FontWeight.Bold)
              }

            })
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceAround)
          .margin({ top: 15 })
        }

        // 最新农讯
        Column() {
          Row() {
            Text('最新农讯')
              .fontColor('#333333')
              .fontSize(14)
              .width('100%')
              .margin({ bottom: 20 })
          }

          Column({ space: 15 }) {
            ForEach(this.newsList, (item: NewsItem) => {
              Row() {
                Image(item.pic).width(90)
                Column() {
                  Text(item.title)
                  Row() {
                    Text(item.channel)
                      .fontSize(12)
                    Text(item.time)
                      .fontSize(12)
                      .margin({ left: 10 })
                  }
                }
                .padding(10)
                // 同时使用height和SpaceBetween可以实现文字向上下两边分来
                .height(90)
                .justifyContent(FlexAlign.SpaceBetween)
                .alignItems(HorizontalAlign.Start) // 让文字全部靠左
                .layoutWeight(1) // 实现title 折行，不知道自己的边界在哪
                .backgroundColor('#fff')
              }
              .borderRadius(10)
              .clip(true) // 开启裁剪！相当于 overflow: hidden
            }
            )
          }
        }

      }
      // .height('100%')
      .backgroundColor('#F5F5F5')
      .padding({
        top: 10,
        bottom: 10,
        left: 10,
        right: 10
      })
    }
    .width('100%')
    .height('100%')
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto) // 设置滚动条为自动隐藏（滑动时才出现）
  }
}