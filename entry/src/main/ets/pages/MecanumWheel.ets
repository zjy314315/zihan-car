import router from '@ohos.router';
import { carApi } from '../CarUtill/CarApi';
import { CarEncode } from '../CarUtill/CarEncode';
import { CarRockerComponents } from '../components/CarRockerComponents';

const TAG = 'SmartCarMecanumWheel'

@Entry
@Component
struct MecanumWheel {
  @State L1Value: number = 0;
  @State L2Value: number = 0;
  @State R1Value: number = 0;
  @State R2Value: number = 0;

  build() {
    Column() {
      // ====== 顶部栏 ======
      Row({ space: '8vp' }) {
        Button('← 返回')
          .fontSize('12fp').fontColor('#ffffff').backgroundColor('#1a1a1a')
          .borderRadius('6vp').padding({ left: '10vp', right: '10vp', top: '6vp', bottom: '6vp' })
          .onClick(() => { router.back(); })
        Text('麦克纳姆轮').fontSize('15fp').fontWeight(FontWeight.Bold).fontColor('#111111')
        Blank()
        Button('归零')
          .fontSize('11fp').fontColor('#999999').backgroundColor('#f1f1f1')
          .borderRadius('6vp').padding({ left: '10vp', right: '10vp', top: '5vp', bottom: '5vp' })
          .onClick(() => { this.L1Value = 0; this.L2Value = 0; this.R1Value = 0; this.R2Value = 0; this.sendSpeed(); })
      }
      .width('100%').padding({ left: '10vp', right: '10vp', top: '8vp', bottom: '6vp' })
      .backgroundColor('#fafafa').border({ width: { bottom: '1vp' }, color: '#e5e5e5' })

      // ====== 主体：左右布局 ======
      Row({ space: '8vp' }) {
        // ---- 左侧：轮速调节 + 当前轮速 + 按钮 ----
        Column({ space: '6vp' }) {
          Text('轮速调节').fontSize('11fp').fontWeight(FontWeight.Medium).fontColor('#999999').width('100%')

          WheelSlider({ label: '左前轮', value: $L1Value })
          WheelSlider({ label: '左后轮', value: $L2Value })
          WheelSlider({ label: '右前轮', value: $R1Value })
          WheelSlider({ label: '右后轮', value: $R2Value })

          // 当前轮速
          Text('当前轮速').fontSize('11fp').fontWeight(FontWeight.Medium).fontColor('#999999').width('100%').margin({ top: '4vp' })
          Row({ space: '4vp' }) {
            SpeedTile({ label: '左前', val: this.L1Value })
            SpeedTile({ label: '右前', val: this.R1Value })
            SpeedTile({ label: '左后', val: this.L2Value })
            SpeedTile({ label: '右后', val: this.R2Value })
          }

          // 按钮
          Row({ space: '6vp' }) {
            Button('更新速度')
              .layoutWeight(1).fontSize('12fp').fontColor('#ffffff').backgroundColor('#1a1a1a')
              .borderRadius('6vp').height('36vp')
              .onClick(() => { this.sendSpeed(); })
            Button('全部归零')
              .layoutWeight(1).fontSize('12fp').fontColor('#666666').backgroundColor('#f1f1f1')
              .borderRadius('6vp').height('36vp')
              .onClick(() => { this.L1Value = 0; this.L2Value = 0; this.R1Value = 0; this.R2Value = 0; this.sendSpeed(); })
          }
        }
        .width('0vp').layoutWeight(5.5)
        .padding('8vp').backgroundColor('#fafafa').borderRadius('12vp')
        .border({ width: '1vp', color: '#e5e5e5' })

        // ---- 右侧：摇杆 ----
        Column({ space: '4vp' }) {
          Text('摇杆操控').fontSize('11fp').fontWeight(FontWeight.Medium).fontColor('#999999').width('100%')
          CarRockerComponents().width('100%').height('100%')
        }
        .width('0vp').layoutWeight(4.5)
        .padding('8vp').backgroundColor('#fafafa').borderRadius('12vp')
        .border({ width: '1vp', color: '#e5e5e5' })
      }
      .width('100%').layoutWeight(1).padding('8vp')
    }
    .width('100%').height('100%').backgroundColor('#ffffff')
  }

  sendSpeed() {
    console.log(TAG, 'speed', this.L1Value, this.L2Value, this.R1Value, this.R2Value);
    carApi.send(CarEncode.UpSpeedCarEncode(this.L1Value, this.L2Value, this.R1Value, this.R2Value));
  }
}

@Component
struct WheelSlider {
  @Prop label: string = '';
  @Link value: number;

  build() {
    Row({ space: '6vp' }) {
      Text(this.label).fontSize('11fp').fontColor('#666666').width('44vp')
      Slider({ value: this.value, min: -100, max: 100, style: SliderStyle.InSet })
        .blockColor('#333333').trackColor('#e5e5e5').selectedColor('#666666')
        .layoutWeight(1).onChange((v: number) => { this.value = v; })
      Text(`${this.value.toFixed(0)}`).fontSize('11fp').fontWeight(FontWeight.Medium)
        .fontColor('#333333').width('32vp').textAlign(TextAlign.End)
    }
    .width('100%').padding({ left: '8vp', right: '8vp', top: '3vp', bottom: '3vp' })
    .backgroundColor('#ffffff').borderRadius('6vp')
  }
}

@Component
struct SpeedTile {
  @Prop label: string = '';
  @Prop val: number = 0;

  build() {
    Column({ space: '2vp' }) {
      Text(`${this.val.toFixed(0)}`).fontSize('16fp').fontWeight(FontWeight.Bold).fontColor('#111111')
      Text(this.label).fontSize('9fp').fontColor('#999999')
    }
    .width('0vp').layoutWeight(1).padding('8vp')
    .backgroundColor('#ffffff').borderRadius('8vp').border({ width: '1vp', color: '#e5e5e5' })
  }
}
