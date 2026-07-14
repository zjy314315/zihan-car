import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import http from '@ohos.net.http';
import { PreferencesUtils } from '../utils/PreferencesUtils';
import { TCPClientManager } from '../tcp/TCPClientManager';
import { VideoComponents } from '../components/VideoComponents';

interface FallResult { status: string; confidence: number; detail: string; enabled: boolean; }
interface YoloPerson { box: number[]; conf: number; }
interface YoloData { enabled: boolean; people: YoloPerson[]; }
interface FaceData { name: string; status: string; }
interface LatestResult { face: FaceData; yolo: YoloData; fall: FallResult; timestamp: string | null; }
interface StatusResponse { running: boolean; face_enabled: boolean; yolo_enabled: boolean; fall_enabled: boolean; latest_result: LatestResult; }

const AUTO_REFRESH_MS: number = 1500; // auto-refresh interval: 1.5 seconds

@Entry
@Component
struct FallDetection {
  @State serviceBaseUrl: string = 'http://10.168.202.242:5000';
  @State resultText: string = '等待数据...';
  @State isConnected: boolean = false;
  @State isMonitoring: boolean = false;
  @State fallStatus: string = '未启动';
  @State fallConfidence: number = 0;
  @State peopleCount: number = 0;
  @State isFallAlarm: boolean = false;
  @State isRunning: boolean = false;
  @State carIp: string = '';
  @State lastUpdateTime: string = '--';
  @State fallDetail: string = '';
  @State refreshCount: number = 0;
  @State alarmFlash: boolean = false;
  @State fallEventCount: number = 0;
  @State showAlertBanner: boolean = false;
  @State buzzerSeconds: number = 0;
  private autoRefreshTimer: number = -1;
  private buzzerTimer: number = -1;

  aboutToAppear(): void { this.initPage(); }
  aboutToDisappear(): void { this.stopAutoRefresh(); }
  async initPage(): Promise<void> {
    this.carIp = await PreferencesUtils.getInstance().netUtils.getIP() as string;
    this.serviceBaseUrl = `http://${this.carIp}:5000`;
    await this.waitLifecycle(700);
    this.isConnected = await TCPClientManager.getInstance().isConnect();
    if (this.isConnected) { await this.getStatus(); }
  }

  build() {
    Column() {
      // ====== ?????? ======
  private async waitLifecycle(ms: number): Promise<void> {
    await new Promise<void>((resolve) => { setTimeout(() => resolve(), ms); });
  }

  private startAutoRefresh(): void {
    if (this.autoRefreshTimer >= 0) return; // already running
    this.autoRefreshTimer = setInterval(() => {
      this.getResult();
    }, AUTO_REFRESH_MS);
  }

  private stopAutoRefresh(): void {
    if (this.autoRefreshTimer >= 0) {
      clearInterval(this.autoRefreshTimer);
      this.autoRefreshTimer = -1;
    }
  }

  private async startMonitor(): Promise<void> {
    // Enable YOLO + fall detection on the server
    await this.callService(http.RequestMethod.POST, '/start_yolo');
    let result = await this.callService(http.RequestMethod.POST, '/start_fall');
    if (result.includes('error') || result.includes('失败')) {
      promptAction.showToast({ message: '启动失败，请检查连接' });
      return;
    }
    this.isMonitoring = true;
    this.isRunning = true;
    this.fallStatus = '监控中';
    promptAction.showToast({ message: '摔倒检测已启动' });
    this.startAutoRefresh();
    await this.getResult();
  }

  private async stopMonitor(): Promise<void> {
    this.stopAutoRefresh();
    if (this.buzzerTimer >= 0) { clearInterval(this.buzzerTimer); this.buzzerTimer = -1; }
    await this.callService(http.RequestMethod.POST, '/stop_fall');
    this.isMonitoring = false;
    this.isRunning = false;
    this.fallStatus = '已停止';
    this.fallConfidence = 0;
    this.peopleCount = 0;
    this.isFallAlarm = false;
    this.fallDetail = '';
    this.buzzerSeconds = 0;
    promptAction.showToast({ message: '已停止' });
  }

  private async startAll(): Promise<void> {
    const result = await this.callService(http.RequestMethod.POST, '/start_all');
    if (!result.includes('error')) {
      this.isMonitoring = true;
      this.isRunning = true;
      promptAction.showToast({ message: '全部功能已启动' });
      this.startAutoRefresh();
      await this.getResult();
    }
    this.resultText = result;
  }

  private async getStatus(): Promise<void> {
    const result = await this.callService(http.RequestMethod.GET, '/status');
    try {
      const data: StatusResponse = JSON.parse(result) as StatusResponse;
      this.isMonitoring = data.fall_enabled;
      this.isRunning = data.running;
      if (this.isMonitoring) {
        this.startAutoRefresh();
      }
    } catch { /* */ }
    this.resultText = result;
  }

  private async getResult(): Promise<void> {
    const result = await this.callService(http.RequestMethod.GET, '/result');
    this.resultText = result;
    this.parseResult(result);
    this.lastUpdateTime = this.formatTime();
    this.refreshCount++;
  }

  private parseResult(result: string): void {
    if (!result) return;
    try {
      const data: LatestResult = JSON.parse(result) as LatestResult;
      if (data.fall) {
        const prevAlarm = this.isFallAlarm;
        switch (data.fall.status) {
          case 'fall_detected':
            this.fallStatus = '摔倒!';
            this.isFallAlarm = true;
            if (!prevAlarm) {
              promptAction.showToast({ message: '检测到摔倒! 蜂鸣器已启动3秒', duration: 3000 });
              // Start 3-second buzzer countdown display
              this.buzzerSeconds = 3;
              if (this.buzzerTimer >= 0) clearInterval(this.buzzerTimer);
              this.buzzerTimer = setInterval(() => {
                this.buzzerSeconds--;
                if (this.buzzerSeconds <= 0) {
                  clearInterval(this.buzzerTimer);
                  this.buzzerTimer = -1;
                }
              }, 1000);
            }
            break;
          case 'no_person':
            this.fallStatus = '无人';
            if (this.buzzerSeconds <= 0) this.isFallAlarm = false;
            break;
          case 'monitoring':
            this.fallStatus = '监控中';
            if (this.buzzerSeconds <= 0) this.isFallAlarm = false;
            break;
          case 'normal':
            this.fallStatus = '正常';
            if (this.buzzerSeconds <= 0) this.isFallAlarm = false;
            break;
          case 'fall_disabled':
            this.fallStatus = '未启用';
            this.isFallAlarm = false;
            this.buzzerSeconds = 0;
            break;
          default:
            this.fallStatus = data.fall.status;
            if (this.buzzerSeconds <= 0) this.isFallAlarm = false;
        }
        this.fallConfidence = data.fall.confidence || 0;
        if (data.fall.detail) {
          this.fallDetail = data.fall.detail;
        }
      }
      if (data.yolo && data.yolo.people) {
        this.peopleCount = data.yolo.people.length;
      }
      if (data.timestamp) {
        this.lastUpdateTime = data.timestamp;
      }
    } catch { /* */ }
  }

  private formatTime(): string {
    const now = new Date();
    const h = now.getHours().toString().padStart(2, '0');
    const m = now.getMinutes().toString().padStart(2, '0');
    const s = now.getSeconds().toString().padStart(2, '0');
    return `${h}:${m}:${s}`;
  }

  private async callService(method: http.RequestMethod, path: string, payload?: Object): Promise<string> {
    const requestUrl = `${this.serviceBaseUrl.trim().replace(/\/$/, '')}${path}`;
    const httpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await new Promise((resolve, reject) => {
        httpRequest.request(requestUrl, {
          method: method, header: { 'Content-Type': 'application/json' },
          expectDataType: http.HttpDataType.STRING, connectTimeout: 5000, readTimeout: 5000,
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
  @Prop highlight: boolean = false;

  build() {
    Column({ space: '2vp' }) {
      Text(this.value)
        .fontSize('14fp').fontWeight(FontWeight.Bold)
        .fontColor(this.highlight ? '#dc2626' : '#111111')
        .maxLines(1)
      Text(this.label).fontSize('9fp').fontColor('#999999')
    }
    .layoutWeight(1).padding('6vp')
    .backgroundColor(this.highlight ? '#fef2f2' : '#fafafa')
    .borderRadius('6vp')
    .border({ width: this.highlight ? '1vp' : '0vp', color: '#fecaca' })
  }
}
