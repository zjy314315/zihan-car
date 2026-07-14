# 建图导航页面设计文档

> 日期: 2026-07-15 | 版本: v1.0

## 1. 概述

在鸿蒙 App 中新增"建图导航"页面，集成栅格地图显示、D-pad 遥控、建图流程和自动巡查功能。

## 2. 路由

| 页面 | 路由 | 说明 |
|------|------|------|
| Index | `pages/Index` | 新增"建图导航"卡片 |
| MappingNav | `pages/MappingNav` | 新建，主页面 |

## 3. 组件树

```
MappingNav.ets (主页面，左右分栏横屏)
├── MapCanvas.ets        ← 左栏：栅格地图 Canvas + 位姿标注
├── DpadControl.ets      ← 右栏上：9 键方向板
├── BuildPanel.ets       ← 右栏中：建图流程按钮
└── NavPanel.ets         ← 右栏下：地图选择 + 巡查按钮
```

## 4. Index.ets 改动

在 FuncCard Grid 中新增第 9 张卡片：

```typescript
GridItem() { FuncCard({ title: '建图导航', desc: 'SLAM 建图与自动导航', tag: '地图',
  action: () => { router.pushUrl({ url: 'pages/MappingNav' }) } }) }
```

## 5. MappingNav.ets

### 5.1 布局

```
┌──────────────────────────────────────────┐
│ ← 返回    建图导航    🔴离线/🟢在线       │ 顶栏
├────────────────┬─────────────────────────┤
│                │  位姿 x y yaw            │
│  MapCanvas     │  速度 [══════]           │
│  栅格地图      │  DpadControl (9键)       │ 右栏 Scroll
│  +航点标记     │  BuildPanel              │
│  +小车位姿     │  NavPanel                │
│                │                          │
├────────────────┴─────────────────────────┤
│ 🟢 就绪 | 已保存: N 张地图                │ 底栏
└──────────────────────────────────────────┘
```

- 左栏 `layoutWeight(6)`，右栏 `layoutWeight(4)`
- 横屏锁定 `setPreferredOrientation(LANDSCAPE)`

### 5.2 状态变量

| 变量 | 类型 | 说明 |
|------|------|------|
| isConnected | boolean | 小车连接状态 |
| pose | {x,y,yaw} | 实时位姿 |
| speed | number | 当前速度 0-100 |
| statusText | string | 底栏状态文字 |
| mapList | MapInfo[] | 已保存地图列表 |
| selectedMap | string | 当前选中地图名 |

## 6. MapCanvas.ets

### 6.1 地图选择栏

```
地图: [map3 ▾] [开始巡查]
```

- 下拉框从 `GET /api/map/list` 加载地图名
- **开始巡查** → `POST /api/map/navigate {name}`
- 巡查按钮接上后端，但当前后端导航逻辑可能不稳定

### 6.2 Canvas 绘制

- 加载选中地图的栅格数据（.pgm），逐像素灰度绘制
- 航点标记：从 JSON waypoints 解析，画圆点 + 名称标签
- 小车位姿：画三角形箭头，方向 = yaw
- 手势：Pinch 缩放（0.5x ~ 5x）、Pan 平移
- 底部分辨率标注 `0.05m/px`

### 6.3 数据接口

| 数据 | 来源 | 刷新 |
|------|------|------|
| 地图列表 | `GET /api/map/list` | 进入页面时 |
| 栅格 .pgm | SFTP/HTTP 加载 | 选择地图时 |
| 航点 JSON | `GET /api/map/list` 返回 | 选择地图时 |
| 小车位姿 | `GET /api/system/pose` | 定时 500ms |

## 7. DpadControl.ets

### 7.1 9 键方向板

```
┌───┬───┬───┐
│ ↖ │ ↑ │ ↗ │
├───┼───┼───┤
│ ← │ ⏹ │ → │
├───┼───┼───┤
│ ↙ │ ↓ │ ↘ │
└───┴───┴───┘
```

### 7.2 方向映射（vx/vy/vz）

| 按键 | vx | vy | vz |
|------|-----|-----|-----|
| ↑ | +speed | 0 | 0 |
| ↓ | -speed | 0 | 0 |
| ← | 0 | +speed | 0 |
| → | 0 | -speed | 0 |
| ↖ | +speed | 0 | +speed |
| ↗ | +speed | 0 | -speed |
| ↙ | -speed | 0 | +speed |
| ↘ | -speed | 0 | -speed |
| ⏹ | 0 | 0 | 0 |

### 7.3 控制逻辑

- 按下（onTouch DOWN）：开始定时器，每 150ms 发送 `POST /api/map/control {vx,vy,vz}`
- 松开（onTouch UP/CANCEL）：清除定时器，发送 `{vx:0,vy:0,vz:0}`
- 速度滑块：0-100，默认 30

## 8. BuildPanel.ets

### 8.1 建图流程按钮

```
─── 建图 ───
[开始建图] [记录航点: 1] [结束保存: map4]
```

### 8.2 API 调用

| 按钮 | API | Body |
|------|-----|------|
| 开始建图 | `POST /api/map/build/start` | - |
| 记录航点 | `POST /api/map/waypoint` | `{name: "1"}` |
| 结束保存 | `POST /api/map/build/end` | `{name: "map4"}` |

- 航点名称自动递增（1, 2, 3...）
- 结束保存后刷新地图列表

## 9. NavPanel.ets

### 9.1 导航按钮

```
─── 导航 ───
[开始导航] [急停]
```

| 按钮 | API |
|------|-----|
| 开始导航 | `POST /api/map/navigate {name}` |
| 急停 | `POST /api/map/stop` |

- 导航使用当前 MapCanvas 选中的地图名
- 急停同时调用 stop + control(0,0,0)

## 10. HttpApi.ets 新增方法

```typescript
// 建图 API
async buildStart(): Promise<ApiResponse>
async buildWaypoint(name: string): Promise<ApiResponse>
async buildEnd(mapName: string): Promise<ApiResponse>
async getMapList(): Promise<MapInfo[]>
async getMapStatus(): Promise<ApiResponse>

// 遥控 API
async carControl(vx: number, vy: number, vz: number): Promise<ApiResponse>

// 导航 API
async startMapNavigate(name: string): Promise<ApiResponse>
async stopMapNavigate(): Promise<ApiResponse>

// 栅格地图
async saveGridMap(name: string): Promise<ApiResponse>
```

## 11. 文件清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `pages/Index.ets` | 修改 | 新增卡片 |
| `pages/MappingNav.ets` | **新建** | 主页面 |
| `components/MapCanvas.ets` | **新建** | 栅格地图 Canvas |
| `components/DpadControl.ets` | **新建** | 9 键方向板 |
| `components/BuildPanel.ets` | **新建** | 建图按钮组 |
| `components/NavPanel.ets` | **新建** | 导航按钮组 |
| `utils/HttpApi.ets` | 修改 | 新增 API 方法 |
