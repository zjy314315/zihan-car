import web_webview from '@ohos.web.webview'
import { carApi } from '../CarUtill/CarApi';
import { CarEncode } from '../CarUtill/CarEncode';
import { ButtonShadow } from '../styles/styles';

let TAG = "VideoComponents"

@Component
export struct VideoComponents {
  controller: web_webview.WebviewController = new web_webview.WebviewController()
  public static port: number = 5000;
  public static ip: string = "192.168.1.11"
  @Prop showControls: boolean = true
  @Prop videoWidth: Length = '300vp'
  @Prop videoHeight: Length = '200vp'
  @State isRecording: boolean = false

  build() {
    Column() {
      RelativeContainer() {
        Web({
          src: this.getWebSrc(),
          controller: this.controller
        })
          .id("Video")
          .width('100%')
          .height('100%')

        if (this.isRecording)
          RedRound()
            .id("RedRound")
            .zIndex(2)
            .alignRules({
              bottom: { anchor: "__container__", align: VerticalAlign.Bottom },
              right: { anchor: "__container__", align: HorizontalAlign.End }
            })
            .offset({
              x: -30,
              y: -30
            })
      }
      .width(this.videoWidth)
      .height(this.videoHeight)
      .backgroundColor(Color.Black)
      .borderRadius('18vp')

      if (this.showControls) {
        Row({ space: '12vp' }) {
          if (!this.isRecording) {
            Button("拍摄")
              .backgroundColor('#2563eb')
              .fontColor('#ffffff')
              .shadow(ButtonShadow)
              .onClick(() => {
                carApi.send(CarEncode.TakePhotosEncode());
              })
          }

          Button(this.isRecording ? "结束" : "录制")
            .backgroundColor(this.isRecording ? '#dc2626' : '#10b981')
            .fontColor('#ffffff')
            .shadow(ButtonShadow)
            .onClick(() => {
              if (this.isRecording) {
                carApi.send(CarEncode.CloselRecordingEncode());
              } else {
                carApi.send(CarEncode.StartRecordingEncode());
              }
              this.isRecording = !this.isRecording;
            })
        }
        .padding({ top: '12vp' })
      }
    }
    .justifyContent(FlexAlign.Center)
  }

  getWebSrc() {
    let v = `http://${VideoComponents.ip}:${VideoComponents.port}/index2`
    console.log(TAG, "getWebSrc()", v)
    return v
  }
}

@Component
struct RedRound {
  @State isShow: boolean = true;

  aboutToAppear(): void {
    setInterval(() => {
      this.isShow = !this.isShow;
    }, 1000);
  }

  build() {
    Text()
      .width('10vp')
      .height('10vp')
      .backgroundColor(Color.Red)
      .animation({
        duration: 1200,
        curve: Curve.Friction,
        delay: 500,
        iterations: -1,
      })
      .border({
        radius: "5vp"
      })
      .visibility(this.isShow ? Visibility.Visible : Visibility.None)
  }
}
