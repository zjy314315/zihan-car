import preferences from '@ohos.data.preferences';

/**首选项对象*/
export class PreferencesUtils {
  /**私有静态实例，懒汉式单例*/
  private static instance: PreferencesUtils | undefined = undefined;

  /**私有构造方法，防止外部直接实例化*/
  private constructor() {
  }

  /**提供一个公共的静态方法返回实例对象*/
  public static getInstance(): PreferencesUtils {
    // 如果对象单例不存在那么构建对象
    if (!PreferencesUtils.instance)
      PreferencesUtils.instance = new PreferencesUtils();
    return PreferencesUtils.instance;
  }

  /**网络工具对象*/
  netUtils!: NetInfoPreferencesUtils

  /*
    * 初始化preferences实例
    * @context  应用上下文
   */
  async init(context: Context) {
    this.netUtils = new NetInfoPreferencesUtils(context)
  }
}

/**
 * 网络配置首选项工具
 */
export class NetInfoPreferencesUtils {
  /**首选项名称*/
  public static readonly NAME = "net_preferences_utils"
  /**KEY IP*/
  public static readonly KEY_IP = "KEY_IP";
  /**KEY IP*/
  public static readonly KEY_TCP_PORT = "KEY_TCP_PORT";
  /**KEY IP*/
  public static readonly KEY_VIDEO_PORT = "KEY_TCP_VIDEO";
  /**首选项实例*/
  private pref!: preferences.Preferences
  /**初始化Promise，防止异步初始化未完成时调用getter/setter*/
  private initPromise: Promise<void>

  /**构造函数*/
  constructor(context: Context) {
    this.initPromise = this.init(context)
  }

  /**初始化首首选项实例*/
  private async init(context: Context) {
    let name = NetInfoPreferencesUtils.NAME;
    try {
      this.pref = await preferences.getPreferences(context, name)
      console.log(`preferences[${name}]初始化成功`)
    } catch (err) {
      console.error(`preferences[${name}]初始化失败`)
      console.error('err: ', JSON.stringify(err))
    }
  }

  /**等待初始化完成*/
  private async waitInit(): Promise<void> {
    if (this.initPromise) {
      await this.initPromise;
    }
  }

  // ------------------------------对外接口------------------------------

  async getIP() {
    await this.waitInit();
    return this.pref.get(NetInfoPreferencesUtils.KEY_IP, '10.168.202.242')
  }

  async setIp(v: string) {
    await this.waitInit();
    this.pref.put(NetInfoPreferencesUtils.KEY_IP, v);
    this.pref.flush()
  }


  async getTcpPort() {
    await this.waitInit();
    return this.pref.get(NetInfoPreferencesUtils.KEY_TCP_PORT, '6000')
  }

  async setTcpPort(v: string) {
    await this.waitInit();
    this.pref.put(NetInfoPreferencesUtils.KEY_TCP_PORT, v);
    this.pref.flush()
  }

  async setVideoPort(v: string) {
    await this.waitInit();
    this.pref.put(NetInfoPreferencesUtils.KEY_VIDEO_PORT, v);
    this.pref.flush()
  }

  async getVideoPort() {
    await this.waitInit();
    return this.pref.get(NetInfoPreferencesUtils.KEY_VIDEO_PORT, '5000')
  }
}

