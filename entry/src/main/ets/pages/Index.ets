import router from '@ohos.router';
import { TCPClientManager } from '../tcp/TCPClientManager';
import { PreferencesUtils } from '../utils/PreferencesUtils';
import { VideoComponents } from '../components/VideoComponents';

@Entry
@Component
struct Index {
  @State carIp: string = '';
  @State isConnected: boolean = false;
  @State connLabel: string = '暂未连接';

  aboutToAppear(): void { this.checkStatus(); }
  onPageShow(): void { this.checkStatus(); }

  async checkStatus(): Promise<void> {
    this.carIp = await PreferencesUtils.getInstance().netUtils.getIP() as string;
    this.isConnected = await TCPClientManager.getInstance().isConnect();
    if (this.isConnected) {
      this.connLabel = `已连接 ${this.carIp}`;
      // 恢复视频连接地址（否则 VideoComponents 会一直用默认 IP）
      VideoComponents.ip = this.carIp;
      let vp: string = await PreferencesUtils.getInstance().netUtils.getVideoPort() as string;
      VideoComponents.port = Number.parseInt(vp);
    } else {
      this.connLabel = '暂未连接';
    }
  }

  build() {
    Column() {
      Row({ space: '12vp' }) {
        Column() {
          Text('智能小车').fontSize('12fp').fontWeight(FontWeight.Bold).fontColor('#707072')
          Text('控制中心').fontSize('28fp').fontWeight(FontWeight.Bold).fontColor('#111111')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('配置')
          .height('44vp').fontSize('14fp').fontWeight(FontWeight.Medium).fontColor('#ffffff')
          .backgroundColor('#111111').borderRadius('24vp').padding({ left: '18vp', right: '18vp' })
          .onClick(() => { router.pushUrl({ url: 'pages/NetworkSettings' }) })
      }
      .width('100%').padding({ left: '20vp', right: '20vp', top: '20vp', bottom: '16vp' })

      Scroll() {
        Column({ space: '28vp' }) {
          Row({ space: '8vp' }) {
            Circle({ width: '9vp', height: '9vp' }).fill(this.isConnected ? '#007d48' : '#9e9ea0')
            Text(this.connLabel).fontSize('13fp').fontWeight(FontWeight.Medium)
              .fontColor(this.isConnected ? '#39393b' : '#707072').maxLines(1)
            Blank()
            Text(this.isConnected ? '在线' : '离线').fontSize('11fp').fontWeight(FontWeight.Bold)
              .fontColor(this.isConnected ? '#007d48' : '#707072')
          }
          .width('100%').padding({ left: '16vp', right: '16vp', top: '12vp', bottom: '12vp' })
          .backgroundColor('#f5f5f5').borderRadius('24vp')

          Column({ space: '4vp' }) {
            Text('功能入口').fontSize('12fp').fontWeight(FontWeight.Bold).fontColor('#707072')
            Text('选择你的操作方式').fontSize('22fp').fontWeight(FontWeight.Bold).fontColor('#111111')
          }.width('100%').alignItems(HorizontalAlign.Start)

          Grid() {
            GridItem() { FuncCard({ title: '麦克纳姆轮', desc: '独立轮速与全向移动', tag: '驾驶', action: () => { router.pushUrl({ url: 'pages/MecanumWheel' }) } }) }
            GridItem() { FuncCard({ title: '遥控驾驶', desc: '实时画面与方向控制', tag: '操控', action: () => { router.pushUrl({ url: 'pages/RemoteControl' }) } }) }
            GridItem() { FuncCard({ title: '人脸识别', desc: '身份登记与智能识别', tag: '视觉', action: () => { router.pushUrl({ url: 'pages/FaceRecognition' }) } }) }
            GridItem() { FuncCard({ title: '跌倒监测', desc: 'YOLO 安全检测守护', tag: '安全', action: () => { router.pushUrl({ url: 'pages/FallDetection' }) } }) }
            GridItem() { FuncCard({ title: '声音控制', desc: '蜂鸣器与律动模式', tag: '音效', action: () => { router.pushUrl({ url: 'pages/MusicPlayer' }) } }) }
            GridItem() { FuncCard({ title: '小车编队', desc: '领航跟随与自动编队', tag: '编队', action: () => { router.pushUrl({ url: 'pages/FormationControl' }) } }) }
            GridItem() { FuncCard({ title: '智能对话', desc: '文字提问与语音回复', tag: 'AI', action: () => { router.pushUrl({ url: 'pages/SmartDialogue' }) } }) }
            GridItem() { FuncCard({ title: '基础功能', desc: '跟随导航与避障', tag: '导航', action: () => { router.pushUrl({ url: 'pages/AutoFunctions' }) } }) }
            GridItem() { FuncCard({ title: '建图导航', desc: 'SLAM 建图与自动巡查', tag: '地图', action: () => { router.pushUrl({ url: 'pages/MappingNav' }) } }) }
          }
          .columnsTemplate('1fr 1fr').columnsGap('12vp').rowsGap('12vp').width('100%')

          Text('随时响应，稳定掌控每一次移动。').fontSize('13fp').fontColor('#707072')
            .width('100%').textAlign(TextAlign.Center).margin({ top: '4vp' })
        }
        .width('100%').padding({ left: '20vp', right: '20vp', bottom: '36vp' })
      }
      .layoutWeight(1).width('100%').scrollBar(BarState.Auto)
    }
    .width('100%').height('100%').backgroundColor('#ffffff')
  }
}

@Component
struct FuncCard {
  title: string = '';
  desc: string = '';
  tag: string = '';
  action: () => void = () => {};

  build() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: '18vp' }) {
        Row() {
          Text(this.tag).fontSize('10fp').fontWeight(FontWeight.Bold).fontColor('#111111')
            .padding({ left: '10vp', right: '10vp', top: '5vp', bottom: '5vp' }).backgroundColor('#ffffff').borderRadius('16vp')
          Blank()
          Text('>').fontSize('20fp').fontColor('#111111')
        }.width('100%')
        Column({ space: '6vp' }) {
          Text(this.title).fontSize('20fp').fontWeight(FontWeight.Bold).fontColor('#111111').maxLines(1)
          Text(this.desc).fontSize('12fp').fontColor('#707072').maxLines(2)
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
      .width('100%').height('100%').alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.SpaceBetween)
      .padding('16vp')
    }
    .width('100%').height('164vp').backgroundColor('#f5f5f5').borderRadius('24vp')
    .onClick(() => { this.action() })
  }
}
