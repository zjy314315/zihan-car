import router from '@ohos.router';
import socket from '@ohos.net.socket';
import { TCPClientManager } from '../tcp/TCPClientManager';
import { PreferencesUtils } from '../utils/PreferencesUtils';

@Entry
@Component
struct SmartDialogue {
  @State question: string = '';
  @State status: string = '等待输入';
  private carIp: string = '';

  async aboutToAppear(): Promise<void> {
    this.carIp = await PreferencesUtils.getInstance().netUtils.getIP() as string;
    TCPClientManager.getInstance().initNetAddress({ address: this.carIp, port: 6001 } as socket.NetAddress);
    await TCPClientManager.getInstance().connect();
  }

  aboutToDisappear(): void {
    TCPClientManager.getInstance().closeConnection();
    TCPClientManager.getInstance().initNetAddress({ address: this.carIp, port: 6000 } as socket.NetAddress);
  }

  async sendQuestion() {
    const text = this.question.trim();
    if (!text) {
      this.status = '请先输入问题';
      return;
    }
    this.status = '正在发送给小车...';
    TCPClientManager.getInstance().initNetAddress({ address: this.carIp, port: 6001 } as socket.NetAddress);
    const payload = `@LLM:${JSON.stringify({ question: text })}` + String.fromCharCode(10);
    const sent = await TCPClientManager.getInstance().sendMessage(payload);
    this.status = sent ? '小车正在语音回复' : '连接不可用，请先连接小车';
  }

  build() {
    Column() {
      Row({ space: '12vp' }) {
        Button('<')
          .width('44vp').height('44vp').fontSize('22fp').fontColor('#111111')
          .backgroundColor('#f5f5f5').borderRadius('22vp')
          .onClick(() => router.back())
        Column() {
          Text('语音助手').fontSize('11fp').fontWeight(FontWeight.Bold).fontColor('#707072')
          Text('智能对话').fontSize('26fp').fontWeight(FontWeight.Bold).fontColor('#111111')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%').padding({ left: '20vp', right: '20vp', top: '20vp', bottom: '16vp' })

      Scroll() {
        Column({ space: '24vp' }) {
          Column({ space: '8vp' }) {
            Text('向小车提问').fontSize('12fp').fontWeight(FontWeight.Bold).fontColor('#707072').width('100%')
            Text('输入一句话，小车会通过语音回答。').fontSize('22fp').fontWeight(FontWeight.Bold).fontColor('#111111').width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start)

          Column({ space: '16vp' }) {
            TextInput({ placeholder: '例如：介绍一下你现在能做什么', text: this.question })
              .onChange((value: string) => this.question = value)
              .width('100%').height('52vp').fontSize('16fp').fontColor('#111111')
              .backgroundColor('#ffffff').borderRadius('26vp')
              .padding({ left: '18vp', right: '18vp' })

            Button('发送给小车')
              .onClick(() => this.sendQuestion())
              .width('100%').height('52vp').fontSize('16fp').fontWeight(FontWeight.Medium)
              .fontColor('#ffffff').backgroundColor('#111111').borderRadius('28vp')
          }
          .width('100%').padding('20vp').backgroundColor('#f5f5f5').borderRadius('24vp')

          Column({ space: '8vp' }) {
            Text('对话状态').fontSize('12fp').fontWeight(FontWeight.Bold).fontColor('#707072').width('100%')
            Text(this.status).fontSize('18fp').fontWeight(FontWeight.Bold).fontColor('#111111').width('100%')
            Text('当前对话服务使用 6001 端口。').fontSize('13fp').fontColor('#707072').width('100%')
          }
          .width('100%').padding('18vp').backgroundColor('#f5f5f5').borderRadius('24vp')
        }
        .width('100%').padding({ left: '20vp', right: '20vp', bottom: '36vp' })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
    }
    .width('100%').height('100%').backgroundColor('#ffffff')
  }
}
