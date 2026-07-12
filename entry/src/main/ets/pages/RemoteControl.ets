import router from '@ohos.router';
import { carApi } from '../CarUtill/CarApi';
import { CarEncode } from '../CarUtill/CarEncode';
import { CarBtnComponents } from '../components/CarBtnComponents';
import { CarRockerComponents } from '../components/CarRockerComponents';
import { VideoComponents } from '../components/VideoComponents';
import { ButtonShadow } from '../styles/styles';

@Entry
@Component
struct RemoteControl {
  @State nowCtrlModel: CtrlModel = CtrlModel.Button
  ctrlTextTextList: string[] = ['按钮', '遥杆']
  ctrlModeList: CtrlModel[] = [CtrlModel.Button, CtrlModel.Rocker]

  build() {
    Column({ space: '14vp' }) {
      Row() {
        Button('返回')
          .backgroundColor('#111827')
          .fontColor('#ffffff')
          .borderRadius('12vp')
          .shadow(ButtonShadow)
          .onClick(() => { router.back(); })
          .padding({ left: '14vp', right: '14vp', top: '10vp', bottom: '10vp' })
      }
      .width('100%')
      .padding({ top: '24vp', left: '16vp', right: '16vp', bottom: '4vp' })

      Scroll() {
        Column({ space: '14vp' }) {
          Column({ space: '12vp' }) {
            Row({ space: '10vp' }) {
              ForEach(this.ctrlTextTextList, (item: string, index: number) => {
                MyTab({
                  state: this.nowCtrlModel == this.ctrlModeList[index],
                  text: item
                }).onClick(() => { state: this.nowCtrlModel = this.ctrlModeList[index] })
              }, (item: string) => item)
            }
            .padding('12vp')
            .backgroundColor('#f8fafc')
            .borderRadius('20vp')
            .border({ width: '1vp', color: '#e2e8f0' })

            Stack() {
              CarBtnComponents()
                .visibility(this.nowCtrlModel == CtrlModel.Button ? Visibility.Visible : Visibility.None)
              CarRockerComponents()
                .visibility(this.nowCtrlModel == CtrlModel.Rocker ? Visibility.Visible : Visibility.None)
            }
            .width('100%')
            .height('280vp')
            .padding('12vp')
            .backgroundColor('#f8fafc')
            .borderRadius('20vp')
            .border({ width: '1vp', color: '#e2e8f0' })
          }

          Column({ space: '12vp' }) {
            Text('摄像头画面')
              .fontSize('15fp')
              .fontWeight(FontWeight.Bold)
              .fontColor('#111827')

            VideoComponents({ showControls: true, videoWidth: '100%', videoHeight: '240vp' })
              .borderRadius('18vp')

            Row() {
              Checkbox() {
                Text('自动循迹')
                  .fontSize('14fp')
                  .fontColor('#111827')
              }.onChange((value: boolean) => {
                if (value) {
                  carApi.send(CarEncode.TrackingOpenEncode());
                } else {
                  carApi.send(CarEncode.TrackingCloseEncode());
                }
              })
            }
          }
          .width('100%')
          .padding('14vp')
          .backgroundColor('#f8fafc')
          .borderRadius('20vp')
          .border({ width: '1vp', color: '#e2e8f0' })
        }
        .padding({ left: '16vp', right: '16vp', bottom: '20vp' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#ffffff')
  }
}

enum CtrlModel {
  Button = 0,
  Rocker = 1,
}

@Component
struct MyTab {
  @Prop state: boolean = false;
  @Prop text: string = 'hello';

  build() {
    Stack() {
      Text(this.text)
        .width('60vp')
        .fontSize('18fp')
        .fontColor(this.state ? '#111827' : '#475569')
    }
    .backgroundColor(this.state ? '#e0f2fe' : '#f8fafc')
    .borderRadius('18vp')
    .padding({ left: '16vp', right: '16vp', top: '10vp', bottom: '10vp' })
  }
}
