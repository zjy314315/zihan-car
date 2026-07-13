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
  target_bbox_height: number;
  confidence_threshold: number;
  speed_kp: number; speed_ki: number; speed_kd: number;
  steer_kp: number; steer_ki: number; steer_kd: number;
  max_lost_frames: number;
  frame_skip: number;
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
  @State showConfig: boolean = false;
  @State targetBboxHeight: number = 200;
  @State confidenceThreshold: number = 0.5;
  @State speedKp: number = 0.8;
  @State speedKi: number = 0.05;
  @State speedKd: number = 0.1;
  @State steerKp: number = 1.2;
  @State steerKi: number = 0.02;
  @State steerKd: number = 0.3;
  @State maxLostFrames: number = 5;
  @State frameSkip: number = 3;

  private dialogShown: boolean = false;
  private pollTimer: number = -1;

  aboutToAppear(): void { this.initPage(); }
  aboutToDisappear(): void { this.cleanup(); }

  async initPage(): Promise<void> {
    this.carIp = await PreferencesUtils.getInstance().netUtils.getIP() as string;
    this.serviceBaseUrl = `http://${this.carIp}:5001`;
    this.isConnected = await TCPClientManager.getInstance().isConnect();
    if (this.isConnected) {
      await this.startDetect();
      this.startPolling();
    }
  }

  cleanup(): void {
    this.stopPolling();
    this.callService(http.RequestMethod.POST, '/formation/stop');
  }

  startPolling(): void {
    this.stopPolling();
    this.pollTimer = setInterval(() => { this.getStatus(); }, 1500);
  }

  stopPolling(): void {
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  build() {
    Column() {
      Row({ space: '12vp' }) {
        Button('<')
          .width('44vp').height('44vp').fontSize('22fp').fontColor('#111111')
          .backgroundColor('#f5f5f5').borderRadius('22vp')
          .onClick(() => { this.cleanup(); router.back(); })
        Column() {
          Text('协同驾驶').fontSize('11fp').fontWeight(FontWeight.Bold).fontColor('#707072')
          Text('小车编队').fontSize('26fp').fontWeight(FontWeight.Bold).fontColor('#111111')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text(this.isConnected ? '在线' : '离线')
          .fontSize('11fp').fontWeight(FontWeight.Bold)
          .fontColor(this.isConnected ? '#007d48' : '#707072')
      }.width('100%').padding({ left: '20vp', right: '20vp', top: '20vp', bottom: '16vp' })

      Scroll() {
        Column({ space: '24vp' }) {
          VideoComponents({ showControls: false, videoWidth: '100%', videoHeight: '230vp' })
            .width('100%').borderRadius('24vp')

          Column({ space: '14vp' }) {
            Row() {
              Column({ space: '5vp' }) {
                Text('编队状态').fontSize('12fp').fontWeight(FontWeight.Bold).fontColor('#707072')
                Text(this.trackingStatus).fontSize('22fp').fontWeight(FontWeight.Bold).fontColor('#111111')
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Column({ space: '4vp' }) {
                Circle({ width: '9vp', height: '9vp' }).fill(this.isFollowing || this.isDetectMode ? '#007d48' : '#9e9ea0')
                Text(this.isFollowing ? '跟随' : (this.isDetectMode ? '检测' : '待机'))
                  .fontSize('11fp').fontWeight(FontWeight.Bold)
                  .fontColor(this.isFollowing || this.isDetectMode ? '#007d48' : '#707072')
              }.alignItems(HorizontalAlign.Center)
            }.width('100%')
            Row({ space: '10vp' }) {
              MetricTile({ label: '置信度', value: this.hasTarget ? this.targetConf.toFixed(2) : '---' })
              MetricTile({ label: '目标高度', value: this.hasTarget ? `${Math.round(this.targetHeight)}` : '---' })
              MetricTile({ label: '丢失帧', value: `${this.lostFrames}` })
            }.width('100%')
            Text(`模型 ${this.modelLoaded ? '已加载' : '未加载'} · 控制 ${this.controlMode}`)
              .fontSize('13fp').fontColor('#707072').width('100%')
            if (this.isDetectMode && !this.isFollowing && !this.hasTarget) {
              Text('正在扫描前方领航车。').fontSize('13fp').fontColor('#707072').width('100%')
            }
          }.width('100%').padding('20vp').backgroundColor('#f5f5f5').borderRadius('24vp')

          Column({ space: '12vp' }) {
            Text('控制输出').fontSize('12fp').fontWeight(FontWeight.Bold).fontColor('#707072').width('100%')
            Row({ space: '10vp' }) {
              GaugeTile({ label: '速度', value: this.cmdLinear, min: -0.5, max: 1.0 })
              GaugeTile({ label: '转向', value: this.cmdAngular, min: -1.0, max: 1.0 })
            }.width('100%')
          }.width('100%').padding('18vp').backgroundColor('#f5f5f5').borderRadius('24vp')

          Column({ space: '10vp' }) {
            if (this.isDetectMode && !this.isFollowing) {
              Button('开始跟随')
                .width('100%').height('52vp').fontSize('16fp').fontWeight(FontWeight.Medium)
                .fontColor('#ffffff').backgroundColor(this.hasTarget ? '#111111' : '#9e9ea0').borderRadius('28vp')
                .onClick(() => { this.startFormation(); })
              Button('取消检测')
                .width('100%').height('48vp').fontSize('15fp').fontColor('#111111')
                .backgroundColor('#f5f5f5').borderRadius('26vp')
                .onClick(() => { this.stopAll(); })
            } else if (this.isFollowing) {
              Button('停止跟随')
                .width('100%').height('52vp').fontSize('16fp').fontWeight(FontWeight.Medium)
                .fontColor('#ffffff').backgroundColor('#111111').borderRadius('28vp')
                .onClick(() => { this.stopFormation(); })
              Button('急停')
                .width('100%').height('48vp').fontSize('15fp').fontColor('#111111')
                .backgroundColor('#f5f5f5').borderRadius('26vp')
                .onClick(() => { this.stopFormation(); })
            } else {
              Button('重新检测')
                .width('100%').height('52vp').fontSize('16fp').fontWeight(FontWeight.Medium)
                .fontColor('#ffffff').backgroundColor('#111111').borderRadius('28vp')
                .onClick(() => { this.restartDetect(); })
            }

            Row({ space: '10vp' }) {
              Button(this.showConfig ? '收起配置' : 'PID 配置')
                .layoutWeight(1).height('46vp').fontSize('15fp').fontColor('#111111')
                .backgroundColor('#f5f5f5').borderRadius('24vp')
                .onClick(() => { this.showConfig = !this.showConfig; })
              Button('刷新')
                .layoutWeight(1).height('46vp').fontSize('15fp').fontColor('#111111')
                .backgroundColor('#f5f5f5').borderRadius('24vp')
                .onClick(() => { this.getStatus(); })
            }.width('100%')
          }.width('100%')

          if (this.showConfig) {
            Column({ space: '14vp' }) {
              this.ConfigDivider('跟随参数')
              Row({ space: '10vp' }) {
                this.SliderItem('目标高度', this.targetBboxHeight, 50, 400, (v: number) => { this.targetBboxHeight = v; })
                this.SliderItem('置信阈值', this.confidenceThreshold, 0.3, 0.9, (v: number) => { this.confidenceThreshold = v; })
              }
              Row({ space: '10vp' }) {
                this.SliderItem('最大丢失', this.maxLostFrames, 2, 15, (v: number) => { this.maxLostFrames = v; })
                this.SliderItem('跳帧', this.frameSkip, 1, 8, (v: number) => { this.frameSkip = v; })
              }
              this.ConfigDivider('速度 PID')
              Row({ space: '10vp' }) {
                this.SliderItem('Kp', this.speedKp, 0, 3, (v: number) => { this.speedKp = v; })
                this.SliderItem('Ki', this.speedKi, 0, 0.5, (v: number) => { this.speedKi = v; })
              }
              this.SliderItem('Kd', this.speedKd, 0, 1, (v: number) => { this.speedKd = v; })
              this.ConfigDivider('转向 PID')
              Row({ space: '10vp' }) {
                this.SliderItem('Kp', this.steerKp, 0, 3, (v: number) => { this.steerKp = v; })
                this.SliderItem('Ki', this.steerKi, 0, 0.5, (v: number) => { this.steerKi = v; })
              }
              this.SliderItem('Kd', this.steerKd, 0, 1, (v: number) => { this.steerKd = v; })
              Button('应用配置')
                .width('100%').height('52vp').fontSize('16fp').fontWeight(FontWeight.Medium)
                .fontColor('#ffffff').backgroundColor('#111111').borderRadius('28vp')
                .onClick(() => { this.applyConfig(); })
            }.width('100%').padding('20vp').backgroundColor('#f5f5f5').borderRadius('24vp')
          }
        }.width('100%').padding({ left: '20vp', right: '20vp', bottom: '36vp' })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
    }.width('100%').height('100%').backgroundColor('#ffffff')
  }

  @Builder ConfigDivider(label: string) {
    Text(label).fontSize('12fp').fontWeight(FontWeight.Bold).fontColor('#707072').width('100%')
  }

  @Builder SliderItem(label: string, value: number, min: number, max: number, onChange: (v: number) => void) {
    Column({ space: '6vp' }) {
      Row() {
        Text(label).fontSize('11fp').fontWeight(FontWeight.Bold).fontColor('#707072')
        Blank()
        Text(max <= 1 ? value.toFixed(2) : `${Math.round(value)}`).fontSize('11fp').fontColor('#111111')
      }.width('100%')
      Slider({ value: value, min: min, max: max, step: max <= 1 ? 0.01 : 1 })
        .width('100%').blockColor('#111111').trackColor('#e5e5e5')
        .onChange((val: number) => { onChange(val); })
    }.layoutWeight(1)
  }

  private async startDetect(): Promise<void> {
    const result = await this.callService(http.RequestMethod.POST, '/formation/detect');
    if (result.includes('error') || result.includes('失败')) {
      promptAction.showToast({ message: '检测启动失败' }); return;
    }
    this.isDetectMode = true;
    this.isFollowing = false;
    this.trackingStatus = '扫描中...';
    this.dialogShown = false;
    this.cmdLinear = 0; this.cmdAngular = 0;
  }
  private async restartDetect(): Promise<void> { this.dialogShown = false; await this.startDetect(); }
  private async startFormation(): Promise<void> {
    const result = await this.callService(http.RequestMethod.POST, '/formation/start');
    if (result.includes('error') || result.includes('失败')) {
      promptAction.showToast({ message: '启动失败' }); return;
    }
    this.isFollowing = true;
    this.isDetectMode = false;
    this.trackingStatus = '跟随中';
    promptAction.showToast({ message: '编队跟随已启动' });
    await this.getStatus();
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
    this.cmdLinear = 0; this.cmdAngular = 0;
    promptAction.showToast({ message: '已取消检测' });
  }
  private async getStatus(): Promise<void> {
    const result = await this.callService(http.RequestMethod.GET, '/formation/status');
    if (!result || result.includes('失败')) return;
    try {
      const data: FormationStatus = JSON.parse(result) as FormationStatus;
      this.modelLoaded = data.model_loaded;
      this.controlMode = data.control_mode;
      this.cmdLinear = data.cmd.linear;
      this.cmdAngular = data.cmd.angular;
      this.lostFrames = data.lost_frames;
      this.isDetectMode = data.detect_only;
      this.isFollowing = data.enabled && !data.detect_only;
      if (data.target) {
        this.hasTarget = true;
        this.targetConf = data.target.confidence;
        this.targetHeight = data.target.bbox ? (data.target.bbox[3] - data.target.bbox[1]) : 0;
      } else {
        this.hasTarget = false; this.targetConf = 0; this.targetHeight = 0;
      }
      if (!data.enabled) this.trackingStatus = '待机';
      else if (data.detect_only && !this.isFollowing) this.trackingStatus = this.hasTarget ? '发现领航车' : '扫描中...';
      else if (this.isFollowing) this.trackingStatus = !this.hasTarget ? (this.lostFrames > 0 ? `丢失 ${this.lostFrames}` : '搜索中...') : '跟随中';
      if (data.detect_only && this.hasTarget && !this.isFollowing && !this.dialogShown) {
        this.dialogShown = true;
        this.showConfirmDialog();
      }
      if (data.config) {
        this.targetBboxHeight = data.config.target_bbox_height;
        this.confidenceThreshold = data.config.confidence_threshold;
        this.speedKp = data.config.speed_kp; this.speedKi = data.config.speed_ki; this.speedKd = data.config.speed_kd;
        this.steerKp = data.config.steer_kp; this.steerKi = data.config.steer_ki; this.steerKd = data.config.steer_kd;
        this.maxLostFrames = data.config.max_lost_frames;
        this.frameSkip = data.config.frame_skip;
      }
    } catch { /* parse error */ }
  }
  private showConfirmDialog(): void {
    AlertDialog.show({
      title: '检测到领航车',
      message: `置信度: ${this.targetConf.toFixed(2)}\n是否开始编队跟随？`,
      autoCancel: false,
      alignment: DialogAlignment.Center,
      primaryButton: { value: '开始跟随', fontColor: '#ffffff', backgroundColor: '#111111', action: () => { this.startFormation(); } },
      secondaryButton: { value: '忽略', fontColor: '#111111', backgroundColor: '#f5f5f5', action: () => { this.dialogShown = false; } },
      cancel: () => { this.dialogShown = false; }
    });
  }
  private async applyConfig(): Promise<void> {
    const payload: FormationConfigPayload = {
      target_bbox_height: this.targetBboxHeight,
      confidence_threshold: parseFloat(this.confidenceThreshold.toFixed(2)),
      speed_kp: parseFloat(this.speedKp.toFixed(2)), speed_ki: parseFloat(this.speedKi.toFixed(2)), speed_kd: parseFloat(this.speedKd.toFixed(2)),
      steer_kp: parseFloat(this.steerKp.toFixed(2)), steer_ki: parseFloat(this.steerKi.toFixed(2)), steer_kd: parseFloat(this.steerKd.toFixed(2)),
      max_lost_frames: this.maxLostFrames,
      frame_skip: this.frameSkip
    };
    await this.callService(http.RequestMethod.POST, '/formation/config', payload);
    promptAction.showToast({ message: '配置已应用' });
    await this.getStatus();
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
  @Prop label: string = '';
  @Prop value: string = '';
  build() {
    Column({ space: '5vp' }) {
      Text(this.value).fontSize('16fp').fontWeight(FontWeight.Bold).fontColor('#111111').maxLines(1)
      Text(this.label).fontSize('9fp').fontWeight(FontWeight.Bold).fontColor('#707072')
    }.layoutWeight(1).padding('14vp').backgroundColor('#ffffff').borderRadius('18vp').alignItems(HorizontalAlign.Start)
  }
}

@Component
struct GaugeTile {
  @Prop label: string = '';
  @Prop value: number = 0;
  @Prop min: number = -1;
  @Prop max: number = 1;
  build() {
    Column({ space: '8vp' }) {
      Text(this.value.toFixed(2)).fontSize('18fp').fontWeight(FontWeight.Bold).fontColor('#111111')
      Text(this.label).fontSize('10fp').fontWeight(FontWeight.Bold).fontColor('#707072')
      Progress({ value: Math.abs(this.value), total: Math.max(Math.abs(this.min), Math.abs(this.max)), type: ProgressType.Linear })
        .width('100%').height('4vp').color('#111111').backgroundColor('#e5e5e5')
    }.layoutWeight(1).padding('16vp').backgroundColor('#ffffff').borderRadius('18vp').alignItems(HorizontalAlign.Start)
  }
}
