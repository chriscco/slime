# Panel · 设计

## 职责与边界

`PanelWindow` 是 nonactivating 浮动面板；`PanelController` 维护查询、真实窗口身份、选择与会话 generation。键盘只由 EventTap 驱动，面板不运行第二个 reducer。枚举和 AX 由 System 层负责。

## 布局与渲染（0.0.5）

- `GridLayout`：固定五列，200×160pt 卡片、12pt 间隔、20pt padding、52pt 搜索区。未分组 0–5 项为 1088×252pt；超过三行滚动。屏幕可用宽度减 40pt 后不足时缩小预览，标题字号不变；总高也不超过屏幕可用高减 40pt。
- 分组开启时按结果中 app 首次出现排序，组内保留搜索排名。每组另起行，28pt 图标/名称标题；高度按内容增长至三行卡片的可视上限，更多滚动。`rowStarts` 描述实际占用的行，方向键不会落入空槽或标题。
- `PanelContentView`：搜索展示、关闭状态提示、滚动网格、空态。先确定窗口尺寸和布局，再 render；document 宽度由 scroll view 传入。
- `CardGridView` 按 windowID 复用视图。高亮为 13% 同色底（14pt 圆角）和 32×4pt 下划线；同行从 presentation layer 当前位置向新目标移动 300ms，连续采样位置和宽度曲线，宽度先伸展（上限 52pt）再收回 32pt；同一选择的异步刷新不打断在途动画，快速重定向不累加伸长，跨行及首尾循环使用 240ms 线→4pt 点→线飞行动画，前 54ms 在起点拉长并收成点，中间 120ms 全程保持 4×4pt 飞行，最后 66ms 在落点展开至 38pt 后收回 32pt；位置单次回弹最多 6pt，位置和宽度均平滑插值，底色独立淡化 160ms。Reduce Motion 直接更新选中。
- `WindowPreviewView` 对 aspect-fit 后的实际图片区域做 10pt 圆角裁切，含纵向图。优先真实图及同窗口缓存；无图绘制通用小窗口、静态示意线和 app 图标。标题保持真实内容，tooltip/辅助功能说明不可预览。
- 面板固定暗色 appearance，与既有黑底遮罩保持文字对比度；设置窗口遵循系统外观。面板默认圆角 20pt，用户已有偏好保留。

## 会话和关闭

show/hide 推进 session generation；缩略图等待最长 300ms，旧等待回调不能打开新/已结束的会话。外部失焦、停用由 dismiss 同时取消 tap 会话。

⌘D 捕获窗口和相邻窗口身份，进入 closing；后台关闭和预览动画并行，二者完成后才移除卡片。动画只作用预览快照：画面垂直收缩并提亮，独立的 2pt 发光横线水平收成点，4pt 亮点短闪和余辉消失，总长 560ms；画面、横线、亮点分别动画，避免把光晕也压成硬边矩形；Reduce Motion 为 120ms 淡出。

closing 期间缓存快照仍更新，但不重排可见卡片；禁止导航和再次关闭。关闭确认后通知 cache 删除目标，再选后邻居（末项选前邻居）；失败恢复预览和目标，并显示原因。Esc/设置/停用可结束会话；旧任务仍可维护 cache，但不能修改新会话的选择、动画或键盘状态。

## 接口和验证

`handle(state:effects:)`、`setWindows(_:)`、`dismiss()`；`onActivate/onRefresh/onOpenSettings/onClosed/onCloseFinished/onCancelSession` 接外部边界。关闭函数可注入异步结果，测试通过真实 controller 验证确认、恢复和会话隔离。GridLayout/PanelLayout 测试验证尺寸、导航、身份复用、纵向图片圆角。

真实原生空白窗口 AX 关闭及下划线连续帧采样已通过；实际键盘动态观感、五列相较旧 240×176 的辨识度仍需真机验收；离屏渲染不能验证玻璃合成、系统焦点或动画手感。

## 已知限制

搜索框仅展示 Effect 更新的文本，不支持 IME；不做鼠标选窗。缩略图随窗口快照更新，不承诺实时视频。五列的新尺寸仍是待真机校准提案，详见 0.0.5 spec。
