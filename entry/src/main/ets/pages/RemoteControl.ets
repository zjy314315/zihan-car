import router from '@ohos.router';
import { carApi } from '../CarUtill/CarApi';
import { CarEncode } from '../CarUtill/CarEncode';
import { CarBtnComponents } from '../components/CarBtnComponents';
import { CarRockerComponents } from '../components/CarRockerComponents';
import { VideoComponents } from '../components/VideoComponents';

enum CtrlModel { Button = 0, Rocker = 1 }

@Entry
@Component
struct RemoteControl {
  @State nowCtrlModel: CtrlModel = CtrlModel.Button
  @State trackingOn: boolean = false;
  @State isRecording: boolean = false;
  tabs: string[] = ['按钮', '摇杆']

  build() {
    Column() {
      // ====== 顶部栏 ======
      Row({ space: '8vp' }) {
        Button('← 返回')
          .fontSize('12fp').fontColor('#ffffff').backgroundColor('#1a1a1a')
          .borderRadius('6vp').padding({ left: '10vp', right: '10vp', top: '6vp', bottom: '6vp' })
          .onClick(() => { router.back(); })
        Text('单独控制').fontSize('15fp').fontWeight(FontWeight.Bold).fontColor('#111111')
        Blank()
        Row({ space: '4vp' }) {
          ForEach(this.tabs, (item: string, idx: number) => {
            Text(item)
              .fontSize('11fp')
              .fontColor(this.nowCtrlModel === idx ? '#ffffff' : '#666666')
              .padding({ left: '12vp', right: '12vp', top: '5vp', bottom: '5vp' })
              .borderRadius('4vp')
              .backgroundColor(this.nowCtrlModel === idx ? '#1a1a1a' : '#f1f1f1')
              .onClick(() => { this.nowCtrlModel = idx as CtrlModel; })
          }, (item: string) => item)
        }
        .padding('2vp').backgroundColor('#f1f1f1').borderRadius('6vp')
      }
      .width('100%').padding({ left: '10vp', right: '10vp', top: '8vp', bottom: '6vp' })
      .backgroundColor('#fafafa').border({ width: { bottom: '1vp' }, color: '#e5e5e5' })

      // ====== 主体：左右布局 ======
      Row({ space: '8vp' }) {
        // ---- 左侧：控制面板 + 循迹 + 录制 ----
        Column({ space: '6vp' }) {
          Text('操控面板').fontSize('11fp').fontWeight(FontWeight.Medium).fontColor('#999999').width('100%')

          Stack() {
            if (this.nowCtrlModel === CtrlModel.Button) { CarBtnComponents() }
            if (this.nowCtrlModel === CtrlModel.Rocker) { CarRockerComponents() }
          }
          .width('100%').layoutWeight(1)
          .padding('4vp').backgroundColor('#fafafa').borderRadius('10vp')
          .border({ width: '1vp', color: '#e5e5e5' })

          // 自动循迹
          Row({ space: '6vp' }) {
            Checkbox({ name: 'tracking', group: 'ctrl' })
              .select(this.trackingOn).selectedColor('#333333')
              .onChange((v: boolean) => {
                this.trackingOn = v;
                carApi.send(v ? CarEncode.TrackingOpenEncode() : CarEncode.TrackingCloseEncode());
              })
            Text('自动循迹').fontSize('11fp').fontColor('#666666')
            Blank()
            Text(this.trackingOn ? 'ON' : 'OFF')
              .fontSize('10fp').fontColor(this.trackingOn ? '#333333' : '#cccccc')
          }
          .width('100%').padding({ left: '10vp', right: '10vp', top: '7vp', bottom: '7vp' })
          .backgroundColor('#fafafa').borderRadius('8vp').border({ width: '1vp', color: '#e5e5e5' })

          // 录制控制
          Row({ space: '6vp' }) {
            Text('录制').fontSize('11fp').fontColor('#999999').width('36vp')
            Button('拍照')
              .layoutWeight(1).fontSize('11fp').fontColor('#666666').backgroundColor('#f1f1f1')
              .borderRadius('6vp').height('32vp')
              .onClick(() => { carApi.send(CarEncode.TakePhotosEncode()); })
            Button(this.isRecording ? '停止' : '录像')
              .layoutWeight(1).fontSize('11fp')
              .fontColor(this.isRecording ? '#ffffff' : '#666666')
              .backgroundColor(this.isRecording ? '#1a1a1a' : '#f1f1f1')
              .borderRadius('6vp').height('32vp')
              .onClick(() => {
                if (this.isRecording) {
                  carApi.send(CarEncode.CloselRecordingEncode());
                } else {
                  carApi.send(CarEncode.StartRecordingEncode());
                }
                this.isRecording = !this.isRecording;
              })
          }
          .width('100%').padding({ left: '10vp', right: '10vp', top: '7vp', bottom: '7vp' })
          .backgroundColor('#fafafa').borderRadius('8vp').border({ width: '1vp', color: '#e5e5e5' })
        }
        .width('0vp').layoutWeight(5)
        .padding('8vp').backgroundColor('#ffffff').borderRadius('12vp')
        .border({ width: '1vp', color: '#e5e5e5' })

        // ---- 右侧：视频画面 ----
        Column({ space: '4vp' }) {
          Text('实时画面').fontSize('11fp').fontWeight(FontWeight.Medium).fontColor('#999999').width('100%')
          VideoComponents({ showControls: false, videoWidth: '100%', videoHeight: '100%' })
            .borderRadius('10vp').layoutWeight(1)
        }
        .width('0vp').layoutWeight(4)
        .padding('8vp').backgroundColor('#fafafa').borderRadius('12vp')
        .border({ width: '1vp', color: '#e5e5e5' })
      }
      .width('100%').layoutWeight(1).padding('8vp')
    }
    .width('100%').height('100%').backgroundColor('#ffffff')
  }
}
