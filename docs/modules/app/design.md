# App · 设计

`main.swift` 在 run 前设置 accessory（无 Dock 图标）；`AppDelegate` 在 MainActor 组装 SettingsWindow、菜单栏、EventTap、WindowCache 和 PanelController。

菜单栏先建立，停用/缺权限/监听失败时仍可打开设置。启用时检查 AX 权限并启动 tap 和 cache；失败显示本地化提示、总开关回关，不假装启用。屏幕录制缺失不阻止切窗，仅影响预览。授权后提示重启。

总开关关闭立即 dismiss 和 configure(false)，释放键盘，保留其余偏好；再次开启复用 tap，无需正常运行期间重启。连续超时兜底关闭总开关、取消会话并提示原生 ⌘Tab 已恢复。

## 接线

- tap effects → panel.handle；panel 失焦/停用 → tap.cancelSession。
- panel.onActivate → WindowActivator.activate + cache.noteActivated。
- panel.onRefresh → cache.refresh；cache.onChange → AppIcons.warm + WindowThumbnails.warm(allWindows) + panel.setWindows。
- panel.onClosed → cache.noteClosed；onCloseFinished → tap.completeClose（revision 校验）。
- panel.onOpenSettings / 菜单栏 → settingsWindow.show。
- settingsWindow.onChange → 重建菜单文案；总开关改变时启停接管。语言即时保存，面板下次展示读取；真实 app 名/标题不翻译。

## 设置

720×510pt 原生 AppKit 窗口，纯色扁平侧栏 General/Appearance/Shortcuts/About，无毛玻璃或按钮边框，选中项用淡色背景。窗口使用 floating 层级、moveToActiveSpace/fullScreenAuxiliary，并显式 orderFrontRegardless，避免非激活面板退出后设置落在其他窗口后。About 仅名称、版本与仓库链接。Settings 注入 UserDefaults 供测试；未选语言（包括升级用户）默认英文。现有颜色/玻璃/圆角偏好保留，新默认面板圆角 20pt。

登录项直接使用 ServiceManagement 的 SMAppService.mainApp，不复制一份真假状态到 defaults。窗口成为 key 时重读状态；注册/注销期间禁用控件；需要批准、找不到 app、调用失败分别显示系统状态或错误。默认不注册。About 从 bundle 读取版本并链接项目仓库。

## 验证与限制

测试覆盖设置持久化、语言控件动作、tap 接管/撤销及异步关闭联动。系统批准、真实登录启动、TCC、macOS 全局按键与焦点需要真机验收。安全输入时原生 ⌘Tab 接管是预期降级。
