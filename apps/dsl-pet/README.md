# DSLPet 开发说明

项目简介、安装方法、播放规则与许可证见 [根目录 README](../../README.md)。

## 构建

从仓库根目录执行：

```sh
python3 apps/dsl-pet/scripts/build.py
```

脚本使用系统 Swift 编译器构建原生 AppKit 应用，读取本目录独立的 `assets/`，复制控制桥和回复桥，生成 `dist/DSLPet.app` 并进行 ad-hoc 签名，最后运行内置状态机自检。

当前应用版本 0.4.0，Bundle Build 9。已验证 macOS Apple Silicon，最低系统版本 macOS 13。无图片生成服务或 OpenCV 运行依赖。

## 源码结构

| 文件 | 责任 |
| --- | --- |
| `Sources/Engine.swift` | 动画播放、状态转换、随机选择、终帧保持与空闲计时 |
| `Sources/App.swift` | 原生窗口、拖动、菜单、IPC 命令、状态输出与活动检测 |
| `Sources/Notices.swift` | 铃铛、消息气泡、分页和通知 |
| `Sources/Reply.swift` | 回复输入气泡、发送与草稿 |
| `Sources/main.swift` | 应用入口及状态机自检 |
| `scripts/bridge.py` | 文件 IPC 和 stdio MCP |
| `scripts/reply.py` | 当前本地 Codex thread owner 的回复传输 |

## 验证

构建自检覆盖全部 25 组动画，以及接单 1 秒停留、纠正 2 秒停留、停止中断、完成无限保持、互动队列、循环 1 秒间隔、空闲 1.5 倍慢放 / 3 次重复与递增计时。

本机此前完成过原生播放器、气泡分页、缩放、双击激活和回复输入界面检查。回复传输通过本地协议检查及真实 owner 的只读发现；完整真实模型回复流程尚待实际使用验证。

`bridge.py snapshot` 保存当前播放器的缓存渲染到用户运行目录中的 `preview.png`；这是播放器缓存，不是桌面全屏截图。

## 素材

157 张 PNG：156 张动画帧和 1 张待机图，另有 26 个时序 / 索引 JSON。素材独立存放于本项目，不依赖原素材仓库。

0.4.0 新增敲电脑、放大镜查资料、拿本子认真推敲、掰手指数数。后两组共用第 1、2、5、6 帧，只替换中间两帧；新动作每轮 2.10 秒，轮间沿用 1 秒停留。自行车篮去掉大饭碗，保留筷子，并加入电脑和放大镜；原出入场的移动、终帧和时序保持。

素材权利独立于代码的 MIT 许可，见 [素材权利声明](../../ASSET_RIGHTS.md)。

## 安装配套应用和插件

从仓库根目录完成构建后，将应用安装到控制桥约定的位置：

```sh
# 更新前从桌宠菜单退出旧版；保留用户设置
mkdir -p "$HOME/Applications"
cp -R apps/dsl-pet/dist/DSLPet.app "$HOME/Applications/"
open "$HOME/Applications/DSLPet.app"

# 注册当前仓库的本地市场并安装插件
codex plugin marketplace add .
codex plugin add dsl-pet@q-ai-local
```

若客户端没有 `codex` 命令或不支持本地市场，应先说明该限制；不要将本插件装成官方 Pets 的宠物皮肤。已有同名市场时检查其路径，避免覆盖其他工作区的配置。安装后按客户端提示重载插件或重新打开聊天，再确认 `dsl_pet_status` 工具可用且桌宠运行。

应用与官方 Pets 使用不同的应用、插件包和控制桥。本插件不调用官方宠物的上传或选择接口，安装时保留官方 Pets 的安装状态与选择。

插件安装方式参考 [OpenAI 官方插件文档](https://developers.openai.com/plugins/build/plugins)。
