import router from '@ohos.router';
import { ButtonShadow } from '../styles/styles';

@Entry
@Component
struct Index {
  build() {
    Column() {
      Column() {
        Text('智行小车控制中心')
          .fontSize('32fp')
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
        Text('选择功能，快速切换到控制、网络或人脸识别界面')
          .fontSize('16fp')
          .fontColor('#475569')
          .margin({ top: '8vp' })
      }
      .padding({ top: '28vp', bottom: '24vp', left: '20vp', right: '20vp' })

      Row({ space: '16vp' }) {
        ItemButton({
          text: "麦科朗姆",
          icon: $r('app.media.tire'),
          event: () => {
            router.pushUrl({ url: 'pages/MecanumWheel' })
          }
        })
          .width('280vp')
          .height('220vp')

        ItemButton({
          text: "单独控制",
          icon: $r('app.media.vector'),
          event: () => {
            router.pushUrl({ url: 'pages/RemoteControl' })
          }
        })
          .width('280vp')
          .height('220vp')
      }
      .padding({ left: '20vp', right: '20vp' })

      Row({ space: '16vp' }) {
        ItemButton({
          text: "人脸识别",
          icon: $r('app.media.app_icon'),
          event: () => {
            router.pushUrl({ url: 'pages/FaceRecognition' })
          }
        })
          .width('280vp')
          .height('220vp')
      }
      .padding({ left: '20vp', right: '20vp', top: '16vp' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#ffffff')
  }
}

@Component
struct ItemButton {
  @State text: string = "";
  @State icon: Resource = $r('app.media.app_icon');
  event: (event?: ClickEvent) => void = () => {
  }

  build() {
    Stack() {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Column({ space: '16vp' }) {
          Image(this.icon)
            .width('100vp')
            .height('100vp')
          Text(this.text)
            .fontColor('#0f172a')
            .fontSize('18fp')
            .fontWeight(FontWeight.Medium)
        }
        .padding('18vp')
      }
      .width('100%')
      .height('100%')
      .onClick(() => {
        this.event()
      })
      .backgroundColor('#f8fafc')
      .border({ width: '1vp', color: '#e2e8f0' })
      .shadow(ButtonShadow)
      .borderRadius('24vp')
    }
  }
}
