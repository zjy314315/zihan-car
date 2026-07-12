import { TCPClientManager } from '../tcp/TCPClientManager'
import { TCPClientSendUtils } from '../tcp/TCPClientSendUtils'
import promptAction from '@ohos.promptAction'
import router from '@ohos.router'
import { PreferencesUtils } from '../utils/PreferencesUtils'
import { VideoComponents } from '../components/VideoComponents'
import { ButtonShadow } from '../styles/styles'
import { MyUtils } from '../utils/MyUtils'

@Entry
@Component
struct NetworkSettings {
  build() {
    Column({ space: '12vp' }) {
      Row() {
        Button('返回')
          .backgroundColor('#111827')
          .fontColor('#ffffff')
          .borderRadius('12vp')
          .shadow(ButtonShadow)
          .onClick(() => { router.back(); })
          .padding({ left: '14vp', right: '14vp', top: '10vp', bottom: '10vp' })
      }
      .width('100%')
      .padding({ top: '24vp', left: '16vp', right: '16vp', bottom: '4vp' })

      Scroll() {
        Column() {
          LoginComponent({
            connectSuccessRun: () => { router.pushUrl({ url: 'pages/Index' }) },
            connectfailRun: () => { if (MyUtils.isDebug) router.pushUrl({ url: 'pages/Index' }) }
          })
            .width('100%')
        }
        .padding({ left: '16vp', right: '16vp', bottom: '20vp' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#ffffff')
  }
}

@Component
struct LoginComponent {
  TextWidth: Length = '80vp';
  FontSize: Length = '20fp'
  BlankWidth: Length = '10vp'
  @State ip: string = '192.168.1.11'
  @State tcpPort: string = '6000'
  @State videoPort: string = '6500'
  connectSuccessRun = () => {}
  connectfailRun = () => {}

  aboutToAppear(): void {
    this.readNetConfig();
  }

  build() {
    Column({ space: '16vp' }) {
      Row({ space: '12vp' }) {
        Text('IP:')
          .width(this.TextWidth)
          .textAlign(TextAlign.End)
          .fontSize(this.FontSize)
          .fontColor('#111827')
        Blank().width(this.BlankWidth)
        TextInput({ text: this.ip })
          .onChange((v) => this.ip = v)
          .layoutWeight(1)
          .backgroundColor('#f1f5f9')
          .fontColor('#111827')
          .padding({ left: '14vp', right: '14vp', top: '12vp', bottom: '12vp' })
      }

      Row({ space: '12vp' }) {
        Text('Port:')
          .width(this.TextWidth)
          .textAlign(TextAlign.End)
          .fontSize(this.FontSize)
          .fontColor('#111827')
        Blank().width(this.BlankWidth)
        TextInput({ text: this.tcpPort })
          .onChange((v) => this.tcpPort = v)
          .layoutWeight(1)
          .backgroundColor('#f1f5f9')
          .fontColor('#111827')
          .padding({ left: '14vp', right: '14vp', top: '12vp', bottom: '12vp' })
      }

      Row({ space: '12vp' }) {
        Text('Video:')
          .width(this.TextWidth)
          .textAlign(TextAlign.End)
          .fontSize(this.FontSize)
          .fontColor('#111827')
        Blank().width(this.BlankWidth)
        TextInput({ text: this.videoPort })
          .onChange((v) => this.videoPort = v)
          .layoutWeight(1)
          .backgroundColor('#f1f5f9')
          .fontColor('#111827')
          .padding({ left: '14vp', right: '14vp', top: '12vp', bottom: '12vp' })
      }

      Button('连接')
        .width('200vp')
        .backgroundColor('#2563eb')
        .fontColor('#ffffff')
        .shadow(ButtonShadow)
        .borderRadius('16vp')
        .onClick(() => {
          this.saveNetConfig();
          this.initTcpConfig();
          VideoComponents.ip = this.ip;
          VideoComponents.port = Number.parseInt(this.videoPort);
        })
    }
    .padding('24vp')
    .backgroundColor('#f8fafc')
    .borderRadius('24vp')
    .border({ width: '1vp', color: '#e2e8f0' })
  }

  private async initTcpConfig() {
    let address = this.ip;
    TCPClientManager.getInstance().initNetAddress({ address: address, port: Number.parseInt(this.tcpPort) });
    let isConnect = await TCPClientManager.getInstance().connect();
    if (isConnect) {
      promptAction.showToast({ message: '连接成功' });
      TCPClientSendUtils.getInstance().init();
      this.connectSuccessRun();
    } else {
      promptAction.showToast({ message: '连接失败，请检查信息' });
      this.connectfailRun();
    }
  }

  private readNetConfig() {
    PreferencesUtils.getInstance().netUtils.getIP().then((v) => this.ip = v as string);
    PreferencesUtils.getInstance().netUtils.getTcpPort().then((v) => this.tcpPort = v as string);
    PreferencesUtils.getInstance().netUtils.getVideoPort().then((v) => this.videoPort = v as string);
  }

  private async saveNetConfig() {
    await PreferencesUtils.getInstance().netUtils.setIp(this.ip);
    await PreferencesUtils.getInstance().netUtils.setTcpPort(this.tcpPort);
    await PreferencesUtils.getInstance().netUtils.setVideoPort(this.videoPort);
  }
}
