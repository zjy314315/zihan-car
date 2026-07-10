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
          Text('单独控制')
            .fontSize('28fp')
            .fontWeight(FontWeight.Bold)
            .fontColor('#111827')
          Text('小车控制与摄像头画面统一风格展示')
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
            Row({ space: '12vp' }) {
              ForEach(this.ctrlTextTextList, (item: string, index: number) => {
                MyTab({
                  state: this.nowCtrlModel == this.ctrlModeList[index],
                  text: item
                }).onClick(() => { state: this.nowCtrlModel = this.ctrlModeList[index] })
              }, (item: string) => item)
            }
            .padding('16vp')
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
            .height('320vp')
            .padding('18vp')
            .backgroundColor('#f8fafc')
            .borderRadius('20vp')
            .border({ width: '1vp', color: '#e2e8f0' })
          }
          .width('0vp')
          .layoutWeight(1)

          Column({ space: '18vp' }) {
            Column({ space: '14vp' }) {
              Text('摄像头画面')
                .fontSize('16fp')
                .fontWeight(FontWeight.Bold)
                .fontColor('#111827')

              VideoComponents({ showControls: true, videoWidth: '100%', videoHeight: '320vp' })
                .borderRadius('18vp')
            }
            .width('100%')
            .padding('18vp')
            .backgroundColor('#f8fafc')
            .borderRadius('20vp')
            .border({ width: '1vp', color: '#e2e8f0' })

            Column({ space: '12vp' }) {
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
            .padding('18vp')
            .backgroundColor('#ffffff')
            .borderRadius('20vp')
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
