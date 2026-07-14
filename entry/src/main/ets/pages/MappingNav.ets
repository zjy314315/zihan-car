/**
 * 建图导航页面
 * 左栏: 栅格地图 Canvas  |  右栏: D-pad + 建图 + 导航
 */
import router from '@ohos.router';
import { DpadControl } from '../components/DpadControl';
import { BuildPanel } from '../components/BuildPanel';
import { NavPanel } from '../components/NavPanel';
import { MapCanvas } from '../components/MapCanvas';
import HttpApi from '../utils/HttpApi';
import promptAction from '@ohos.promptAction';

@Entry
@Component
struct MappingNav {
  @State speed: number = 30;
  @State statusText: string = '就绪';
  @State selectedMapName: string = '';
  @State mapListRefresh: number = 0;

  aboutToAppear(): void {
    // 锁定横屏
    // window.getLastWindow().then(w => w.setPreferredOrientation(window.Orientation.LANDSCAPE));
  }

  aboutToDisappear(): void {
    // window.getLastWindow().then(w => w.setPreferredOrientation(window.Orientation.AUTO_ROTATION));
  }

  build() {
    Column() {
      // ====== 顶栏 ======
      Row({ space: '8vp' }) {
        Button('← 返回')
          .fontSize('12fp').fontColor('#ffffff').backgroundColor('#1a1a1a')
          .borderRadius('6vp').padding({ left: '10vp', right: '10vp', top: '6vp', bottom: '6vp' })
          .onClick(() => { router.back(); })
        Text('建图导航').fontSize('15fp').fontWeight(FontWeight.Bold).fontColor('#111111')
        Blank()
        Text(this.carStatusText()).fontSize('10fp').fontColor('#999999').maxLines(1)
      }
      .width('100%').padding({ left: '10vp', right: '10vp', top: '8vp', bottom: '6vp' })
      .backgroundColor('#fafafa').border({ width: { bottom: '1vp' }, color: '#e5e5e5' })

      // ====== 主体：左右分栏 ======
      Row({ space: '6vp' }) {
        // ---- 左栏：地图 ----
        MapCanvas({
          statusText: $statusText,
          selectedMapName: $selectedMapName,
          mapListRefresh: $mapListRefresh
        })
          .width('0vp').layoutWeight(6).height('100%')

        // ---- 右栏：操控 + 建图 + 导航 ----
        Scroll() {
          Column({ space: '8vp' }) {
            // 位姿
            this.poseDisplay()

            // 速度
            Row({ space: '6vp' }) {
              Text('速度').fontSize('11fp').fontColor('#666666')
              Slider({ value: this.speed, min: 10, max: 100, step: 5 })
                .layoutWeight(1).height('24vp')
                .onChange((v: number) => { this.speed = v; })
              Text(`${this.speed}`).fontSize('12fp').fontWeight(FontWeight.Bold).fontColor('#2563eb').width('30vp')
            }
            .width('100%').padding({ left: '6vp', right: '6vp' })

            // 急停
            Button('⏹ 急停')
              .width('100%').height('36vp')
              .fontSize('15fp').fontWeight(FontWeight.Bold).fontColor('#ffffff')
              .backgroundColor('#dc2626').borderRadius('8vp')
              .onClick(() => { this.doEmergencyStop(); })

            // D-pad 操控
            DpadControl({ speed: this.speed, statusText: $statusText })

            // 建图面板
            BuildPanel({ statusText: $statusText, mapListRefresh: $mapListRefresh })

            // 导航面板
            NavPanel({ statusText: $statusText, selectedMap: this.selectedMapName,
              selectedMapName: $selectedMapName, mapListRefresh: $mapListRefresh })
          }
          .width('100%').padding('4vp')
        }
        .width('0vp').layoutWeight(4).scrollBar(BarState.Auto).height('100%')
      }
      .layoutWeight(1).width('100%').padding('6vp')

      // ====== 底栏 ======
      Row({ space: '8vp' }) {
        Text(this.statusText).fontSize('11fp').fontColor('#666666').maxLines(1)
        Blank()
        Text(`地图: ${this.selectedMapName || '未选择'}`).fontSize('10fp').fontColor('#999999').maxLines(1)
      }
      .width('100%').padding({ left: '10vp', right: '10vp', top: '6vp', bottom: '6vp' })
      .backgroundColor('#fafafa').border({ width: { top: '1vp' }, color: '#e5e5e5' })
    }
    .width('100%').height('100%').backgroundColor('#ffffff')
  }

  @Builder poseDisplay() {
    Text('等待位姿数据…').fontSize('10fp').fontColor('#999999').width('100%')
      .padding({ left: '6vp', right: '6vp', top: '4vp', bottom: '4vp' })
  }

  private carStatusText(): string {
    return '就绪';
  }

  private async doEmergencyStop(): Promise<void> {
    try {
      await HttpApi.getInstance().stopMapNavigate();
    } catch (_) {}
    try {
      await HttpApi.getInstance().carControl(0, 0, 0);
    } catch (_) {}
    this.statusText = '已急停';
    promptAction.showToast({ message: '⏹ 已急停', duration: 1500 });
  }
}
