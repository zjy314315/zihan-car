import socket from '@ohos.net.socket';
import { PreferencesUtils } from './PreferencesUtils';

export class ProcessLifecycle {
  private static readonly PORT: number = 6001;
  private static isRunning: boolean = false;
  private static startInFlight: Promise<boolean> | null = null;

  public static async start(feature: string): Promise<boolean> {
    return true;
  }

  public static async stop(feature: string): Promise<boolean> {
    return true;
  }

  public static async status(feature: string): Promise<boolean> {
    return await ProcessLifecycle.send('status', feature);
  }

  public static async startAll(): Promise<boolean> {
    if (ProcessLifecycle.isRunning) {
      return true;
    }
    if (ProcessLifecycle.startInFlight !== null) {
      return await ProcessLifecycle.startInFlight;
    }
    ProcessLifecycle.startInFlight = ProcessLifecycle.send('start_all', 'all');
    const started: boolean = await ProcessLifecycle.startInFlight;
    ProcessLifecycle.startInFlight = null;
    if (started) {
      ProcessLifecycle.isRunning = true;
    }
    return started;
  }

  public static async stopAll(): Promise<boolean> {
    if (ProcessLifecycle.startInFlight !== null) {
      await ProcessLifecycle.startInFlight;
    }
    if (!ProcessLifecycle.isRunning) {
      return true;
    }
    const stopped: boolean = await ProcessLifecycle.send('stop_all', 'all');
    if (stopped) {
      ProcessLifecycle.isRunning = false;
    }
    return stopped;
  }

  private static async send(action: string, feature: string): Promise<boolean> {
    const carIp: string = await PreferencesUtils.getInstance().netUtils.getIP() as string;
    const tcp = socket.constructTCPSocketInstance();
    try {
      await tcp.bind({ address: '0.0.0.0', family: 1 });
      await tcp.connect({ address: { address: carIp, port: ProcessLifecycle.PORT }, timeout: 1800 });
      tcp.send({ data: `@PROC:${JSON.stringify({ action: action, feature: feature })}\n` });
      await new Promise<void>((resolve) => { setTimeout(() => resolve(), 80); });
      tcp.close();
      return true;
    } catch (error) {
      try { tcp.close(); } catch (_) { }
      console.error('ProcessLifecycle', `${action} ${feature} failed`, JSON.stringify(error));
      return false;
    }
  }
}
