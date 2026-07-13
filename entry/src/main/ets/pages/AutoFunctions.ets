import router from '@ohos.router';
import { carApi } from '../CarUtill/CarApi';
import { CarEncode } from '../CarUtill/CarEncode';

@Entry
@Component
struct AutoFunctions {
  @State isLineFollowing: boolean = false;
  @State isObstacleAvoidance: boolean = false;
  @State statusText: string = '就绪';

  build() {
    Column({ space: '16vp' }) {
      // 顶部导航栏
      Row({ space: '8vp' }) {
        Button('← 返回')
          .fontSize('12fp').fontColor('#ffffff').backgroundColor('#1a1a1a')
          .borderRadius('6vp').padding({ left: '10vp', right: '10vp', top: '6vp', bottom: '6vp' })
          .onClick(() => { router.back(); })
        Text('基础功能').fontSize('15fp').fontWeight(FontWeight.Bold).fontColor('#111111')
        Blank()
        Text(this.statusText).fontSize('10fp').fontColor('#999999').maxLines(1)
      }
      .width('100%').padding({ left: '10vp', right: '10vp', top: '8vp', bottom: '6vp' })

      // 功能卡片
      Column({ space: '14vp' }) {
        // 跟随导航
        Column() {
          Row({ space: '12vp' }) {
            Column() {
              Text('跟随导航').fontSize('14fp').fontWeight(FontWeight.Bold).fontColor('#111111')
              Text('自动跟踪引导线行驶').fontSize('10fp').fontColor('#999999').margin({ top: '2vp' })
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.isLineFollowing })
              .onChange((val: boolean) => {
                this.isLineFollowing = val;
                this.statusText = val ? '跟随导航已开启' : '跟随导航已关闭';
              })
          }.width('100%').padding('12vp')
        }
        .width('100%').backgroundColor('#f8f8f8').borderRadius('10vp')
        .border({ width: '1vp', color: '#e5e5e5' })

        // 自动避障
        Column() {
          Row({ space: '12vp' }) {
            Column() {
              Text('自动避障').fontSize('14fp').fontWeight(FontWeight.Bold).fontColor('#111111')
              Text('智能检测并绕开障碍物').fontSize('10fp').fontColor('#999999').margin({ top: '2vp' })
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.isObstacleAvoidance })
              .onChange((val: boolean) => {
                this.isObstacleAvoidance = val;
                this.statusText = val ? '自动避障已开启' : '自动避障已关闭';
              })
          }.width('100%').padding('12vp')
        }
        .width('100%').backgroundColor('#f8f8f8').borderRadius('10vp')
        .border({ width: '1vp', color: '#e5e5e5' })

        // 说明
        Text('提示：开启跟随导航后，小车将自动沿引导线行驶；开启自动避障后，系统将实时检测并规避障碍物。')
          .fontSize('10fp').fontColor('#b0b0b0').width('100%').lineHeight('16vp')
      }.width('100%').padding('12vp')
    }
    .width('100%').height('100%').backgroundColor('#ffffff')
  }
}
