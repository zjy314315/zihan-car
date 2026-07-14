/**
 * 栅格地图 Canvas 组件
 * 绘制栅格地图 + 航点标记 + 小车位姿
 * 支持手势缩放平移
 */
import HttpApi from '../utils/HttpApi';
import { MapInfo, MapWaypoints, MapWaypoint, Pose2D, GridData } from '../utils/HttpApi';
import promptAction from '@ohos.promptAction';

interface SelectOption {
  value: string;
  label: string;
}

interface PinchGestureEvent extends GestureEvent {
  scale: number;
}

@Component
export struct MapCanvas {
  @Link statusText: string;
  @Link selectedMapName: string;
  @Link mapListRefresh: number;
  @State mapList: MapInfo[] = [];
  @State pose: Pose2D = { x: 0, y: 0, yaw: 0 };
  @State waypoints: MapWaypoints | null = null;
  @State gridData: GridData | null = null;
  @State patrolConfirm: boolean = false;
  private confirmTimer: number = -1;
  private gridTimer: number = -1;

  // Canvas 参数
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  @State mapScale: number = 10.0; // px per meter
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  private poseTimer: number = -1;
  private readonly CANVAS_W: number = 600;
  private readonly CANVAS_H: number = 500;

  aboutToAppear(): void {
    this.loadMapList();
    this.startPosePolling();
    this.startGridPolling();
  }

  aboutToDisappear(): void {
    if (this.poseTimer !== -1) clearInterval(this.poseTimer);
    if (this.gridTimer !== -1) clearInterval(this.gridTimer);
  }

  build() {
    Column({ space: '4vp' }) {
      // 顶部选择栏
      Row({ space: '4vp' }) {
        Text('地图').fontSize('11fp').fontColor('#666666')
        Select(this.getSelectOptions())
          .layoutWeight(1).font({ size: '11fp' }).height('32vp')
          .value(this.selectedMapName)
          .onSelect((idx: number) => {
            if (idx > 0 && idx <= this.mapList.length) {
              const m = this.mapList[idx - 1];
              this.selectedMapName = m.name;
              if (m.waypoints) this.waypoints = m.waypoints;
              this.statusText = `已选: ${m.name}`;
            }
          })

        Button(this.patrolConfirm ? '确认巡查?' : '开始巡查')
          .fontSize('10fp').height('32vp')
          .fontColor('#ffffff')
          .backgroundColor(this.patrolConfirm ? '#f59e0b' : (this.selectedMapName ? '#059669' : '#9e9ea0'))
          .borderRadius('6vp')
          .enabled(this.selectedMapName !== '')
          .onClick(() => {
            if (this.patrolConfirm) {
              this.doStartPatrol();
            } else {
              this.patrolConfirm = true;
              this.statusText = '再次点击确认巡查';
              if (this.confirmTimer !== -1) clearTimeout(this.confirmTimer);
              this.confirmTimer = setTimeout(() => {
                this.patrolConfirm = false;
                this.statusText = '确认已取消';
              }, 5000);
            }
          })
      }.width('100%').padding('6vp')

      // Canvas 地图
      Stack() {
        // 默认背景图：无栅格数据时显示
        Image($rawfile('yahboomcar.png'))
          .width('100%').height('100%')
          .objectFit(ImageFit.Contain)
          .visibility(this.gridData && this.gridData.data && this.gridData.data.length > 0 ? Visibility.Hidden : Visibility.Visible)

        Canvas(this.ctx)
          .width('100%').height('100%')
          .backgroundColor('#1a1a2e')
          .onReady(() => { this.drawMap(); })
          .gesture(
            GestureGroup(GestureMode.Parallel,
              PinchGesture().onActionUpdate((e: GestureEvent) => {
                this.mapScale = Math.max(2, Math.min(50, this.mapScale * (e as PinchGestureEvent).scale));
                this.drawMap();
              }),
              PanGesture({ fingers: 1, distance: 5 })
                .onActionUpdate((e: GestureEvent) => {
                  this.offsetX += (e as PanGestureEvent).offsetX;
                  this.offsetY += (e as PanGestureEvent).offsetY;
                  this.drawMap();
                })
            )
          )
      }
      .width('100%').layoutWeight(1).borderRadius('8vp').clip(true)

      // 底部信息栏
      Row({ space: '8vp' }) {
        Text(`(${this.pose.x.toFixed(2)}, ${this.pose.y.toFixed(2)})`).fontSize('10fp').fontColor('#999')
        Text(`${this.pose.yaw.toFixed(0)}°`).fontSize('10fp').fontColor('#999')
        Blank()
        Text(`1m = ${this.mapScale.toFixed(0)}px`).fontSize('10fp').fontColor('#999')
        Button('🔄').fontSize('10fp').height('24vp').width('24vp').backgroundColor('#f1f1f1')
          .borderRadius('4vp').onClick(() => { this.resetView(); })
      }.width('100%').padding('4vp')
    }
    .width('100%').height('100%').backgroundColor('#fafafa').borderRadius('10vp')
    .border({ width: '1vp', color: '#e5e5e5' })
  }

  // ========== 绘制 ==========

  private drawMap(): void {
    const ctx = this.ctx;
    const w = ctx.width;
    const h = ctx.height;

    // Draw SLAM grid map background if available
    if (this.gridData && this.gridData.data && this.gridData.data.length > 0) {
      const gw = this.gridData.width;
      const gh = this.gridData.height;
      const imgData = ctx.createImageData(gw, gh);
      for (let i = 0; i < this.gridData.data.length; i++) {
        const v = this.gridData.data[i];
        const idx = i * 4;
        if (v === -1) {
          imgData.data[idx] = 30; imgData.data[idx+1] = 30; imgData.data[idx+2] = 50; imgData.data[idx+3] = 255;
        } else if (v === 0) {
          imgData.data[idx] = 220; imgData.data[idx+1] = 220; imgData.data[idx+2] = 230; imgData.data[idx+3] = 255;
        } else {
          const c = 255 - Math.min(255, v * 2);
          imgData.data[idx] = c; imgData.data[idx+1] = c; imgData.data[idx+2] = c; imgData.data[idx+3] = 255;
        }
      }
      // Render grid at native resolution at top-left
      ctx.putImageData(imgData, 0, 0);
    }

    // Guide grid lines
    ctx.strokeStyle = '#2a2a4a';
    ctx.lineWidth = 0.5;
    const gridSpacing = this.mapScale * 0.5;
    for (let x = this.offsetX % gridSpacing; x < w; x += gridSpacing) {
      ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, h); ctx.stroke();
    }
    for (let y = this.offsetY % gridSpacing; y < h; y += gridSpacing) {
      ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke();
    }

    // 原点十字
    const ox = w / 2 + this.offsetX;
    const oy = h / 2 + this.offsetY;
    ctx.strokeStyle = '#4a4a6a';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(ox, 0); ctx.lineTo(ox, h); ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(0, oy); ctx.lineTo(w, oy); ctx.stroke();

    // 航点标记
    if (this.waypoints) {
      const allPts: MapWaypoint[] = [this.waypoints.origin].concat(this.waypoints.waypoints);
      for (let i = 0; i < allPts.length; i++) {
        const pt = allPts[i];
        const px = ox + pt.x * this.mapScale;
        const py = oy - pt.y * this.mapScale;

        // 连线
        if (i > 0) {
          const prev = allPts[i - 1];
          const px0 = ox + prev.x * this.mapScale;
          const py0 = oy - prev.y * this.mapScale;
          ctx.strokeStyle = '#818cf8';
          ctx.lineWidth = 1;
          ctx.setLineDash([4, 4]);
          ctx.beginPath();
          ctx.moveTo(px0, py0);
          ctx.lineTo(px, py);
          ctx.stroke();
          ctx.setLineDash([]);
        }

        // 圆点
        ctx.fillStyle = i === 0 ? '#38bdf8' : '#f59e0b';
        ctx.beginPath();
        ctx.arc(px, py, 5, 0, 2 * Math.PI);
        ctx.fill();

        // 标签
        ctx.fillStyle = '#ffffff';
        ctx.font = '10px sans-serif';
        ctx.fillText(pt.name, px + 8, py - 4);
      }
    }

    // 小车位姿（三角形箭头）
    const carX = ox + this.pose.x * this.mapScale;
    const carY = oy - this.pose.y * this.mapScale;
    const yawRad = this.pose.yaw * Math.PI / 180;
    const size = 8;
    ctx.fillStyle = '#ef4444';
    ctx.beginPath();
    ctx.moveTo(carX + size * Math.cos(yawRad), carY - size * Math.sin(yawRad));
    ctx.lineTo(carX + size * 0.5 * Math.cos(yawRad + 2.5), carY - size * 0.5 * Math.sin(yawRad + 2.5));
    ctx.lineTo(carX + size * 0.5 * Math.cos(yawRad - 2.5), carY - size * 0.5 * Math.sin(yawRad - 2.5));
    ctx.closePath();
    ctx.fill();
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 1;
    ctx.stroke();
  }

  // ========== 数据 ==========

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

  private startPosePolling(): void {
    this.poseTimer = setInterval(async () => {
      try {
        const p = await HttpApi.getInstance().getPose();
        if (p.x !== undefined) {
          this.pose = { x: p.x, y: p.y, yaw: p.yaw };
          this.drawMap();
        }
      } catch (e) {
        // ignore
      }
    }, 500);
  }

  private startGridPolling(): void {
    this.loadGridData();
    this.gridTimer = setInterval(() => { this.loadGridData(); }, 2000);
  }

  private async loadGridData(): Promise<void> {
    try {
      const d = await HttpApi.getInstance().getGridData();
      if (d && d.data) {
        this.gridData = d;
        this.drawMap();
      }
    } catch (e) {
      // ignore
    }
  }

  private resetView(): void {
    this.mapScale = 10;
    this.offsetX = 0;
    this.offsetY = 0;
    this.drawMap();
  }

  private async doStartPatrol(): Promise<void> {
    try {
      const r = await HttpApi.getInstance().startMapNavigate(this.selectedMapName);
      if (r.status === 'navigating') {
        this.statusText = `巡查中: ${this.selectedMapName}`;
        promptAction.showToast({ message: '巡查开始', duration: 1500 });
      }
    } catch (e) {
      promptAction.showToast({ message: '巡查启动失败', duration: 2000 });
    }
  }
}
