import router from '@ohos.router';
import socket from '@ohos.net.socket';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import { common } from '@ohos.app.ability';
import { speechRecognizer } from '@kit.CoreSpeechKit';
import { TCPClientManager } from '../tcp/TCPClientManager';
import { PreferencesUtils } from '../utils/PreferencesUtils';

interface SpeechResult {
  text?: string;
  result?: string;
  transcript?: string;
  data?: SpeechResult;
}

@Entry
@Component
struct SmartDialogue {
  @State question: string = '';
  @State recognizedText: string = '点击开始说话，识别结果会显示在这里。';
  @State status: string = '等待提问';
  @State isListening: boolean = false;
  private carIp: string = '';
  private recognizer: Object | undefined = undefined;

  async aboutToAppear(): Promise<void> {
    this.carIp = await PreferencesUtils.getInstance().netUtils.getIP() as string;
    TCPClientManager.getInstance().initNetAddress({ address: this.carIp, port: 6001 } as socket.NetAddress);
    await TCPClientManager.getInstance().connect();
  }

  aboutToDisappear(): void {
    this.stopListening(false);
    TCPClientManager.getInstance().closeConnection();
    TCPClientManager.getInstance().initNetAddress({ address: this.carIp, port: 6000 } as socket.NetAddress);
  }

  async sendQuestion(): Promise<void> {
    const text = this.question.trim();
    if (!text) {
      this.status = '请先输入问题或使用语音识别';
      return;
    }
    this.status = '正在发送给小车...';
    TCPClientManager.getInstance().initNetAddress({ address: this.carIp, port: 6001 } as socket.NetAddress);
    const payload = `@LLM:${JSON.stringify({ question: text })}` + String.fromCharCode(10);
    let sent = await TCPClientManager.getInstance().sendMessage(payload);
    if (!sent && await TCPClientManager.getInstance().connect()) {
      sent = await TCPClientManager.getInstance().sendMessage(payload);
    }
    this.status = sent ? '小车正在生成并播放回复' : '连接不可用，请先连接小车';
  }

  async toggleListening(): Promise<void> {
    if (this.isListening) {
      this.stopListening(true);
      return;
    }
    if (!await this.requestMicrophonePermission()) {
      this.status = '未获得麦克风权限';
      return;
    }
    try {
      const api = speechRecognizer as Object;
      const create = this.getMethod(api, ['createSpeechRecognizer', 'createRecognizer', 'create']);
      if (!create) {
        throw new Error('当前设备未提供语音识别服务');
      }
      this.recognizer = await Promise.resolve(Reflect.apply(create, api, [])) as Object;
      this.bindRecognizerEvents(this.recognizer);
      const start = this.getMethod(this.recognizer, ['startListening', 'start']);
      if (!start) {
        throw new Error('当前设备不支持启动语音识别');
      }
      const options = { language: 'zh-CN', locale: 'zh-CN', continuous: false };
      const callbacks = {
        onResult: (result: Object) => this.receiveSpeechResult(result),
        onError: (error: Object) => this.receiveSpeechError(error)
      };
      try {
        await Promise.resolve(Reflect.apply(start, this.recognizer, [options, callbacks]));
      } catch (_) {
        await Promise.resolve(Reflect.apply(start, this.recognizer, [options]));
      }
      this.isListening = true;
      this.status = '正在聆听，请说出问题';
      this.recognizedText = '正在识别...';
    } catch (error) {
      this.isListening = false;
      this.status = `语音识别不可用：${this.errorText(error)}`;
    }
  }

  private stopListening(sendAfterStop: boolean): void {
    if (!this.recognizer) {
      return;
    }
    const stop = this.getMethod(this.recognizer, ['stopListening', 'stop', 'cancel']);
    try {
      if (stop) {
        Reflect.apply(stop, this.recognizer, []);
      }
    } catch (error) {
      this.status = `停止识别失败：${this.errorText(error)}`;
      return;
    }
    this.isListening = false;
    if (sendAfterStop && this.question.trim()) {
      this.sendQuestion();
    } else if (sendAfterStop) {
      this.status = '未识别到有效语音，请重试';
    }
  }

  private bindRecognizerEvents(recognizer: Object): void {
    const subscribe = this.getMethod(recognizer, ['on', 'addListener']);
    if (!subscribe) {
      return;
    }
    const onResult = (result: Object) => this.receiveSpeechResult(result);
    const onError = (error: Object) => this.receiveSpeechError(error);
    Reflect.apply(subscribe, recognizer, ['result', onResult]);
    Reflect.apply(subscribe, recognizer, ['recognitionResult', onResult]);
    Reflect.apply(subscribe, recognizer, ['error', onError]);
  }

  private receiveSpeechResult(result: Object): void {
    const text = this.speechText(result).trim();
    if (!text) {
      return;
    }
    this.question = text;
    this.recognizedText = text;
    this.status = '已识别，点击停止并发送';
  }

  private receiveSpeechError(error: Object): void {
    this.isListening = false;
    this.status = `语音识别失败：${this.errorText(error)}`;
  }

  private async requestMicrophonePermission(): Promise<boolean> {
    const context = getContext(this) as common.UIAbilityContext;
    const manager = abilityAccessCtrl.createAtManager();
    const result = await manager.requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE']);
    return result.authResults.length > 0 && result.authResults[0] === 0;
  }

  private getMethod(target: Object, names: string[]): Function | undefined {
    for (let index = 0; index < names.length; index++) {
      const candidate = Reflect.get(target, names[index]);
      if (typeof candidate === 'function') {
        return candidate as Function;
      }
    }
    return undefined;
  }

  private speechText(result: Object): string {
    try {
      const data = JSON.parse(JSON.stringify(result)) as SpeechResult | string;
      if (typeof data === 'string') {
        return data;
      }
      return data.text || data.transcript || data.result || data.data?.text || data.data?.transcript || data.data?.result || '';
    } catch (_) {
      return '';
    }
  }

  private errorText(error: Object): string {
    try {
      return JSON.stringify(error);
    } catch (_) {
      return '系统服务异常';
    }
  }

  build() {
    Column({ space: '16vp' }) {
      Row({ space: '12vp' }) {
        Button('<')
          .width('40vp').height('40vp').fontSize('20fp').fontColor('#111111')
          .backgroundColor('#f1f5f9').borderRadius('8vp')
          .onClick(() => router.back())
        Column({ space: '2vp' }) {
          Text('智能对话').fontSize('22fp').fontWeight(FontWeight.Bold).fontColor('#111111')
          Text('语音提问，小车语音回答').fontSize('13fp').fontColor('#64748b')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%').padding({ left: '20vp', right: '20vp', top: '20vp' })

      Scroll() {
        Column({ space: '16vp' }) {
          Column({ space: '12vp' }) {
            Text('语音提问').fontSize('16fp').fontWeight(FontWeight.Bold).fontColor('#111111').width('100%')
            Text(this.recognizedText).fontSize('16fp').fontColor('#334155').lineHeight('24fp').width('100%')
            Button(this.isListening ? '停止并发送' : '开始说话')
              .onClick(() => this.toggleListening())
              .width('100%').height('52vp').fontSize('16fp').fontWeight(FontWeight.Medium)
              .fontColor('#ffffff').backgroundColor(this.isListening ? '#dc2626' : '#2563eb').borderRadius('8vp')
          }.width('100%').padding('18vp').backgroundColor('#eff6ff').border({ width: '1vp', color: '#bfdbfe' }).borderRadius('8vp')

          Column({ space: '10vp' }) {
            Text('文字提问').fontSize('16fp').fontWeight(FontWeight.Bold).fontColor('#111111').width('100%')
            TextInput({ placeholder: '也可以直接输入问题', text: this.question })
              .onChange((value: string) => this.question = value)
              .width('100%').height('50vp').fontSize('16fp').fontColor('#111111')
              .backgroundColor('#ffffff').border({ width: '1vp', color: '#cbd5e1' }).borderRadius('8vp')
              .padding({ left: '14vp', right: '14vp' })
            Button('发送给小车')
              .onClick(() => this.sendQuestion())
              .width('100%').height('48vp').fontSize('16fp').fontWeight(FontWeight.Medium)
              .fontColor('#ffffff').backgroundColor('#111827').borderRadius('8vp')
          }.width('100%').padding('18vp').border({ width: '1vp', color: '#e2e8f0' }).borderRadius('8vp')

          Column({ space: '6vp' }) {
            Text('对话状态').fontSize('13fp').fontWeight(FontWeight.Bold).fontColor('#64748b').width('100%')
            Text(this.status).fontSize('16fp').fontColor('#111111').width('100%')
          }.width('100%').padding('16vp').backgroundColor('#f8fafc').borderRadius('8vp')
        }.width('100%').padding({ left: '20vp', right: '20vp', bottom: '28vp' })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
    }.width('100%').height('100%').backgroundColor('#ffffff')
  }
}
