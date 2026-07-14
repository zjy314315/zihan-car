import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import http from '@ohos.net.http';
import web_webview from '@ohos.web.webview';
import { PreferencesUtils } from '../utils/PreferencesUtils';
import { TCPClientManager } from '../tcp/TCPClientManager';
import { VideoComponents } from '../components/VideoComponents';
import { ProcessLifecycle } from '../utils/ProcessLifecycle';

interface FormationTarget { bbox: number[]; confidence: number; }
interface FormationCmd { linear: number; angular: number; }
interface FormationConfig {
  confidence_threshold: number; target_bbox_height: number;
  speed_kp: number; speed_ki: number; speed_kd: number;
  steer_kp: number; steer_ki: number; steer_kd: number;
  max_lost_frames: number; frame_skip: number;
}
interface FormationStatus {
  enabled: boolean; detect_only: boolean; model_loaded: boolean; control_mode: string;
  target: FormationTarget | null; cmd: FormationCmd;
  lost_frames: number; config: FormationConfig;
}
interface FormationConfigPayload {
  target_bbox_height: number; confidence_threshold: number;
  speed_kp: number; speed_ki: number; speed_kd: number;
  steer_kp: number; steer_ki: number; steer_kd: number;
  max_lost_frames: number; frame_skip: number;
}

@Entry
@Component
struct FormationControl {
  @State serviceBaseUrl: string = 'http://192.168.1.11:5001';
  @State carIp: string = '';
  @State isConnected: boolean = false;
  @State isDetectMode: boolean = false;
  @State isFollowing: boolean = false;
  @State modelLoaded: boolean = false;
  @State controlMode: string = '---';
  @State trackingStatus: string = '待机';
  @State hasTarget: boolean = false;
  @State targetConf: number = 0;
  @State targetHeight: number = 0;
  @State targetWidth: number = 0;
  @State cmdLinear: number = 0;
  @State cmdAngular: number = 0;
  @State lostFrames: number = 0;

  private pollTimer: number = -1;

  aboutToAppear(): void { this.initPage(); }
  aboutToDisappear(): void { this.cleanup(); }

  async initPage(): Promise<void> {
    this.carIp = await PreferencesUtils.getInstance().netUtils.getIP() as string;
    this.serviceBaseUrl = `http://${this.carIp}:5001`;
    await ProcessLifecycle.start('vision');
    await ProcessLifecycle.start('monitor');
    await this.waitLifecycle(1200);
    this.isConnected = await TCPClientManager.getInstance().isConnect();
    if (this.isConnected) {
      await this.startDetect();
      this.startPolling();
    }
  }
  cleanup(): void {
    this.stopPolling();
    this.callService(http.RequestMethod.POST, '/formation/stop');
    ProcessLifecycle.stop('monitor');
    ProcessLifecycle.stop('vision');
  }
  private async waitLifecycle(ms: number): Promise<void> {
    await new Promise<void>((resolve) => { setTimeout(() => resolve(), ms); });
  }

  startPolling(): void { this.stopPolling(); this.pollTimer = setInterval(() => { this.getStatus(); }, 1500); }
  stopPolling(): void { if (this.pollTimer !== -1) { clearInterval(this.pollTimer); this.pollTimer = -1; } }

  build() {
    Column() {
      // ====== 顶部栏 ======
      Row({ space: '8vp' }) {
        Button('← 返回')
          .fontSize('12fp').fontColor('#ffffff').backgroundColor('#1a1a1a')
          .borderRadius('6vp').padding({ left: '10vp', right: '10vp', top: '6vp', bottom: '6vp' })
          .onClick(() => { this.cleanup(); router.back(); })
        Text('小车编队').fontSize('15fp').fontWeight(FontWeight.Bold).fontColor('#111111')
        Blank()
        Circle({ width: '7vp', height: '7vp' }).fill(this.isConnected ? '#22c55e' : '#999999')
        Text(this.isConnected ? `已连接 ${this.carIp}` : '未连接').fontSize('11fp')
          .fontColor(this.isConnected ? '#333333' : '#999999')
        Text(this.isFollowing ? ' | 跟随' : (this.isDetectMode ? ' | 检测' : ' | 待机')).fontSize('11fp')
          .fontColor(this.isFollowing ? '#22c55e' : (this.isDetectMode ? '#3b82f6' : '#cccccc'))
      }
      .width('100%').padding({ left: '10vp', right: '10vp', top: '8vp', bottom: '6vp' })
      .backgroundColor('#fafafa').border({ width: { bottom: '1vp' }, color: '#e5e5e5' })

      // ====== 主体：左视频 + 右面板 ======
      Row({ space: '8vp' }) {
        // 左侧：标注帧视频
        Column({ space: '4vp' }) {
          Web({ src: `http://${VideoComponents.ip}:5001/formation/video_page`, controller: new web_webview.WebviewController() })
            .javaScriptAccess(true).domStorageAccess(true)
            .borderRadius('10vp').layoutWeight(1)
        }
        .width('0vp').layoutWeight(5.5).padding('6vp')
        .backgroundColor('#fafafa').borderRadius('12vp').border({ width: '1vp', color: '#e5e5e5' })

        // 右侧：面板
        Column({ space: '6vp' }) {
          // 状态条
          Row() {
            Text(this.trackingStatus)
              .fontSize('13fp').fontWeight(FontWeight.Bold).fontColor('#ffffff')
          }
          .width('100%').padding('8vp')
          .backgroundColor(this.isFollowing ? (this.hasTarget ? '#22c55e' : '#eab308')
            : (this.hasTarget ? '#3b82f6' : (this.isDetectMode ? '#888888' : '#999999')))
          .borderRadius('6vp').justifyContent(FlexAlign.Center)

          // 检测指标
          Row({ space: '4vp' }) {
            MetricTile({ label: '置信度', value: this.hasTarget ? this.targetConf.toFixed(2) : '---' })
            MetricTile({ label: '尺寸', value: this.hasTarget ? `${Math.round(this.targetWidth)}×${Math.round(this.targetHeight)}` : '---' })
            MetricTile({ label: '丢失帧', value: `${this.lostFrames}` })
          }

          // 控制输出
          Text('控制输出').fontSize('11fp').fontColor('#999999').alignSelf(ItemAlign.Start)
          Row({ space: '6vp' }) {
            GaugeTile({ label: '速度', value: this.cmdLinear, color: '#2563eb' })
            GaugeTile({ label: '转向', value: this.cmdAngular, color: '#dc2626' })
          }

          // 按钮区
          if (this.hasTarget && !this.isFollowing && this.isDetectMode) {
            Text('检测到领航车，绿色框已标注').fontSize('11fp').fontColor('#3b82f6')
              .padding({ top: '4vp', bottom: '2vp' })
          }

          Row({ space: '5vp' }) {
            if (this.isDetectMode && !this.isFollowing) {
              Button(this.hasTarget ? '▶ 开始跟随' : '等待检测...').layoutWeight(1).fontSize('13fp').fontColor('#ffffff')
                .backgroundColor(this.hasTarget ? '#22c55e' : '#888888').borderRadius('8vp').height('38vp')
                .enabled(this.hasTarget)
                .onClick(() => { this.startFormation(); })
              Button('取消').layoutWeight(0.5).fontSize('12fp').fontColor('#ffffff')
                .backgroundColor('#dc2626').borderRadius('8vp').height('38vp')
                .onClick(() => { this.stopAll(); })
            } else if (this.isFollowing) {
              Button('停止跟随').layoutWeight(1).fontSize('13fp').fontColor('#ffffff')
                .backgroundColor('#dc2626').borderRadius('8vp').height('38vp')
                .onClick(() => { this.stopFormation(); })
              Button('急停').layoutWeight(0.5).fontSize('12fp').fontColor('#ffffff')
                .backgroundColor('#1a1a1a').borderRadius('8vp').height('38vp')
                .onClick(() => { this.stopFormation(); })
            } else {
              Button('重新检测').layoutWeight(1).fontSize('13fp').fontColor('#ffffff')
                .backgroundColor('#3b82f6').borderRadius('8vp').height('38vp')
                .onClick(() => { this.restartDetect(); })
            }
          }

          Row({ space: '5vp' }) {
            Button('刷新').layoutWeight(1).fontSize('12fp').fontColor('#666666').backgroundColor('#f1f1f1')
              .borderRadius('6vp').height('32vp').onClick(() => { this.getStatus(); })
          }
        }
        .width('0vp').layoutWeight(4.5).padding('8vp')
        .backgroundColor('#ffffff').borderRadius('12vp').border({ width: '1vp', color: '#e5e5e5' })
      }
      .width('100%').layoutWeight(1).padding('8vp')
    }
    .width('100%').height('100%').backgroundColor('#ffffff')
  }

  // ====== 业务逻辑 ======
  private async startDetect(): Promise<void> {
    const result = await this.callService(http.RequestMethod.POST, '/formation/detect');
    if (result.includes('error') || result.includes('失败')) { promptAction.showToast({ message: '检测启动失败' }); return; }
    this.isDetectMode = true; this.isFollowing = false; this.trackingStatus = '扫描中...';
    this.cmdLinear = 0; this.cmdAngular = 0;
  }
  private async restartDetect(): Promise<void> { await this.startDetect(); }
  private async startFormation(): Promise<void> {
    const result = await this.callService(http.RequestMethod.POST, '/formation/start');
    if (result.includes('error') || result.includes('失败')) { promptAction.showToast({ message: '启动失败' }); return; }
    this.isFollowing = true; this.isDetectMode = false; this.trackingStatus = '跟随中';
    promptAction.showToast({ message: '编队跟随已启动' }); await this.getStatus();
  }
  private async stopFormation(): Promise<void> {
    await this.callService(http.RequestMethod.POST, '/formation/stop');
    this.isFollowing = false; this.isDetectMode = false; this.trackingStatus = '已停止';
    this.cmdLinear = 0; this.cmdAngular = 0; this.hasTarget = false; this.lostFrames = 0;
    promptAction.showToast({ message: '已停止并急停' });
  }
  private async stopAll(): Promise<void> {
    await this.callService(http.RequestMethod.POST, '/formation/stop');
    this.isFollowing = false; this.isDetectMode = false; this.trackingStatus = '已取消';
    this.cmdLinear = 0; this.cmdAngular = 0; promptAction.showToast({ message: '已取消检测' });
  }
  private async getStatus(): Promise<void> {
    const result = await this.callService(http.RequestMethod.GET, '/formation/status');
    if (!result || result.includes('失败')) return;
    try {
      const data: FormationStatus = JSON.parse(result) as FormationStatus;
      this.modelLoaded = data.model_loaded; this.controlMode = data.control_mode;
      this.cmdLinear = data.cmd.linear; this.cmdAngular = data.cmd.angular; this.lostFrames = data.lost_frames;
      this.isDetectMode = data.detect_only; this.isFollowing = data.enabled && !data.detect_only;
      if (data.target) {
        this.hasTarget = true; this.targetConf = data.target.confidence;
        let b: number[] = data.target.bbox;
        this.targetHeight = b[3] - b[1]; this.targetWidth = b[2] - b[0];
      } else { this.hasTarget = false; this.targetConf = 0; this.targetHeight = 0; this.targetWidth = 0; }
      if (!data.enabled) this.trackingStatus = '待机';
      else if (data.detect_only && !this.isFollowing) this.trackingStatus = this.hasTarget ? '发现领航车' : '扫描中...';
      else if (this.isFollowing) this.trackingStatus = !this.hasTarget ? (this.lostFrames > 0 ? `丢失 ${this.lostFrames}` : '搜索中...') : '跟随中';
    } catch { /* parse error */ }
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
    } catch (error) { return '请求失败'; }
    finally { httpRequest.destroy(); }
  }
}

@Component
struct MetricTile {
  @Prop label: string = ''; @Prop value: string = '';
  build() {
    Column({ space: '2vp' }) {
      Text(this.value).fontSize('14fp').fontWeight(FontWeight.Bold).fontColor('#111111').maxLines(1)
      Text(this.label).fontSize('9fp').fontColor('#999999')
    }.layoutWeight(1).padding('6vp').backgroundColor('#fafafa').borderRadius('6vp')
  }
}

@Component
struct GaugeTile {
  @Prop label: string = ''; @Prop value: number = 0; @Prop color: string = '#2563eb';
  build() {
    Column({ space: '3vp' }) {
      Text(this.value.toFixed(2)).fontSize('13fp').fontWeight(FontWeight.Bold)
        .fontColor(Math.abs(this.value) > 0.01 ? this.color : '#999999')
      Text(this.label).fontSize('9fp').fontColor('#999999')
      Progress({ value: Math.abs(this.value), total: 1, type: ProgressType.Linear })
        .width('100%').height('3vp').color(this.color)
    }.layoutWeight(1).padding('6vp').backgroundColor('#fafafa').borderRadius('6vp')
  }
}
