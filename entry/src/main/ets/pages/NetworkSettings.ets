import { TCPClientManager } from '../tcp/TCPClientManager'
import { TCPClientSendUtils } from '../tcp/TCPClientSendUtils'
import promptAction from '@ohos.promptAction'
import router from '@ohos.router'
import socket from '@ohos.net.socket'
import { PreferencesUtils } from '../utils/PreferencesUtils'
import { VideoComponents } from '../components/VideoComponents'
import { MyUtils } from '../utils/MyUtils'
import util from '@ohos.util'

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
    Column() {
      Row({ space: '12vp' }) {
        Button('<')
          .width('44vp').height('44vp').fontSize('22fp').fontColor('#111111')
          .backgroundColor('#f5f5f5').borderRadius('22vp')
          .onClick(() => { this.stopScan(); router.back(); })
        Column() {
          Text('连接配置').fontSize('11fp').fontWeight(FontWeight.Bold).fontColor('#707072')
          Text('网络设置').fontSize('26fp').fontWeight(FontWeight.Bold).fontColor('#111111')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%').padding({ left: '20vp', right: '20vp', top: '20vp', bottom: '16vp' })

      Scroll() {
        Column({ space: '24vp' }) {
          Column({ space: '14vp' }) {
            Row() {
              Column({ space: '5vp' }) {
                Text('自动发现').fontSize('12fp').fontWeight(FontWeight.Bold).fontColor('#707072')
                Text('扫描附近小车').fontSize('22fp').fontWeight(FontWeight.Bold).fontColor('#111111')
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Button(this.scanText)
                .height('44vp').fontSize('14fp').fontWeight(FontWeight.Medium)
                .fontColor(this.isScanning ? '#111111' : '#ffffff')
                .backgroundColor(this.isScanning ? '#ffffff' : '#111111')
                .borderRadius('24vp').padding({ left: '18vp', right: '18vp' })
                .onClick(() => { this.isScanning ? this.stopScan() : this.startScan() })
            }.width('100%')

            if (this.isScanning) {
              Row({ space: '8vp' }) {
                LoadingProgress().width('16vp').height('16vp').color('#111111')
                Text('正在扫描附近小车...').fontSize('13fp').fontColor('#707072')
              }.width('100%').padding({ top: '6vp', bottom: '6vp' })
            }

            if (this.carList.length > 0) {
              List({ space: '10vp' }) {
                ForEach(this.carList, (car: CarInfo, index: number) => {
                  ListItem() { this.CarCard(car) }
                }, (car: CarInfo, index: number) => car.ip + car.name)
              }.width('100%').height('220vp')
            } else if (!this.isScanning) {
              Text('点击开始扫描，自动读取小车 IP、控制端口和视频端口。')
                .fontSize('13fp').fontColor('#707072')
                .padding('18vp').width('100%').textAlign(TextAlign.Center)
                .backgroundColor('#ffffff').borderRadius('18vp')
            }
          }
          .width('100%').padding('20vp').backgroundColor('#f5f5f5').borderRadius('24vp')

          Column({ space: '12vp' }) {
            Row() {
              Column({ space: '5vp' }) {
                Text('手动配置').fontSize('12fp').fontWeight(FontWeight.Bold).fontColor('#707072')
                Text('填写连接信息').fontSize('22fp').fontWeight(FontWeight.Bold).fontColor('#111111')
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Button(this.showManual ? '收起' : '展开')
                .height('42vp').fontSize('14fp').fontColor('#111111')
                .backgroundColor('#ffffff').borderRadius('22vp').padding({ left: '18vp', right: '18vp' })
                .onClick(() => { this.showManual = !this.showManual })
            }.width('100%')

            if (this.showManual) {
              LoginComponent({
                connectSuccessRun: () => { router.pushUrl({ url: 'pages/Index' }) },
                connectfailRun: () => { if (MyUtils.isDebug) router.pushUrl({ url: 'pages/Index' }) }
              })
            }
          }
          .width('100%').padding('20vp').backgroundColor('#f5f5f5').borderRadius('24vp')
        }
        .width('100%').padding({ left: '20vp', right: '20vp', bottom: '36vp' })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
    }
    .width('100%').height('100%').backgroundColor('#ffffff')
  }

  @Builder CarCard(car: CarInfo) {
    Row({ space: '12vp' }) {
      Column({ space: '3vp' }) {
        Text(car.name).fontSize('16fp').fontWeight(FontWeight.Bold).fontColor('#111111').maxLines(1)
        Text(car.ip).fontSize('13fp').fontColor('#707072')
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)

      Column({ space: '2vp' }) {
        Text('TCP ' + car.tcp_port.toString()).fontSize('10fp').fontWeight(FontWeight.Bold).fontColor('#707072')
        Text('视频 ' + car.video_port.toString()).fontSize('10fp').fontWeight(FontWeight.Bold).fontColor('#707072')
      }.alignItems(HorizontalAlign.End)

      Button('连接')
        .height('42vp').fontSize('14fp').fontColor('#ffffff').backgroundColor('#111111')
        .borderRadius('22vp').padding({ left: '18vp', right: '18vp' })
        .onClick(() => { this.selectCar(car) })
    }
    .width('100%').padding('14vp')
    .backgroundColor('#ffffff').borderRadius('18vp')
  }

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

@Component
struct LoginComponent {
  @State ip: string = '192.168.1.11'
  @State tcpPort: string = '6000'
  @State videoPort: string = '5000'
  connectSuccessRun: () => void = () => {}
  connectfailRun: () => void = () => {}

  aboutToAppear(): void { this.readNetConfig() }

  build() {
    Column({ space: '14vp' }) {
      NetworkField({ label: '车辆 IP 地址', value: $ip })
      NetworkField({ label: 'TCP 端口', value: $tcpPort })
      NetworkField({ label: '视频端口', value: $videoPort })
      Button('连接小车')
        .width('100%').height('52vp').fontSize('16fp').fontWeight(FontWeight.Medium)
        .fontColor('#ffffff').backgroundColor('#111111').borderRadius('28vp')
        .onClick(() => {
          this.saveNetConfig()
          this.initTcpConfig()
          VideoComponents.ip = this.ip
          VideoComponents.port = Number.parseInt(this.videoPort)
        })
    }.width('100%')
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

@Component
struct NetworkField {
  label: string = ''
  @Link value: string

  build() {
    Column({ space: '8vp' }) {
      Text(this.label).fontSize('11fp').fontWeight(FontWeight.Bold).fontColor('#707072')
      TextInput({ text: this.value })
        .height('50vp').fontSize('16fp').fontColor('#111111')
        .backgroundColor('#ffffff').borderRadius('24vp')
        .padding({ left: '18vp', right: '18vp' })
        .onChange((v: string) => { this.value = v })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
