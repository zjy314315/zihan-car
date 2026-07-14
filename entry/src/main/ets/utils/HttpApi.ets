/**
 * HTTP API 通信封装
 * 调用小车端 ros_http_api.py (port 7000)
 */
import http from '@ohos.net.http';
import { PreferencesUtils } from './PreferencesUtils';

// ========== 通用基础类型 ==========

class ApiResponse {
  status?: string;
  error?: string;
}

interface Point2D {
  x: number;
  y: number;
}

interface Pose2D extends Point2D {
  yaw: number;
}

interface PoseTheta extends Point2D {
  theta: number;
}

// ========== 请求体类型 ==========

interface WaypointsBody {
  waypoints: Waypoint[];
}

interface LatLngHeadingBody {
  lat: number;
  lng: number;
  heading: number;
}

interface LatLngBody {
  lat: number;
  lng: number;
}

interface NameBody {
  name: string;
}

interface CarControlBody {
  vx: number;
  vy: number;
  vz: number;
}

// ========== HttpApi 类 ==========

class HttpApi {
  private baseUrl: string = '';
  private static instance: HttpApi;

  static getInstance(): HttpApi {
    if (!HttpApi.instance) {
      HttpApi.instance = new HttpApi();
    }
    return HttpApi.instance;
  }

  async init(): Promise<void> {
    const ip = await PreferencesUtils.getInstance().netUtils.getIP();
    this.baseUrl = `http://${ip}:7000`;
  }

  setBaseUrl(url: string): void {
    this.baseUrl = url;
  }

  async get<T = ApiResponse>(path: string): Promise<T> {
    return this.request<T>('GET', path);
  }

  async post<T = ApiResponse>(path: string, body?: Object): Promise<T> {
    return this.request<T>('POST', path, body);
  }

  private async request<T>(method: string, path: string, body?: Object): Promise<T> {
    const url = `${this.baseUrl}${path}`;
    const httpRequest = http.createHttp();

    return new Promise<T>((resolve, reject) => {
      httpRequest.request(
        url,
        {
          method: method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
          header: { 'Content-Type': 'application/json' },
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 5000,
          readTimeout: 10000,
          extraData: body ? JSON.stringify(body) : undefined,
        },
        (err: Error, data: http.HttpResponse) => {
          if (err) {
            reject(new Error(`请求失败: ${JSON.stringify(err)}`));
          } else {
            try {
              const result: Object = typeof data.result === 'string'
                ? JSON.parse(data.result as string)
                : data.result;
              resolve(result as T);
            } catch (e) {
              resolve(data.result as T);
            }
          }
        }
      );
    });
  }

  // ========== 导航 API ==========

  async startWaypointNav(waypoints: Waypoint[]): Promise<ApiResponse> {
    const body: WaypointsBody = { waypoints };
    return this.post('/api/nav/waypoints', body);
  }

  async stopNav(): Promise<ApiResponse> {
    return this.post('/api/nav/stop');
  }

  async getNavStatus(): Promise<NavStatus> {
    return this.get<NavStatus>('/api/nav/status');
  }

  // ========== 坐标转换 API ==========

  async setTransformRef(lat: number, lng: number, heading: number): Promise<ApiResponse> {
    const body: LatLngHeadingBody = { lat, lng, heading };
    return this.post('/api/transform/set_ref', body);
  }

  async gpsToMap(lat: number, lng: number): Promise<ApiResponse> {
    const body: LatLngBody = { lat, lng };
    return this.post('/api/transform/gps_to_map', body);
  }

  // ========== 救援 API ==========

  async startRescue(lat: number, lng: number): Promise<ApiResponse> {
    const body: LatLngBody = { lat, lng };
    return this.post('/api/rescue/start', body);
  }

  async getRescueStatus(): Promise<RescueStatus> {
    return this.get<RescueStatus>('/api/rescue/status');
  }

  async confirmReturn(): Promise<ApiResponse> {
    return this.post('/api/rescue/confirm_return');
  }

  async abortRescue(): Promise<ApiResponse> {
    return this.post('/api/rescue/abort');
  }

  // ========== 系统 API ==========

  async ping(): Promise<ApiResponse> {
    return this.get('/api/system/ping');
  }

  async getBattery(): Promise<ApiResponse> {
    return this.get('/api/system/battery');
  }

  async getPose(): Promise<Pose2D> {
    return this.get<Pose2D>('/api/system/pose');
  }

  // ========== 建图 API ==========

  async buildStart(): Promise<ApiResponse> {
    return this.post('/api/map/build/start');
  }

  async buildWaypoint(name: string): Promise<ApiResponse> {
    const body: NameBody = { name };
    return this.post('/api/map/waypoint', body);
  }

  async buildEnd(mapName: string): Promise<ApiResponse> {
    const body: NameBody = { name: mapName };
    return this.post('/api/map/build/end', body);
  }

  async getBuildInfo(): Promise<ApiResponse> {
    return this.get('/api/map/info');
  }

  // ========== 地图数据 API ==========

  async getMapList(): Promise<MapInfo[]> {
    return this.get<MapInfo[]>('/api/map/list');
  }

  async getMapStatus(): Promise<ApiResponse> {
    return this.get('/api/map/status');
  }

  async saveGridMap(name: string): Promise<ApiResponse> {
    const body: NameBody = { name };
    return this.post('/api/map/save_map', body);
  }

  async getGridData(): Promise<GridData> {
    return this.get<GridData>('/api/map/grid_data');
  }

  // ========== 遥控 API ==========

  async carControl(vx: number, vy: number, vz: number): Promise<ApiResponse> {
    const body: CarControlBody = { vx, vy, vz };
    return this.post('/api/map/control', body);
  }

  // ========== 地图导航 API ==========

  async startMapNavigate(name: string): Promise<ApiResponse> {
    const body: NameBody = { name };
    return this.post('/api/map/navigate', body);
  }

  async stopMapNavigate(): Promise<ApiResponse> {
    return this.post('/api/map/stop');
  }
}

// ========== 领域类型定义 ==========

interface Waypoint {
  x: number;
  y: number;
  theta?: number;
}

interface NavStatus {
  status: string;
  current_index: number;
  total: number;
  pose: Pose2D;
  target: Waypoint | null;
}

interface RescueStatus {
  rescue_id: string;
  status: string;
  message: string;
  origin: PoseTheta | null;
  target: Point2D | null;
  navigation: NavStatus | null;
}

interface MapWaypoint {
  name: string;
  x: number;
  y: number;
}

interface MapWaypoints {
  name: string;
  origin: MapWaypoint;
  waypoints: MapWaypoint[];
  total: number;
}

interface MapGrid {
  pgm: string;
  yaml: string;
}

interface GridData {
  width: number;
  height: number;
  resolution: number;
  origin_x: number;
  origin_y: number;
  data: number[];
}

interface MapInfo {
  name: string;
  waypoints?: MapWaypoints;
  grid?: MapGrid;
}

export default HttpApi;
export { HttpApi, ApiResponse, Waypoint, NavStatus, RescueStatus, MapInfo, MapWaypoints, MapWaypoint, MapGrid, GridData, Pose2D, Point2D, PoseTheta };
