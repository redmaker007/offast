# 关卡引擎设计

目标：在游戏里做一个 GM 模式的编辑器，**用它完全取代 Godot 编辑器来做内容**。
玩家和开发者用的是同一套东西，导出后的游戏也能编辑（入口以后藏起来让玩家自己找）。
所以现在所有的内容——剧本、世界设定、房间布局——最终都要转成这个引擎的格式。

这份文档记的是 2026-10-23 讨论定下来的架构，以及第 0 阶段落地的文件格式。

---

## 1. 分层

| 层 | 内容 | 原则 |
|---|---|---|
| 数据 | 关卡图（外层）、天内图（内层）、背景设定、世界数据表 | 只存结构、坐标、数值和文字，存成 JSON |
| 执行 | 解释器，照着图一步步跑 | 不认识编辑器，只吃数据 |
| 编辑 | GM 模式下的 2D 画布 + 表单 | 用 Godot 自带的 `GraphEdit` / `GraphNode`（运行时也能用） |

**校验器是独立的纯函数**：输入一份关卡，输出全部错误。编辑器即时标红、游戏启动前拦截、
无头测试，三处共用这一份。

**代码和内容的分界线**：代码只提供「元件类型、内建 app、玩法规则」；
所有文字、数值、布局、素材都是可编辑的内容。

---

## 2. 外层：关卡图

节点三种：

| 类型 | 说明 | 出口 |
|---|---|---|
| `day` 天节点 | `role` 是 `start`（初始天）/ `normal` / `ending`（结局天）。里面装一张天内图 | `next`：一个，结局天没有 |
| `brancher` 分化器 | 一组**有顺序**的条件，第一个成立的算数（和原来的结局规则一样） | `case_1`…`case_n` 各一个，外加**必须有**的 `else` |
| `jumper` 天数跳转器 | 改天数，时空跳跃用。`mode` 是 `set`（设成 N）或 `add`（加减 N） | `next`：一个 |

- 条件语法沿用 `story_condition`（`score.A>=2`、`did(fire,Rick,day3)` 之类），自带语法检查。
- **天数**：初始天是第 1 天，之后每进一个天节点 +1，结局天也算一天。天数跳转器可以改它。
- **历史按「第几次经过」记流水账**（顺序、天节点 id、当时的天数），不能只拿天数当 key——
  有了时空跳跃，「第 3 天」可能出现两次。条件里写的 `day3` 指**最近一次**天数为 3 的那天。
- 每天开始时存一份快照，以后要做「倒回当时的状态」不用改存档格式。

## 3. 内层：天内图

| 类型 | 说明 | 出口 |
|---|---|---|
| `start` | 一天的入口，每张天内图恰好一个 | `next` |
| `free_play` 自由环节 | **枢纽**：进入时让接在 `listen` 上的所有可互动物件同时进入监听；也是**唯一的存档点**。带时钟设置 | `listen`（多个，只能接可互动物件）、`time_up`（到点，必须接） |
| `interactable` 可互动物件 | 引用房间里的一个物件。`unlock` 是条件，成立才响应点击；`repeat` 决定能不能重复触发 | `next` |
| `story_bubble` 剧情 bubble | 一段对话，保留 `.story` 的文字语法（选项、效果、`goto`、`?if`） | `next` |
| `window_bubble` 视窗 bubble | 强制打开某个物件自带的弹窗（电脑 app、电话……），可以指定落在哪一页 | `next` |
| `send_mail` 发信 | 发出一批邮件，邮件内容存在节点里 | `next` |
| `effect` 效果 | 可带条件：成立才改变量、设 flag（原来的 `[score]` 就是一串这个） | `next` |
| `show_result` / `show_log` | 显示每日结算 / 人事日志 | `next` |
| `day_end` 天结束 | 这一天结束，回外层走 `next` | 无 |
| `if` 条件分支 | 强制链里瞬间判一次条件，第一个成立的走，和外层分化器同一套 | `case_1`…`case_n`、`else` |
| `clock_out` 下班 | 停钟、收窗口、判分、记人事日志、扣命。`[score]` 的效果要排在它后面（规则查的就是当天日志） | `next` |
| `show_ending` 结局卡 | 显示 `props.ending` 那个结局的结局卡 | `next` |

可互动物件的参数：`object`（房间物件 id）、`unlock`（条件，空 = 一直解锁，每次点击时重新判）、
`repeat`（能不能重复触发）、`non_blocking`（为真时强制链期间这个物件也不锁，比如便签：
要能一边看笔记一边输密码）。

**强制链**：从 `start`、某个可互动物件的 `next`、或某个自由环节的 `time_up` 出发，经过的
剧情、视窗、发信、效果、条件分支、结算、日志都是强制的（播放期间锁住所有物件，`non_blocking`
的除外，用 `cutscene` 那把锁）。
**强制链必须收在某个自由环节或 `day_end` 上**——这就是「自由环节是所有强制元件的出口」。
中途回主菜单就退回链开始前的那个自由环节。

**物件的弹窗显式连线**：点电脑打开电脑 app 也要画出来（自由环节 → 电脑 → 视窗(电脑) → 回自由环节），
没有隐藏规则。哪天不想让电脑能开，删掉这条线就行。

**逻辑全部基于状态**（2026-10-24 定），不做「事件到齐才触发」的 AND 节点：

- **if**：上面的条件分支节点。门就是瞬发判定：门 → if `inbox_empty` → 下班结算 / 否则提示「活还没干完」。
- **and / or**：写在条件里（`flag:a and flag:b`）。编辑器以后可以做可视化条件编辑器，存下来还是这串文字。
- **counter**：背景设定里定义变量 → 效果节点 `deltas` 给它 +1 → 条件里写 `var.mails_read>=3`。

条件语法在 `story_condition` 原有原子之外新增：`var.名字`（读自定义变量，A/B/C/D 也是变量，
`var.A` 和 `score.A` 是同一个值）、`inbox_empty`（收件箱清空）。`var.` 引用了没定义的变量由校验器报
`UNKNOWN_VARIABLE`。

## 4. 背景设定

- `lives`：命数。现在只有 3 一个选项。
- `fired_ending`：被开除（命掉光）时去哪个结局天。被开除不画在图上，是全局中断。
- `variables`：自定义变量（结局分线、派系、计数器），取代写死的 A/B/C/D 和 A/B/GROUND。

## 5. 世界数据表

不属于某一天、整局都在的东西，用表单编辑：房间物件、账户（随机密码）、员工档案、
联系人和通话（随机号码）、随机名字池、结局卡文案。

**房间物件**（`world.objects`，第 3 阶段起游戏按它生成房间，场景里不再手摆）：

| 字段 | 含义 |
|---|---|
| `id` | 物件 id，也是生成出来的节点名（`Control/<id>_control/<id>`），天内图里的可互动物件按它引用 |
| `name` | 多语言显示名 |
| `texture` | 贴图的素材 id |
| `anchors` / `offsets` / `grow` | 和 Control 的锚点、偏移、生长方向一样（左上右下） |
| `scale` / `pivot` / `z` | 缩放、缩放原点、层级 |
| `clickable` | 能不能点（桌子是 false：不发光、不响应） |
| `glow` | 悬停时描边发光 |
| `hover` | 悬停放大和音效：`scale`、`volume`、`click_volume`、`hover_sound`、`click_sound`、`center_pivot` |
| `window` | 自带的弹窗（内建 app）：`laptop` / `notes` / `calendar` / `caller`，空 = 没有。视窗 bubble 按它开窗 |
| `camera` | 点击推近：`zoom`、`duration`、`enabled` |
| `faces` | 按剩余命数换图（日历）：`{"3": …, "2": …, "1": …, "0": …}` |

校验器会报 `BAD_WINDOW`（弹窗类型不认识）、`MISSING_ASSET`（素材找不到）、
`NO_WINDOW`（视窗 bubble 要开一个没有弹窗的物件）。

## 6. 其它约定

- **多语言**：每个文字字段直接存多个语言的值：`{"zh": "…", "en": "…"}`。UI 文字也收进引擎。
- **素材**：不做导入界面。内容里用「相对 `res://` 的路径」当素材 id（`theme/items/2t.png`）。
  玩家按同样的相对路径把文件丢进外部素材文件夹就会盖掉游戏自带的：先找 `<游戏目录>/assets/`
  （导出后的游戏才有），再找 `user://assets/`，都没有才用 `res://` 自带的。外部文件按扩展名直接读
  （png / jpg / webp / svg，mp3 / ogg / wav）。见 `main_game/engine/asset_library.gd`。
- **房间**：所有可互动物件是同一种元件，只是贴图、位置、热区、弹窗不同。需要房间布局编辑器。
- **内建 app**（电脑、便签、电话、日历）、主菜单、设置、存读档是**引擎外壳**，不开放编辑。
- **存储**：`res://levels/` 是原版，`user://levels/` 里有同名文件就用它覆盖。文件带版本号。
- **校验错误**存成「错误代码 + 参数」，显示时再翻成文字（翻译 key 是 `LEVEL_ERR_<代码>`，
  没有翻译就用代码里的中文模板）。

---

## 7. 文件格式（version 1）

```json
{
  "format": "offast-level",
  "version": 1,
  "settings": {
    "lives": 3,
    "fired_ending": "ending_e",
    "variables": [
      {"id": "A", "kind": "score", "name": {"zh": "A 派", "en": "Faction A"}}
    ]
  },
  "world": {
    "objects": [{"id": "laptop", "name": {"zh": "电脑", "en": "Laptop"}}]
  },
  "graph": {
    "nodes": {
      "day_1": {
        "type": "day",
        "pos": [0, 0],
        "props": {"role": "start", "name": {"zh": "第一天"}},
        "outs": {"next": ["branch_1"]},
        "body": {"nodes": {"start": {"type": "start", "pos": [0, 0], "props": {}, "outs": {"next": ["…"]}}}}
      }
    }
  }
}
```

- 节点用**稳定的字串 id** 做 key，不用数组下标：存档、条件、引用都靠它。
- `outs` 是「出口名 → 目标 id 数组」。单出口的数组最多一个元素。
- 只有 `day` 节点有 `body`（天内图）。

## 8. 校验规则和错误代码

外层：

| 代码 | 含义 |
|---|---|
| `LOAD_FAILED` | 关卡文件读不进来（找不到、JSON 坏了、版本太新），`detail` 是原因 |
| `START_COUNT` | 初始天不是恰好一个 |
| `NO_ENDING` | 没有结局天 |
| `UNREACHABLE` | 从入口走不到的节点（孤立节点） |
| `NO_PATH_TO_END` | 这个节点走不到任何结局（会被困在循环里） |
| `ENDING_HAS_EXIT` | 结局天接了出口 |
| `BAD_ROLE` / `BAD_JUMP_MODE` | 天节点的 role、跳转器的 mode 不认识 |
| `FIRED_ENDING_MISSING` / `FIRED_ENDING_NOT_ENDING` | 被开除去的结局没填，或者填的不是结局天 |
| `LIVES_INVALID` | 命数不在允许的选项里 |
| `DUP_VARIABLE` / `UNKNOWN_VARIABLE` | 变量重名 / 引用了没定义的变量 |
| `DUP_WORLD_ID` / `UNKNOWN_OBJECT` | 世界表里 id 重复 / 引用了不存在的房间物件 |

内外层共用：

| 代码 | 含义 |
|---|---|
| `UNKNOWN_TYPE` | 节点类型不认识 |
| `UNKNOWN_PORT` | 接了这个类型没有的出口 |
| `PORT_MISSING` | 必须接的出口没接 |
| `TOO_MANY_TARGETS` | 单出口接了多个目标 |
| `BAD_TARGET` | 连线指向不存在的节点 |
| `WRONG_TARGET_TYPE` | 连线指向的节点类型不对 |
| `BAD_CONDITION` | 条件语法错误（附带 `story_condition` 给的说明） |

内层：

| 代码 | 含义 |
|---|---|
| `DAY_BODY_MISSING` | 天节点没有天内图 |
| `DAY_START_COUNT` | 天内图的 `start` 不是恰好一个 |
| `DAY_NO_END` | 天内图里走不到 `day_end` |
| `CHAIN_LOOP` | 强制链绕回自己，永远收不到自由环节 |
| `NOT_LISTENED` | 可互动物件没有接在任何自由环节的 `listen` 上 |

连线指回 `start`、从 `listen` 以外的地方接到可互动物件，都报 `WRONG_TARGET_TYPE`。

每条错误都带 `day`（出错的天节点 id，外层错误为空）和 `node`（节点 id），能精准定位。

---

## 9. 阶段

| 阶段 | 内容 |
|---|---|
| 0 | 本文档、数据模型、读写、校验器、无头测试（没有界面） |
| 1 | 转换器：把现有 5 天 `.story` 和 `world.story` 转成新格式；外层执行接管换天和结局。线性图必须玩起来和现在一模一样 |
| 2 | 天内图执行：各元件接管 `round_manager` 的三段流程和 `event_page`。开工前先细谈逻辑门 |
| 3 | 房间数据化：8 个物件从 `main_scene` 搬进数据，加素材文件夹扫描 |
| 4 | GM 编辑器：外层画布 → 天内画布 → 表单 → 房间布局 → 剧本文字编辑框（即时语法检查） |
| 5 | 隐藏入口 |

## 10. 第 1 阶段现状

- `res://levels/main.level.json` 由转换器生成：
  `godot --headless --path <项目> -s res://tools/convert_story_to_level.gd`。
  结构是 day_1 → … → day_5 → `ending_branch`（条件照抄 `world.story` 的 `[ending]`，else 走 C）→ `end_A`…`end_E`，
  被开除去 `end_E`。天节点的 `props.plan` 指向用第几天的剧本，结局天的 `props.ending` 是结局 id。
- `round_manager` 开局前校验关卡，有错就弹出全部原因、不开局；每天结束问 `level_runner.advance()`
  要下一个天节点，走到结局天就通关；命掉光调 `fire()`。命数来自背景设定。
- `ending_director` 直接用关卡图走到的结局。直接发 `game_cleared` 信号（测试、调试）时才退回查规则表。
- 剧情、邮件、桥段仍然从 `day_N.story` 读。

## 10b. 第 2 阶段

拆成三步：

| 步 | 内容 | 状态 |
|---|---|---|
| 2a | 数据：条件语法扩展、`if` / `clock_out` / `show_ending`、`non_blocking`；转换器为现有 5 天生成**完整的显式天内图** | 完成 |
| 2b | 执行：天内图解释器接管一天的流程（取代 `round_manager` 的三段状态机），物件点击、门、电话都改走图 | 完成 |
| 2c | 内容搬家：剧情、邮件的文字从 `.story` 搬进节点 | 完成（世界设定除外） |

2a 之后的约定：
- 剧情 bubble / 发信节点暂时用 `props.source` 引用 `.story` 里的内容（`{"plan": 3, "part": "story"}`、
  `{"plan": 1, "event": "caller"}`、`{"ending": "A"}`、`{"plan": 2}`），2c 再换成 `props.script` / 邮件表单。
  一次性提示（「活还没干完」）已经直接存 `props.script`，文字取自 `ui.csv` 的全部语言。
- 桥段「今天播过了」用 flag `event_<物件>_day_<N>`，和原来 `event_page.flag_for` 同名，旧存档照样认。
- 被开除去单独的结局天 `end_E_fired`（只出结局卡）；从规则表走到的 `end_E` 要先摊日志、播结局对话。

2b 之后的运行方式：
- `day_runner`（`main_game/engine/day_runner.gd`）走天内图。`if` 和效果节点它自己算；
  其它强制元件交给 host（`round_manager.run_step`）执行，要等界面事件的（开场剧情、桥段、
  结局对话、结算确认、看完日志）等到了再 `step_done()`。
- 物件被点击时 `clickable_item` 发 `SignalBus.object_clicked(节点名)`，节点名就是物件 id。
  原来的 `leave_office_request` / `open_caller_request` / `open_electricbox_request` / `open_light_request`
  删掉了；`open_laptop_request` / `open_notes_request` / `open_calendar_request` 只是「开窗」命令，由视窗 bubble 发。
- 强制链期间点物件没反应（`non_blocking` 的例外，它后面只能接瞬间元件）；期间到点先记着，
  回到自由环节立刻下班。为了不改变原有手感，强制链期间**没有**锁 `RoundState`（上班时钟照走，
  和原来接电话时一样）。
- `RoundState` 的三段现在是「画面模式」：开场剧情进 STORY、进自由环节是 GAME（第一次进才开钟）、
  下班元件进 RESULT。
- 读档：存盘时停在强制链中间（桥段播到一半）就退回链开始前的自由环节；停在开场剧情 / 结算画面照原样接着等。
- 结局天的「日志 → 结局对话 → 结局卡」也由图走；`ending_director` 只在直接发 `game_cleared` /
  `game_over` 信号（测试、调试）时才自己串一遍。
- 测试换剧本（`_swap_day_plan`）时用 `round_manager.replace_day_body()` 同时换掉当天的天内图。

2c 之后，**每天的内容都在关卡文件里**，不再从 `day_N.story` 读：
- 剧情 bubble：`props.layer` 决定在哪层播——`notice`（一句话提示框，`script` 是纯文字）、
  `story`（全屏剧情层：开场剧情；结局对话暂时还是 `source.ending`）、`event`（桌面桥段层）。
  `props.script` 是每种语言一份的对话文字，写法和 `.story` 的对话一样，可以带 `[dialogue x]` 分支。
- 发信节点：`filler`、`filler_exclude`、`roster`、`conditional_roster`（`[{"name", "if"}]`）是结构化字段；
  `mails` 是 `[{"id", "script": {"zh": "[mail id …]\n…", "en": …}}]`，一封一条。
- 运行时由 `level_content` 当场用 `story_parser` 解析，按「节点 + 语言」缓存；中途换语言再要一次就是另一种语言。
  按 id 找剧情信走 `round_manager.mail_def()`（关卡里找，找不到再问 `story_book`）。
- 校验器多了 `BAD_LAYER`、`BAD_SCRIPT`（带 `locale`，说明是哪种语言写错）、`DUP_MAIL_ID`。
  注意：剧情文字解析报错的行号比节点里的文字多 1（解析时前面补了一行 `[story]`）。
- `day_N.story` 现在只是转换器的输入。改剧情要么改关卡文件，要么改 `.story` 再重新转一遍
  （重新转会覆盖关卡文件里手改的部分）。
- **还没搬的**：`world.story` 的账户、档案、联系人和通话、名字池、结局规则以外的结局文字（结局对话、结局卡）。
  这些属于世界数据表，留到做表单编辑时一起迁。
- 天数跳转器的语义：`set N` → 下一个天节点就是第 N 天；`add N` → 下一个天节点是「本来的天数 + N」。
- 历史流水账已经在记，但条件里的 `day3` 还是按天数查日志；等真有时空跳跃时再改成「最近一次」。

## 10c. 第 3 阶段

- 房间里 8 个物件从 `main_scene` 搬进了 `world.objects`（转换器照原来手摆的参数抄的）。
  场景里 `Control` 节点挂 `room_view.gd`，开局时按数据生成物件，节点结构和名字和原来一样。
- 视窗 bubble 开哪个窗改成看物件的 `window` 字段，`round_manager` 里不再写死。
- 外部素材文件夹覆盖（见第 6 节）。改了外部文件要 `asset_library.clear_cache()` 再重建房间才会换图。
- 还没做：房间布局的编辑界面（第 4 阶段）；`hover_scale.tscn` 里那个默认悬停音效、glow shader 的参数
  还是写在代码里，没进数据。

## 11. 代码位置

`main_game/engine/`：

- `flow_node.gd` / `flow_graph.gd`：内外层共用的图结构，负责和字典互转。
- `node_types.gd`：节点类型注册表，每种类型有哪些出口、哪些必须接。
- `level_doc.gd`：一份完整的关卡（设定 + 世界 + 外层图）。
- `level_error.gd`：一条校验错误（代码 + 参数 + 位置），以及转成文字。
- `level_validator.gd`：校验器。
- `level_store.gd`：读写 JSON，`res://` / `user://` 覆盖，版本检查。
- `level_runner.gd`：外层解释器（第 1 阶段）。
- `level_converter.gd`：把 `.story` 转成关卡图（第 1 阶段），工具脚本在 `tools/convert_story_to_level.gd`。
- `day_runner.gd`：天内图解释器（第 2b 步）。
- `level_content.gd`：节点文字 → 对话 / 邮件（第 2c 步）。
- `asset_library.gd`：素材查找，外部文件夹覆盖（第 3 阶段）。
- `main_game/game/room_view.gd`：按物件表生成房间（第 3 阶段）。
- `main_game/editor/level_editor.gd`：GM 关卡编辑器（第 4 阶段）。

## 12. GM 编辑器（第 4 阶段）

入口：`LocaleSettings.gm_mode` 为真时，主菜单「退出」上面多一个「关卡编辑器」按钮（按钮在
`menu_scene.gd` 里现做，不存进场景文件——以后藏入口只改这一处）。编辑器是独立场景
`main_game/editor/level_editor.tscn`，界面全在 `level_editor.gd` 里用代码搭，Godot 默认工具风格。

| 区域 | 内容 |
|---|---|
| 顶栏 | 关卡名 › 当前在哪一层；状态（读了哪个文件 / 有没保存的改动）；重新读取、保存、返回菜单 |
| 左边 | 元件栏：点一下在画布中间新建 |
| 中间 | `GraphEdit` 画布：拖节点、从出口拖线到别的节点、右键拖线拆线、Delete 删节点 |
| 右边 | 属性面板：选中节点的参数；条件边写边查语法 |
| 底部 | 错误列表：校验器实时结果，出错的框标红；点一条跳到那个节点（天内的错误先落在它所在的天节点上） |

- 改动只动内存里的关卡；「保存」写到 `user://levels/main.level.json`，导出后也能存。
  开发时要更新原版，把这个文件拷回 `res://levels/`。有没保存的改动时返回菜单会先问。
- 编辑操作都是 `level_editor` 上的方法（`add_node` / `link` / `unlink` / `delete_node` / `set_prop` /
  `add_case` / `remove_case`），界面事件和测试都走它们。
- 分化器删条件时，后面条件的出口线跟着往前挪一格。

| 步 | 内容 | 状态 |
|---|---|---|
| 4a | 编辑器外壳 + 外层画布（天节点 / 分化器 / 天数跳转器，属性面板，错误列表，保存读取） | 完成 |
| 4b | 天内画布 + 试玩 | 未开始 |
| 4c | 世界设定表单（背景设定、自定义变量、世界表） | 未开始 |
| 4d | 房间布局编辑器 | 未开始 |
| 4e | 剧本编辑框（行号、即时语法检查、修好行号多 1） | 未开始 |
