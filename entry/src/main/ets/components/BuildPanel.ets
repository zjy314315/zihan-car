/**
 * 建图流程控制面板
 * 开始建图 → 记录航点 → 结束保存
 */
import HttpApi from '../utils/HttpApi';
import promptAction from '@ohos.promptAction';

@Component
export struct BuildPanel {
  @Link statusText: string;
  @Link mapListRefresh: number; // 用于触发父组件刷新地图列表
  @State isBuilding: boolean = false;
  @State waypointIndex: number = 0;
  @State mapName: string = '';

  build() {
    Column({ space: '6vp' }) {
      Text('建图').fontSize('11fp').fontWeight(FontWeight.Medium).fontColor('#999999').width('100%')

      Row({ space: '4vp' }) {
        Button(this.isBuilding ? '建图中…' : '开始建图')
          .layoutWeight(1).fontSize('11fp').height('34vp')
          .fontColor('#ffffff').backgroundColor(this.isBuilding ? '#9e9ea0' : '#2563eb')
          .borderRadius('8vp')
          .enabled(!this.isBuilding)
          .onClick(() => { this.doBuildStart(); })

        Button(`记录航点: ${this.waypointIndex}`)
          .layoutWeight(1).fontSize('11fp').height('34vp')
          .fontColor('#ffffff').backgroundColor(this.isBuilding ? '#059669' : '#9e9ea0')
          .borderRadius('8vp')
          .enabled(this.isBuilding)
          .onClick(() => { this.doRecordWaypoint(); })
      }.width('100%')

      Row({ space: '4vp' }) {
        TextInput({ placeholder: '地图名', text: this.mapName })
          .layoutWeight(1).fontSize('11fp').height('34vp')
          .borderRadius('8vp').backgroundColor('#f1f1f1')
          .onChange((v: string) => { this.mapName = v; })

        Button('结束保存')
          .layoutWeight(1).fontSize('11fp').height('34vp')
          .fontColor('#ffffff').backgroundColor(this.isBuilding ? '#dc2626' : '#9e9ea0')
          .borderRadius('8vp')
          .enabled(this.isBuilding)
          .onClick(() => { this.doBuildEnd(); })
      }.width('100%')
    }
    .width('100%').padding('8vp').backgroundColor('#fafafa').borderRadius('10vp')
    .border({ width: '1vp', color: '#e5e5e5' })
  }

  private async doBuildStart(): Promise<void> {
    try {
      const r = await HttpApi.getInstance().buildStart();
      if (r.status === 'building') {
        this.isBuilding = true;
        this.waypointIndex = 0;
        this.statusText = '建图中…原点已记录';
        promptAction.showToast({ message: '建图开始', duration: 1500 });
      } else {
        promptAction.showToast({ message: `失败: ${r.error}`, duration: 2000 });
      }
    } catch (e) {
      promptAction.showToast({ message: '开始建图失败', duration: 2000 });
    }
  }

  private async doRecordWaypoint(): Promise<void> {
    const name = `${this.waypointIndex}`;
    try {
      await HttpApi.getInstance().buildWaypoint(name);
      this.waypointIndex++;
      this.statusText = `航点 ${name} 已记录`;
      promptAction.showToast({ message: `航点 ${name} 已记录`, duration: 1000 });
    } catch (e) {
      promptAction.showToast({ message: '记录失败', duration: 2000 });
    }
  }

  private async doBuildEnd(): Promise<void> {
    const name = this.mapName || '未命名地图';
    try {
      const r = await HttpApi.getInstance().buildEnd(name);
      if (r.status === 'saved') {
        this.isBuilding = false;
        this.statusText = `地图 ${name} 已保存`;
        this.mapListRefresh++;
        promptAction.showToast({ message: `${name} 已保存`, duration: 2000 });
      }
    } catch (e) {
      promptAction.showToast({ message: '保存失败', duration: 2000 });
    }
  }
}
