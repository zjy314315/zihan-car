/**
 * 导航控制面板
 * 选择地图 → 开始导航 → 急停
 */
import HttpApi from '../utils/HttpApi';
import { MapInfo } from '../utils/HttpApi';
import promptAction from '@ohos.promptAction';

interface SelectOption {
  value: string;
  label: string;
}

@Component
export struct NavPanel {
  @Link statusText: string;
  @Prop selectedMap: string;
  @Link selectedMapName: string;
  @State mapList: MapInfo[] = [];
  @State isNavigating: boolean = false;
  @State patrolConfirm: boolean = false;
  @Link mapListRefresh: number;
  private confirmTimer: number = -1;

  aboutToAppear(): void { this.loadMapList(); }
  onPageShow(): void { this.loadMapList(); }

  build() {
    Column({ space: '6vp' }) {
      Text('导航').fontSize('11fp').fontWeight(FontWeight.Medium).fontColor('#999999').width('100%')

      Row({ space: '4vp' }) {
        Text('地图').fontSize('11fp').fontColor('#666666')
        Select(this.getSelectOptions())
          .layoutWeight(1).font({ size: '11fp' }).height('34vp')
          .value(this.selectedMapName)
          .onSelect((idx: number) => {
            if (idx > 0 && idx <= this.mapList.length) {
              this.selectedMapName = this.mapList[idx - 1].name;
            }
          })
      }.width('100%')

      Row({ space: '4vp' }) {
        Button(this.patrolConfirm ? '确认巡查?' : '开始巡查')
          .layoutWeight(1).fontSize('11fp').height('34vp')
          .fontColor('#ffffff')
          .backgroundColor(this.patrolConfirm ? '#f59e0b' : (this.selectedMapName ? '#059669' : '#9e9ea0'))
          .borderRadius('8vp')
          .enabled(this.selectedMapName !== '')
          .onClick(() => {
            if (this.patrolConfirm) {
              this.doStartPatrol();
            } else {
              this.setConfirm();
            }
          })

        Button(this.isNavigating ? '急停 ⏹' : '急停')
          .layoutWeight(1).fontSize('11fp').height('34vp')
          .fontColor('#ffffff').backgroundColor('#dc2626')
          .borderRadius('8vp')
          .onClick(() => { this.doStop(); })
      }.width('100%')
    }
    .width('100%').padding('8vp').backgroundColor('#fafafa').borderRadius('10vp')
    .border({ width: '1vp', color: '#e5e5e5' })
  }

  private getSelectOptions(): SelectOption[] {
    const defaultOption: SelectOption = { value: '', label: '请选择' };
    const mapOptions: SelectOption[] = this.mapList.map((m: MapInfo): SelectOption => {
      return { value: m.name, label: m.name };
    });
    return [defaultOption].concat(mapOptions);
  }

  private async loadMapList(): Promise<void> {
    try {
      this.mapList = await HttpApi.getInstance().getMapList();
    } catch (e) {
      // ignore
    }
  }

  private setConfirm(): void {
    this.patrolConfirm = true;
    this.statusText = '再次点击确认巡查';
    // 5 秒后自动取消确认状态
    if (this.confirmTimer !== -1) clearTimeout(this.confirmTimer);
    this.confirmTimer = setTimeout(() => {
      this.patrolConfirm = false;
      this.statusText = '确认已取消';
    }, 5000);
  }

  private async doStartPatrol(): Promise<void> {
    this.patrolConfirm = false;
    if (this.confirmTimer !== -1) { clearTimeout(this.confirmTimer); this.confirmTimer = -1; }
    if (!this.selectedMapName) return;
    try {
      const r = await HttpApi.getInstance().startMapNavigate(this.selectedMapName);
      if (r.status === 'navigating') {
        this.isNavigating = true;
        this.statusText = `巡查中: ${this.selectedMapName}`;
        promptAction.showToast({ message: `${this.selectedMapName} 巡查开始`, duration: 1500 });
      }
    } catch (e) {
      promptAction.showToast({ message: '巡查启动失败', duration: 2000 });
    }
  }

  private async doStop(): Promise<void> {
    try {
      await HttpApi.getInstance().stopMapNavigate();
      await HttpApi.getInstance().carControl(0, 0, 0);
      this.isNavigating = false;
      this.statusText = '已急停';
      promptAction.showToast({ message: '已急停', duration: 1500 });
    } catch (e) {
      promptAction.showToast({ message: '急停失败', duration: 2000 });
    }
  }
}
