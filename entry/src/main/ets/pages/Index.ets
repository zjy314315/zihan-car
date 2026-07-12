import router from '@ohos.router';
import { ButtonShadow } from '../styles/styles';

@Entry
@Component
struct Index {
  build() {
    Column({ space: '16vp' }) {
      Text('智行小车控制中心')
        .fontSize('24fp')
        .fontWeight(FontWeight.Bold)
        .fontColor('#111827')
        .width('100%')
        .textAlign(TextAlign.Start)

      Grid() {
        GridItem() {
          ItemButton({
            text: '麦克纳姆轮',
            icon: $r('app.media.tire'),
            event: () => {
              router.pushUrl({ url: 'pages/MecanumWheel' })
            }
          })
        }

        GridItem() {
          ItemButton({
            text: '单独控制',
            icon: $r('app.media.vector'),
            event: () => {
              router.pushUrl({ url: 'pages/RemoteControl' })
            }
          })
        }

        GridItem() {
          ItemButton({
            text: '人脸识别',
            icon: $r('app.media.app_icon'),
            event: () => {
              router.pushUrl({ url: 'pages/FaceRecognition' })
            }
          })
        }
      }
      .width('100%')
      .columnsTemplate('1fr 1fr 1fr')
      .rowsTemplate('1fr')
      .columnsGap('10vp')
      .rowsGap('10vp')
      .height('176vp')
    }
    .width('100%')
    .height('100%')
    .padding({ top: '24vp', left: '16vp', right: '16vp', bottom: '20vp' })
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
            .width('72vp')
            .height('72vp')
          Text(this.text)
            .fontColor('#0f172a')
            .fontSize('15fp')
            .fontWeight(FontWeight.Medium)
        }
        .padding('12vp')
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
