# Charles 5.2.2 简体中文语言包（含授权补丁）

给 [Charles](https://www.charlesproxy.com/) 5.2.2 用的简体中文语言包：把界面文本汉化，并移除“30 天试用 / 未授权只能运行 30 分钟”的限制。

- 适配版本：**Charles 5.2.2**（`lib/charles.jar`，Java 模块 `com.charlesproxy`，官方自带 JRE 25 的 Windows 版）
- 语言包形态：替换 `lib/charles.jar` 一个文件即可，**汉化与授权同时生效**
- 覆盖范围：菜单栏、工具栏、工具面板、设置项、会话标签页、概览字段、状态栏、右键菜单、对话框
- 保留英文：`HTTP/HTTPS/TLS/Cookie/WebSocket`、HTTP 标头名、域名、URL、文件格式名 —— 避免影响抓包与导出

> 本仓库仅包含**修改后的 jar 与文本词库**，不含 Charles 原版安装包。Charles 是 XK72 的商业软件，请自行获取正版安装包；本项目仅供个人学习与研究使用。

---

## 下载

| 项目 | 地址 |
| --- | --- |
| **官方安装包（必需，版本须为 5.2.2）** | [Charles 下载页](https://www.charlesproxy.com/download/) · [Windows x64 MSI 直链](https://www.charlesproxy.com/assets/release/5.2.2/charles-proxy-5.2.2-win-x86_64.msi) · [Windows x64 APPX 直链](https://www.charlesproxy.com/assets/release/5.2.2/charles-proxy-5.2.2-win-x86_64.appx) |
| 历史版本 | <https://www.charlesproxy.com/download/previous-release/> |
| 本语言包（一键包） | [Releases · Charles-5.2.2-CN-v1.0.zip](https://github.com/lieovoa-hue/charles-cn/releases/latest) |
| 只要 jar | 仓库内 `dist/charles-zh.jar` |

> 语言包不含官方程序，需要先安装官方 Charles **5.2.2** 再覆盖 `lib\charles.jar`。
> 推荐用 **MSI** 包安装（安装目录可控、无包签名校验）；APPX/MSIX 安装在
> `C:\Program Files\WindowsApps\…`，受系统保护且带签名校验，不适合直接替换文件。
> 其它版本（5.2.1、5.3.x…）的 jar 结构可能不同，语言包未做适配。

压缩包内已含 `dist/charles-zh.jar`、`scripts/安装汉化.bat`、`scripts/还原原版.bat`、`tools/汉化词库.tsv` 与本文档。

## 目录结构

```
charles-cn/
├── dist/
│   └── charles-zh.jar        # 已汉化 + 已授权的 charles.jar（5.9 MB）
├── scripts/
│   ├── 安装汉化.bat           # 一键安装：备份原 jar 并替换
│   └── 还原原版.bat           # 一键回滚
├── tools/
│   └── 汉化词库.tsv           # 565 条中英对照词条，可自行改译后重新构建
└── README.md
```

---

## 快速开始

### 方式 A：替换现有安装的 jar（推荐）

1. 完全退出 Charles（含任务栏托盘图标）。
2. 解压本仓库，双击 `scripts/安装汉化.bat`。
3. 按提示输入 Charles 安装根目录（该目录下应存在 `lib\charles.jar`），例如：
   ```
   D:\Program Files\Charles
   ```
   直接回车则使用脚本所在目录。
4. 脚本会自动把原版备份为 `lib\charles.jar.orig`，再写入汉化版。
5. 重新启动 Charles → 中文界面 + 已授权。

手动等价操作：

```powershell
Copy-Item "<Charles安装目录>\lib\charles.jar" "<Charles安装目录>\lib\charles.jar.orig"   # 备份
Copy-Item ".\dist\charles-zh.jar" "<Charles安装目录>\lib\charles.jar" -Force               # 覆盖
```

测试过的环境：Windows 10/11 x64，官方 Windows 安装包（zip 便携版同样适用）。

### 方式 B：便携版目录（不改动已有安装）

1. 取一份官方 Charles 5.2.2 Windows 便携包并解压到任意目录。
2. 用 `dist\charles-zh.jar` 覆盖其中的 `lib\charles.jar`。
3. 双击 `Charles.exe` 启动。

若希望配置与证书不写入 `%APPDATA%`，在 `Charles.ini` 的 `[Java]` 段追加两行（路径按需修改）：

```ini
vmarg.14=-Dcharles.data=.\data
vmarg.16=-Dcharles.config=.\data\charles.config
```

这样设置文件、CA 证书、密钥库都会落在程序目录下的 `data\`，删除该目录即恢复全新状态。

### 方式 C：只想要汉化、不要授权补丁

用本项目 `tools/汉化词库.tsv` 自行构建（见下文「如何构建」），但在补丁清单里删掉 `HoYV` / `eZEl` 三条，只保留文本替换即可。

---

## 如何验证生效

| 检查点 | 正常表现 |
| --- | --- |
| 菜单栏 | 文件 / 编辑 / 视图 / 代理 / 工具 / 窗口 / 帮助 |
| 会话标签页 | 概览 / 内容 / SSL / 摘要 / 图表 / 备注 |
| 概览字段 | 方法、状态、备注、响应代码、内容类型、客户端地址、远程地址、协议、标签、长连接、计时、耗时、连接、TLS 握手、请求、响应、延迟、速度、大小、总计 |
| 状态栏 | 已开始记录 / 过滤 / 记录中 |
| 授权 | 「帮助」菜单显示「注册给 Charles CN」，不再出现“输入 Charles 许可证…” |
| 启动提示 | 不再出现 “This is a 30 day trial version…” |

---

## 常见问题

**Q：重启后还是英文？**
确认 `lib\charles.jar` 已被替换（比对文件大小：汉化版约 5.9 MB / 6167137 字节），且 Charles 进程已完全退出后重启。

**Q：Microsoft Store（MSIX）版能直接用吗？**
不建议。Store 版程序目录位于 `C:\Program Files\WindowsApps\…`，受系统 ACL 保护，且包内 `AppxBlockMap.xml` + `AppxSignature.p7x` 会校验文件哈希，直接替换会导致包校验失败；商店更新也会覆盖回去。Store 版请改用方式 B 的便携目录。

**Q：启动报 `Module com.charlesproxy not found`？**
`charles.jar` 写坏了（下载不完整或覆盖中断）。用 `scripts/还原原版.bat` 回滚，或重新解压官方包后重做一次。

**Q：提示 `拒绝访问 … RoamingState` / 配置无法保存？**
说明在包容器外运行 Store 版程序。改用方式 B，或按上文追加 `-Dcharles.data` / `-Dcharles.config`。

**Q：怎么回滚？**
运行 `scripts/还原原版.bat`（使用 `lib\charles.jar.orig`），或重新解压官方包。

**Q：会影响抓包功能吗？**
不会。补丁只改 Java 层的界面文本与许可证判定，代理引擎、证书处理、映射/重写/断点等功能逻辑未改动。

---

## 实现原理

1. **解包**：`jar xf charles.jar`，2461 个 class；界面文本集中在资源包
   `com/charlesproxy/strings*.properties` 与常量池中的 `ldc` 字符串。
2. **定位可汉化文本（四层命中，避免误伤逻辑）**
   - 显示调用点：`ldc "文本"` 紧跟 `JLabel/JButton/JCheckBox/JMenuItem/JTabbedPane/JOptionPane` 构造，或 `setText / setToolTipText / setTitle / addTab / addColumn / showMessageDialog` 的 `String` 参数；
   - 返回 Swing/AWT 类型的工具方法参数；
   - `gui/transaction/**`、`gui/session/tables/**`、`gui/frames/**` 中的名称提供方法（`()Ljava/lang/String;`）；
   - 少量精确规则（状态栏、树节点等）。
3. **安全护栏**
   - 黑名单：`Name`、`string`、`ShortDescription`、`MnemonicKey`、`ActionCommand`、`Selected` 等标识符永不翻译；
   - 全大写字符串视为 ID 跳过；大小写回退仅对首字母大写的文本启用；
   - `gui/actions/**`（Action 注册表）整包跳过。
4. **授权补丁（字节码级，3 个方法）**

   | 类.方法 | 原语义 | 补丁后 |
   | --- | --- | --- |
   | `com.charlesproxy.HoYV.yPDK()Z` | 返回单例字段 `Oezn`（是否已注册） | `iconst_1; ireturn` |
   | `com.charlesproxy.HoYV.xGrV()Ljava/lang/String;` | 返回注册名 | `ldc "Charles CN"; areturn` |
   | `com.charlesproxy.eZEl.run()V` | 未授权 30 分钟到期弹窗并退出 | `return` |

5. **重新打包**：按原 zip 顺序写回（丢弃 `META-INF/*.SF/*.RSA` 等签名），保持模块描述符不变。

统计：class 常量池替换 509 处，资源包替换 355 处，精确规则 14 条，词库 565 条。

---

## 如何构建（可选）

需要一个 JDK 21+（推荐 25，使用 `java.lang.classfile`）与 Python 3：

```bash
# 1. 解包官方 jar
python unpack.py charles.jar ./jar

# 2. 生成资源包译文
python translate_props.py ./jar ./res_override

# 3. 改写 class 常量池 + 打补丁（CharLoc 见 tools/ 说明）
java -Dfile.encoding=UTF-8 -cp jloc CharLoc build ./jar ./tools/汉化词库.tsv ./jar_patched \
     --patches patches.tsv --force force.tsv --display-only --lib ./lib

# 4. 重新打包
python repack.py ./lib/charles.jar ./jar_patched ./res_override ./dist/charles-zh.jar
```

改译法：直接编辑 `tools/汉化词库.tsv` 右侧中文（`原文<TAB>译文`），重跑第 2~4 步。

---

## 更新日志

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| v1.0 | 2026-10-28 | 首个版本：Charles 5.2.2 简体中文 + 授权补丁，词库 565 条 |

---

## 声明

- Charles 版权归 [XK72 Ltd](https://www.charlesproxy.com/) 所有，本项目不提供原版程序。
- 语言包与脚本仅供个人学习、研究与本地测试；请在条件允许时购买正版授权。
- 使用本补丁产生的一切后果由使用者自行承担。