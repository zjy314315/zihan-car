import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import http from '@ohos.net.http';
import socket from '@ohos.net.socket';
import { carApi } from '../CarUtill/CarApi';
import { CarEncode } from '../CarUtill/CarEncode';
import { CarDirection } from '../CarUtill/CarEnum';
import { TCPClientManager } from '../tcp/TCPClientManager';
import { PreferencesUtils } from '../utils/PreferencesUtils';

interface AudioFile {
  name: string;
  size_kb: number;
}

interface DanceAction {
  direction: CarDirection;
  durationMs: number;
}

@Entry
@Component
struct MusicPlayer {
  @State carIp: string = '';
  @State audioUrl: string = 'http://192.168.1.11:5000';
  @State volume: number = 70;
  @State isPlaying: boolean = false;
  @State currentTrack: number = 0;
  @State currentTime: string = '00:00';
  @State audioFiles: AudioFile[] = [];
  @State hasAudioServer: boolean = false;
  @State statusText: string = '妫€娴嬩腑...';
  @State isConnected: boolean = false;
  private playTimer: number = -1;
  private elapsed: number = 0;
  @State danceMode: boolean = false;
  @State bpm: number = 120;
  private danceTimer: number = -1;
  private danceStopTimer: number = -1;
  private danceActionTimer: number = -1;
  private danceStep: number = 0;
  private danceRound: number = 0;
  private danceMaxRounds: number = 0;
  private dancePlan: DanceAction[] = [];

  // 铚傞福鍣ㄥ悗澶囨洸鐩?
  private beepTracks: string[] = ['闊充箰1', '闊充箰2', '闊充箰3', '闊充箰4', '闊充箰5', '闊充箰6', '闊充箰7', '闊充箰8'];
  private beepPatterns: number[][] = [
    [200, 200, 6], [500, 100, 4], [300, 800, 3], [150, 100, 8],
    [2000, 0, 1], [100, 150, 3], [400, 600, 5], [100, 100, 10],
  ];

  aboutToAppear(): void { this.initPage(); }
  aboutToDisappear(): void { this.stopAll(); }

  async initPage(): Promise<void> {
    this.carIp = await PreferencesUtils.getInstance().netUtils.getIP() as string;
    this.audioUrl = `http://${this.carIp}:5000`;
    TCPClientManager.getInstance().initNetAddress({ address: this.carIp, port: 6000 } as socket.NetAddress);
    this.isConnected = await TCPClientManager.getInstance().isConnect();
    if (!this.isConnected) {
      this.isConnected = await TCPClientManager.getInstance().connect();
    }
    await this.detectAudioServer();
  }

  async detectAudioServer(): Promise<void> {
    // Try text format first, then JSON fallback
    let result = await this.callAudioApi('/audio/list?fmt=text');
    if (result !== null && result.length >= 3) {
      const lines: string[] = result.split('\n');
      this.audioFiles = [];
      for (let i: number = 0; i < lines.length; i++) {
        const name: string = lines[i].trim();
        if (name.length > 3) { this.audioFiles.push({ name: name, size_kb: 0 }); }
      }
      if (this.audioFiles.length > 0) {
        this.hasAudioServer = true;
        this.statusText = `${this.audioFiles.length} 首`;
        return;
      }
    }
    // JSON fallback
    result = await this.callAudioApi('/audio/list');
    if (result !== null && result.indexOf('"files"') > 0) {
      this.audioFiles = [];
      // Extract filenames from JSON: "files":["a.wav","b.wav"]
      const tag: string = '"files":[';
      const start: number = result.indexOf(tag);
      if (start >= 0) {
        const end: number = result.indexOf(']', start + tag.length);
        if (end >= 0) {
          const list: string = result.substring(start + tag.length, end);
          let pos: number = 0;
          while (pos < list.length) {
            const q1: number = list.indexOf('"', pos);
            if (q1 < 0) { break; }
            const q2: number = list.indexOf('"', q1 + 1);
            if (q2 < 0) { break; }
            const nm: string = list.substring(q1 + 1, q2);
            if (nm.length > 3) { this.audioFiles.push({ name: nm, size_kb: 0 }); }
            pos = q2 + 1;
          }
        }
      }
      if (this.audioFiles.length > 0) {
        this.hasAudioServer = true;
        this.statusText = `${this.audioFiles.length} 首`;
        return;
      }
    }
    this.hasAudioServer = false;
    this.statusText = '无音频服务';
  }

  build() {
    Column() {
      Row({ space: '8vp' }) {
        Button('鈫?杩斿洖')
          .fontSize('12fp').fontColor('#ffffff').backgroundColor('#1a1a1a')
          .borderRadius('6vp').padding({ left: '10vp', right: '10vp', top: '6vp', bottom: '6vp' })
          .onClick(() => { this.stopAll(); router.back(); })
        Text('闊充箰鎾斁').fontSize('15fp').fontWeight(FontWeight.Bold).fontColor('#111111')
        Blank()
        Text(this.statusText).fontSize('10fp').fontColor('#999999').maxLines(1)
      }
      .width('100%').padding({ left: '10vp', right: '10vp', top: '8vp', bottom: '6vp' })
      .backgroundColor('#fafafa').border({ width: { bottom: '1vp' }, color: '#e5e5e5' })

      Row({ space: '8vp' }) {
        Column({ space: '10vp' }) {
          Stack() {
            Column({ space: '4vp' }) {
              Text(this.getTrackName())
                .fontSize('20fp').fontWeight(FontWeight.Bold).fontColor('#ffffff').maxLines(1)
              Text(this.hasAudioServer ? '车载音乐' : '蜂鸣器').fontSize('12fp').fontColor('#888888')
            }
            .width('100%').height('100%').justifyContent(FlexAlign.Center)
            .backgroundColor('#1a1a1a').borderRadius('14vp')

            if (this.isPlaying) {
              Row({ space: '3vp' }) {
                Column().width('3vp').height('16vp').backgroundColor('#555').borderRadius('2vp')
                Column().width('3vp').height('28vp').backgroundColor('#777').borderRadius('2vp')
                Column().width('3vp').height('22vp').backgroundColor('#666').borderRadius('2vp')
                Column().width('3vp').height('30vp').backgroundColor('#777').borderRadius('2vp')
                Column().width('3vp').height('18vp').backgroundColor('#555').borderRadius('2vp')
              }.offset({ y: '-24vp' })
            }
          }
          .width('100%').layoutWeight(1)

          Row({ space: '6vp' }) {
            Text(this.currentTime).fontSize('10fp').fontColor('#999999')
            Slider({ value: this.isPlaying ? (this.elapsed % 30) / 30 * 100 : 0, min: 0, max: 100, style: SliderStyle.InSet })
              .blockColor('#555555').trackColor('#e5e5e5').selectedColor('#999999').layoutWeight(1).enabled(false)
            Text(this.isPlaying ? 'ON' : 'OFF').fontSize('10fp').fontColor('#999999')
          }.width('100%')

          Row({ space: '8vp' }) {
            Text('-').fontSize('18fp').fontWeight(FontWeight.Bold).fontColor('#999999')
            Slider({ value: this.volume, min: 0, max: 100, style: SliderStyle.InSet })
              .blockColor('#333333').trackColor('#e5e5e5').selectedColor('#999999').layoutWeight(1)
              .onChange((v: number) => { this.setVolume(v); })
            Text('+').fontSize('18fp').fontWeight(FontWeight.Bold).fontColor('#999999')
          }.width('100%')

          Row({ space: '16vp' }) {
            Button('|<').fontSize('16fp').fontColor('#666').backgroundColor('#f1f1f1')
              .borderRadius('8vp').width('52vp').height('44vp').onClick(() => { this.prevTrack(); })
            Button(this.isPlaying ? '||' : '>').fontSize('22fp').fontColor('#fff').backgroundColor('#1a1a1a')
              .borderRadius('8vp').width('64vp').height('48vp').onClick(() => { this.togglePlay(); })
            Button('>|').fontSize('16fp').fontColor('#666').backgroundColor('#f1f1f1')
              .borderRadius('8vp').width('52vp').height('44vp').onClick(() => { this.nextTrack(); })
          }.justifyContent(FlexAlign.Center)

          Row({ space: '8vp' }) {
            Text('节奏跳舞').fontSize('12fp').fontWeight(FontWeight.Medium).fontColor('#333333')
            Slider({ value: this.bpm, min: 80, max: 160, step: 10, style: SliderStyle.InSet })
              .layoutWeight(1)
              .onChange((value: number) => {
                this.bpm = value;
                if (this.danceMode) { this.stopDance(); this.startDance(); }
              })
            Text(`${this.bpm} BPM`).fontSize('10fp').fontColor('#666666')
            Button(this.danceMode ? '停止跳舞' : '开始跳舞')
              .fontSize('12fp').fontColor('#ffffff')
              .backgroundColor(this.danceMode ? '#b91c1c' : '#0f766e')
              .borderRadius('6vp').height('36vp')
              .onClick(() => { this.danceMode ? this.stopDance() : this.startDance(); })
          }.width('100%').padding('8vp').backgroundColor('#f8fafc').borderRadius('8vp')
        }
        .width('0vp').layoutWeight(5.5).padding('8vp')
        .backgroundColor('#ffffff').borderRadius('12vp').border({ width: '1vp', color: '#e5e5e5' })

        Column({ space: '4vp' }) {
          Text('鎾斁鍒楄〃').fontSize('11fp').fontWeight(FontWeight.Medium).fontColor('#999999').width('100%')
          Row({ space: '5vp' }) {
            Button('鍒锋柊').fontSize('10fp').fontColor('#666').backgroundColor('#f1f1f1')
              .borderRadius('4vp').height('28vp').padding({ left: '8vp', right: '8vp' })
              .onClick(() => { this.detectAudioServer(); })
            Button('鍋滄').fontSize('10fp').fontColor('#666').backgroundColor('#f1f1f1')
              .borderRadius('4vp').height('28vp').padding({ left: '8vp', right: '8vp' })
              .onClick(() => { this.stopAll(); })
          }
          Scroll() {
            Column({ space: '2vp' }) {
              ForEach(this.getTrackList(), (track: string, idx: number) => {
                Row({ space: '8vp' }) {
                  Text(`${idx + 1}`).fontSize('11fp').fontWeight(FontWeight.Medium)
                    .fontColor(idx === this.currentTrack ? '#333' : '#ccc').width('22vp').textAlign(TextAlign.Center)
                  Text(this.displayName(track)).fontSize('12fp').fontWeight(FontWeight.Medium)
                    .fontColor(idx === this.currentTrack ? '#111' : '#666').layoutWeight(1).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (idx === this.currentTrack && this.isPlaying) {
                    Row({ space: '1vp' }) {
                      Column().width('2vp').height('8vp').backgroundColor('#666').borderRadius('1vp')
                      Column().width('2vp').height('12vp').backgroundColor('#333').borderRadius('1vp')
                      Column().width('2vp').height('6vp').backgroundColor('#999').borderRadius('1vp')
                    }
                  }
                }
                .width('100%').padding('7vp')
                .backgroundColor(idx === this.currentTrack ? '#f5f5f5' : '#fafafa')
                .borderRadius('6vp').border({ width: '1vp', color: idx === this.currentTrack ? '#e5e5e5' : '#f5f5f5' })
                .onClick(() => { this.selectTrack(idx); })
              }, (track: string, idx: number) => `${idx}`)
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

  // Display name (without extension)
  displayName(name: string): string {
    const dot: number = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  // Full filenames for API calls
  getTrackList(): string[] {
    if (this.hasAudioServer && this.audioFiles.length > 0) {
      const names: string[] = [];
      for (let i: number = 0; i < this.audioFiles.length; i++) {
        const raw: string = this.audioFiles[i].name;
        if (raw.startsWith('test_')) { continue; }
        names.push(raw);  // Keep full filename with .wav extension
      }
      if (names.length > 0) { return names; }
    }
    return this.beepTracks;
  }

  // Show name WITHOUT .wav in the cover/display
  getTrackName(): string {
    const list: string[] = this.getTrackList();
    return this.currentTrack < list.length ? this.displayName(list[this.currentTrack]) : '无曲目';
  }

  togglePlay(): void { if (this.isPlaying) { this.pause(); } else { this.play(); } }

  play(): void {
    if (this.hasAudioServer && this.audioFiles.length > 0) {
      const track: string = this.getTrackList()[this.currentTrack];
      this.callAudioApi(`/audio/play?file=${encodeURIComponent(track)}&volume=${this.volume}`);
    } else if (this.isConnected) {
      this.startBeep(this.currentTrack);
    } else {
      promptAction.showToast({ message: '璇峰厛杩炴帴灏忚溅' });
      return;
    }
    this.isPlaying = true;
    this.elapsed = 0;
    this.startTimer();
    this.startDance();
  }

  pause(): void {
    this.stopDance();
    this.isPlaying = false;
    if (this.hasAudioServer) { this.callAudioApi('/audio/stop'); }
    carApi.send(CarEncode.BuzzerEncode(false));
    this.stopTimer();
  }

  stopAll(): void {
    this.stopDance();
    this.isPlaying = false; this.elapsed = 0; this.currentTime = '00:00';
    this.stopTimer();
    if (this.hasAudioServer) { this.callAudioApi('/audio/stop'); }
    carApi.send(CarEncode.BuzzerEncode(false));
  }

  nextTrack(): void {
    const was: boolean = this.isPlaying; this.pause();
    this.currentTrack = (this.currentTrack + 1) % this.getTrackList().length;
    if (was) { this.play(); }
  }

  prevTrack(): void {
    const was: boolean = this.isPlaying; this.pause();
    const len: number = this.getTrackList().length;
    this.currentTrack = (this.currentTrack - 1 + len) % len;
    if (was) { this.play(); }
  }

  selectTrack(idx: number): void {
    if (idx === this.currentTrack && this.isPlaying) { return; }
    this.pause(); this.currentTrack = idx; this.play();
  }

  setVolume(v: number): void {
    this.volume = v;
    if (this.hasAudioServer) { this.callAudioApi(`/audio/volume?level=${v}`); }
  }

  private startDance(): void {
    if (!this.isPlaying) {
      promptAction.showToast({ message: '请先播放音乐' });
      return;
    }
    if (!this.isConnected) {
      promptAction.showToast({ message: '请先连接小车' });
      return;
    }

    const plan: DanceAction[] = this.getDancePlan(this.currentTrack);
    if (plan.length === 0) {
      this.stopDance();
      return;
    }

    this.stopDance();
    this.danceMode = true;
    this.danceStep = 0;
    this.danceRound = 0;
    this.danceMaxRounds = 10;
    this.dancePlan = plan;
    this.runDanceAction();
  }
  private stopDance(): void {
    this.danceMode = false;
    if (this.danceTimer !== -1) { clearInterval(this.danceTimer); this.danceTimer = -1; }
    if (this.danceStopTimer !== -1) { clearTimeout(this.danceStopTimer); this.danceStopTimer = -1; }
    if (this.danceActionTimer !== -1) { clearTimeout(this.danceActionTimer); this.danceActionTimer = -1; }
    this.danceStep = 0;
    this.danceRound = 0;
    this.dancePlan = [];
    carApi.send(CarEncode.ButtonCarEncode(CarDirection.Stop));
  }

  private runDanceAction(): void {
    if (!this.danceMode || this.dancePlan.length === 0) { return; }
    if (this.danceRound >= this.danceMaxRounds) {
      this.stopDance();
      return;
    }

    const action: DanceAction = this.dancePlan[this.danceStep];
    carApi.send(CarEncode.ButtonCarEncode(action.direction));
    this.danceStep++;
    if (this.danceStep >= this.dancePlan.length) {
      this.danceStep = 0;
      this.danceRound++;
    }

    this.danceActionTimer = setTimeout(() => {
      this.runDanceAction();
    }, action.durationMs);
  }

  private getDancePlan(trackIndex: number): DanceAction[] {
    if (trackIndex === 0) {
      return [
        { direction: CarDirection.LeftRotate, durationMs: 500 },
        { direction: CarDirection.Stop, durationMs: 100 },
        { direction: CarDirection.RightRotate, durationMs: 500 },
        { direction: CarDirection.Stop, durationMs: 100 },
      ];
    }
    if (trackIndex === 1) {
      return [
        { direction: CarDirection.LeftRotate, durationMs: 300 },
        { direction: CarDirection.Stop, durationMs: 200 },
        { direction: CarDirection.LeftRotate, durationMs: 400 },
        { direction: CarDirection.Stop, durationMs: 100 },
        { direction: CarDirection.RightRotate, durationMs: 300 },
        { direction: CarDirection.Stop, durationMs: 200 },
        { direction: CarDirection.RightRotate, durationMs: 400 },
        { direction: CarDirection.Stop, durationMs: 100 },
      ];
    }
    if (trackIndex === 2) {
      return [
        { direction: CarDirection.Front, durationMs: 300 },
        { direction: CarDirection.Stop, durationMs: 80 },
        { direction: CarDirection.After, durationMs: 300 },
        { direction: CarDirection.Stop, durationMs: 80 },
        { direction: CarDirection.Front, durationMs: 300 },
        { direction: CarDirection.Stop, durationMs: 80 },
        { direction: CarDirection.After, durationMs: 300 },
        { direction: CarDirection.Stop, durationMs: 100 },
        { direction: CarDirection.Left, durationMs: 200 },
        { direction: CarDirection.Stop, durationMs: 80 },
        { direction: CarDirection.Right, durationMs: 200 },
        { direction: CarDirection.Stop, durationMs: 100 },
      ];
    }
    return [];
  }
  startTimer(): void {
    this.stopTimer();
    this.playTimer = setInterval(() => {
      if (this.isPlaying) {
        this.elapsed++;
        const m: number = Math.floor(this.elapsed / 60);
        const s: number = this.elapsed % 60;
        this.currentTime = `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
      }
    }, 1000);
  }

  stopTimer(): void { if (this.playTimer !== -1) { clearInterval(this.playTimer); this.playTimer = -1; } }

  startBeep(idx: number): void {
    const p: number[] = this.beepPatterns[idx];
    if (!p || p.length < 3) { return; }
    let cnt: number = 0;
    const onT: number = p[0]; const offT: number = p[1]; const rep: number = p[2];
    const tick = (): void => {
      if (!this.isPlaying) { return; }
      if (cnt >= rep) { cnt = 0; setTimeout(() => { if (this.isPlaying) { cnt = 0; tick(); } }, 500); return; }
      carApi.send(CarEncode.BuzzerEncode(true));
      setTimeout(() => { carApi.send(CarEncode.BuzzerEncode(false)); cnt++; setTimeout(() => { if (this.isPlaying) { tick(); } }, offT); }, onT);
    };
    tick();
  }

  async callAudioApi(path: string): Promise<string | null> {
    const url: string = `${this.audioUrl.trim().replace(/\/$/, '')}${path}`;
    const req = http.createHttp();
    try {
      const resp: http.HttpResponse = await new Promise((resolve, reject) => {
        req.request(url, { method: http.RequestMethod.GET, expectDataType: http.HttpDataType.STRING, connectTimeout: 5000, readTimeout: 5000 },
          (err, data) => { if (err) { reject(err); } else { resolve(data); } });
      });
      return typeof resp.result === 'string' ? resp.result : null;
    } catch { return null; }
    finally { req.destroy(); }
  }
}
