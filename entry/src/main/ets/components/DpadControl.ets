/**
 * 9 键方向板组件
 * 通过 HTTP /api/map/control 发送遥控指令
 */
import HttpApi from '../utils/HttpApi';

@Component
export struct DpadControl {
  @Prop speed: number = 30;
  @Link statusText: string;
  private timer: number = -1;
  private readonly MOVE_INTERVAL: number = 150;

  build() {
    Column({ space: '4vp' }) {
      Text('操控').fontSize('11fp').fontWeight(FontWeight.Medium).fontColor('#999999').width('100%')

      // 第 1 行
      Row({ space: '4vp' }) {
        this.dpadBtn('↖', () => this.startMove(1, 0, 1))
        this.dpadBtn('↑', () => this.startMove(1, 0, 0))
        this.dpadBtn('↗', () => this.startMove(1, 0, -1))
      }.width('100%').justifyContent(FlexAlign.Center)

      // 第 2 行
      Row({ space: '4vp' }) {
        this.dpadBtn('←', () => this.startMove(0, 1, 0))
        this.dpadBtn('⏹', () => this.stopMove(), '#dc2626')
        this.dpadBtn('→', () => this.startMove(0, -1, 0))
      }.width('100%').justifyContent(FlexAlign.Center)

      // 第 3 行
      Row({ space: '4vp' }) {
        this.dpadBtn('↙', () => this.startMove(-1, 0, 1))
        this.dpadBtn('↓', () => this.startMove(-1, 0, 0))
        this.dpadBtn('↘', () => this.startMove(-1, 0, -1))
      }.width('100%').justifyContent(FlexAlign.Center)
    }
    .width('100%').padding('8vp').backgroundColor('#fafafa').borderRadius('10vp')
    .border({ width: '1vp', color: '#e5e5e5' })
  }

  @Builder dpadBtn(label: string, onDown: () => void, color?: string) {
    Button(label)
      .width('44vp').height('44vp')
      .fontSize('16fp').fontColor('#ffffff')
      .backgroundColor(color ?? '#2563eb')
      .borderRadius('10vp')
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          onDown();
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.stopMove();
        }
      })
  }

  private startMove(vxDir: number, vyDir: number, vzDir: number): void {
    this.sendMove(vxDir * this.speed, vyDir * this.speed, vzDir * this.speed);
    this.timer = setInterval(() => {
      this.sendMove(vxDir * this.speed, vyDir * this.speed, vzDir * this.speed);
    }, this.MOVE_INTERVAL);
  }

  private stopMove(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    this.sendMove(0, 0, 0);
  }

  private async sendMove(vx: number, vy: number, vz: number): Promise<void> {
    try {
      await HttpApi.getInstance().carControl(vx, vy, vz);
      this.statusText = vx === 0 && vy === 0 && vz === 0 ? '已停止' : `移动中 vx:${vx} vy:${vy} vz:${vz}`;
    } catch (e) {
      this.statusText = '控制失败';
    }
  }
}
