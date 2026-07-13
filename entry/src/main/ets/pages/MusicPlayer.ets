import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { carApi } from '../CarUtill/CarApi';
import { CarEncode } from '../CarUtill/CarEncode';
import { TCPClientManager } from '../tcp/TCPClientManager';
import { PreferencesUtils } from '../utils/PreferencesUtils';

interface Track { name: string; artist: string; }

@Entry
@Component
struct MusicPlayer {
  @State isConnected: boolean = false;
  @State connLabel: string = '未连接';
  @State carIp: string = '';
  @State volume: number = 50;
  @State isPlaying: boolean = false;
  @State currentTrack: number = 0;
  @State currentTime: string = '00:00';
  private playTimer: number = -1;
  private beepTimer: number = -1;
  private elapsed: number = 0;
  @State danceMode: boolean = false;
  @State bpm: number = 120;
  private danceTimer: number = -1;
  private danceStopTimer: number = -1;
  private danceStep: number = 0;

  tracks: Track[] = [
    { name: '滴滴提醒', artist: '蜂鸣器' },  { name: '警报音效', artist: '蜂鸣器' },
    { name: '倒车提示', artist: '蜂鸣器' },  { name: '欢快节奏', artist: '蜂鸣器' },
    { name: '长鸣警告', artist: '蜂鸣器' },  { name: '短促三声', artist: '蜂鸣器' },
    { name: '间隔蜂鸣', artist: '蜂鸣器' },  { name: '连续滴滴', artist: '蜂鸣器' },
  ];
  beepPatterns: number[][] = [
    [200, 200, 6], [500, 100, 4], [300, 800, 3], [150, 100, 8],
    [2000, 0, 1],  [100, 150, 3], [400, 600, 5], [100, 100, 10],
  ];

  aboutToAppear(): void { this.checkStatus(); }
  aboutToDisappear(): void { this.stopDance(); this.stopBeep(); }

  async checkStatus(): Promise<void> {
    this.isConnected = await TCPClientManager.getInstance().isConnect();
    if (this.isConnected) {
      this.carIp = await PreferencesUtils.getInstance().netUtils.getIP() as string;
      this.connLabel = `已连接 ${this.carIp}`;
    } else { this.connLabel = '未连接 · 请配置网络'; }
  }

  build() {
    Column() {
      // ====== 顶部栏 ======
      Row({ space: '8vp' }) {
        Button('← 返回')
          .fontSize('12fp').fontColor('#ffffff').backgroundColor('#1a1a1a')
          .borderRadius('6vp').padding({ left: '10vp', right: '10vp', top: '6vp', bottom: '6vp' })
          .onClick(() => { this.stopBeep(); router.back(); })
        Text('音乐播放').fontSize('15fp').fontWeight(FontWeight.Bold).fontColor('#111111')
        Blank()
        Circle({ width: '7vp', height: '7vp' }).fill(this.isConnected ? '#22c55e' : '#999999')
        Text(this.connLabel).fontSize('11fp').fontColor(this.isConnected ? '#333333' : '#999999')
      }
      .width('100%').padding({ left: '10vp', right: '10vp', top: '8vp', bottom: '6vp' })
      .backgroundColor('#fafafa').border({ width: { bottom: '1vp' }, color: '#e5e5e5' })

      // ====== 主体 ======
      Row({ space: '8vp' }) {
        // ---- 左侧：播放器 ----
        Column({ space: '10vp' }) {
          // 封面
          Stack() {
            Column({ space: '4vp' }) {
              Text(this.tracks[this.currentTrack].name).fontSize('22fp').fontWeight(FontWeight.Bold).fontColor('#ffffff')
              Text(this.tracks[this.currentTrack].artist).fontSize('12fp').fontColor('#999999')
            }
            .width('100%').height('100%').justifyContent(FlexAlign.Center)
            .backgroundColor('#1a1a1a').borderRadius('14vp')

            if (this.isPlaying) {
              Row({ space: '3vp' }) {
                Column().width('3vp').height('16vp').backgroundColor('#555555').borderRadius('2vp')
                Column().width('3vp').height('28vp').backgroundColor('#777777').borderRadius('2vp')
                Column().width('3vp').height('22vp').backgroundColor('#666666').borderRadius('2vp')
                Column().width('3vp').height('30vp').backgroundColor('#777777').borderRadius('2vp')
                Column().width('3vp').height('18vp').backgroundColor('#555555').borderRadius('2vp')
              }.offset({ y: '-24vp' })
            }
          }
          .width('100%').layoutWeight(1)

          // 进度
          Row({ space: '6vp' }) {
            Text(this.currentTime).fontSize('10fp').fontColor('#999999')
            Slider({ value: this.isPlaying ? (this.elapsed % 30) / 30 * 100 : 0, min: 0, max: 100, style: SliderStyle.InSet })
              .blockColor('#555555').trackColor('#e5e5e5').selectedColor('#999999')
              .layoutWeight(1).enabled(false)
            Text(this.isPlaying ? 'ON' : 'OFF').fontSize('10fp').fontColor('#999999')
          }.width('100%')

          // 音量
          Row({ space: '8vp' }) {
            Text('-').fontSize('18fp').fontWeight(FontWeight.Bold).fontColor('#999999')
            Slider({ value: this.volume, min: 0, max: 100, style: SliderStyle.InSet })
              .blockColor('#333333').trackColor('#e5e5e5').selectedColor('#999999')
              .layoutWeight(1).onChange((v: number) => { this.volume = v; })
            Text('+').fontSize('18fp').fontWeight(FontWeight.Bold).fontColor('#999999')
          }.width('100%')

          // 控制
          Row({ space: '16vp' }) {
            Button('|<')
              .fontSize('16fp').fontColor('#666666').backgroundColor('#f1f1f1')
              .borderRadius('8vp').width('52vp').height('44vp')
              .onClick(() => { this.prevTrack(); })
            Button(this.isPlaying ? '||' : '>')
              .fontSize('22fp').fontColor('#ffffff').backgroundColor('#1a1a1a')
              .borderRadius('8vp').width('64vp').height('48vp')
              .onClick(() => { this.isPlaying ? this.pause() : this.play(); })
            Button('>|')
              .fontSize('16fp').fontColor('#666666').backgroundColor('#f1f1f1')
              .borderRadius('8vp').width('52vp').height('44vp')
              .onClick(() => { this.nextTrack(); })
          }.justifyContent(FlexAlign.Center)

          Row({ space: '8vp' }) {
            Text('Rhythm dance').fontSize('12fp').fontWeight(FontWeight.Medium).fontColor('#333333')
            Slider({ value: this.bpm, min: 80, max: 160, step: 10, style: SliderStyle.InSet })
              .layoutWeight(1).onChange((value: number) => {
                this.bpm = value;
                if (this.danceMode) { this.stopDance(); this.startDance(); }
              })
            Text(`${this.bpm} BPM`).fontSize('10fp').fontColor('#666666')
            Button(this.danceMode ? 'Stop' : 'Dance')
              .fontSize('12fp').fontColor('#ffffff')
              .backgroundColor(this.danceMode ? '#b91c1c' : '#0f766e')
              .borderRadius('6vp').height('36vp')
              .onClick(() => { this.danceMode ? this.stopDance() : this.startDance(); })
          }.width('100%').padding('8vp').backgroundColor('#f8fafc').borderRadius('8vp')
        }
        .width('0vp').layoutWeight(5.5).padding('8vp')
        .backgroundColor('#ffffff').borderRadius('12vp').border({ width: '1vp', color: '#e5e5e5' })

        // ---- 右侧：播放列表 ----
        Column({ space: '4vp' }) {
          Text('播放列表').fontSize('11fp').fontWeight(FontWeight.Medium).fontColor('#999999').width('100%')
          Scroll() {
            Column({ space: '2vp' }) {
              ForEach(this.tracks, (track: Track, idx: number) => {
                Row({ space: '8vp' }) {
                  Text(`${idx + 1}`).fontSize('11fp').fontWeight(FontWeight.Medium)
                    .fontColor(idx === this.currentTrack ? '#333333' : '#cccccc').width('22vp').textAlign(TextAlign.Center)
                  Column({ space: '1vp' }) {
                    Text(track.name).fontSize('12fp').fontWeight(FontWeight.Medium)
                      .fontColor(idx === this.currentTrack ? '#111111' : '#666666')
                    Text(track.artist).fontSize('9fp').fontColor('#cccccc')
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  if (idx === this.currentTrack && this.isPlaying) {
                    Row({ space: '1vp' }) {
                      Column().width('2vp').height('8vp').backgroundColor('#666666').borderRadius('1vp')
                      Column().width('2vp').height('12vp').backgroundColor('#333333').borderRadius('1vp')
                      Column().width('2vp').height('6vp').backgroundColor('#999999').borderRadius('1vp')
                    }
                  }
                }
                .width('100%').padding('7vp')
                .backgroundColor(idx === this.currentTrack ? '#f5f5f5' : '#fafafa')
                .borderRadius('6vp').border({ width: '1vp', color: idx === this.currentTrack ? '#e5e5e5' : '#f5f5f5' })
                .onClick(() => { this.selectTrack(idx); })
              }, (track: Track, idx: number) => `${idx}`)
            }
          }.layoutWeight(1).scrollBar(BarState.Off)
        }
        .width('0vp').layoutWeight(4.5).padding('8vp')
        .backgroundColor('#ffffff').borderRadius('12vp').border({ width: '1vp', color: '#e5e5e5' })
      }
      .width('100%').layoutWeight(1).padding('8vp')
    }
    .width('100%').height('100%').backgroundColor('#ffffff')
  }

  // ====== 播放逻辑 ======
  private play(): void {
    if (!this.isConnected) { promptAction.showToast({ message: '请先连接小车' }); return; }
    this.isPlaying = true; this.elapsed = 0; this.startBeep(); this.startTimer();
  }
  private pause(): void { this.isPlaying = false; this.stopDance(); this.stopBeep(); carApi.send(CarEncode.BuzzerEncode(false)); }
  private nextTrack(): void { const w = this.isPlaying; this.pause(); this.currentTrack = (this.currentTrack + 1) % this.tracks.length; if (w) this.play(); }
  private prevTrack(): void { const w = this.isPlaying; this.pause(); this.currentTrack = (this.currentTrack - 1 + this.tracks.length) % this.tracks.length; if (w) this.play(); }
  private selectTrack(idx: number): void { if (idx === this.currentTrack && this.isPlaying) return; this.pause(); this.currentTrack = idx; this.play(); }

  private startDance(): void {
    if (!this.isConnected) { promptAction.showToast({ message: 'Connect to the car first' }); return; }
    if (!this.isPlaying) { this.play(); }
    this.danceMode = true;
    this.danceStep = 0;
    const pattern: CarDirection[] = [CarDirection.Front, CarDirection.Left, CarDirection.After, CarDirection.Right];
    const beatMs = Math.round(60000 / this.bpm);
    const move = () => {
      if (!this.danceMode) return;
      carApi.send(CarEncode.ButtonCarEncode(pattern[this.danceStep % pattern.length]));
      this.danceStep++;
      if (this.danceStopTimer !== -1) { clearTimeout(this.danceStopTimer); }
      this.danceStopTimer = setTimeout(() => {
        carApi.send(CarEncode.ButtonCarEncode(CarDirection.Stop));
      }, Math.round(beatMs * 0.65));
    };
    move();
    this.danceTimer = setInterval(move, beatMs);
  }

  private stopDance(): void {
    this.danceMode = false;
    if (this.danceTimer !== -1) { clearInterval(this.danceTimer); this.danceTimer = -1; }
    if (this.danceStopTimer !== -1) { clearTimeout(this.danceStopTimer); this.danceStopTimer = -1; }
    carApi.send(CarEncode.ButtonCarEncode(CarDirection.Stop));
  }
  private startBeep(): void {
    const pattern = this.beepPatterns[this.currentTrack];
    const onT = pattern[0]; const offT = pattern[1]; const rep = pattern[2];
    let count = 0;
    const doBeep = () => {
      if (!this.isPlaying) return;
      if (count >= rep) { count = 0; this.beepTimer = setTimeout(() => { if (this.isPlaying) { count = 0; doBeep(); } }, 500); return; }
      carApi.send(CarEncode.BuzzerEncode(true));
      this.beepTimer = setTimeout(() => {
        carApi.send(CarEncode.BuzzerEncode(false));
        count++;
        this.beepTimer = setTimeout(() => { if (this.isPlaying) doBeep(); }, offT);
      }, onT);
    };
    doBeep();
  }
  private stopBeep(): void {
    if (this.beepTimer !== -1) { clearTimeout(this.beepTimer); this.beepTimer = -1; }
    if (this.playTimer !== -1) { clearInterval(this.playTimer); this.playTimer = -1; }
    carApi.send(CarEncode.BuzzerEncode(false));
  }
  private startTimer(): void {
    this.playTimer = setInterval(() => {
      if (this.isPlaying) { this.elapsed++; const m = Math.floor(this.elapsed / 60); const s = this.elapsed % 60; this.currentTime = `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`; }
    }, 1000);
  }
}
