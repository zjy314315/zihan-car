import router from '@ohos.router';
import { TCPClientManager } from '../tcp/TCPClientManager';
import { PreferencesUtils } from '../utils/PreferencesUtils';

@Entry
@Component
struct Index {
  @State carIp: string = '';
  @State isConnected: boolean = false;
  @State connLabel: string = '未连接';

  aboutToAppear(): void { this.checkStatus(); }
  onPageShow(): void { this.checkStatus(); }

  async checkStatus(): Promise<void> {
    this.isConnected = await TCPClientManager.getInstance().isConnect();
    if (this.isConnected) {
      this.carIp = await PreferencesUtils.getInstance().netUtils.getIP() as string;
      this.connLabel = `已连接 ${this.carIp}`;
    } else {
      this.connLabel = '未连接 · 请配置网络';
    }
  }

  build() {
    Column() {
      // ====== 顶部栏 ======
      Row({ space: '8vp' }) {
        Image($r('app.media.startLogo')).width('32vp').height('32vp').borderRadius('8vp').visibility(Visibility.Hidden)
        Text('智行小车').fontSize('16fp').fontWeight(FontWeight.Bold).fontColor('#111111')
        Blank()
        Circle({ width: '7vp', height: '7vp' }).fill(this.isConnected ? '#22c55e' : '#999999')
        Text(this.connLabel).fontSize('11fp').fontColor(this.isConnected ? '#333333' : '#999999').maxLines(1)
        Button('配置').fontSize('11fp').fontColor('#ffffff').backgroundColor('#1a1a1a')
          .borderRadius('6vp').padding({ left: '12vp', right: '12vp', top: '6vp', bottom: '6vp' })
          .onClick(() => { router.pushUrl({ url: 'pages/NetworkSettings' }) })
      }
      .width('100%').padding({ left: '12vp', right: '12vp', top: '10vp', bottom: '8vp' })
      .backgroundColor('#fafafa').border({ width: { bottom: '1vp' }, color: '#e5e5e5' })

      // ====== 3×2 功能入口 ======
      Grid() {
        GridItem() { FuncCard({ title: '麦克纳姆轮', desc: '全向移动 · 独立轮控', char: 'M', action: () => { router.pushUrl({ url: 'pages/MecanumWheel' }) } }) }
        GridItem() { FuncCard({ title: '单独控制', desc: '方向操控 · 巡线模式', char: 'C', action: () => { router.pushUrl({ url: 'pages/RemoteControl' }) } }) }
        GridItem() { FuncCard({ title: '人脸识别', desc: '身份注册 · 智能识别', char: 'F', action: () => { router.pushUrl({ url: 'pages/FaceRecognition' }) } }) }
        GridItem() { FuncCard({ title: '摔倒检测', desc: 'YOLO 监控 · 安全告警', char: 'S', action: () => { router.pushUrl({ url: 'pages/FallDetection' }) } }) }
        GridItem() { FuncCard({ title: '音乐播放', desc: '车载蜂鸣 · 音量调节', char: 'M', action: () => { router.pushUrl({ url: 'pages/MusicPlayer' }) } }) }
      }
      .columnsTemplate('1fr 1fr 1fr')
      .rowsTemplate('1fr 1fr')
      .columnsGap('10vp').rowsGap('10vp')
      .width('100%').layoutWeight(1)
      .padding('10vp')
    }
    .width('100%').height('100%').backgroundColor('#ffffff')
  }
}

@Component
struct FuncCard {
  title: string = '';
  desc: string = '';
  char: string = '';
  action: () => void = () => {};

  build() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: '10vp' }) {
        Column() {
          Text(this.char).fontSize('20fp').fontWeight(FontWeight.Bold).fontColor('#333333')
        }
        .width('44vp').height('44vp').borderRadius('10vp')
        .backgroundColor('#f1f1f1').justifyContent(FlexAlign.Center)

        Column({ space: '2vp' }) {
          Text(this.title).fontSize('13fp').fontWeight(FontWeight.Bold).fontColor('#111111')
          Text(this.desc).fontSize('10fp').fontColor('#999999').maxLines(1)
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1)

        Text('›').fontSize('18fp').fontColor('#cccccc')
      }
      .width('100%').padding('10vp').alignItems(VerticalAlign.Center)
    }
    .width('100%').height('100%')
    .backgroundColor('#fafafa').border({ width: '1vp', color: '#e5e5e5' }).borderRadius('14vp')
    .onClick(() => { this.action() })
  }
}
