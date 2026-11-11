================================================================
 UnblockNeteaseMusic · 网易云 3.x 适配版
 基线：上游 0.28.0 + 3.x 客户端补丁
 验证环境：网易云音乐 3.1.34.205281 / Windows 10 19045
================================================================

【一】快速开始

方式 A —— 直接用 exe（推荐，不需要装 Node）

    dist\unm-3x.exe

  默认监听 127.0.0.1:8080 (HTTP) 和 127.0.0.1:8081 (HTTPS MITM)。
  两个端口都必须活，只开一个等于全挂。

  常用参数：
    unm-3x.exe -p 8090:8091              换端口
    unm-3x.exe -a 0.0.0.0                监听所有网卡（给局域网/手机用）

方式 B —— 源码运行

    cd unm-3x
    .\start.ps1

  start.ps1 会自动检查 Node、端口、依赖和证书。

【二】客户端设置（必做）

  网易云音乐 → 右上角头像旁「设置」→ 工具 → http代理
    ○ 自定义代理
    服务器：127.0.0.1
    端口：  8080
    点「确定」

    代理设置一次即可，长期有效，不需要每次重启都重新配置。

【三】证书（只需做一次）

  项目的 server.crt 是给 *.music.163.com 签的，由 ca.crt 签发。
  3.x 走 CEF/cronet，读 Windows 根证书区，所以要把 ca.crt 导入：

    右键 ca.crt → 安装证书 → 本地计算机 → 受信任的根证书颁发机构

  或者管理员命令行：
    certutil -addstore -f Root ca.crt

  本机已确认导入过（指纹 7D3EA9D87EA2F2600FCCE237AA8989B8805549DC）。

【四】配置（重点）

  两种方式，改完都要重启服务生效。

  ■ 方式 1：双击 config.bat（推荐）

    出来的菜单直接按数字切换：

      [1] 本地 VIP          svip / cvip / true / 关闭
      [2] 优先无损 FLAC     开 / 关
      [3] 屏蔽广告          开 / 关
      [4] 禁用升级检测      开 / 关
      [5] 选择最高码率      开 / 关
      [6] 严格音源顺序      开 / 关
      [7] 最低码率 MIN_BR   直接输入数值
      [8] 日志等级          debug / info / warn / error
      [9] 网易 Cookie       粘贴整串
      [Q] QQ Cookie         粘贴整串
      [P] 监听端口         默认 8080:8081
      [A] 开机自启+守护    开 / 关（一键切换）

    最后选 [S] 保存，或 [R] 保存并自动重启服务。

  ■ [A] 开机自启 + 后台守护做什么

    按一次 [A]，会在本机建立三层保护：

      ① 计划任务  UnblockNeteaseMusic-Watchdog
                 每分钟检查一次，服务掉了自动拉起
      ② 启动器    watchdog_run.vbs（无窗口，调 powershell 跑 watchdog.ps1）
      ③ 兜底      HKCU\...\Run\UnblockNeteaseMusic → autostart.vbs

    效果：

      · 开机自动跑，不弹黑框，黑框可以关掉了
      · 服务被误杀 / 崩溃 / 端口被释放 → 1 分钟内自动恢复
      · 每次自动拉起都会写一行到 watchdog.log
      · 服务正常时静默退出，不会反复刷日志

    关掉 [A] 会同时删除计划任务和两个 vbs。

    ⚠ 整个文件夹挪位置后，要重新进菜单开关一次，路径才会更新。

  ■ 嫌 8080 端口爱被占用？

    [P] 监听端口 可以改，但改完客户端代理端口要跟着改。

    默认保持 8080:8081 就好 —— 配合上面的守护，被别的程序短暂占用
    之后也能自己回来。真遇到长期占用再去 [P] 换，常见备选：

      18080:18081    冲突概率低
      7890:7891      常见代理端口段

  ■ 方式 2：直接编辑 .env

    记事本打开 .env，改完保存，重启 unm-3x.exe。
    .env 必须和 unm-3x.exe 放同一个目录（或从该目录启动）。

  ■ 全部可用变量（照 GitHub 文档整理）

    本地 VIP
      ENABLE_LOCAL_VIP     true / cvip / svip     客户端内伪装黑胶
      LOCAL_VIP_UID        123456789,987654321    只对这些 UID 生效，留空=全部

    音质
      ENABLE_FLAC          true                   优先无损音源
      MIN_BR               320000 / 999000        低于该码率一律换源
      SELECT_MAX_BR        true                   所有音源里挑最高码率
      FOLLOW_SOURCE_ORDER  true                   严格按 -o 顺序查，不并发
      SEARCH_ALBUM         true                   搜索时带专辑名

    客户端行为
      BLOCK_ADS            true                   屏蔽应用内广告
      DISABLE_UPGRADE_CHECK true                  禁用更新检测
      ENABLE_HTTPDNS       true                   启用 HTTPDNS（不建议）

    日志
      LOG_LEVEL            trace/debug/info/warn/error
      LOG_FILE             unm.log                日志写文件
      JSON_LOG             true                   JSON 格式日志

    性能
      NO_CACHE             true                   停用缓存

    音源凭证
      QQ_COOKIE            uin=xxx; qm_keyst=xxx
      NEW_QQ_COOKIE        新版 QQ 音乐
      KUWO_COOKIE          酷我
      MIGU_COOKIE          咪咕 aversionid
      JOOX_COOKIE          wmid=xxx; session_key=xxx
      YOUTUBE_KEY          YouTube Data API v3 Key

    网易 / 证书
      NETEASE_COOKIE       MUSIC_U=xxx; __csrf=xxx
      SIGN_CERT            ./server.crt
      SIGN_KEY             ./server.key

  优先级：系统环境变量 > .env 文件。
  也就是说你在命令行 SET 了同名变量，会覆盖 .env 里的值。

  ⚠ 用记事本改 .env 时注意保持 UTF-8 编码，别存成 ANSI，
    否则中文注释会变乱码（不影响功能，但难看）。

【五】这一版修了什么

  1. interfacepc.music.163.com 加入域名白名单
     —— 3.x 的唯一 eapi 入口，老代码没有它，一次都不换源

  2. 必须双端口 —— 3.x 全 HTTPS 且不降级，单端口会让所有 :443 被判 blank

  3. X-Real-IP 只注入白名单接口
     —— 接管 interfacepc 后，评论/歌词等接口带上了伪造 IP 被风控拒掉，
        表现为评论区空白、歌词加载不出来

  4. 换源条件补 !item.url，换源后清 freeTrialPrivilege / freeTimeTrialPrivilege

  5. 补 3.x 新接口：/api/v3/discovery/recommend/songs、/api/song/chorus

  6. 修 server.js 的 proxy.log 嵌套 if，MITM 日志之前永远不打印

  详细说明见 unm-3x\README-3x.md，代码差异见 patch-3x.diff。

【六】排障

  问：客户端显示全部灰色 / 加载失败
  答：检查两个端口是否都活着（netstat -ano | findstr 8080 和 8081）。
      只监听 8080 就会出现这个现象。

  问：能播放但评论区空白 / 歌词不出来
  答：确认用的是本包里的版本（含 X-Real-IP 补丁）。
      LOG_LEVEL=debug 启动，看日志里 /api/resource/commentInfo/list 和
      /api/song/lyric/v1 的 RESP 行是否 status=200。

  问：换源了但播放 30 秒就停
  答：说明 freeTrialPrivilege 没清干净，确认 src/hook.js 里那段是
      item.freeTrialPrivilege = { resConsumable: false, ... }。

  问：声音从哪来的
  答：kugou / kuwo 竞速，失败才试 migu / bilibili / ytdlp。
      migu 目前基本超时，ytdlp 需要另装 yt-dlp。

【七】目录说明

  unm-3x.exe         自包含主程序（Node 18 运行时 + 代码 + 证书全内嵌）
  .env               配置文件（改这个，和 exe 放一起）
  config.bat         双击打开配置菜单
  config.ps1         配置菜单本体（config.bat 会调用它）
  autostart.vbs      隐藏启动器（开 [A] 后生成）
  watchdog.ps1       守护脚本（端口掉了自动拉起）
  watchdog_run.vbs   守护的计划任务入口（无窗口）
  watchdog.log       守护日志（每次自动拉起记一行）
  ca.crt             根证书，导入系统用
  patch-3x.diff      相对上游 0.28.0 的代码补丁
  unm-3x\            完整源码（0.28.0 + 补丁），含 node_modules 和证书
    unm-3x\README-3x.md  详细适配说明
    unm-3x\start.ps1     源码模式一键启动
  tools\             调试探针
    probe_eapi.js      单曲探针：直连网易看真实响应
    probe_batch.js     批量探测：统计「会换源 / 可播 / 灰歌」
    probe_api.js       任意接口探针，支持走代理
    cmp_eapi.js        直连 vs 代理逐字节对比（验证代理没破坏接口）

  探针用法示例：
    node tools\probe_eapi.js 185811
    node tools\probe_batch.js 周杰伦 五月天

================================================================
