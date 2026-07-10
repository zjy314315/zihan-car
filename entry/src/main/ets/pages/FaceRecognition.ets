import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import http from '@ohos.net.http';
import { PreferencesUtils } from '../utils/PreferencesUtils';
import { TCPClientManager } from '../tcp/TCPClientManager';
import { ButtonShadow } from '../styles/styles';
import { VideoComponents } from '../components/VideoComponents';

interface FacePayload {
  name: string;
}

interface FaceData {
  name?: string;
}

interface FaceResult {
  name?: string;
  faceName?: string;
  person?: string;
  result?: string;
  data?: FaceData;
}

@Entry
@Component
struct FaceRecognition {
  @State name: string = '张三';
  @State serviceBaseUrl: string = 'http://192.168.1.11:5001';
  @State statusText: string = '等待操作';
  @State resultText: string = '这里会显示识别结果';
  @State connectionState: string = '检查连接状态...';
  @State isRecognizing: boolean = false;
  @State faceLabel: string = '暂无识别结果';

  aboutToAppear(): void {
    this.initFacePage();
  }

  async initFacePage(): Promise<void> {
    await this.loadServiceAddress();
    await this.refreshConnectionState();
    if (this.connectionState.includes('已连接')) {
      await this.autoStartRecognition();
    }
  }

  build() {
    Column({ space: '18vp' }) {
      Row() {
        Button('返回')
          .backgroundColor('#111827')
          .fontColor('#ffffff')
          .borderRadius('12vp')
          .shadow(ButtonShadow)
          .onClick(() => { router.back(); })
          .padding({ left: '14vp', right: '14vp', top: '10vp', bottom: '10vp' })

        Blank().width('14vp')

        Column() {
          Text('人脸识别')
            .fontSize('28fp')
            .fontWeight(FontWeight.Bold)
            .fontColor('#111827')
          Text('摄像头在左侧，操作与输出在右侧，结果即时显示')
            .fontSize('14fp')
            .fontColor('#475569')
        }
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ top: '24vp', left: '20vp', right: '20vp', bottom: '4vp' })

      Scroll() {
        Row({ space: '18vp' }) {
          Column({ space: '18vp' }) {
            Column({ space: '14vp' }) {
              Text('摄像头画面')
                .fontSize('16fp')
                .fontWeight(FontWeight.Bold)
                .fontColor('#111827')

              VideoComponents({ showControls: false, videoWidth: '100%', videoHeight: '340vp' })
                .borderRadius('18vp')
            }
            .width('100%')
            .padding('18vp')
            .backgroundColor('#f8fafc')
            .borderRadius('24vp')
            .border({ width: '1vp', color: '#e2e8f0' })

            Column({ space: '10vp' }) {
              Text('运行状态')
                .fontSize('16fp')
                .fontWeight(FontWeight.Bold)
                .fontColor('#111827')
              Text(this.connectionState)
                .fontSize('14fp')
                .fontColor(this.connectionState.includes('已连接') ? '#16a34a' : '#d97706')
              Text(this.isRecognizing ? '识别已启动，摄像头实时采集中' : '尚未识别，等待自动或手动启动')
                .fontSize('14fp')
                .fontColor('#475569')
              Text(this.statusText)
                .fontSize('14fp')
                .fontColor('#475569')
            }
            .width('100%')
            .padding('18vp')
            .backgroundColor('#ffffff')
            .borderRadius('24vp')
            .border({ width: '1vp', color: '#e2e8f0' })
          }
          .width('0vp')
          .layoutWeight(1)

          Column({ space: '18vp' }) {
            Column({ space: '18vp' }) {
              Text('服务与识别参数')
                .fontSize('16fp')
                .fontWeight(FontWeight.Bold)
                .fontColor('#111827')

              Column({ space: '12vp' }) {
                Row({ space: '10vp' }) {
                  Text('服务地址')
                    .fontSize('14fp')
                    .fontColor('#475569')
                  Text(this.serviceBaseUrl)
                    .fontSize('14fp')
                    .fontColor('#111827')
                    .layoutWeight(1)
                }
                Row({ space: '10vp' }) {
                  Text('姓名')
                    .width('80vp')
                    .fontSize('14fp')
                    .fontColor('#475569')
                  TextInput({ text: this.name })
                    .onChange((value: string) => this.name = value)
                    .layoutWeight(1)
                    .backgroundColor('#f1f5f9')
                    .fontColor('#111827')
                    .padding({ left: '14vp', right: '14vp', top: '10vp', bottom: '10vp' })
                }
              }
            }
            .width('100%')
            .padding('18vp')
            .backgroundColor('#f8fafc')
            .borderRadius('24vp')
            .border({ width: '1vp', color: '#e2e8f0' })

            Column({ space: '14vp' }) {
              Text('操作')
                .fontSize('16fp')
                .fontWeight(FontWeight.Bold)
                .fontColor('#111827')

              Row({ space: '12vp' }) {
                Button('注册人脸')
                  .layoutWeight(1)
                  .backgroundColor('#2563eb')
                  .fontColor('#ffffff')
                  .shadow(ButtonShadow)
                  .borderRadius('16vp')
                  .onClick(() => this.registerFace())
                Button(this.isRecognizing ? '停止识别' : '开始识别')
                  .layoutWeight(1)
                  .backgroundColor(this.isRecognizing ? '#dc2626' : '#10b981')
                  .fontColor('#ffffff')
                  .shadow(ButtonShadow)
                  .borderRadius('16vp')
                  .onClick(() => this.isRecognizing ? this.stopRecognize() : this.startRecognize())
              }

              Row({ space: '12vp' }) {
                Button('刷新结果')
                  .layoutWeight(1)
                  .backgroundColor('#f1f5f9')
                  .fontColor('#111827')
                  .shadow(ButtonShadow)
                  .borderRadius('16vp')
                  .onClick(() => this.getResult())
                Button('查询状态')
                  .layoutWeight(1)
                  .backgroundColor('#f1f5f9')
                  .fontColor('#111827')
                  .shadow(ButtonShadow)
                  .borderRadius('16vp')
                  .onClick(() => this.getStatus())
              }
            }
            .width('100%')
            .padding('18vp')
            .backgroundColor('#ffffff')
            .borderRadius('24vp')
            .border({ width: '1vp', color: '#e2e8f0' })

            Column({ space: '12vp' }) {
              Text('识别结果')
                .fontSize('16fp')
                .fontWeight(FontWeight.Bold)
                .fontColor('#111827')
              Text(this.faceLabel)
                .fontSize('18fp')
                .fontWeight(FontWeight.Medium)
                .fontColor('#2563eb')
                .lineHeight('24fp')
            }
            .width('100%')
            .padding('18vp')
            .backgroundColor('#f8fafc')
            .borderRadius('24vp')
            .border({ width: '1vp', color: '#e2e8f0' })

            Column({ space: '10vp' }) {
              Text('接口输出')
                .fontSize('16fp')
                .fontWeight(FontWeight.Bold)
                .fontColor('#111827')
              Text(this.resultText)
                .fontSize('14fp')
                .fontColor('#475569')
                .lineHeight('22fp')
            }
            .width('100%')
            .padding('18vp')
            .backgroundColor('#ffffff')
            .borderRadius('24vp')
            .border({ width: '1vp', color: '#e2e8f0' })
          }
          .width('0vp')
          .layoutWeight(1)
        }
        .padding({ left: '20vp', right: '20vp', bottom: '20vp' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#ffffff')
  }

  private async autoStartRecognition(): Promise<void> {
    if (this.isRecognizing) {
      return;
    }
    this.statusText = '正在自动启动人脸识别...';
    const result = await this.callFaceService(http.RequestMethod.POST, '/start');
    this.resultText = result;
    if (!result.includes('失败')) {
      this.isRecognizing = true;
      this.statusText = '人脸识别已自动启动';
      await this.getResult();
    } else {
      this.statusText = '自动启动失败，请手动启动';
    }
  }

  private async loadServiceAddress(): Promise<void> {
    const ip = await PreferencesUtils.getInstance().netUtils.getIP();
    this.serviceBaseUrl = `http://${ip}:5001`;
  }

  private async refreshConnectionState(): Promise<void> {
    const connected = await TCPClientManager.getInstance().isConnect();
    this.connectionState = connected ? '当前已连接到小车，可以进行人脸注册与识别' : '当前尚未连接到小车，请先在网络设置页完成连接';
  }

  private async registerFace(): Promise<void> {
    if (!this.name.trim()) {
      promptAction.showToast({ message: '请输入姓名' });
      return;
    }
    this.statusText = '正在注册人脸...';
    const requestPayload: FacePayload = { name: this.name.trim() };
    const result = await this.callFaceService(http.RequestMethod.POST, '/register', requestPayload);
    this.resultText = result;
    this.faceLabel = this.parseFaceResult(result);
    this.statusText = '注册人脸完成';
    await this.refreshConnectionState();
  }

  private async startRecognize(): Promise<void> {
    this.statusText = '正在开始识别...';
    const result = await this.callFaceService(http.RequestMethod.POST, '/start');
    this.resultText = result;
    this.isRecognizing = !result.includes('失败');
    this.statusText = this.isRecognizing ? '识别已启动' : '识别启动失败';
    if (this.isRecognizing) {
      await this.getResult();
    }
  }

  private async stopRecognize(): Promise<void> {
    this.statusText = '正在停止识别...';
    const result = await this.callFaceService(http.RequestMethod.POST, '/stop');
    this.resultText = result;
    this.isRecognizing = false;
    this.statusText = '识别已停止';
  }

  private async getStatus(): Promise<void> {
    this.statusText = '正在查询状态...';
    const result = await this.callFaceService(http.RequestMethod.GET, '/status');
    this.resultText = result;
    this.statusText = '状态查询完成';
  }

  private async getResult(): Promise<void> {
    this.statusText = '正在查询结果...';
    const result = await this.callFaceService(http.RequestMethod.GET, '/result');
    this.resultText = result;
    this.faceLabel = this.parseFaceResult(result);
    this.statusText = '结果查询完成';
  }

  private parseFaceResult(result: string): string {
    if (!result || result.trim().length === 0) {
      return '暂无识别结果';
    }
    const raw = result.trim();
    try {
      const data = JSON.parse(raw) as FaceResult;
      if (typeof data === 'string') {
        return data;
      }
      if (data.name) {
        return `识别到：${data.name}`;
      }
      if (data.faceName) {
        return `识别到：${data.faceName}`;
      }
      if (data.person) {
        return `识别到：${data.person}`;
      }
      if (data.result) {
        return `识别到：${data.result}`;
      }
      if (data.data && data.data.name) {
        return `识别到：${data.data.name}`;
      }
      return JSON.stringify(data);
    } catch {
      return raw;
    }
  }

  private async callFaceService(method: http.RequestMethod, path: string, payload?: FacePayload): Promise<string> {
    const baseUrl = this.serviceBaseUrl.trim().replace(/\/$/, '');
    const requestUrl = `${baseUrl}${path}`;
    const httpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await new Promise((resolve, reject) => {
        httpRequest.request(
          requestUrl,
          {
            method: method,
            header: {
              'Content-Type': 'application/json'
            },
            expectDataType: http.HttpDataType.STRING,
            connectTimeout: 10000,
            readTimeout: 10000,
            extraData: payload ? JSON.stringify(payload) : undefined
          },
          (err, data) => {
            if (err) {
              reject(err);
            } else {
              resolve(data);
            }
          }
        );
      });

      return typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
    } catch (error) {
      return `请求失败: ${JSON.stringify(error)}`;
    } finally {
      httpRequest.destroy();
    }
  }
}
