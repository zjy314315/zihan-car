import router from '@ohos.router';
import socket from '@ohos.net.socket';
import { TCPClientManager } from '../tcp/TCPClientManager';
import { PreferencesUtils } from '../utils/PreferencesUtils';
import promptAction from '@ohos.promptAction';
import speechRecognizer from '@ohos.ai.speechRecognizer';

@Entry
@Component
struct SmartDialogue {
  @State question: string = '';
  @State status: string = '等待提问';
  @State isSending: boolean = false;
  @State isListening: boolean = false;
  @State voiceText: string = '';
  private carIp: string = '';
  private asrEngine: speechRecognizer.SpeechRecognizer | null = null;

  async aboutToAppear(): Promise<void> {
    this.carIp = await PreferencesUtils.getInstance().netUtils.getIP() as string;
    TCPClientManager.getInstance().initNetAddress({ address: this.carIp, port: 6001 } as socket.NetAddress);
    await TCPClientManager.getInstance().connect();
    this.initAsr();
  }

  aboutToDisappear(): void {
    this.stopListening();
    if (this.asrEngine) {
      try { this.asrEngine.destroy(); } catch (_) { /* */ }
      this.asrEngine = null;
    }
    TCPClientManager.getInstance().closeConnection();
    TCPClientManager.getInstance().initNetAddress({ address: this.carIp, port: 6000 } as socket.NetAddress);
  }

  // ====== ASR 语音识别 ======
  private async initAsr(): Promise<void> {
    try {
      this.asrEngine = await speechRecognizer.createRecognizer({
        language: 'zh-CN',
        online: 1
      });
      this.asrEngine.on('result', (result: speechRecognizer.SpeechRecognitionResult) => {
        let text: string = result.result?.full || '';
        this.voiceText = text;
        this.question = text;
        this.status = `语音识别: "${text}"`;
      });
      this.asrEngine.on('error', (err: number) => {
        this.isListening = false;
        this.status = '语音识别失败，请使用文字输入';
        promptAction.showToast({ message: '语音识别失败' });
      });
      this.asrEngine.on('end', () => {
        this.isListening = false;
        if (this.voiceText) {
          this.status = '语音识别完成，点击发送';
        }
      });
    } catch (e) {
      console.error('ASR 初始化失败:', JSON.stringify(e));
      this.status = '语音服务不可用，请使用文字输入';
    }
  }

  private async startListening(): Promise<void> {
    if (!this.asrEngine) {
      await this.initAsr();
    }
    if (!this.asrEngine) {
      promptAction.showToast({ message: '语音服务不可用' });
      return;
    }
    try {
      this.isListening = true;
      this.voiceText = '';
      this.status = '正在聆听...';
      this.asrEngine.startListening({
        mode: 'short',
        silenceTime: 3000
      });
    } catch (e) {
      this.isListening = false;
      this.status = '语音启动失败';
    }
  }

  private stopListening(): void {
    if (this.asrEngine && this.isListening) {
      try {
        this.asrEngine.stopListening();
      } catch (_) { /* */ }
    }
    this.isListening = false;
  }

  // ====== 发送 ======
  async sendQuestion(): Promise<void> {
    await this.sendQuestionText(this.question.trim(), '请先输入问题或点击语音按钮');
  }

  private async sendQuestionText(text: string, emptyTip: string): Promise<void> {
    if (!text) {
      this.status = emptyTip;
      return;
    }
    this.question = text;
    this.isSending = true;
    this.status = '正在发送给小车...';
    TCPClientManager.getInstance().initNetAddress({ address: this.carIp, port: 6001 } as socket.NetAddress);
    const payload = `@LLM:${JSON.stringify({ question: text })}` + String.fromCharCode(10);
    let sent = await TCPClientManager.getInstance().sendMessage(payload);
    if (!sent && await TCPClientManager.getInstance().connect()) {
      sent = await TCPClientManager.getInstance().sendMessage(payload);
    }
    this.isSending = false;
    this.status = sent ? '小车正在生成并播放回复' : '连接不可用，请先连接小车';
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
          Text('语音或文字提问，小车语音回答').fontSize('13fp').fontColor('#64748b')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%').padding({ left: '20vp', right: '20vp', top: '20vp' })

      Scroll() {
        Column({ space: '16vp' }) {

          // ====== 语音输入 ======
          Column({ space: '10vp' }) {
            Text('语音提问').fontSize('16fp').fontWeight(FontWeight.Bold).fontColor('#111111').width('100%')
            Text(this.isListening ? '正在聆听...' : (this.voiceText || '点击按钮开始说话'))
              .fontSize('14fp').fontColor(this.isListening ? '#dc2626' : '#666666').width('100%')

            Row({ space: '10vp' }) {
              Button(this.isListening ? '⏹ 停止' : '🎤 按住说话')
                .layoutWeight(1).height('52vp')
                .fontSize('16fp').fontWeight(FontWeight.Medium).fontColor('#ffffff')
                .backgroundColor(this.isListening ? '#dc2626' : '#2563eb').borderRadius('26vp')
                .onClick(() => {
                  if (this.isListening) {
                    this.stopListening();
                  } else {
                    this.startListening();
                  }
                })

              Button('发送语音')
                .layoutWeight(1).height('52vp')
                .fontSize('16fp').fontWeight(FontWeight.Medium).fontColor('#ffffff')
                .backgroundColor(this.voiceText ? '#22c55e' : '#9e9ea0').borderRadius('26vp')
                .enabled(this.voiceText.length > 0)
                .onClick(() => this.sendQuestionText(this.voiceText, ''))
            }.width('100%')
          }.width('100%').padding('18vp')
            .border({ width: '1vp', color: '#dbeafe' }).borderRadius('8vp')
            .backgroundColor('#eff6ff')

          // ====== 文字输入 ======
          Column({ space: '10vp' }) {
            Text('文字提问').fontSize('16fp').fontWeight(FontWeight.Bold).fontColor('#111111').width('100%')
            TextInput({ placeholder: '输入问题，如：apple 的中文是什么', text: this.question })
              .onChange((value: string) => this.question = value)
              .width('100%').height('50vp').fontSize('16fp').fontColor('#111111')
              .backgroundColor('#ffffff').border({ width: '1vp', color: '#cbd5e1' }).borderRadius('8vp')
              .padding({ left: '14vp', right: '14vp' })
            Button(this.isSending ? '发送中...' : '发送给小车')
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