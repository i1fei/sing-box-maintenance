# sing-box 维护脚本合集

适用环境：VPS 上通过 [233boy/sing-box 脚本](https://github.com/233boy/sing-box) 部署的 sing-box 服务端。
默认假设：配置文件在 `/etc/sing-box/config.json`，访问日志在 `/var/log/sing-box/access.log`，
服务由 systemd 管理，服务名为 `sing-box`。如果实际路径/服务名不同，改一下各脚本开头的变量即可。

## 包含内容

| 脚本 | 作用 | 是否修改 sing-box 本身 |
|---|---|---|
| `scripts/01-fix-adblock.sh` | 在 `dns.rules` / `route.rule_set` 加入广告域名拒绝解析规则，恢复去广告能力 | 是，直接改 `config.json` 并重启服务 |
| `scripts/02-setup-logrotate.sh` | 写入 `/etc/logrotate.d/sing-box`，让系统级 logrotate 接管日志的循环保留（默认 30 天，可改） | 否，只操作日志文件本身，不碰 sing-box 配置/服务 |
| `scripts/03-check-schedule.sh` | 只读检测：确认系统已有自动机制（`logrotate.timer` 或 `cron.daily`）会按天触发 logrotate | 否，纯检测，不做任何修改 |
| `scripts/04-setup-keepalive.sh` | 保活：优化崩溃重启参数（间隔 + 不限重试次数）+ 新建每日定时重启的 service/timer | 否，只新增 systemd override 和独立的 restart service/timer，不碰 `config.json` |
| `scripts/run-all.sh` | 按顺序依次执行以上四个脚本 | 见上 |

## 设计要点（背景信息，供后续维护/改造参考）

- **去广告的原理**：sing-box 的 DNS 模块支持"域名命中规则集 → 直接拒绝解析"，这是原生能力，
  不需要额外起 AdGuardHome / SmartDNS 之类的服务。规则集来源用的是官方
  `geosite-category-ads-all`（`https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs`），
  如果该地址下载慢/不通，可以换成社区镜像仓库（如 `DustinWin/ruleset_geodata`、
  `YuanLi-Tech/sing-box_ADBlock-Rules`）里的同名 `.srs` 文件，内容一致。
- **01 脚本的校验方式**：233boy 脚本自带的 `sing-box test` 命令在服务已运行时会直接跳过、
  不做真实语法校验（实测输出 "sing-box 正在运行, 跳过测试"），不能作为可靠的失败判定依据。
  因此改用"重启后检查 `systemctl is-active`"来判断配置是否真的生效，如果服务没能正常拉起，
  会自动回滚到执行前的备份（`config.json.bak.<时间戳>`）。
- **02 脚本为什么不用 `delaycompress`**：早期版本加了 `delaycompress`，效果是"这一轮先不压缩，
  等下一轮才压缩上一份"，导致已经很大的日志文件要再等一整天才会被压缩瘦身，白占磁盘。
  现在去掉了这个选项，轮转即压缩；同时脚本本身也会扫描并压缩历史遗留的未压缩日志文件，
  避免旧文件一直占用空间。
- **02 脚本用 `copytruncate` 而不是常规的重命名轮转**：因为 sing-box 没有"收到信号后重新打开
  日志文件"的机制，用常规轮转会导致进程持续写入一个已经被改名/删除的文件（磁盘空间不会真正
  释放）。`copytruncate` 是原地复制后清空文件，不需要重启或通知 sing-box 进程，兼容性最好。
- **03 脚本存在的意义**：`logrotate` 装好之后不会自己运行，需要靠系统的
  `systemd timer`（较新发行版）或传统 `cron.daily`（较老发行版）按天触发它，这一步只是确认
  该机制已经存在，绝大多数标准 Linux 发行版默认就有，不需要额外新建计划任务或系统服务。
- **04 脚本的两层保活逻辑**：233boy 脚本生成的原始 unit 已经带了 `Restart=on-failure`，
  所以崩溃后会重启这件事本身不用重新配置；04 脚本只是通过 `override.conf`（而不是直接改
  原始 unit，避免升级时被覆盖）补两个细节参数——`RestartSec` 让重启前有个缓冲，
  `StartLimitIntervalSec=0` 取消 systemd 默认的"短时间内重启太多次就放弃拉起"限制。
  定时重启是完全独立的一套 service + timer（`<SERVICE_NAME>-restart.*`），不修改原
  `sing-box.service`，逻辑上和崩溃重启互不影响。
- **04 脚本为什么不用 cron 而用 systemd timer**：和 03 脚本检测的对象是同一套体系，
  日志统一走 `journalctl`，且 `systemctl list-timers` 能直接看到下次触发时间，比 crontab
  更方便排查。如果目标机器没有 systemd（少见），需要改用 crontab 方式实现，当前脚本不处理
  这种情况。

## 使用方法

```bash
sudo bash scripts/run-all.sh
```

或者按需单独执行某一个：

```bash
sudo bash scripts/01-fix-adblock.sh
sudo bash scripts/02-setup-logrotate.sh
sudo bash scripts/03-check-schedule.sh
sudo bash scripts/04-setup-keepalive.sh
```

所有脚本都设计为**幂等**：重复执行不会产生重复的规则/重复的 crontab 条目，可以放心重复跑。

## 已知限制 / 可以改进的方向

- 目前只检测/管理了单一日志文件 `access.log`；如果 sing-box 配置中还有额外的日志输出路径，
  需要在 `02-setup-logrotate.sh` 里追加对应的 stanza。
- `01-fix-adblock.sh` 目前只加了一条广告规则集；如果想同时做 CN 域名分流、fakeip 等，需要在
  同一个 `jq` 表达式里继续扩展 `.dns.rules` / `.route.rule_set`。
- 目前假设服务名固定为 `sing-box`；如果实际 systemd unit 名称不同，需要同步修改
  `SERVICE_NAME` 变量（01、04 两个脚本里都有，需要一起改）。
- `04-setup-keepalive.sh` 的定时重启时间默认凌晨 4 点，写死在脚本开头的 `RESTART_TIME`
  变量里；如果是多用户/多节点场景，建议改成流量最低谷的时段，避免重启瞬间断开连接。
- `04-setup-keepalive.sh` 依赖 systemd，没有适配纯 cron / OpenRC 等其他 init 系统的场景。
