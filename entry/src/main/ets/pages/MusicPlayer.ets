import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { carApi } from '../CarUtill/CarApi';
import { CarEncode } from '../CarUtill/CarEncode';
import { CarDirection } from '../CarUtill/CarEnum';
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
    { name: '滴滴提醒', artist: '蜂鸣器' }, { name: '警报音效', artist: '蜂鸣器' },
    { name: '倒车提示', artist: '蜂鸣器' }, { name: '欢快节奏', artist: '蜂鸣器' },
    { name: '长鸣警告', artist: '蜂鸣器' }, { name: '短促三声', artist: '蜂鸣器' },
    { name: '间隔蜂鸣', artist: '蜂鸣器' }, { name: '连续滴滴', artist: '蜂鸣器' },
  ];
  beepPatterns: number[][] = [
    [200, 200, 6], [500, 100, 4], [300, 800, 3], [150, 100, 8],
    [2000, 0, 1], [100, 150, 3], [400, 600, 5], [100, 100, 10],
  ];

  aboutToAppear(): void { this.checkStatus(); }
  aboutToDisappear(): void { this.stopDance(); this.stopBeep(); }

  async checkStatus(): Promise<void> {
    this.isConnected = await TCPClientManager.getInstance().isConnect();
    if (this.isConnected) {
      this.carIp = await PreferencesUtils.getInstance().netUtils.getIP() as string;
      this.connLabel = `已连接 ${this.carIp}`;
    } else {
      this.connLabel = '未连接 · 请配置网络';
    }
  }

  build() {
    Column() {
      Row({ space: '12vp' }) {
        Button('<')
          .width('44vp').height('44vp').fontSize('22fp').fontColor('#111111')
          .backgroundColor('#f5f5f5').borderRadius('22vp')
          .onClick(() => { this.stopBeep(); router.back(); })
        Column() {
          Text('音效管理').fontSize('11fp').fontWeight(FontWeight.Bold).fontColor('#707072')
          Text('声音控制').fontSize('26fp').fontWeight(FontWeight.Bold).fontColor('#111111')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%').padding({ left: '20vp', right: '20vp', top: '20vp', bottom: '16vp' })

      Scroll() {
        Column({ space: '24vp' }) {
          Column({ space: '8vp' }) {
            Text(this.tracks[this.currentTrack].name).fontSize('28fp').fontWeight(FontWeight.Bold).fontColor('#ffffff')
            Text(this.tracks[this.currentTrack].artist).fontSize('14fp').fontColor('#9e9ea0')
            Text(this.isPlaying ? '播放中' : '准备就绪')
              .fontSize('11fp').fontWeight(FontWeight.Bold).fontColor('#ffffff')
              .padding({ left: '10vp', right: '10vp', top: '5vp', bottom: '5vp' })
              .backgroundColor('#39393b').borderRadius('16vp')
          }
          .width('100%').height('190vp').padding('22vp')
          .alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.End)
          .backgroundColor('#111111').borderRadius('24vp')

          Column({ space: '14vp' }) {
            Row() {
              Text('音量').fontSize('12fp').fontWeight(FontWeight.Bold).fontColor('#707072')
              Blank()
              Text(`${this.volume.toFixed(0)}%`).fontSize('14fp').fontWeight(FontWeight.Bold).fontColor('#111111')
            }.width('100%')
            Slider({ value: this.volume, min: 0, max: 100, style: SliderStyle.InSet })
              .blockColor('#111111').trackColor('#e5e5e5').selectedColor('#111111')
              .width('100%').onChange((v: number) => { this.volume = v; })
            Row({ space: '12vp' }) {
              Button('上一首')
                .layoutWeight(1).height('46vp').fontSize('14fp').fontColor('#111111')
                .backgroundColor('#ffffff').borderRadius('24vp').onClick(() => { this.prevTrack(); })
              Button(this.isPlaying ? '暂停' : '播放')
                .layoutWeight(1).height('46vp').fontSize('14fp').fontColor('#ffffff')
                .backgroundColor('#111111').borderRadius('24vp').onClick(() => { this.isPlaying ? this.pause() : this.play(); })
              Button('下一首')
                .layoutWeight(1).height('46vp').fontSize('14fp').fontColor('#111111')
                .backgroundColor('#ffffff').borderRadius('24vp').onClick(() => { this.nextTrack(); })
            }.width('100%')
          }
          .width('100%').padding('20vp').backgroundColor('#f5f5f5').borderRadius('24vp')

          Column({ space: '14vp' }) {
            Row() {
              Column({ space: '5vp' }) {
                Text('律动模式').fontSize('12fp').fontWeight(FontWeight.Bold).fontColor('#707072')
                Text(this.danceMode ? '小车正在跟随节拍移动' : '按节奏控制小车动作')
                  .fontSize('18fp').fontWeight(FontWeight.Bold).fontColor('#111111')
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Text(`${this.bpm} BPM`).fontSize('12fp').fontWeight(FontWeight.Bold).fontColor('#707072')
            }.width('100%')
            Slider({ value: this.bpm, min: 80, max: 160, step: 10, style: SliderStyle.InSet })
              .width('100%').blockColor('#111111').trackColor('#e5e5e5').selectedColor('#111111')
              .onChange((value: number) => {
                this.bpm = value;
                if (this.danceMode) {
                  this.stopDance();
                  this.startDance();
                }
              })
            Button(this.danceMode ? '停止律动' : '开始律动')
              .width('100%').height('48vp').fontSize('15fp').fontWeight(FontWeight.Medium)
              .fontColor(this.danceMode ? '#111111' : '#ffffff')
              .backgroundColor(this.danceMode ? '#ffffff' : '#111111')
              .borderRadius('26vp')
              .onClick(() => { this.danceMode ? this.stopDance() : this.startDance(); })
          }
          .width('100%').padding('20vp').backgroundColor('#f5f5f5').borderRadius('24vp')

          Column({ space: '8vp' }) {
            Text('播放列表').fontSize('12fp').fontWeight(FontWeight.Bold).fontColor('#707072').width('100%')
            ForEach(this.tracks, (track: Track, idx: number) => {
              Row() {
                Text(`${idx + 1}`).width('28vp').fontSize('13fp').fontWeight(FontWeight.Bold)
                  .fontColor(idx === this.currentTrack ? '#111111' : '#707072')
                Column() {
                  Text(track.name).fontSize('16fp').fontWeight(FontWeight.Medium).fontColor('#111111')
                  Text(track.artist).fontSize('12fp').fontColor('#707072')
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Text(idx === this.currentTrack && this.isPlaying ? '播放中' : '')
                  .fontSize('10fp').fontWeight(FontWeight.Bold).fontColor('#007d48')
              }
              .width('100%').padding('16vp')
              .backgroundColor(idx === this.currentTrack ? '#f5f5f5' : '#ffffff')
              .borderRadius('18vp')
              .onClick(() => { this.selectTrack(idx); })
            }, (track: Track, idx: number) => `${idx}`)
          }.width('100%')
        }
        .width('100%').padding({ left: '20vp', right: '20vp', bottom: '36vp' })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
    }
    .width('100%').height('100%').backgroundColor('#ffffff')
  }

  private play(): void {
    if (!this.isConnected) { promptAction.showToast({ message: '请先连接小车' }); return; }
    this.isPlaying = true; this.elapsed = 0; this.startBeep(); this.startTimer();
  }
  private pause(): void { this.isPlaying = false; this.stopDance(); this.stopBeep(); carApi.send(CarEncode.BuzzerEncode(false)); }
  private nextTrack(): void { const w = this.isPlaying; this.pause(); this.currentTrack = (this.currentTrack + 1) % this.tracks.length; if (w) this.play(); }
  private prevTrack(): void { const w = this.isPlaying; this.pause(); this.currentTrack = (this.currentTrack - 1 + this.tracks.length) % this.tracks.length; if (w) this.play(); }
  private selectTrack(idx: number): void { if (idx === this.currentTrack && this.isPlaying) return; this.pause(); this.currentTrack = idx; this.play(); }

  private startDance(): void {
    if (!this.isConnected) { promptAction.showToast({ message: '请先连接小车' }); return; }
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
      if (count >= rep) {
        count = 0;
        this.beepTimer = setTimeout(() => { if (this.isPlaying) { count = 0; doBeep(); } }, 500);
        return;
      }
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
      if (this.isPlaying) {
        this.elapsed++;
        const m = Math.floor(this.elapsed / 60);
        const s = this.elapsed % 60;
        this.currentTime = `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
      }
    }, 1000);
  }
}
