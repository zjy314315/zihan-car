import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import http from '@ohos.net.http';
import { PreferencesUtils } from '../utils/PreferencesUtils';
import { TCPClientManager } from '../tcp/TCPClientManager';
import { VideoComponents } from '../components/VideoComponents';

interface FallResult { status: string; confidence: number; detail: string; enabled: boolean; }
interface YoloPerson { box_coords: number[]; confidence: number; label: string; }
interface YoloData { enabled: boolean; people: YoloPerson[]; }
interface FaceData { name: string; status: string; }
interface LatestResult { face: FaceData; yolo: YoloData; fall: FallResult; timestamp: string | null; }
interface StatusResponse { running: boolean; face_enabled: boolean; yolo_enabled: boolean; fall_enabled: boolean; latest_result: LatestResult; }

@Entry
@Component
struct FallDetection {
  @State serviceBaseUrl: string = 'http://192.168.1.11:5001';
  @State resultText: string = '等待数据...';
  @State isConnected: boolean = false;
  @State isMonitoring: boolean = false;
  @State fallStatus: string = '未启动';
  @State fallConfidence: number = 0;
  @State peopleCount: number = 0;
  @State isFallAlarm: boolean = false;
  @State isRunning: boolean = false;
  @State carIp: string = '';

  aboutToAppear(): void { this.initPage(); }
  async initPage(): Promise<void> {
    this.carIp = await PreferencesUtils.getInstance().netUtils.getIP() as string;
    this.serviceBaseUrl = `http://${this.carIp}:5001`;
    this.isConnected = await TCPClientManager.getInstance().isConnect();
    if (this.isConnected) { await this.getStatus(); }
  }

  build() {
    Column() {
      // ====== 顶部栏 ======
      Row({ space: '8vp' }) {
        Button('← 返回')
          .fontSize('12fp').fontColor('#ffffff').backgroundColor('#1a1a1a')
          .borderRadius('6vp').padding({ left: '10vp', right: '10vp', top: '6vp', bottom: '6vp' })
          .onClick(() => { router.back(); })
        Text('摔倒检测').fontSize('15fp').fontWeight(FontWeight.Bold).fontColor('#111111')
        Blank()
        Circle({ width: '7vp', height: '7vp' }).fill(this.isConnected ? '#22c55e' : '#999999')
        Text(this.isConnected ? `已连接 ${this.carIp}` : '未连接').fontSize('11fp')
          .fontColor(this.isConnected ? '#333333' : '#999999')
        Text(this.isRunning ? ' | 运行中' : ' | 待机').fontSize('11fp')
          .fontColor(this.isRunning ? '#333333' : '#cccccc')
      }
      .width('100%').padding({ left: '10vp', right: '10vp', top: '8vp', bottom: '6vp' })
      .backgroundColor('#fafafa').border({ width: { bottom: '1vp' }, color: '#e5e5e5' })

      // ====== 主体 ======
      Row({ space: '8vp' }) {
        // 左侧：视频
        Column({ space: '4vp' }) {
          VideoComponents({ showControls: false, videoWidth: '100%', videoHeight: '100%' })
            .borderRadius('10vp').layoutWeight(1)
        }
        .width('0vp').layoutWeight(5.5).padding('6vp')
        .backgroundColor('#fafafa').borderRadius('12vp').border({ width: '1vp', color: '#e5e5e5' })

        // 右侧：面板
        Column({ space: '6vp' }) {
          // 告警条
          Row() {
            Text(this.isFallAlarm ? 'DETECTED' : (this.isMonitoring ? 'MONITORING' : 'STANDBY'))
              .fontSize('13fp').fontWeight(FontWeight.Bold).fontColor('#ffffff')
          }
          .width('100%').padding('8vp')
          .backgroundColor(this.isFallAlarm ? '#1a1a1a' : (this.isMonitoring ? '#555555' : '#999999'))
          .borderRadius('6vp').justifyContent(FlexAlign.Center)

          // 指标
          Row({ space: '4vp' }) {
            MetricTile({ label: '状态', value: this.fallStatus })
            MetricTile({ label: '人数', value: `${this.peopleCount}` })
            MetricTile({ label: '置信度', value: this.fallConfidence.toFixed(2) })
          }

          // 按钮
          Row({ space: '5vp' }) {
            Button(this.isMonitoring ? '停止' : '开始')
              .layoutWeight(1).fontSize('12fp').fontColor('#ffffff')
              .backgroundColor(this.isMonitoring ? '#555555' : '#1a1a1a')
              .borderRadius('6vp').height('34vp')
              .onClick(() => { this.isMonitoring ? this.stopMonitor() : this.startMonitor(); })
            Button('一键全开')
              .layoutWeight(1).fontSize('12fp').fontColor('#ffffff').backgroundColor('#1a1a1a')
              .borderRadius('6vp').height('34vp')
              .onClick(() => { this.startAll(); })
          }
          Row({ space: '5vp' }) {
            Button('刷新').layoutWeight(1).fontSize('12fp').fontColor('#666666').backgroundColor('#f1f1f1')
              .borderRadius('6vp').height('32vp').onClick(() => { this.getResult(); })
            Button('状态').layoutWeight(1).fontSize('12fp').fontColor('#666666').backgroundColor('#f1f1f1')
              .borderRadius('6vp').height('32vp').onClick(() => { this.getStatus(); })
          }

          Text(this.resultText).fontSize('9fp').fontColor('#cccccc').lineHeight('12fp').maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            .padding('6vp').backgroundColor('#fafafa').borderRadius('6vp')
        }
        .width('0vp').layoutWeight(4.5).padding('8vp')
        .backgroundColor('#ffffff').borderRadius('12vp').border({ width: '1vp', color: '#e5e5e5' })
      }
      .width('100%').layoutWeight(1).padding('8vp')
    }
    .width('100%').height('100%').backgroundColor('#ffffff')
  }

  // ====== 业务逻辑 ======
  private async startMonitor(): Promise<void> {
    let result = await this.callService(http.RequestMethod.POST, '/start');
    if (result.includes('失败')) { promptAction.showToast({ message: '启动失败' }); return; }
    result = await this.callService(http.RequestMethod.POST, '/start_fall');
    if (!result.includes('error')) { this.isMonitoring = true; this.isRunning = true; promptAction.showToast({ message: '已启动' }); await this.getResult(); }
  }
  private async stopMonitor(): Promise<void> {
    await this.callService(http.RequestMethod.POST, '/stop_fall');
    this.isMonitoring = false; this.isRunning = false;
    this.fallStatus = '已停止'; this.fallConfidence = 0; this.peopleCount = 0; this.isFallAlarm = false;
    promptAction.showToast({ message: '已停止' });
  }
  private async startAll(): Promise<void> {
    const result = await this.callService(http.RequestMethod.POST, '/start_all');
    if (!result.includes('error')) { this.isMonitoring = true; this.isRunning = true; promptAction.showToast({ message: '全部已启动' }); await this.getResult(); }
    this.resultText = result;
  }
  private async getStatus(): Promise<void> {
    const result = await this.callService(http.RequestMethod.GET, '/status');
    try { const data: StatusResponse = JSON.parse(result) as StatusResponse; this.isMonitoring = data.running && data.fall_enabled; this.isRunning = data.running; } catch { /* */ }
    this.resultText = result;
  }
  private async getResult(): Promise<void> {
    const result = await this.callService(http.RequestMethod.GET, '/result');
    this.resultText = result; this.parseResult(result);
  }
  private parseResult(result: string): void {
    if (!result) return;
    try {
      const data: LatestResult = JSON.parse(result) as LatestResult;
      if (data.fall) {
        if (data.fall.status === 'fall_detected') { this.fallStatus = 'DETECTED'; this.isFallAlarm = true; }
        else if (data.fall.status === 'no_person') this.fallStatus = '无人';
        else if (data.fall.status === 'monitoring') this.fallStatus = '监控中';
        else if (data.fall.status === 'normal') this.fallStatus = '正常';
        else this.fallStatus = data.fall.status;
        this.fallConfidence = data.fall.confidence || 0;
      }
      if (data.yolo && data.yolo.people) this.peopleCount = data.yolo.people.length;
    } catch { /* */ }
  }
  private async callService(method: http.RequestMethod, path: string, payload?: Object): Promise<string> {
    const requestUrl = `${this.serviceBaseUrl.trim().replace(/\/$/, '')}${path}`;
    const httpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await new Promise((resolve, reject) => {
        httpRequest.request(requestUrl, {
          method: method, header: { 'Content-Type': 'application/json' },
          expectDataType: http.HttpDataType.STRING, connectTimeout: 10000, readTimeout: 10000,
          extraData: payload ? JSON.stringify(payload) : undefined
        }, (err, data) => { err ? reject(err) : resolve(data); });
      });
      return typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
    } catch (error) { return `请求失败`; }
    finally { httpRequest.destroy(); }
  }
}

@Component
struct MetricTile {
  @Prop label: string = '';
  @Prop value: string = '';

  build() {
    Column({ space: '2vp' }) {
      Text(this.value).fontSize('14fp').fontWeight(FontWeight.Bold).fontColor('#111111').maxLines(1)
      Text(this.label).fontSize('9fp').fontColor('#999999')
    }
    .layoutWeight(1).padding('6vp').backgroundColor('#fafafa').borderRadius('6vp')
  }
}
