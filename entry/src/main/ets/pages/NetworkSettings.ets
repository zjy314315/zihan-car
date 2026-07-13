import { TCPClientManager } from '../tcp/TCPClientManager'
import { TCPClientSendUtils } from '../tcp/TCPClientSendUtils'
import promptAction from '@ohos.promptAction'
import router from '@ohos.router'
import socket from '@ohos.net.socket'
import { PreferencesUtils } from '../utils/PreferencesUtils'
import { VideoComponents } from '../components/VideoComponents'
import { ButtonShadow } from '../styles/styles'
import { MyUtils } from '../utils/MyUtils'
import util from '@ohos.util'

// ---- 小车信息 ----
interface CarInfo {
  name: string; ip: string; tcp_port: number; monitor_port: number; video_port: number;
}
interface BindInfo { address: string; port: number; family: number; }

@Entry
@Component
struct NetworkSettings {
  @State isScanning: boolean = false
  @State carList: CarInfo[] = []
  @State scanText: string = '开始扫描'
  @State showManual: boolean = false

  private udpSocket: socket.UDPSocket | null = null
  private seenCars: Set<string> = new Set()

  aboutToDisappear(): void { this.stopScan() }

  build() {
    Column({ space: '12vp' }) {
      // 顶栏
      Row() {
        Button('返回').backgroundColor('#111827').fontColor('#ffffff')
          .borderRadius('12vp').shadow(ButtonShadow)
          .onClick(() => { this.stopScan(); router.back(); })
          .padding({ left: '14vp', right: '14vp', top: '10vp', bottom: '10vp' })
      }
      .width('100%').padding({ top: '24vp', left: '16vp', right: '16vp', bottom: '4vp' })

      Scroll() {
        Column({ space: '14vp' }) {
          // ====== 扫描区域 ======
          Column({ space: '10vp' }) {
            Row({ space: '10vp' }) {
              Text('发现小车').fontSize('16fp').fontWeight(FontWeight.Bold).fontColor('#111827')
              Blank()
              Button(this.scanText)
                .fontSize('12fp').fontColor('#ffffff')
                .backgroundColor(this.isScanning ? '#dc2626' : '#2563eb')
                .borderRadius('10vp')
                .padding({ left: '14vp', right: '14vp', top: '8vp', bottom: '8vp' })
                .onClick(() => { this.isScanning ? this.stopScan() : this.startScan() })
            }
            .width('100%')

            if (this.isScanning) {
              Row({ space: '6vp' }) {
                LoadingProgress().width('14vp').height('14vp').color('#2563eb')
                Text('正在扫描附近小车...').fontSize('12fp').fontColor('#6b7280')
              }
              .width('100%').padding('6vp')
            }

            // 小车列表
            if (this.carList.length > 0) {
              List({ space: '8vp' }) {
                ForEach(this.carList, (car: CarInfo, index: number) => {
                  ListItem() { this.CarCard(car) }
                }, (car: CarInfo, index: number) => car.ip + car.name)
              }
              .width('100%').height('220vp').divider({ strokeWidth: '1vp', color: '#f1f5f9' })
            } else if (!this.isScanning) {
              Text('点击「开始扫描」发现附近小车').fontSize('13fp').fontColor('#9ca3af')
                .padding('20vp').width('100%').textAlign(TextAlign.Center)
            }
          }
          .padding('16vp').backgroundColor('#f8fafc').borderRadius('16vp')
          .border({ width: '1vp', color: '#e2e8f0' })

          // ====== 手动输入 ======
          Row({ space: '8vp' }) {
            Text('手动配置').fontSize('16fp').fontWeight(FontWeight.Bold).fontColor('#111827')
            Blank()
            Button(this.showManual ? '收起' : '展开')
              .fontSize('12fp').fontColor('#6b7280').backgroundColor('#f1f5f9')
              .borderRadius('8vp').padding({ left: '12vp', right: '12vp', top: '6vp', bottom: '6vp' })
              .onClick(() => { this.showManual = !this.showManual })
          }
          .width('100%')

          if (this.showManual) {
            LoginComponent({
              connectSuccessRun: () => { router.pushUrl({ url: 'pages/Index' }) },
              connectfailRun: () => { if (MyUtils.isDebug) router.pushUrl({ url: 'pages/Index' }) }
            })
          }
        }
        .padding({ left: '16vp', right: '16vp', bottom: '20vp' })
      }
    }
    .width('100%').height('100%').backgroundColor('#ffffff')
  }

  @Builder CarCard(car: CarInfo) {
    Row({ space: '10vp' }) {
      Column() {
        Text(car.name)
          .fontSize('13fp').fontWeight(FontWeight.Bold).fontColor('#111827').maxLines(1)
        Text(car.ip)
          .fontSize('11fp').fontColor('#6b7280')
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)

      Column({ space: '2vp' }) {
        Text('T:' + car.tcp_port.toString()).fontSize('9fp').fontColor('#9ca3af')
        Text('V:' + car.video_port.toString()).fontSize('9fp').fontColor('#9ca3af')
      }

      Button('连接')
        .fontSize('12fp').fontColor('#ffffff').backgroundColor('#22c55e')
        .borderRadius('8vp').padding({ left: '12vp', right: '12vp', top: '6vp', bottom: '6vp' })
        .onClick(() => { this.selectCar(car) })
    }
    .width('100%').padding('10vp')
    .backgroundColor('#ffffff').borderRadius('10vp')
    .border({ width: '1vp', color: '#e5e7eb' })
  }

  // ====== UDP 扫描 ======
  private async startScan(): Promise<void> {
    this.carList = []
    this.seenCars.clear()
    this.isScanning = true
    this.scanText = '停止扫描'

    try {
      this.udpSocket = socket.constructUDPSocketInstance()
      let opts: BindInfo = { address: '0.0.0.0', port: 9999, family: 1 }
      await this.udpSocket.bind(opts)
      this.udpSocket.on('message', (value: socket.SocketMessageInfo) => {
        let msg: string = this.buf2String(value.message)
        try {
          let car: CarInfo = JSON.parse(msg) as CarInfo
          let key: string = car.ip + ':' + car.tcp_port.toString()
          if (!this.seenCars.has(key)) {
            this.seenCars.add(key)
            let newList: CarInfo[] = this.carList.concat([car])
            this.carList = newList
          }
        } catch { /* skip bad json */ }
      })
      promptAction.showToast({ message: '开始扫描' })
    } catch (e) {
      promptAction.showToast({ message: 'UDP 绑定失败' })
      this.stopScan()
    }
  }

  private stopScan(): void {
    this.isScanning = false
    this.scanText = '开始扫描'
    if (this.udpSocket) {
      try { this.udpSocket.close() } catch { /* ok */ }
      this.udpSocket = null
    }
  }

  private async selectCar(car: CarInfo): Promise<void> {
    this.stopScan()
    await PreferencesUtils.getInstance().netUtils.setIp(car.ip)
    await PreferencesUtils.getInstance().netUtils.setTcpPort(car.tcp_port.toString())
    await PreferencesUtils.getInstance().netUtils.setVideoPort(car.video_port.toString())
    VideoComponents.ip = car.ip
    VideoComponents.port = car.video_port
    let addr: socket.NetAddress = { address: car.ip, port: car.tcp_port, family: 1 }
    TCPClientManager.getInstance().initNetAddress(addr)
    let ok: boolean = await TCPClientManager.getInstance().connect()
    if (ok) {
      promptAction.showToast({ message: '已连接 ' + car.name })
      TCPClientSendUtils.getInstance().init()
      router.pushUrl({ url: 'pages/Index' })
    } else {
      promptAction.showToast({ message: '连接失败' })
      if (MyUtils.isDebug) router.pushUrl({ url: 'pages/Index' })
    }
  }

  private buf2String(buf: ArrayBuffer): string {
    let decoder: util.TextDecoder = new util.TextDecoder('utf-8')
    let uint8: Uint8Array = new Uint8Array(buf)
    return decoder.decode(uint8, { stream: false })
  }
}

// ====== 手动输入组件（保留原有逻辑） ======
@Component
struct LoginComponent {
  TextWidth: Length = '80vp'
  FontSize: Length = '20fp'
  BlankWidth: Length = '10vp'
  @State ip: string = '192.168.1.11'
  @State tcpPort: string = '6000'
  @State videoPort: string = '6500'
  connectSuccessRun: () => void = () => {}
  connectfailRun: () => void = () => {}

  aboutToAppear(): void { this.readNetConfig() }

  build() {
    Column({ space: '16vp' }) {
      Row({ space: '12vp' }) {
        Text('IP:').width(this.TextWidth).textAlign(TextAlign.End).fontSize(this.FontSize).fontColor('#111827')
        Blank().width(this.BlankWidth)
        TextInput({ text: this.ip }).onChange((v) => { this.ip = v })
          .layoutWeight(1).backgroundColor('#f1f5f9').fontColor('#111827')
          .padding({ left: '14vp', right: '14vp', top: '12vp', bottom: '12vp' })
      }

      Row({ space: '12vp' }) {
        Text('Port:').width(this.TextWidth).textAlign(TextAlign.End).fontSize(this.FontSize).fontColor('#111827')
        Blank().width(this.BlankWidth)
        TextInput({ text: this.tcpPort }).onChange((v) => { this.tcpPort = v })
          .layoutWeight(1).backgroundColor('#f1f5f9').fontColor('#111827')
          .padding({ left: '14vp', right: '14vp', top: '12vp', bottom: '12vp' })
      }

      Row({ space: '12vp' }) {
        Text('Video:').width(this.TextWidth).textAlign(TextAlign.End).fontSize(this.FontSize).fontColor('#111827')
        Blank().width(this.BlankWidth)
        TextInput({ text: this.videoPort }).onChange((v) => { this.videoPort = v })
          .layoutWeight(1).backgroundColor('#f1f5f9').fontColor('#111827')
          .padding({ left: '14vp', right: '14vp', top: '12vp', bottom: '12vp' })
      }

      Button('连接')
        .width('200vp').backgroundColor('#2563eb').fontColor('#ffffff')
        .shadow(ButtonShadow).borderRadius('16vp')
        .onClick(() => { this.saveNetConfig(); this.initTcpConfig();
          VideoComponents.ip = this.ip; VideoComponents.port = Number.parseInt(this.videoPort) })
    }
    .padding('24vp').backgroundColor('#f8fafc').borderRadius('24vp')
    .border({ width: '1vp', color: '#e2e8f0' })
  }

  private async initTcpConfig(): Promise<void> {
    let address: string = this.ip
    TCPClientManager.getInstance().initNetAddress({ address: address, port: Number.parseInt(this.tcpPort), family: 1 })
    let isConnect: boolean = await TCPClientManager.getInstance().connect()
    if (isConnect) {
      promptAction.showToast({ message: '连接成功' })
      TCPClientSendUtils.getInstance().init()
      this.connectSuccessRun()
    } else {
      promptAction.showToast({ message: '连接失败，请检查信息' })
      this.connectfailRun()
    }
  }

  private readNetConfig(): void {
    PreferencesUtils.getInstance().netUtils.getIP().then((v) => { this.ip = v as string })
    PreferencesUtils.getInstance().netUtils.getTcpPort().then((v) => { this.tcpPort = v as string })
    PreferencesUtils.getInstance().netUtils.getVideoPort().then((v) => { this.videoPort = v as string })
  }

  private async saveNetConfig(): Promise<void> {
    await PreferencesUtils.getInstance().netUtils.setIp(this.ip)
    await PreferencesUtils.getInstance().netUtils.setTcpPort(this.tcpPort)
    await PreferencesUtils.getInstance().netUtils.setVideoPort(this.videoPort)
  }
}
