import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import http from '@ohos.net.http';
import { PreferencesUtils } from '../utils/PreferencesUtils';
import { TCPClientManager } from '../tcp/TCPClientManager';
import { VideoComponents } from '../components/VideoComponents';

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
  @State cmdLinear: number = 0;
  @State cmdAngular: number = 0;
  @State lostFrames: number = 0;
  @State snapshotUrl: string = 'http://192.168.1.11:5001/formation/frame'
  @State showConfig: boolean = false;
  @State targetBboxHeight: number = 200;
  @State confidenceThreshold: number = 0.5;
  @State speedKp: number = 0.8; @State speedKi: number = 0.05; @State speedKd: number = 0.1;
  @State steerKp: number = 1.2; @State steerKi: number = 0.02; @State steerKd: number = 0.3;
  @State maxLostFrames: number = 5; @State frameSkip: number = 3;

  private dialogShown: boolean = false;
  private pollTimer: number = -1;
  private frameTimer: number = -1;

  aboutToAppear(): void { this.initPage(); }
  aboutToDisappear(): void { this.cleanup(); }

  async initPage(): Promise<void> {
    this.carIp = await PreferencesUtils.getInstance().netUtils.getIP() as string;
    this.serviceBaseUrl = `http://${this.carIp}:5001`;
    this.isConnected = await TCPClientManager.getInstance().isConnect();
    if (this.isConnected) {
      await this.startDetect();
      this.startPolling();
      this.startFrameTimer();
    }
  }
  cleanup(): void {
    this.stopPolling();
    if (this.frameTimer !== -1) { clearInterval(this.frameTimer); this.frameTimer = -1; }
    this.callService(http.RequestMethod.POST, '/formation/stop');
  }
  startPolling(): void { this.stopPolling(); this.pollTimer = setInterval(() => { this.getStatus(); }, 1500); }
  stopPolling(): void { if (this.pollTimer !== -1) { clearInterval(this.pollTimer); this.pollTimer = -1; } }
  startFrameTimer(): void {
    if (this.frameTimer !== -1) return;
    this.frameTimer = setInterval(() => {
      this.snapshotUrl = `http://${this.carIp}:5001/formation/frame?t=${Date.now()}`;
    }, 250);
  }

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
        Text(this.isFollowing ? ' | 跟随中' : (this.isDetectMode ? ' | 检测中' : ' | 待机')).fontSize('11fp')
          .fontColor(this.isFollowing ? '#22c55e' : (this.isDetectMode ? '#3b82f6' : '#cccccc'))
      }
      .width('100%').padding({ left: '10vp', right: '10vp', top: '8vp', bottom: '6vp' })
      .backgroundColor('#fafafa').border({ width: { bottom: '1vp' }, color: '#e5e5e5' })

      // ====== 主体：左视频 + 右面板 ======
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
          // 状态条
          Row() {
            Text(this.trackingStatus)
              .fontSize('13fp').fontWeight(FontWeight.Bold).fontColor('#ffffff')
          }
          .width('100%').padding('8vp')
          .backgroundColor(this.isFollowing ? (this.hasTarget ? '#22c55e' : '#eab308')
            : (this.hasTarget ? '#3b82f6' : (this.isDetectMode ? '#888888' : '#999999')))
          .borderRadius('6vp').justifyContent(FlexAlign.Center)

          // 指标
          Row({ space: '4vp' }) {
            MetricTile({ label: '置信度', value: this.hasTarget ? this.targetConf.toFixed(2) : '---' })
            MetricTile({ label: '高度px', value: this.hasTarget ? `${Math.round(this.targetHeight)}` : '---' })
            MetricTile({ label: '丢失帧', value: `${this.lostFrames}` })
          }

          // 控制输出
          Text('控制输出').fontSize('11fp').fontColor('#999999').alignSelf(ItemAlign.Start)
          Row({ space: '6vp' }) {
            GaugeTile({ label: '速度', value: this.cmdLinear, color: '#2563eb' })
            GaugeTile({ label: '转向', value: this.cmdAngular, color: '#dc2626' })
          }

          // 模式信息
          Text(`模型: ${this.modelLoaded ? '已加载' : '未加载'} | 控制: ${this.controlMode}`)
            .fontSize('9fp').fontColor('#cccccc')

          // 按钮
          Row({ space: '5vp' }) {
            if (this.isDetectMode && !this.isFollowing) {
              Button('开始跟随').layoutWeight(1).fontSize('12fp').fontColor('#ffffff')
                .backgroundColor(this.hasTarget ? '#22c55e' : '#888888').borderRadius('6vp').height('34vp')
                .onClick(() => { this.startFormation(); })
              Button('取消').layoutWeight(1).fontSize('12fp').fontColor('#ffffff')
                .backgroundColor('#dc2626').borderRadius('6vp').height('34vp')
                .onClick(() => { this.stopAll(); })
            } else if (this.isFollowing) {
              Button('停止跟随').layoutWeight(1).fontSize('12fp').fontColor('#ffffff')
                .backgroundColor('#dc2626').borderRadius('6vp').height('34vp')
                .onClick(() => { this.stopFormation(); })
              Button('急停').layoutWeight(1).fontSize('12fp').fontColor('#ffffff')
                .backgroundColor('#1a1a1a').borderRadius('6vp').height('34vp')
                .onClick(() => { this.stopFormation(); })
            } else {
              Button('重新检测').layoutWeight(1).fontSize('12fp').fontColor('#ffffff')
                .backgroundColor('#3b82f6').borderRadius('6vp').height('34vp')
                .onClick(() => { this.restartDetect(); })
            }
          }

          Row({ space: '5vp' }) {
            Button(this.showConfig ? '收起' : 'PID 配置').layoutWeight(1).fontSize('12fp').fontColor('#666666')
              .backgroundColor('#f1f1f1').borderRadius('6vp').height('32vp')
              .onClick(() => { this.showConfig = !this.showConfig; })
            Button('刷新').layoutWeight(1).fontSize('12fp').fontColor('#666666')
              .backgroundColor('#f1f1f1').borderRadius('6vp').height('32vp')
              .onClick(() => { this.getStatus(); })
          }

          // PID 配置
          if (this.showConfig) {
            Text(`PID 参数 - 请在连接小车后调整`).fontSize('9fp').fontColor('#cccccc')
              .width('100%').padding('6vp').backgroundColor('#fafafa').borderRadius('6vp')
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
    this.dialogShown = false; this.cmdLinear = 0; this.cmdAngular = 0;
  }
  private async restartDetect(): Promise<void> { this.dialogShown = false; await this.startDetect(); }
  private async startFormation(): Promise<void> {
    const result = await this.callService(http.RequestMethod.POST, '/formation/start');
    if (result.includes('error') || result.includes('失败')) { promptAction.showToast({ message: '启动失败' }); return; }
    this.isFollowing = true; this.isDetectMode = false; this.trackingStatus = '跟随中';
    promptAction.showToast({ message: '编队跟随已启动' }); await this.getStatus();
  }
  private async stopFormation(): Promise<void> {
    await this.callService(http.RequestMethod.POST, '/formation/stop');
    this.isFollowing = false; this.isDetectMode = false; this.trackingStatus = '已停止';
    this.cmdLinear = 0; this.cmdAngular = 0; this.hasTarget = false; this.lostFrames = 0; this.dialogShown = false;
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
      if (data.target) { this.hasTarget = true; this.targetConf = data.target.confidence; this.targetHeight = data.target.bbox ? (data.target.bbox[3] - data.target.bbox[1]) : 0; }
      else { this.hasTarget = false; this.targetConf = 0; this.targetHeight = 0; }
      if (!data.enabled) this.trackingStatus = '待机';
      else if (data.detect_only && !this.isFollowing) this.trackingStatus = this.hasTarget ? '发现领航车!' : '扫描中...';
      else if (this.isFollowing) this.trackingStatus = !this.hasTarget ? (this.lostFrames > 0 ? `丢失 ${this.lostFrames}` : '搜索中...') : '跟随中';
      if (data.detect_only && this.hasTarget && !this.isFollowing && !this.dialogShown) {
        this.dialogShown = true;
        AlertDialog.show({
          title: '检测到领航车', message: `置信度: ${this.targetConf.toFixed(2)}\n是否开始编队跟随？`,
          autoCancel: false, alignment: DialogAlignment.Center,
          primaryButton: { value: '开始跟随', fontColor: '#ffffff', backgroundColor: '#22c55e', action: () => { this.startFormation(); } },
          secondaryButton: { value: '忽略', fontColor: '#666666', backgroundColor: '#f1f1f1', action: () => { this.dialogShown = false; } },
          cancel: () => { this.dialogShown = false; }
        });
      }
      if (data.config) {
        this.targetBboxHeight = data.config.target_bbox_height; this.confidenceThreshold = data.config.confidence_threshold;
        this.speedKp = data.config.speed_kp; this.speedKi = data.config.speed_ki; this.speedKd = data.config.speed_kd;
        this.steerKp = data.config.steer_kp; this.steerKi = data.config.steer_ki; this.steerKd = data.config.steer_kd;
        this.maxLostFrames = data.config.max_lost_frames; this.frameSkip = data.config.frame_skip;
      }
    } catch { /* parse error */ }
  }
  private async applyConfig(): Promise<void> {
    const payload: FormationConfigPayload = {
      target_bbox_height: this.targetBboxHeight, confidence_threshold: parseFloat(this.confidenceThreshold.toFixed(2)),
      speed_kp: parseFloat(this.speedKp.toFixed(2)), speed_ki: parseFloat(this.speedKi.toFixed(2)), speed_kd: parseFloat(this.speedKd.toFixed(2)),
      steer_kp: parseFloat(this.steerKp.toFixed(2)), steer_ki: parseFloat(this.steerKi.toFixed(2)), steer_kd: parseFloat(this.steerKd.toFixed(2)),
      max_lost_frames: this.maxLostFrames, frame_skip: this.frameSkip
    };
    await this.callService(http.RequestMethod.POST, '/formation/config', payload);
    promptAction.showToast({ message: '配置已应用' }); await this.getStatus();
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
