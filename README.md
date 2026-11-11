# UnblockNeteaseMusic · 3.x 适配版

> 让网易云音乐客户端继续能播放变灰 / 无版权 / VIP 专享的歌曲。

基于上游 [`@unblockneteasemusic/server` 0.28.0](https://github.com/UnblockNeteaseMusic/server)（2025-09-23）
加上 **网易云音乐 3.x 客户端（Electron/CEF 架构）** 的适配补丁。

原项目 `zhongjieyang/UnblockNeteaseMusic` 停留在 `0.27.6-patch.1`，
在新版客户端上已经完全失效 —— 本项目把它修好并跟上了 3.x 的协议变化。

---

## 为什么原版不能用

用 MITM 抓包解密后，网易云音乐 **3.1.34.205281** 的真实请求长这样：

```json
POST https://interfacepc.music.163.com/eapi/song/enhance/player/url/v1
{
  "ids": "[\"2600493765\"]",
  "level": "sky",
  "immerseType": "ste",
  "encodeType": "aac",
  "trialMode": "-1",
  "e_r": true,
  "header": "{\"os\":\"pc\",\"appver\":\"3.1.34.205281\",...}"
}
```

对照老代码，三个硬断点：

| # | 断点 | 后果 |
|---|---|---|
| 1 | API 主域名变成 `interfacepc.music.163.com`，老代码 `hook.target.host` 里没有它 | 请求全部透传，**一次都不换源** |
| 2 | 3.x 全流量走 HTTPS 且**不再降级**到 HTTP | 只开 HTTP 端口时，所有 `:443` 走 `decision='blank'` 被掐断，客户端全灰 |
| 3 | 响应是否加密改由请求体里的 `e_r` 显式声明 | 老代码靠 JSON.parse 失败兜底，会误判、回写格式错 |

还有一个副作用：接管 `interfacepc` 整个域名后，**评论、歌词等接口也会被代理**，
老逻辑对它们无差别注入 `X-Real-IP`，被网易风控拒掉 —— 表现就是评论区空白、歌词加载不出来。

---

## 本版修复

1. **域名白名单** —— `interfacepc.music.163.com`（含 `.163jiasu.com` 变体）
2. **双端口强制** —— `-p 8080:8081`，缺 HTTPS 端口等于全挂
3. **`X-Real-IP` 只注入白名单接口** —— 评论 / 歌词 / 用户信息原样透传
4. **换源条件补 `!item.url`** —— 3.x 下架曲返回 `code:200 + url=""`
5. **清 `freeTrialPrivilege` / `freeTimeTrialPrivilege`** —— 3.x 靠这两个对象判断整曲/试听
6. **补 3.x 新接口** —— `/api/v3/discovery/recommend/songs`、`/api/song/chorus`
7. **修 `server.js` 的 `proxy.log` 嵌套 if** —— MITM 日志之前永远打不出来
8. **`.env` 真正生效** —— 上游 `src/app.js` 根本不加载它（只有 `bootstrap/` 加载，而 exe 入口绕过了）

实测数据：

| 项 | 修复前 | 修复后 |
|---|---|---|
| `music.163.com:443` | `decision: blank` 全掐断 | 0 次 blank，全部 MITM |
| `interfacepc` 命中 | 0 | 38 次/轮 |
| 换源 | 不触发 | kugou / kuwo 竞速成功 |
| `/api/resource/commentInfo/list` | 被拒 | 200 / 272B，与直连一致 |
| `/api/song/lyric/v1` | 被拒 | 200 / 1736B，与直连一致 |

---

## 快速开始

### 方式 A：直接跑 exe（无需 Node）

从 Releases 下载 `unm-3x.exe`，和 `.env`、`config.bat` 放在同一目录：

```powershell
.\unm-3x.exe
```

默认监听 `127.0.0.1:8080`（HTTP）和 `127.0.0.1:8081`（HTTPS MITM）。
**两个端口都必须活。**

### 方式 B：源码运行

```bash
npm install --omit=dev
node src/app.js -p 8080:8081 -a 127.0.0.1
```

Windows 下也可以直接 `.\start.ps1`（自动检查 Node / 端口 / 依赖 / 证书）。

### 客户端设置

网易云音乐 → 设置 → 工具 → http代理 → 自定义代理：

```
服务器：127.0.0.1
端口：  8080
```

> 代理设置一次即可，长期有效，不需要每次重启都重新配置。

### 证书

`server.crt` 是给 `*.music.163.com` 签的，由 `ca.crt` 签发。
3.x 走 CEF/cronet，读 Windows 根证书区，需要把 CA 导入「受信任的根证书颁发机构」：

```powershell
certutil -addstore -f Root ca.crt     # 需要管理员
```

macOS / Linux 客户端用系统证书库导入 `ca.crt` 即可。

---

## 配置

双击 `config.bat` 打开菜单式配置：

```
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
[A] 开机自启          开 / 关
[S] 保存   [R] 保存并重启服务   [E] 记事本编辑   [X] 退出
```

也可以直接编辑 `.env`（参考 `.env.example`，含全部 24 个变量）。

| 变量 | 说明 |
|---|---|
| `ENABLE_LOCAL_VIP` | `true` / `cvip` / `svip`，客户端内伪装黑胶 |
| `LOCAL_VIP_UID` | 只对这些 UID 生效，逗号分隔 |
| `ENABLE_FLAC` | 优先无损音源 |
| `MIN_BR` | 低于该码率一律换源（320000 / 999000） |
| `SELECT_MAX_BR` | 所有音源里挑最高码率 |
| `FOLLOW_SOURCE_ORDER` | 严格按 `-o` 顺序查，不并发 |
| `BLOCK_ADS` | 屏蔽应用内广告 |
| `DISABLE_UPGRADE_CHECK` | 禁用更新检测 |
| `LOG_LEVEL` | `trace` / `debug` / `info` / `warn` / `error` |
| `NO_CACHE` | 停用缓存 |
| `QQ_COOKIE` / `KUWO_COOKIE` / `MIGU_COOKIE` / `JOOX_COOKIE` / `YOUTUBE_KEY` | 各音源凭证 |
| `NETEASE_COOKIE` | 网易云登录态 |

优先级：**系统环境变量 > `.env`**。

`.env` 查找顺序：当前工作目录 → exe 所在目录 → 项目根目录。

---

## 音源

| 音源 | 代号 | 默认 | 备注 |
|---|---|---|---|
| 酷狗 | `kugou` | 是 | 稳定 |
| 酷我 | `kuwo` | 是 | 稳定，常出 FLAC |
| 咪咕 | `migu` | 是 | 接口经常超时 |
| B站 | `bilibili` | 是 | 需要视频 ID 匹配 |
| B站视频 | `bilivideo` | | 0.28.0 新增 |
| 波点音乐 | `bodian` | | 0.28.0 新增 |
| yt-dlp | `ytdlp` | 是 | 需另装 `yt-dlp` |
| QQ 音乐 | `qq` | | 需 `QQ_COOKIE` |
| JOOX | `joox` | | 需 `JOOX_COOKIE` |
| YouTube | `youtube` | | 需 `YOUTUBE_KEY` |

指定顺序：`node src/app.js -o kuwo kugou`

---

## 命令行参数

```
-p, --port http[:https]      端口，例如 8080:8081
-a, --address address        监听地址
-u, --proxy-url url          上游代理
-f, --force-host host        强制网易服务器 IP
-o, --match-order source     音源优先级
-t, --token token            代理认证
-e, --endpoint url           替换虚拟端点
-s, --strict                 严格模式（只放行网易域名）
-c, --cnrelay host:port      中国大陆中转
```

---

## 已知限制

| 项 | 状态 |
|---|---|
| `migu` 音源 | `m.music.migu.cn` 超时或返回 HTML，实际不参与竞速 |
| `ytdlp` 音源 | 需要外部 `yt-dlp` 可执行文件 |
| `sky` / `dolby` 音质 | 外部源最高到 FLAC(999000)，回写 `lossless` |
| 沉浸声 `immerseType: ste` | 请求原样透传，换源后返回普通立体声 |

---

## 诊断工具

仓库自带几个探针，排障时很有用：

```bash
# 单曲直连网易，看真实响应（不走代理）
node tools/probe_eapi.js 185811

# 批量探测：统计「会换源 / 可播 / 灰歌」
node tools/probe_batch.js 周杰伦 五月天

# 任意接口探测，支持走代理
node tools/probe_api.js /api/song/lyric/v1

# 直连 vs 代理逐字节对比（验证代理没破坏接口）
node tools/cmp_eapi.js /api/resource/commentInfo/list
```

---

## 致谢

- [UnblockNeteaseMusic/server](https://github.com/UnblockNeteaseMusic/server) —— 上游实现
- [zhongjieyang/UnblockNeteaseMusic](https://github.com/zhongjieyang/UnblockNeteaseMusic) —— enhanced 分支
- 所有逆向 eapi 协议的研究者

## License

[LGPL-3.0-only](COPYING.LESSER) —— 与上游保持一致。
`src/` 下所有改动同样以 LGPL-3.0 发布。
