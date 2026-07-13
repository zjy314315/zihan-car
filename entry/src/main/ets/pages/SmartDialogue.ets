import router from '@ohos.router';
import { TCPClientManager } from '../tcp/TCPClientManager';

@Entry
@Component
struct SmartDialogue {
  @State question: string = '';
  @State status: string = '';

  async sendQuestion() {
    const text = this.question.trim();
    if (!text) {
      this.status = 'Enter a question first.';
      return;
    }
    this.status = 'Sending to car...';
    const payload = `@LLM:${JSON.stringify({ question: text })}` + String.fromCharCode(10);
    const sent = await TCPClientManager.getInstance().sendMessage(payload);
    this.status = sent ? 'Car is speaking...' : 'Connection unavailable.';
  }

  build() {
    Column({ space: '16vp' }) {
      Row() {
        Button('<').onClick(() => router.back()).width('44vp').height('40vp')
        Text('AI Dialogue').fontSize('22fp').fontWeight(FontWeight.Bold).margin({ left: '12vp' })
      }.width('100%')
      TextInput({ placeholder: 'Type a question for the car', text: this.question })
        .onChange((value: string) => this.question = value)
        .width('100%').height('52vp').backgroundColor('#f1f5f9').borderRadius('10vp')
      Button('Ask car').onClick(() => this.sendQuestion()).width('100%').height('52vp')
        .fontColor('#ffffff').backgroundColor('#0f766e').borderRadius('10vp')
      Text(this.status).fontSize('15fp').fontColor('#475569').width('100%')
    }.width('100%').height('100%').padding('20vp').backgroundColor('#ffffff')
  }
}