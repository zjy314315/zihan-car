import router from '@ohos.router';
import socket from '@ohos.net.socket';
import { TCPClientManager } from '../tcp/TCPClientManager';
import { PreferencesUtils } from '../utils/PreferencesUtils';
import { ProcessLifecycle } from '../utils/ProcessLifecycle';

@Entry
@Component
struct SmartDialogue {
  @State question: string = '';
  @State status: string = '等待提问';
  @State isSending: boolean = false;
  private carIp: string = '';

  async aboutToAppear(): Promise<void> {
    this.carIp = await PreferencesUtils.getInstance().netUtils.getIP() as string;
    await ProcessLifecycle.start('dialogue');
    TCPClientManager.getInstance().initNetAddress({ address: this.carIp, port: 6001 } as socket.NetAddress);
    await TCPClientManager.getInstance().connect();
  }

  aboutToDisappear(): void {
    ProcessLifecycle.stop('dialogue');
    TCPClientManager.getInstance().closeConnection();
    TCPClientManager.getInstance().initNetAddress({ address: this.carIp, port: 6000 } as socket.NetAddress);
  }

  async sendQuestion(): Promise<void> {
    await this.sendQuestionText(this.question.trim(), '请先输入问题');
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
          Text('文字提问，小车语音回答').fontSize('13fp').fontColor('#64748b')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%').padding({ left: '20vp', right: '20vp', top: '20vp' })

      Scroll() {
        Column({ space: '16vp' }) {

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