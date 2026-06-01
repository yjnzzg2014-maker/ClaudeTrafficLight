# Claude Traffic Light

macOS 红绿灯状态指示器，通过 Claude Code hooks 实时显示工作状态。

基于 [ooaaeiei2-beep/CodexTrafficLight](https://github.com/ooaaeiei2-beep/CodexTrafficLight) 适配。

## 效果

| 状态 | 灯光 | 说明 |
|---|---|---|
| 思考中 | 绿灯呼吸 | Claude 正在处理请求 |
| 需要确认 | 黄灯急闪 + 8s 通知 | Claude 等待审批 |
| 空闲 | 红灯常亮 | Claude 回合结束 |

两个显示位置：
- **菜单栏** — 小型红绿灯图标
- **桌面悬浮窗** — 可拖拽的大号红绿灯，始终置顶，可在菜单栏开关

## 安装

```bash
cd ClaudeTrafficLight

# 编译
./build.sh

# 安装 hooks（自动合并到 ~/.claude/settings.json）
./install_hooks.sh

# 初始化状态文件
echo "idle" > /tmp/claude_traffic_light_state

# 启动
open ../ClaudeTrafficLight.app
```

## 使用

- 点击菜单栏图标 → 显示状态、打开终端、开关悬浮窗、退出
- 悬浮窗可拖拽到屏幕任意位置
- 黄灯 8 秒后弹系统通知，点通知切到终端
- 空闲时显示「上次思考 X 分 X 秒」

## 开机自启

系统设置 → 通用 → 登录项 → 添加 `ClaudeTrafficLight.app`

## Hook 事件映射

| Claude Code 事件 | 状态 | 含义 |
|---|---|---|
| `SessionStart` | idle | 会话启动 |
| `Stop` | idle | 回合结束 |
| `PreToolUse` | working | 工具执行前 |
| `PostToolUse` | working | 工具执行后 |
| `Notification` | input | 等待审批 |

## 手动测试

```bash
echo "working" > /tmp/claude_traffic_light_state   # 绿灯
echo "input"   > /tmp/claude_traffic_light_state   # 黄灯
echo "idle"    > /tmp/claude_traffic_light_state   # 红灯
```
