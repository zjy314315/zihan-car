import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import http from '@ohos.net.http';
import { PreferencesUtils } from '../utils/PreferencesUtils';
import { TCPClientManager } from '../tcp/TCPClientManager';
import { VideoComponents } from '../components/VideoComponents';
import { ProcessLifecycle } from '../utils/ProcessLifecycle';

interface FacePayload { name: string; }
interface StatusData { running: boolean; face_enabled: boolean; }
interface FaceInfo { status: string; name: string; }
interface FaceResultData { face?: FaceInfo; status?: string; name?: string; }

@Entry
@Component
struct FaceRecognition {
  @State name: string = '';
  @State serviceBaseUrl: string = 'http://192.168.1.11:5000';
  @State statusText: string = '等待操作';
  @State resultText: string = '等待数据...';
  @State isConnected: boolean = false;
  @State isRecognizing: boolean = false;
  @State faceLabel: string = '暂无结果';
  @State carIp: string = '';

  aboutToAppear(): void { this.initPage(); }
  aboutToDisappear(): void { this.stopRecognize(); ProcessLifecycle.stop('vision'); }

  async initPage(): Promise<void> {
    this.carIp = await PreferencesUtils.getInstance().netUtils.getIP() as string;
    this.serviceBaseUrl = `http://${this.carIp}:5000`;
    await ProcessLifecycle.start('vision');
    await this.waitLifecycle(700);
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
        Text('人脸识别').fontSize('15fp').fontWeight(FontWeight.Bold).fontColor('#111111')
        Blank()
        Circle({ width: '7vp', height: '7vp' }).fill(this.isConnected ? '#22c55e' : '#999999')
        Text(this.isConnected ? `已连接 ${this.carIp}` : '未连接').fontSize('11fp')
          .fontColor(this.isConnected ? '#333333' : '#999999')
        Text(this.isRecognizing ? ' | 识别中' : '').fontSize('11fp').fontColor('#333333')
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

        // 右侧：操作
        Column({ space: '6vp' }) {
          Row({ space: '6vp' }) {
            Text('服务').fontSize('10fp').fontColor('#999999').width('30vp')
            Text(this.serviceBaseUrl).fontSize('10fp').fontColor('#999999').layoutWeight(1).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          Row({ space: '6vp' }) {
            TextInput({ text: this.name, placeholder: '输入姓名' })
              .onChange((v: string) => { this.name = v; })
              .layoutWeight(1).fontSize('12fp').backgroundColor('#f1f1f1')
              .padding({ left: '10vp', right: '10vp', top: '7vp', bottom: '7vp' })
            Button('注册')
              .fontSize('12fp').fontColor('#ffffff').backgroundColor('#1a1a1a')
              .borderRadius('6vp').height('34vp').padding({ left: '12vp', right: '12vp' })
              .onClick(() => { this.registerFace(); })
          }

          Row({ space: '5vp' }) {
            Button(this.isRecognizing ? '停止' : '开始识别')
              .layoutWeight(1).fontSize('12fp').fontColor('#ffffff')
              .backgroundColor(this.isRecognizing ? '#555555' : '#1a1a1a')
              .borderRadius('6vp').height('34vp')
              .onClick(() => { this.isRecognizing ? this.stopRecognize() : this.startRecognize(); })
            Button('刷新')
              .layoutWeight(1).fontSize('12fp').fontColor('#666666').backgroundColor('#f1f1f1')
              .borderRadius('6vp').height('34vp').onClick(() => { this.getResult(); })
            Button('状态')
              .layoutWeight(1).fontSize('12fp').fontColor('#666666').backgroundColor('#f1f1f1')
              .borderRadius('6vp').height('34vp').onClick(() => { this.getStatus(); })
          }

          Column({ space: '4vp' }) {
            Text('识别结果').fontSize('10fp').fontWeight(FontWeight.Medium).fontColor('#999999').width('100%')
            Text(this.faceLabel).fontSize('15fp').fontWeight(FontWeight.Bold)
              .fontColor(this.faceLabel.includes('识别到') ? '#333333' : '#999999')
              .width('100%').textAlign(TextAlign.Center).padding('10vp')
              .backgroundColor('#fafafa').borderRadius('8vp')
          }
          .width('100%').padding('8vp').backgroundColor('#ffffff').borderRadius('10vp').border({ width: '1vp', color: '#e5e5e5' })

          Text(this.statusText).fontSize('10fp').fontColor('#999999').width('100%').maxLines(2)

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
  private async waitLifecycle(ms: number): Promise<void> {
    await new Promise<void>((resolve) => { setTimeout(() => resolve(), ms); });
  }

  private async startRecognize(): Promise<void> {
    this.statusText = '正在启动...';
    const result = await this.callService(http.RequestMethod.POST, '/start');
    this.resultText = result;
    if (!result.includes('失败')) {
      this.isRecognizing = true; this.statusText = '识别运行中';
      promptAction.showToast({ message: '人脸识别已启动' });
      await this.getResult();
    } else { this.statusText = '启动失败'; promptAction.showToast({ message: '启动失败' }); }
  }
  private async stopRecognize(): Promise<void> {
    const result = await this.callService(http.RequestMethod.POST, '/stop');
    this.resultText = result; this.isRecognizing = false;
    this.faceLabel = '已停止'; this.statusText = '已停止';
    promptAction.showToast({ message: '已停止' });
  }
  private async registerFace(): Promise<void> {
    if (!this.name.trim()) { promptAction.showToast({ message: '请输入姓名' }); return; }
    this.statusText = '正在注册...';
    const result = await this.callService(http.RequestMethod.POST, '/register', { name: this.name.trim() });
    this.resultText = result; this.statusText = '注册完成';
    promptAction.showToast({ message: '注册请求已发送' });
  }
  private async getStatus(): Promise<void> {
    const result = await this.callService(http.RequestMethod.GET, '/status');
    this.resultText = result;
    try { const data: StatusData = JSON.parse(result) as StatusData; this.isRecognizing = data.running && data.face_enabled; } catch { /* */ }
  }
  private async getResult(): Promise<void> {
    const result = await this.callService(http.RequestMethod.GET, '/result');
    this.resultText = result; this.parseFaceResult(result);
  }
  private parseFaceResult(result: string): void {
    if (!result || result.trim().length === 0) { this.faceLabel = '暂无结果'; return; }
    try {
      const data: FaceResultData = JSON.parse(result) as FaceResultData;
      if (data.face) {
        if (data.face.status === 'recognized' && data.face.name !== 'unknown') { this.faceLabel = `识别到: ${data.face.name}`; }
        else if (data.face.status === 'no_face') { this.faceLabel = '未检测到人脸'; }
        else if (data.face.status === 'face_disabled') { this.faceLabel = '未启用'; }
        else { this.faceLabel = data.face.name !== 'unknown' ? `识别到: ${data.face.name}` : '未识别'; }
        return;
      }
      if (data.name && data.name !== 'unknown') { this.faceLabel = `识别到: ${data.name}`; }
      else if (data.status) { this.faceLabel = data.status; }
      else { this.faceLabel = JSON.stringify(data).substring(0, 30); }
    } catch { this.faceLabel = result.substring(0, 30); }
  }
  private async callService(method: http.RequestMethod, path: string, payload?: FacePayload): Promise<string> {
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
    } catch (error) { return `请求失败: ${JSON.stringify(error)}`; }
    finally { httpRequest.destroy(); }
  }
}
