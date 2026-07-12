import router from '@ohos.router';
import { carApi } from '../CarUtill/CarApi';
import { CarEncode } from '../CarUtill/CarEncode';
import { CarRockerComponents } from '../components/CarRockerComponents';
import { ButtonShadow } from '../styles/styles';

const TAG = 'SmartCarMecanumWheel'

@Entry
@Component
struct MecanumWheel {
  @State L1Value: number = 0;
  @State L2Value: number = 0;
  @State R1Value: number = 0;
  @State R2Value: number = 0;

  build() {
    Column({ space: '14vp' }) {
      Row() {
        Button('返回')
          .backgroundColor('#111827')
          .fontColor('#ffffff')
          .borderRadius('14vp')
          .shadow(ButtonShadow)
          .onClick(() => { router.back(); })
          .padding({ left: '16vp', right: '16vp', top: '12vp', bottom: '12vp' })
      }
      .width('100%')
      .padding({ top: '24vp', left: '16vp', right: '16vp', bottom: '4vp' })

      Scroll() {
        Column({ space: '14vp' }) {
          Column({ space: '12vp' }) {
            Text('轮速调节')
              .fontSize('16fp')
              .fontWeight(FontWeight.Bold)
              .fontColor('#111827')

            Column({ space: '10vp' }) {
              WheelSlider({ title: '左前轮', value: $L1Value })
              WheelSlider({ title: '左后轮', value: $L2Value })
              WheelSlider({ title: '右前轮', value: $R1Value })
              WheelSlider({ title: '右后轮', value: $R2Value })
            }
          }
          .padding('14vp')
          .backgroundColor('#f8fafc')
          .borderRadius('24vp')
          .border({ width: '1vp', color: '#e2e8f0' })

          Column({ space: '10vp' }) {
            Text('摇杆控制')
              .fontSize('16fp')
              .fontWeight(FontWeight.Bold)
              .fontColor('#111827')
            CarRockerComponents()
              .width('100%')
              .height('240vp')
          }
          .padding('14vp')
          .backgroundColor('#ffffff')
          .borderRadius('24vp')
          .border({ width: '1vp', color: '#e2e8f0' })

          Column({ space: '10vp' }) {
            Text('当前轮速')
              .fontSize('16fp')
              .fontWeight(FontWeight.Bold)
              .fontColor('#111827')
            Grid() {
              GridItem() {
                InfoCard({ title: '左前', value: `${this.L1Value.toFixed(0)}` })
              }
              GridItem() {
                InfoCard({ title: '左后', value: `${this.L2Value.toFixed(0)}` })
              }
              GridItem() {
                InfoCard({ title: '右前', value: `${this.R1Value.toFixed(0)}` })
              }
              GridItem() {
                InfoCard({ title: '右后', value: `${this.R2Value.toFixed(0)}` })
              }
            }
            .columnsTemplate('1fr 1fr')
            .rowsTemplate('1fr 1fr')
            .columnsGap('10vp')
            .rowsGap('10vp')
          }
          .padding('14vp')
          .backgroundColor('#f8fafc')
          .borderRadius('24vp')
          .border({ width: '1vp', color: '#e2e8f0' })

          Row({ space: '10vp' }) {
            Button('更新速度')
              .layoutWeight(1)
              .backgroundColor('#2563eb')
              .fontColor('#ffffff')
              .shadow(ButtonShadow)
              .borderRadius('18vp')
              .padding({ top: '12vp', bottom: '12vp' })
              .onClick(() => { this.sendSpeed(); })
            Button('全部归零')
              .layoutWeight(1)
              .backgroundColor('#f1f5f9')
              .fontColor('#111827')
              .shadow(ButtonShadow)
              .borderRadius('18vp')
              .padding({ top: '12vp', bottom: '12vp' })
              .onClick(() => {
                this.L1Value = 0;
                this.L2Value = 0;
                this.R1Value = 0;
                this.R2Value = 0;
                this.sendSpeed();
              })
          }
        }
        .padding({ left: '16vp', right: '16vp', bottom: '20vp' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#ffffff')
  }

  sendSpeed() {
    console.log(TAG, 'speed', `l1`, this.L1Value, 'l2', this.L2Value, 'r1', this.R1Value, 'r2', this.R2Value);
    carApi.send(CarEncode.UpSpeedCarEncode(this.L1Value, this.L2Value, this.R1Value, this.R2Value));
  }
}

@Component
struct WheelSlider {
  @Prop title: string = '';
  @Link value: number;

  build() {
    Column({ space: '10vp' }) {
      Row() {
        Text(this.title)
          .fontSize('16fp')
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')
        Blank().layoutWeight(1)
        Text(`${this.value.toFixed(0)}`)
          .fontSize('16fp')
          .fontColor('#2563eb')
      }

      Slider({
        value: this.value,
        min: -100,
        max: 100,
        style: SliderStyle.InSet
      })
        .blockColor('#2563eb')
        .trackColor('#e2e8f0')
        .selectedColor('#2563eb')
        .onChange((value: number, mode: SliderChangeMode) => {
          this.value = value;
          console.info('value:' + value + ' mode:' + mode.toString());
        })
    }
    .padding('14vp')
    .backgroundColor('#ffffff')
    .borderRadius('20vp')
    .border({ width: '1vp', color: '#e2e8f0' })
  }
}

@Component
struct InfoCard {
  @Prop title: string = '';
  @Prop value: string = '';

  build() {
    Column({ space: '8vp' }) {
      Text(this.title)
        .fontSize('14fp')
        .fontColor('#475569')
      Text(this.value)
        .fontSize('20fp')
        .fontWeight(FontWeight.Bold)
        .fontColor('#111827')
    }
    .padding({ left: '16vp', right: '16vp', top: '14vp', bottom: '14vp' })
    .backgroundColor('#ffffff')
    .borderRadius('20vp')
    .border({ width: '1vp', color: '#e2e8f0' })
    .width('0vp')
    .layoutWeight(1)
  }
}
