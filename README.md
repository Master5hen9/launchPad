# launchPad

这是一个复刻 macOS 启动台的项目。由于苹果在 macOS 26 删除了启动台,所以需要以应用的形式将其添加回来。

## 运行

需要 macOS 26 和 Swift 6.2+ 工具链(Command Line Tools 即可,无需 Xcode):

```sh
swift run launchPad
```

启动后应用常驻(无窗口)。打开启动台的方式:

- 触控板四指(或五指)聚拢
- 点击 Dock 中的应用图标(再次点击可关闭)
- 调试用:`swift run launchPad --show`(启动后立即打开)

关闭启动台:按 `Esc`,或点击应用图标之外的空白区域;点击应用图标会启动该应用并自动关闭启动台。

## 设置

应用菜单(Cmd+,)中有「设置」:

- **四指(或五指)聚拢打开**:开关触控板手势,设置保存在 `com.ming.launchpad` 偏好里
- **开机自启动**:一键安装/卸载登录项。安装后会打包生成 `~/Applications/launchPad.app` 并注册 LaunchAgent,下次登录自动运行

命令行方式:

```sh
swift run launchPad --install-login-item    # 安装登录项
swift run launchPad --uninstall-login-item  # 卸载登录项
```

注意:日常调试用 `swift run` 即可;**安装登录项请用 Release 构建**,否则动画(尤其图标飞入)会因未优化而掉帧:

```sh
swift run -c release launchPad --install-login-item
```

## 测试

```sh
swift run launchPadTests
```

说明:当前环境(仅有 Command Line Tools)下 `swift test` 无法发现 Swift Testing 测试,所以测试以可执行程序方式运行;安装完整 Xcode 后可直接使用 `swift test`。

## 功能

- 扫描 `/System/Applications`、`/Applications` 和 `~/Applications`
- 全屏展示应用图标与名称,背景为高斯模糊(系统 `fullScreenUI` 材质)
- 按屏幕大小分页展示,左右滑动翻页,底部有页面指示点(可点击跳页)
- 打开时图标从中心缩放浮现,带逐项延迟动画
- 点击启动应用并自动关闭
- 顶部搜索框实时过滤
- 右键菜单:启动 / 在 Finder 中显示
- 触控板四指/五指聚拢手势唤起(全局监听,应用需保持运行)
- 开机自启动登录项(应用内一键安装/卸载)

注意:手势检测依赖真实触控板验证(事件监听基于系统公开的 `.gesture` 事件与触摸数据);如果你的触控板设置里该手势被系统占用,请在「系统设置 → 触控板」中调整为「无」。
