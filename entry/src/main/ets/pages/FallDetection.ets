import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import http from '@ohos.net.http';
import geoLocationManager from '@ohos.geoLocationManager';
import { PreferencesUtils } from '../utils/PreferencesUtils';
import { TCPClientManager } from '../tcp/TCPClientManager';
import { VideoComponents } from '../components/VideoComponents';

interface FallResult { status: string; confidence: number; detail: string; enabled: boolean; }
interface YoloPerson { box: number[]; conf: number; }
interface YoloData { enabled: boolean; people: YoloPerson[]; }
interface FaceData { name: string; status: string; }
interface LatestResult { face: FaceData; yolo: YoloData; fall: FallResult; timestamp: string | null; }
interface StatusResponse { running: boolean; face_enabled: boolean; yolo_enabled: boolean; fall_enabled: boolean; latest_result: LatestResult; }

const AUTO_REFRESH_MS: number = 1500;
const AMAP_KEY: string = '4aa56ceebd276f40f94ae045085353c6';

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
  @State buzzerSeconds: number = 0;
  @State emergencyEmail: string = '';
  @State emailStatus: string = '';
  @State gpsLocation: string = '';
  private autoRefreshTimer: number = -1;
  private buzzerTimer: number = -1;

  aboutToAppear(): void { this.initPage(); }
  aboutToDisappear(): void { this.stopAutoRefresh(); }

  async initPage(): Promise<void> {
    this.carIp = await PreferencesUtils.getInstance().netUtils.getIP() as string;
    this.serviceBaseUrl = `http://${this.carIp}:5000`;
    // 优先从本地加载紧急邮箱，避免后端不可用时邮箱为空
    await this.loadLocalEmergencyEmail();
    this.isConnected = await TCPClientManager.getInstance().isConnect();
    if (this.isConnected) {
      await this.getStatus();
      await this.loadEmergencyConfig();
    }
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
        Text(this.isMonitoring ? '⟳ 实时' : '●').fontSize('9fp')
          .fontColor(this.isMonitoring ? '#22c55e' : '#999999')
        Circle({ width: '7vp', height: '7vp' }).fill(this.isConnected ? '#22c55e' : '#999999')
        Text(this.isConnected ? `已连接 ${this.carIp}` : '未连接').fontSize('11fp')
          .fontColor(this.isConnected ? '#333333' : '#999999')
        Text(this.isRunning ? ' | 运行中' : ' | 待机').fontSize('11fp')
          .fontColor(this.isRunning ? '#333333' : '#cccccc')
      }
      .width('100%').padding({ left: '10vp', right: '10vp', top: '8vp', bottom: '6vp' })
      .backgroundColor('#fafafa').border({ width: { bottom: '1vp' }, color: '#e5e5e5' })

      // ===== 摔倒告警横幅 =====
      if (this.isFallAlarm) {
        Column() {
          Row({ space: '6vp' }) {
            Text('🚨').fontSize('18fp')
            Text('检测到摔倒事件!').fontSize('14fp').fontWeight(FontWeight.Bold).fontColor('#ffffff')
            Text('🚨').fontSize('18fp')
          }.width('100%').justifyContent(FlexAlign.Center)
          Row({ space: '12vp' }) {
            Text(`置信度: ${this.fallConfidence.toFixed(2)}`).fontSize('11fp').fontColor('#fecaca')
            Text(`触发: ${this.fallDetail}`).fontSize('10fp').fontColor('#fca5a5').maxLines(1)
          }.width('100%').justifyContent(FlexAlign.Center).margin({ top: '4vp' })
          if (this.buzzerSeconds > 0) {
            Text(`🔊 蜂鸣器报警中... ${this.buzzerSeconds}s`).fontSize('11fp').fontColor('#fbbf24').margin({ top: '3vp' })
          }
          if (this.emailStatus) {
            Text(this.emailStatus).fontSize('11fp').fontColor('#fbbf24').margin({ top: '3vp' })
          }
          if (this.gpsLocation) {
            Text(`📍 ${this.gpsLocation}`).fontSize('10fp').fontColor('#fca5a5').maxLines(1).margin({ top: '3vp' })
          }
        }
        .width('100%').padding({ top: '6vp', bottom: '6vp', left: '10vp', right: '10vp' })
        .backgroundColor(this.alarmFlash ? '#dc2626' : '#991b1b')
        .animation({ duration: 400, curve: Curve.EaseInOut, delay: 0, iterations: -1 })
      }

      // ====== 主体 ======
      Row({ space: '8vp' }) {
        Column({ space: '4vp' }) {
          VideoComponents({ showControls: false, videoWidth: '100%', videoHeight: '100%' })
            .borderRadius('10vp').layoutWeight(1)
        }
        .width('0vp').layoutWeight(5.5).padding('6vp')
        .backgroundColor('#fafafa').borderRadius('12vp').border({ width: '1vp', color: '#e5e5e5' })

        Column({ space: '6vp' }) {
          Row() {
            Text(this.isFallAlarm ? '⚠ FALL DETECTED' : (this.isMonitoring ? '● MONITORING' : '○ STANDBY'))
              .fontSize('13fp').fontWeight(FontWeight.Bold).fontColor('#ffffff')
          }
          .width('100%').padding('8vp')
          .backgroundColor(this.isFallAlarm ?
            (this.alarmFlash ? '#dc2626' : '#991b1b') :
            (this.isMonitoring ? '#2563eb' : '#6b7280'))
          .borderRadius('6vp').justifyContent(FlexAlign.Center)
          .animation({ duration: 500, curve: Curve.EaseInOut, delay: 0, iterations: this.isFallAlarm ? -1 : 0 })

          Row({ space: '4vp' }) {
            MetricTile({ label: '状态', value: this.fallStatus, highlight: this.isFallAlarm })
            MetricTile({ label: '人数', value: `${this.peopleCount}`, highlight: false })
            MetricTile({ label: '置信度', value: this.fallConfidence.toFixed(2), highlight: this.isFallAlarm })
          }

          Row() {
            Text(this.fallDetail ? this.fallDetail : '等待检测...')
              .fontSize('10fp').fontColor(this.isFallAlarm ? '#dc2626' : '#666666')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%').padding('5vp').backgroundColor('#f5f5f5').borderRadius('4vp')

          Row({ space: '4vp' }) {
            Text('⏱').fontSize('9fp')
            Text(`更新: ${this.lastUpdateTime}`).fontSize('9fp').fontColor('#999999')
            Text(`(#${this.refreshCount})`).fontSize('8fp').fontColor('#cccccc')
          }

          Row({ space: '5vp' }) {
            Button(this.isMonitoring ? '⏹ 停止' : '▶ 开始')
              .layoutWeight(1).fontSize('12fp').fontColor('#ffffff')
              .backgroundColor(this.isMonitoring ? '#ef4444' : '#22c55e')
              .borderRadius('6vp').height('34vp')
              .onClick(() => { this.isMonitoring ? this.stopMonitor() : this.startMonitor(); })
            Button('⚡ 一键全开')
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

          Text(this.resultText).fontSize('9fp').fontColor('#cccccc').lineHeight('12fp').maxLines(3)
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
  private startAutoRefresh(): void {
    if (this.autoRefreshTimer >= 0) return;
    this.autoRefreshTimer = setInterval(() => { this.getResult(); }, AUTO_REFRESH_MS);
  }

  private stopAutoRefresh(): void {
    if (this.autoRefreshTimer >= 0) {
      clearInterval(this.autoRefreshTimer);
      this.autoRefreshTimer = -1;
    }
  }

  private async startMonitor(): Promise<void> {
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
    this.emailStatus = '';
    this.gpsLocation = '';
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
      this.isRunning = data.running || data.fall_enabled || data.yolo_enabled;
      if (this.isMonitoring) { this.startAutoRefresh(); }
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
              promptAction.showToast({ message: '检测到摔倒!', duration: 3000 });
              this.buzzerSeconds = 3;
              if (this.buzzerTimer >= 0) clearInterval(this.buzzerTimer);
              this.buzzerTimer = setInterval(() => {
                this.buzzerSeconds--;
                if (this.buzzerSeconds <= 0) { clearInterval(this.buzzerTimer); this.buzzerTimer = -1; }
              }, 1000);
              this.sendEmergencyNotification();
            }
            break;
          case 'no_person': this.fallStatus = '无人'; if (this.buzzerSeconds <= 0) this.isFallAlarm = false; break;
          case 'monitoring': this.fallStatus = '监控中'; if (this.buzzerSeconds <= 0) this.isFallAlarm = false; break;
          case 'normal': this.fallStatus = '正常'; if (this.buzzerSeconds <= 0) this.isFallAlarm = false; break;
          case 'fall_disabled': this.fallStatus = '未启用'; this.isFallAlarm = false; this.buzzerSeconds = 0; break;
          default: this.fallStatus = data.fall.status; if (this.buzzerSeconds <= 0) this.isFallAlarm = false;
        }
        this.fallConfidence = data.fall.confidence || 0;
        if (data.fall.detail) { this.fallDetail = data.fall.detail; }
      }
      if (data.yolo && data.yolo.people) { this.peopleCount = data.yolo.people.length; }
      if (data.timestamp) { this.lastUpdateTime = data.timestamp; }
    } catch { /* */ }
  }

  private formatTime(): string {
    const now = new Date();
    const h = now.getHours().toString().padStart(2, '0');
    const m = now.getMinutes().toString().padStart(2, '0');
    const s = now.getSeconds().toString().padStart(2, '0');
    return `${h}:${m}:${s}`;
  }

  private async callService(method: http.RequestMethod, path: string, payload?: Object, fullUrl?: string): Promise<string> {
    const requestUrl = fullUrl || `${this.serviceBaseUrl.trim().replace(/\/$/, '')}${path}`;
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

  // ===== 紧急联系人 + GPS + 邮件 =====
  private async loadLocalEmergencyEmail(): Promise<void> {
    // 优先从本地读取紧急邮箱（NetworkSettings 页面保存的）
    let localEmail: string = await PreferencesUtils.getInstance().netUtils.getEmergencyEmail();
    if (localEmail && localEmail.length > 0) {
      this.emergencyEmail = localEmail;
    }
  }

  private async loadEmergencyConfig(): Promise<void> {
    // 从后端同步邮箱（可能比本地更新），失败时保留本地值
    let result = await this.callService(http.RequestMethod.GET, '/emergency/config');
    try {
      let d = JSON.parse(result) as Record<string, Object>;
      let backendEmail: string = (d['email'] as string) || '';
      if (backendEmail && backendEmail.length > 0) {
        this.emergencyEmail = backendEmail;
        // 同步到本地
        await PreferencesUtils.getInstance().netUtils.setEmergencyEmail(backendEmail);
      }
    } catch { /* 后端不可用时保留本地邮箱 */ }
  }

  private async reverseGeocode(lat: number, lng: number): Promise<string> {
    if (lat === 0 && lng === 0) return '';
    try {
      let url = `https://restapi.amap.com/v3/geocode/regeo?key=${AMAP_KEY}&location=${lng},${lat}&radius=50&extensions=base`;
      let result = await this.callService(http.RequestMethod.GET, '', undefined, url);
      let data = JSON.parse(result) as Record<string, Object>;
      if (data['status'] === '1') {
        let regeo = data['regeocode'] as Record<string, Object>;
        if (regeo) { return (regeo['formatted_address'] as string) || ''; }
      }
    } catch { /* */ }
    return '';
  }

  private async getCurrentLocation(): Promise<Record<string, Object>> {
    try {
      let location = await geoLocationManager.getCurrentLocation();
      let lat: number = location.latitude;
      let lng: number = location.longitude;
      if (lat === 0 && lng === 0) {
        return { 'latitude': 0, 'longitude': 0, 'address': '', 'success': false };
      }
      let address = await this.reverseGeocode(lat, lng);
      return { 'latitude': lat, 'longitude': lng, 'address': address || `${lat.toFixed(4)}, ${lng.toFixed(4)}`, 'success': true };
    } catch (e) {
      return { 'latitude': 0, 'longitude': 0, 'address': '', 'success': false };
    }
  }

  private async sendEmergencyNotification(): Promise<void> {
    await this.loadEmergencyConfig();
    if (!this.emergencyEmail) {
      // 后端没有邮箱，尝试从本地读取
      await this.loadLocalEmergencyEmail();
    }
    if (!this.emergencyEmail) {
      this.emailStatus = '⚠ 未设置紧急邮箱';
      promptAction.showToast({ message: '请先在网络设置中配置紧急邮箱' });
      return;
    }
    // 确保邮箱同步到后端
    let emailPayload: Record<string, Object> = { 'email': this.emergencyEmail };
    await this.callService(http.RequestMethod.POST, '/emergency/config', emailPayload);
    this.emailStatus = '📧 正在获取GPS并发送邮件...';
    this.gpsLocation = '';
    let loc = await this.getCurrentLocation();
    if (loc['success'] === false) {
      this.emailStatus = '⚠ GPS获取失败，使用坐标发送';
      this.gpsLocation = 'GPS未获取到';
    }
    let address: string = (loc['address'] as string) || '未获取到地址';
    this.gpsLocation = address;
    let payload: Record<string, Object> = {
      'email': this.emergencyEmail,
      'latitude': loc['latitude'],
      'longitude': loc['longitude'],
      'address': address
    };
    let result = await this.callService(http.RequestMethod.POST, '/emergency/notify', payload);
    try {
      let data = JSON.parse(result) as Record<string, Object>;
      if (data['status'] === 'sent') {
        this.emailStatus = '✅ 邮件已发送至 ' + this.emergencyEmail;
        promptAction.showToast({ message: '紧急邮件已发送', duration: 3000 });
      } else {
        this.emailStatus = '❌ 发送失败: ' + (data['message'] as string || '');
        promptAction.showToast({ message: '邮件发送失败' });
      }
    } catch {
      this.emailStatus = '📧 邮件请求已提交';
    }
  }
}

@Component
struct MetricTile {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop highlight: boolean = false;

  build() {
    Column({ space: '2vp' }) {
      Text(this.value).fontSize('14fp').fontWeight(FontWeight.Bold)
        .fontColor(this.highlight ? '#dc2626' : '#111111').maxLines(1)
      Text(this.label).fontSize('9fp').fontColor('#999999')
    }
    .layoutWeight(1).padding('6vp')
    .backgroundColor(this.highlight ? '#fef2f2' : '#fafafa').borderRadius('6vp')
    .border({ width: this.highlight ? '1vp' : '0vp', color: '#fecaca' })
  }
}
