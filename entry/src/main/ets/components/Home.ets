import { http } from '@kit.NetworkKit';


// 天气内层数据接口
interface WeatherNow {
  district: string;   // 地区
  temp: string;       // 温度
  text: string;       // 天气状况
  humidity: string;   // 湿度
  windDir: string;    // 风向
  windScale: string;  // 风力等级
  aqi: string;        // AQI
  aqiText: string;    // AQI 描述
  body: string;       // 体感描述
}

// 五天预报单日数据
interface ForecastDay {
  date: string;       // 日期
  week: string;       // 星期
  tempRange: string;  // 温度范围
  text: string;       // 天气
  aqi: string;        // AQI
  windDir: string;    // 风向
  windScale: string;  // 风力
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
  @State forecastList: ForecastDay[] = [];
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

  // 从纯文本中解析天气数据
  private parseWeatherText(text: string): void {
    const lines = text.split('\n');

    // --- 解析实时天气 ---
    let district = '';
    let temp = '';
    let weatherText = '';
    let body = '';
    let windDir = '';
    let windScale = '';
    let humidity = '';
    let aqi = '';
    let aqiText = '';

    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.startsWith('地区：')) {
        district = trimmed.substring(3);
      } else if (trimmed.startsWith('温度：') && temp === '') {
        temp = trimmed.substring(3);
      } else if (trimmed.startsWith('天气：') && weatherText === '') {
        weatherText = trimmed.substring(3);
      } else if (trimmed.startsWith('体感：')) {
        body = trimmed.substring(3);
      } else if (trimmed.startsWith('风向：') && windDir === '') {
        windDir = trimmed.substring(3);
      } else if (trimmed.startsWith('风力：') && windScale === '') {
        windScale = trimmed.substring(3);
      } else if (trimmed.startsWith('湿度：')) {
        humidity = trimmed.substring(3);
      } else if (trimmed.startsWith('AQI：') && aqi === '') {
        const aqiStr = trimmed.substring(4);
        // AQI 格式如 “49 优”，用最后一个空格分隔数值和描述
        const lastSpace = aqiStr.lastIndexOf(' ');
        if (lastSpace > -1) {
          aqi = aqiStr.substring(0, lastSpace);
          aqiText = aqiStr.substring(lastSpace + 1);
        } else {
          aqi = aqiStr;
        }
      }
    }

    this.weatherInfo = {
      district: district,
      temp: temp,
      text: weatherText,
      humidity: humidity,
      windDir: windDir,
      windScale: windScale,
      aqi: aqi,
      aqiText: aqiText,
      body: body
    };

    // --- 解析五天预报 ---
    const forecast: ForecastDay[] = [];
    let curDate = '';
    let curWeek = '';
    let curTempRange = '';
    let curText = '';
    let curAqi = '';
    let curWindDir = '';
    let curWindScale = '';

    let inForecast = false;
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed === '五天预报：') {
        inForecast = true;
        continue;
      }
      if (!inForecast) {
        continue;
      }
      if (trimmed === '') {
        if (curDate !== '') {
          forecast.push({ date: curDate, week: curWeek, tempRange: curTempRange, text: curText, aqi: curAqi, windDir: curWindDir, windScale: curWindScale });
          curDate = ''; curWeek = ''; curTempRange = ''; curText = ''; curAqi = ''; curWindDir = ''; curWindScale = '';
        }
        continue;
      }
      if (trimmed.startsWith('日期：')) {
        if (curDate !== '') {
          forecast.push({ date: curDate, week: curWeek, tempRange: curTempRange, text: curText, aqi: curAqi, windDir: curWindDir, windScale: curWindScale });
          curDate = ''; curWeek = ''; curTempRange = ''; curText = ''; curAqi = ''; curWindDir = ''; curWindScale = '';
        }
        curDate = trimmed.substring(3);
      } else if (trimmed.startsWith('星期：')) {
        curWeek = trimmed.substring(3);
      } else if (trimmed.startsWith('温度：')) {
        curTempRange = trimmed.substring(3);
      } else if (trimmed.startsWith('天气：')) {
        curText = trimmed.substring(3);
      } else if (trimmed.startsWith('AQI：')) {
        curAqi = trimmed.substring(4);
      } else if (trimmed.startsWith('风向：')) {
        curWindDir = trimmed.substring(3);
      } else if (trimmed.startsWith('风力：')) {
        curWindScale = trimmed.substring(3);
      }
    }
    // 别漏掉最后一天
    if (curDate !== '') {
      forecast.push({ date: curDate, week: curWeek, tempRange: curTempRange, text: curText, aqi: curAqi, windDir: curWindDir, windScale: curWindScale });
    }
    this.forecastList = forecast;
    console.log('weatherInfo parsed:', JSON.stringify(this.weatherInfo));
    console.log('forecastList parsed:', JSON.stringify(this.forecastList));
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

        // --- 实时天气卡片 ---
        Column({ space: 10 }) {
          // 标题行：地区 + AQI 标签
          Row() {
            Text(this.weatherInfo ? this.weatherInfo.district : '天气加载中...')
              .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333')
            Blank()
            if (this.weatherInfo && this.weatherInfo.aqi) {
              Text(`AQI ${this.weatherInfo.aqi} ${this.weatherInfo.aqiText}`)
                .fontSize(12).fontColor('#fff')
                .backgroundColor(this.weatherInfo.aqiText === '优' ? '#4CAF50' : '#FF9800')
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .borderRadius(10)
            }
          }
          .width('100%')

          if (this.weatherInfo) {
            // 核心温度 + 天气状况
            Row() {
              Text(this.weatherInfo.temp)
                .fontSize(42).fontWeight(FontWeight.Bold).fontColor('#FF6B35')
              Text(`℃\n${this.weatherInfo.text}`)
                .fontSize(16).fontColor('#666666').margin({ left: 4 })
              Blank()
              // 体感提示
              if (this.weatherInfo.body) {
                Text(this.weatherInfo.body)
                  .fontSize(12).fontColor('#999999').maxLines(2)
                  .constraintSize({ maxWidth: '40%' }).textAlign(TextAlign.End)
              }
            }
            .width('100%')

            // 详细信息行
            Row() {
              Text(`💧 湿度 ${this.weatherInfo.humidity}`)
                .fontSize(13).fontColor('#666')
              Text(`🌬 ${this.weatherInfo.windDir} ${this.weatherInfo.windScale}`)
                .fontSize(13).fontColor('#666')
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
          } else {
            Text('正在获取天气数据...')
              .fontSize(14).fontColor('#999999')
              .width('100%').textAlign(TextAlign.Center)
              .padding(20)
          }

          // --- 五天预报 ---
          if (this.forecastList.length > 0) {
            Column({ space: 8 }) {
              Text('未来五天').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#333')
                .width('100%').margin({ top: 4 })
              ForEach(this.forecastList, (day: ForecastDay) => {
                Row() {
                  Text(day.date).fontSize(13).fontColor('#333').width(50)
                  Text(day.week).fontSize(13).fontColor('#999').width(40)
                  Text(day.text).fontSize(13).fontColor('#333').width(60)
                  Text(day.tempRange).fontSize(13).fontColor('#FF6B35')
                  Blank()
                  Text(`${day.windDir} ${day.windScale}`).fontSize(12).fontColor('#999')
                }
                .width('100%')
                .padding({ top: 6, bottom: 6 })
              })
            }
            .width('100%')
          }
        }
        .width('100%')
        .padding(20)
        .backgroundColor('#FFF')
        .borderRadius(10)
        .border({ width: { left: 4 }, color: '#FF9E00' })

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
          .layoutWeight(1)

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