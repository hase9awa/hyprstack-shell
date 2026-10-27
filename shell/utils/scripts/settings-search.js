.pragma library

// Static metadata: searching never creates hidden pages or starts their services.
var catalogue = [
  {"page": 4, "subpages": [2, 6], "path": ["Panels", "Taskbar", "Workspaces"], "label": "Second monitor overlay with Super+S", "context": "", "target": "workspaceSecondaryOnSpecial", "match": "Second monitor overlay with Super+S", "keywords": "Super Win S второй монитор выключен отключён рабочие столы пространства наложение поверх"},
  {"page": 0, "subpages": [4], "path": ["Wallpaper & style", "Application colours"], "label": "Synchronize application colours", "context": "", "target": "themeSyncEnabled", "match": "Synchronize application colours", "keywords": "GTK Qt Java приложения синхронизация тема цвета"},
  {"page": 0, "subpages": [4], "path": ["Wallpaper & style", "Application colours"], "label": "System colour preference", "context": "", "target": "themeSyncSystem", "match": "System colour preference", "keywords": "system dark light системная светлая тёмная тема"},
  {"page": 0, "subpages": [4], "path": ["Wallpaper & style", "Application colours"], "label": "GTK 2 / 3 / 4 · libadwaita", "context": "", "target": "themeSyncGtk", "match": "GTK 2 / 3 / 4 · libadwaita", "keywords": "GTK libadwaita цвета приложений"},
  {"page": 0, "subpages": [4], "path": ["Wallpaper & style", "Application colours"], "label": "Qt 5 / 6 · KDE", "context": "", "target": "themeSyncQt", "match": "Qt 5 / 6 · KDE", "keywords": "Qt KDE qt5ct qt6ct цвета приложений"},
  {"page": 0, "subpages": [4], "path": ["Wallpaper & style", "Application colours"], "label": "Java · Swing", "context": "", "target": "themeSyncJava", "match": "Java · Swing", "keywords": "Java Swing GTK цвета приложений"},
  {"page": 0, "subpages": [4], "path": ["Wallpaper & style", "Application colours"], "label": "Synchronize terminal colours", "context": "", "target": "themeSyncTerminals", "match": "Synchronize terminal colours", "keywords": "терминал цвета синхронизация ANSI"},
  {"page": 0, "subpages": [4], "path": ["Wallpaper & style", "Application colours"], "label": "Update running terminals", "context": "", "target": "themeSyncLiveReload", "match": "Update running terminals", "keywords": "терминал обновление цвета"},
  {"page": 0, "subpages": [4], "path": ["Wallpaper & style", "Application colours"], "label": "kitty", "context": "", "target": "themeSync_kitty", "match": "kitty", "keywords": "терминал цвета ANSI"},
  {"page": 0, "subpages": [4], "path": ["Wallpaper & style", "Application colours"], "label": "foot", "context": "", "target": "themeSync_foot", "match": "foot", "keywords": "терминал цвета ANSI"},
  {"page": 0, "subpages": [4], "path": ["Wallpaper & style", "Application colours"], "label": "Alacritty", "context": "", "target": "themeSync_alacritty", "match": "Alacritty", "keywords": "терминал цвета ANSI"},
  {"page": 0, "subpages": [4], "path": ["Wallpaper & style", "Application colours"], "label": "WezTerm", "context": "", "target": "themeSync_wezterm", "match": "WezTerm", "keywords": "терминал цвета ANSI"},
  {"page": 0, "subpages": [4], "path": ["Wallpaper & style", "Application colours"], "label": "Ghostty", "context": "", "target": "themeSync_ghostty", "match": "Ghostty", "keywords": "терминал цвета ANSI"},
  {"page": 0, "subpages": [4], "path": ["Wallpaper & style", "Application colours"], "label": "Konsole", "context": "", "target": "themeSync_konsole", "match": "Konsole", "keywords": "терминал цвета ANSI"},
  {"page": 0, "subpages": [4], "path": ["Wallpaper & style", "Application colours"], "label": "Xfce Terminal", "context": "", "target": "themeSync_xfce4Terminal", "match": "Xfce Terminal", "keywords": "терминал цвета ANSI"},
  {"page": 0, "subpages": [4], "path": ["Wallpaper & style", "Application colours"], "label": "GNOME Terminal", "context": "", "target": "themeSync_gnomeTerminal", "match": "GNOME Terminal", "keywords": "терминал цвета ANSI"},
  {"page": 0, "subpages": [4], "path": ["Wallpaper & style", "Application colours"], "label": "Tilix", "context": "", "target": "themeSync_tilix", "match": "Tilix", "keywords": "терминал цвета ANSI"},
  {"page": 0, "subpages": [4], "path": ["Wallpaper & style", "Application colours"], "label": "XTerm", "context": "", "target": "themeSync_xterm", "match": "XTerm", "keywords": "терминал цвета ANSI"},
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Wallpaper & style",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Display wallpaper",
    "context": "",
    "target": "",
    "match": "Display wallpaper",
    "keywords": ""
  },
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Transparency",
    "context": "",
    "target": "appearanceTransparency",
    "match": "Transparency",
    "keywords": "Base %1, layers %2"
  },
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Opacity",
    "context": "",
    "target": "appearanceOpacity",
    "match": "Opacity",
    "keywords": ""
  },
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Blur",
    "context": "",
    "target": "appearanceBlur",
    "match": "Blur",
    "keywords": ""
  },
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Desktop frame in tiling mode",
    "context": "",
    "target": "appearanceDesktopFrame",
    "match": "Desktop frame in tiling mode",
    "keywords": ""
  },
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Gaps in tiling mode",
    "context": "",
    "target": "appearanceTilingGaps",
    "match": "Gaps in tiling mode",
    "keywords": "Toggle with Win+G"
  },
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Switch windows on hover in tiling mode",
    "context": "",
    "target": "appearanceTilingFocusOnHover",
    "match": "Switch windows on hover in tiling mode",
    "keywords": "When disabled, hover a partly hidden window or the screen edge, then click the arrow to switch."
  },
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Scroll columns at screen edges on hover",
    "context": "",
    "target": "appearanceTilingEdgeScroll",
    "match": "Scroll columns at screen edges on hover",
    "keywords": "Disable to keep hover focus without moving the tape. Click a window or use shortcuts to reveal it. прокрутка край экрана наведение лента"
  },
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Middle-click autoscroll",
    "context": "",
    "target": "appearanceAutoscroll",
    "match": "Middle-click autoscroll",
    "keywords": "Hold the wheel briefly, then move. Short clicks keep tab and link actions; Esc stops."
  },
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Window border width",
    "context": "",
    "target": "appearanceFocusBorderWidth",
    "match": "Window border width",
    "keywords": "Scrolling mode only; 0 hides the window border"
  },
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Window border colour",
    "context": "",
    "target": "appearanceFocusBorderColor",
    "match": "Window border colour",
    "keywords": "Scrolling mode; choose a colour from the current scheme independently of the theme accent"
  },
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Window corner rounding",
    "context": "",
    "target": "appearanceWindowRounding",
    "match": "Window corner rounding",
    "keywords": "Radius in pixels; 0 makes window corners square"
  },
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Dark theme",
    "context": "",
    "target": "appearanceDarkTheme",
    "match": "Dark theme",
    "keywords": ""
  },
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Inner gaps",
    "context": "",
    "target": "appearanceGapsIn",
    "match": "Inner gaps",
    "keywords": "Padding on each side of a tiled window, in pixels"
  },
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Outer gaps",
    "context": "",
    "target": "appearanceGapsOut",
    "match": "Outer gaps",
    "keywords": "Padding at the workspace edges, in pixels; identical for every window count"
  },
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Window shadows",
    "context": "",
    "target": "appearanceWindowShadows",
    "match": "Window shadows",
    "keywords": "The same shadow for active and inactive windows"
  },
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Interface shadows",
    "context": "",
    "target": "appearanceUiShadows",
    "match": "Interface shadows",
    "keywords": "Panels, menus and desktop widgets"
  },
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Shadow size",
    "context": "",
    "target": "appearanceShadowSize",
    "match": "Shadow size",
    "keywords": "Pixels; 0 disables shadows"
  },
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Shadow intensity",
    "context": "",
    "target": "appearanceShadowOpacity",
    "match": "Shadow intensity",
    "keywords": ""
  },
  {
    "page": 0,
    "subpages": [],
    "path": [
      "Wallpaper & style"
    ],
    "label": "Shell scale",
    "context": "",
    "target": "appearanceShellScale",
    "match": "Shell scale",
    "keywords": "Panel, menus, text and desktop widgets, in percent"
  },
  {
    "page": 0,
    "subpages": [
      1
    ],
    "path": [
      "Wallpaper & style",
      "Wallpapers"
    ],
    "label": "Wallpapers",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 0,
    "subpages": [
      3
    ],
    "path": [
      "Wallpaper & style",
      "Colours"
    ],
    "label": "Colours",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 1,
    "subpages": [],
    "path": [
      "Network"
    ],
    "label": "Network",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 1,
    "subpages": [],
    "path": [
      "Network"
    ],
    "label": "Wi-Fi",
    "context": "",
    "target": "",
    "match": "Wi-Fi",
    "keywords": ""
  },
  {
    "page": 1,
    "subpages": [
      5
    ],
    "path": [
      "Network",
      "Show all networks (%1)"
    ],
    "label": "Show all networks (%1)",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 1,
    "subpages": [
      6
    ],
    "path": [
      "Network",
      "Saved networks"
    ],
    "label": "Saved networks",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 1,
    "subpages": [
      2
    ],
    "path": [
      "Network",
      "Add network"
    ],
    "label": "Add network",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 1,
    "subpages": [],
    "path": [
      "Network"
    ],
    "label": "VPN",
    "context": "",
    "target": "",
    "match": "VPN",
    "keywords": ""
  },
  {
    "page": 1,
    "subpages": [],
    "path": [
      "Network"
    ],
    "label": "Add provider",
    "context": "",
    "target": "",
    "match": "Add provider",
    "keywords": ""
  },
  {
    "page": 1,
    "subpages": [
      5
    ],
    "path": [
      "Network",
      "All networks"
    ],
    "label": "All networks",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 1,
    "subpages": [
      4
    ],
    "path": [
      "Network",
      "Add VPN"
    ],
    "label": "Add VPN",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 2,
    "subpages": [],
    "path": [
      "Connected devices"
    ],
    "label": "Connected devices",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 2,
    "subpages": [],
    "path": [
      "Connected devices"
    ],
    "label": "Bluetooth",
    "context": "",
    "target": "",
    "match": "Bluetooth",
    "keywords": ""
  },
  {
    "page": 2,
    "subpages": [
      2
    ],
    "path": [
      "Connected devices",
      "Pair new device"
    ],
    "label": "Pair new device",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 2,
    "subpages": [],
    "path": [
      "Connected devices"
    ],
    "label": "Discoverable",
    "context": "bluetooth setting",
    "target": "",
    "match": "Discoverable",
    "keywords": "Allow nearby devices to find this one"
  },
  {
    "page": 2,
    "subpages": [],
    "path": [
      "Connected devices"
    ],
    "label": "Pairable",
    "context": "bluetooth setting",
    "target": "",
    "match": "Pairable",
    "keywords": "Allow nearby devices to pair with this one"
  },
  {
    "page": 2,
    "subpages": [
      2
    ],
    "path": [
      "Connected devices",
      "Bluetooth pairing"
    ],
    "label": "Bluetooth pairing",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 3,
    "subpages": [],
    "path": [
      "Audio"
    ],
    "label": "Audio",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 3,
    "subpages": [],
    "path": [
      "Audio"
    ],
    "label": "Output",
    "context": "audio output",
    "target": "",
    "match": "Output",
    "keywords": ""
  },
  {
    "page": 3,
    "subpages": [],
    "path": [
      "Audio"
    ],
    "label": "Muted",
    "context": "audio output muted",
    "target": "",
    "match": "Muted",
    "keywords": ""
  },
  {
    "page": 3,
    "subpages": [],
    "path": [
      "Audio"
    ],
    "label": "Input",
    "context": "audio input",
    "target": "",
    "match": "Input",
    "keywords": ""
  },
  {
    "page": 3,
    "subpages": [
      1
    ],
    "path": [
      "Audio",
      "App volumes"
    ],
    "label": "App volumes",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [],
    "path": [
      "Panels"
    ],
    "label": "Panels",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      1
    ],
    "path": [
      "Panels",
      "Dashboard"
    ],
    "label": "Dashboard",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      2
    ],
    "path": [
      "Panels",
      "Taskbar"
    ],
    "label": "Taskbar",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      3
    ],
    "path": [
      "Panels",
      "Launcher"
    ],
    "label": "Launcher",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      4
    ],
    "path": [
      "Panels",
      "Sidebar"
    ],
    "label": "Sidebar",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      5
    ],
    "path": [
      "Panels",
      "Utilities"
    ],
    "label": "Utilities",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      1
    ],
    "path": [
      "Panels",
      "Dashboard"
    ],
    "label": "Enabled",
    "context": "toggle label",
    "target": "",
    "match": "Enabled",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      1
    ],
    "path": [
      "Panels",
      "Dashboard"
    ],
    "label": "Show on hover",
    "context": "",
    "target": "",
    "match": "Show on hover",
    "keywords": "Reveal when the cursor reaches the screen edge"
  },
  {
    "page": 4,
    "subpages": [
      1
    ],
    "path": [
      "Panels",
      "Dashboard"
    ],
    "label": "Show clock seconds",
    "context": "",
    "target": "",
    "match": "Show clock seconds",
    "keywords": "Display seconds for the clock in the main panel"
  },
  {
    "page": 4,
    "subpages": [
      1
    ],
    "path": [
      "Panels",
      "Dashboard"
    ],
    "label": "Dashboard",
    "context": "",
    "target": "",
    "match": "Dashboard",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      1
    ],
    "path": [
      "Panels",
      "Dashboard"
    ],
    "label": "Media",
    "context": "",
    "target": "",
    "match": "Media",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      1
    ],
    "path": [
      "Panels",
      "Dashboard"
    ],
    "label": "Performance",
    "context": "",
    "target": "",
    "match": "Performance",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      1
    ],
    "path": [
      "Panels",
      "Dashboard"
    ],
    "label": "Weather",
    "context": "",
    "target": "",
    "match": "Weather",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      1
    ],
    "path": [
      "Panels",
      "Dashboard"
    ],
    "label": "Weather settings",
    "context": "",
    "target": "dashboardWeatherSettings",
    "match": "Weather settings",
    "keywords": "City, automatic IP location and weather provider"
  },
  {
    "page": 4,
    "subpages": [
      1
    ],
    "path": [
      "Panels",
      "Dashboard"
    ],
    "label": "Battery",
    "context": "",
    "target": "",
    "match": "Battery",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      1
    ],
    "path": [
      "Panels",
      "Dashboard"
    ],
    "label": "GPU",
    "context": "",
    "target": "",
    "match": "GPU",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      1
    ],
    "path": [
      "Panels",
      "Dashboard"
    ],
    "label": "CPU",
    "context": "",
    "target": "",
    "match": "CPU",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      1
    ],
    "path": [
      "Panels",
      "Dashboard"
    ],
    "label": "Memory",
    "context": "",
    "target": "",
    "match": "Memory",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      1
    ],
    "path": [
      "Panels",
      "Dashboard"
    ],
    "label": "Storage",
    "context": "",
    "target": "",
    "match": "Storage",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      1
    ],
    "path": [
      "Panels",
      "Dashboard"
    ],
    "label": "Network",
    "context": "",
    "target": "",
    "match": "Network",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      1
    ],
    "path": [
      "Panels",
      "Dashboard"
    ],
    "label": "Drag threshold",
    "context": "",
    "target": "",
    "match": "Drag threshold",
    "keywords": "Pixels dragged before the dashboard opens"
  },
  {
    "page": 4,
    "subpages": [
      2
    ],
    "path": [
      "Panels",
      "Taskbar"
    ],
    "label": "Persistent",
    "context": "",
    "target": "",
    "match": "Persistent",
    "keywords": "Keep the bar visible at all times"
  },
  {
    "page": 4,
    "subpages": [
      2
    ],
    "path": [
      "Panels",
      "Taskbar"
    ],
    "label": "Show on hover",
    "context": "",
    "target": "",
    "match": "Show on hover",
    "keywords": "Reveal the bar when the cursor reaches the screen edge"
  },
  {
    "page": 4,
    "subpages": [
      2
    ],
    "path": [
      "Panels",
      "Taskbar"
    ],
    "label": "Drag threshold",
    "context": "",
    "target": "",
    "match": "Drag threshold",
    "keywords": "Pixels dragged before the bar reveals"
  },
  {
    "page": 4,
    "subpages": [
      2
    ],
    "path": [
      "Panels",
      "Taskbar"
    ],
    "label": "Screen",
    "context": "",
    "target": "taskbarScreenSelector",
    "match": "Screen",
    "keywords": "Choose a screen to hide individual panel elements"
  },
  {
    "page": 4,
    "subpages": [
      2
    ],
    "path": [
      "Panels",
      "Taskbar"
    ],
    "label": "Notification centre",
    "context": "",
    "target": "taskbarElement_notifications",
    "match": "Notification centre",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      2
    ],
    "path": [
      "Panels",
      "Taskbar"
    ],
    "label": "Applications in stacking mode",
    "context": "",
    "target": "taskbarElement_tasks",
    "match": "Applications in stacking mode",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      2,
      6
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Workspaces"
    ],
    "label": "Workspaces",
    "context": "",
    "target": "",
    "match": "",
    "keywords": "Indicators, window icons"
  },
  {
    "page": 4,
    "subpages": [
      2,
      7
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Active window"
    ],
    "label": "Active window",
    "context": "",
    "target": "",
    "match": "",
    "keywords": "Title display, popout"
  },
  {
    "page": 4,
    "subpages": [
      2,
      8
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Tray"
    ],
    "label": "Tray",
    "context": "",
    "target": "",
    "match": "",
    "keywords": "System tray icons"
  },
  {
    "page": 4,
    "subpages": [
      2,
      9
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Status icons"
    ],
    "label": "Status icons",
    "context": "",
    "target": "",
    "match": "",
    "keywords": "Visible indicators"
  },
  {
    "page": 4,
    "subpages": [
      2,
      10
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Clock"
    ],
    "label": "Clock",
    "context": "",
    "target": "",
    "match": "",
    "keywords": "Date, icon, background"
  },
  {
    "page": 4,
    "subpages": [
      2
    ],
    "path": [
      "Panels",
      "Taskbar"
    ],
    "label": "Workspaces",
    "context": "",
    "target": "",
    "match": "Workspaces",
    "keywords": "Scroll over the workspace indicator to switch workspaces"
  },
  {
    "page": 4,
    "subpages": [
      2
    ],
    "path": [
      "Panels",
      "Taskbar"
    ],
    "label": "Logo",
    "context": "",
    "target": "taskbarElement_logo",
    "match": "Logo",
    "keywords": "Screen element visibility monitor hide"
  },
  {
    "page": 4,
    "subpages": [
      2
    ],
    "path": [
      "Panels",
      "Taskbar"
    ],
    "label": "Workspaces",
    "context": "",
    "target": "taskbarElement_workspaces",
    "match": "Workspaces",
    "keywords": "Screen element visibility monitor hide"
  },
  {
    "page": 4,
    "subpages": [
      2
    ],
    "path": [
      "Panels",
      "Taskbar"
    ],
    "label": "Active window",
    "context": "",
    "target": "taskbarElement_activeWindow",
    "match": "Active window",
    "keywords": "Screen element visibility monitor hide"
  },
  {
    "page": 4,
    "subpages": [
      2
    ],
    "path": [
      "Panels",
      "Taskbar"
    ],
    "label": "Tray",
    "context": "",
    "target": "taskbarElement_tray",
    "match": "Tray",
    "keywords": "Screen element visibility monitor hide"
  },
  {
    "page": 4,
    "subpages": [
      2
    ],
    "path": [
      "Panels",
      "Taskbar"
    ],
    "label": "Clock",
    "context": "",
    "target": "taskbarElement_clock",
    "match": "Clock",
    "keywords": "Screen element visibility monitor hide"
  },
  {
    "page": 4,
    "subpages": [
      2
    ],
    "path": [
      "Panels",
      "Taskbar"
    ],
    "label": "Status icons",
    "context": "",
    "target": "taskbarElement_statusIcons",
    "match": "Status icons",
    "keywords": "Screen element visibility monitor hide"
  },
  {
    "page": 4,
    "subpages": [
      2
    ],
    "path": [
      "Panels",
      "Taskbar"
    ],
    "label": "Power button",
    "context": "",
    "target": "taskbarElement_power",
    "match": "Power button",
    "keywords": "Screen element visibility monitor hide"
  },
  {
    "page": 4,
    "subpages": [
      3
    ],
    "path": [
      "Panels",
      "Launcher"
    ],
    "label": "Enabled",
    "context": "toggle label",
    "target": "",
    "match": "Enabled",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      3
    ],
    "path": [
      "Panels",
      "Launcher"
    ],
    "label": "Show on hover",
    "context": "",
    "target": "",
    "match": "Show on hover",
    "keywords": "Reveal when the cursor reaches the screen edge"
  },
  {
    "page": 4,
    "subpages": [
      3
    ],
    "path": [
      "Panels",
      "Launcher"
    ],
    "label": "Action prefix",
    "context": "",
    "target": "",
    "match": "Action prefix",
    "keywords": "Prefix used to run actions in the launcher"
  },
  {
    "page": 4,
    "subpages": [
      3
    ],
    "path": [
      "Panels",
      "Launcher"
    ],
    "label": "Max items shown",
    "context": "",
    "target": "",
    "match": "Max items shown",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      3
    ],
    "path": [
      "Panels",
      "Launcher"
    ],
    "label": "Max wallpapers",
    "context": "",
    "target": "",
    "match": "Max wallpapers",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      3
    ],
    "path": [
      "Panels",
      "Launcher"
    ],
    "label": "Drag threshold",
    "context": "",
    "target": "",
    "match": "Drag threshold",
    "keywords": "Pixels dragged before the launcher opens"
  },
  {
    "page": 4,
    "subpages": [
      3
    ],
    "path": [
      "Panels",
      "Launcher"
    ],
    "label": "Vim keybinds",
    "context": "",
    "target": "",
    "match": "Vim keybinds",
    "keywords": "Navigate results with Ctrl+hjkl"
  },
  {
    "page": 4,
    "subpages": [
      3
    ],
    "path": [
      "Panels",
      "Launcher"
    ],
    "label": "Enable dangerous actions",
    "context": "",
    "target": "",
    "match": "Enable dangerous actions",
    "keywords": "Allow actions that shut down or log out"
  },
  {
    "page": 4,
    "subpages": [
      3
    ],
    "path": [
      "Panels",
      "Launcher"
    ],
    "label": "Apps",
    "context": "",
    "target": "",
    "match": "Apps",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      3
    ],
    "path": [
      "Panels",
      "Launcher"
    ],
    "label": "Actions",
    "context": "",
    "target": "",
    "match": "Actions",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      3
    ],
    "path": [
      "Panels",
      "Launcher"
    ],
    "label": "Schemes",
    "context": "",
    "target": "",
    "match": "Schemes",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      3
    ],
    "path": [
      "Panels",
      "Launcher"
    ],
    "label": "Variants",
    "context": "",
    "target": "",
    "match": "Variants",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      3
    ],
    "path": [
      "Panels",
      "Launcher"
    ],
    "label": "Wallpapers",
    "context": "",
    "target": "",
    "match": "Wallpapers",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      4
    ],
    "path": [
      "Panels",
      "Sidebar"
    ],
    "label": "Enabled",
    "context": "toggle label",
    "target": "",
    "match": "Enabled",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      4
    ],
    "path": [
      "Panels",
      "Sidebar"
    ],
    "label": "Drag threshold",
    "context": "",
    "target": "",
    "match": "Drag threshold",
    "keywords": "Pixels dragged before the sidebar opens"
  },
  {
    "page": 4,
    "subpages": [
      5
    ],
    "path": [
      "Panels",
      "Utilities"
    ],
    "label": "Enabled",
    "context": "toggle label",
    "target": "",
    "match": "Enabled",
    "keywords": "Show the utilities panel"
  },
  {
    "page": 4,
    "subpages": [
      5
    ],
    "path": [
      "Panels",
      "Utilities"
    ],
    "label": "Keep awake",
    "context": "",
    "target": "",
    "match": "Keep awake",
    "keywords": "Show the idle inhibitor card"
  },
  {
    "page": 4,
    "subpages": [
      5
    ],
    "path": [
      "Panels",
      "Utilities"
    ],
    "label": "Screen recorder",
    "context": "",
    "target": "",
    "match": "Screen recorder",
    "keywords": "Show the screen recorder card"
  },
  {
    "page": 4,
    "subpages": [
      5
    ],
    "path": [
      "Panels",
      "Utilities"
    ],
    "label": "Quick toggles",
    "context": "",
    "target": "",
    "match": "Quick toggles",
    "keywords": "Show the quick toggles card"
  },
  {
    "page": 4,
    "subpages": [
      5
    ],
    "path": [
      "Panels",
      "Utilities"
    ],
    "label": "Wi-Fi",
    "context": "",
    "target": "",
    "match": "Wi-Fi",
    "keywords": "Toggle wireless networking"
  },
  {
    "page": 4,
    "subpages": [
      5
    ],
    "path": [
      "Panels",
      "Utilities"
    ],
    "label": "Bluetooth",
    "context": "",
    "target": "",
    "match": "Bluetooth",
    "keywords": "Toggle the Bluetooth adapter"
  },
  {
    "page": 4,
    "subpages": [
      5
    ],
    "path": [
      "Panels",
      "Utilities"
    ],
    "label": "Microphone",
    "context": "",
    "target": "",
    "match": "Microphone",
    "keywords": "Mute or unmute the default source"
  },
  {
    "page": 4,
    "subpages": [
      5
    ],
    "path": [
      "Panels",
      "Utilities"
    ],
    "label": "Settings",
    "context": "",
    "target": "",
    "match": "Settings",
    "keywords": "Open the settings window"
  },
  {
    "page": 4,
    "subpages": [
      5
    ],
    "path": [
      "Panels",
      "Utilities"
    ],
    "label": "Game mode",
    "context": "",
    "target": "",
    "match": "Game mode",
    "keywords": "Toggle game mode"
  },
  {
    "page": 4,
    "subpages": [
      5
    ],
    "path": [
      "Panels",
      "Utilities"
    ],
    "label": "Do not disturb",
    "context": "",
    "target": "",
    "match": "Do not disturb",
    "keywords": "Silence notifications"
  },
  {
    "page": 4,
    "subpages": [
      5
    ],
    "path": [
      "Panels",
      "Utilities"
    ],
    "label": "VPN",
    "context": "",
    "target": "",
    "match": "VPN",
    "keywords": "Connect or disconnect the VPN"
  },
  {
    "page": 4,
    "subpages": [
      2,
      6
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Workspaces"
    ],
    "label": "Shown",
    "context": "bar workspaces",
    "target": "",
    "match": "Shown",
    "keywords": "Number of workspaces displayed"
  },
  {
    "page": 4,
    "subpages": [
      2,
      6
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Workspaces"
    ],
    "label": "Active indicator",
    "context": "bar workspaces",
    "target": "",
    "match": "Active indicator",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      2,
      6
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Workspaces"
    ],
    "label": "Active trail",
    "context": "bar workspaces",
    "target": "",
    "match": "Active trail",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      2,
      6
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Workspaces"
    ],
    "label": "Occupied background",
    "context": "bar workspaces",
    "target": "",
    "match": "Occupied background",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      2,
      6
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Workspaces"
    ],
    "label": "Show unoccupied",
    "context": "bar workspaces",
    "target": "",
    "match": "Show unoccupied",
    "keywords": "When disabled, hide only empty workspaces after the last occupied or active workspace"
  },
  {
    "page": 4,
    "subpages": [
      2,
      6
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Workspaces"
    ],
    "label": "Per monitor",
    "context": "bar workspaces",
    "target": "",
    "match": "Per monitor",
    "keywords": "Hide workspaces not on the current monitor"
  },
  {
    "page": 4,
    "subpages": [
      2,
      6
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Workspaces"
    ],
    "label": "Show windows",
    "context": "bar workspaces",
    "target": "",
    "match": "Show windows",
    "keywords": "Show icons of open windows on each workspace"
  },
  {
    "page": 4,
    "subpages": [
      2,
      6
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Workspaces"
    ],
    "label": "Windows on special workspaces",
    "context": "bar workspaces",
    "target": "",
    "match": "Windows on special workspaces",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      2,
      6
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Workspaces"
    ],
    "label": "Max window icons",
    "context": "bar workspaces",
    "target": "",
    "match": "Max window icons",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      2,
      6
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Workspaces"
    ],
    "label": "Workspace indicator",
    "context": "",
    "target": "workspaceIndicatorStyle",
    "match": "Workspace indicator",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      2,
      6
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Workspaces"
    ],
    "label": "Window icons",
    "context": "",
    "target": "workspaceIconStyle",
    "match": "Window icons",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      2,
      6
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Workspaces"
    ],
    "label": "Window icon size",
    "context": "",
    "target": "workspaceIconSize",
    "match": "Window icon size",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      2,
      6
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Workspaces"
    ],
    "label": "Active icon colour",
    "context": "",
    "target": "workspaceActiveIconColour",
    "match": "Active icon colour",
    "keywords": "Tinted icons and symbols; choose a colour from the current scheme"
  },
  {
    "page": 4,
    "subpages": [
      2,
      6
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Workspaces"
    ],
    "label": "Inactive icon colour",
    "context": "",
    "target": "workspaceInactiveIconColour",
    "match": "Inactive icon colour",
    "keywords": "Tinted icons and symbols; choose a colour from the current scheme"
  },
  {
    "page": 4,
    "subpages": [
      2,
      7
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Active window"
    ],
    "label": "Compact",
    "context": "taskbar active window layout",
    "target": "",
    "match": "Compact",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      2,
      7
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Active window"
    ],
    "label": "Inverted",
    "context": "taskbar active window: swap the title and class order",
    "target": "",
    "match": "Inverted",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      2,
      7
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Active window"
    ],
    "label": "Show on hover",
    "context": "",
    "target": "",
    "match": "Show on hover",
    "keywords": "Only show the active window title while hovering"
  },
  {
    "page": 4,
    "subpages": [
      2,
      7
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Active window"
    ],
    "label": "Popout on hover",
    "context": "",
    "target": "",
    "match": "Popout on hover",
    "keywords": "Show a window details popout when hovering"
  },
  {
    "page": 4,
    "subpages": [
      2,
      8
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Tray"
    ],
    "label": "Background",
    "context": "taskbar tray: draw a background behind the tray",
    "target": "",
    "match": "Background",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      2,
      8
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Tray"
    ],
    "label": "Recolour icons",
    "context": "",
    "target": "",
    "match": "Recolour icons",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      2,
      8
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Tray"
    ],
    "label": "Compact",
    "context": "taskbar tray layout",
    "target": "",
    "match": "Compact",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      2,
      8
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Tray"
    ],
    "label": "Popout on hover",
    "context": "",
    "target": "",
    "match": "Popout on hover",
    "keywords": "Show the tray menu popout when hovering"
  },
  {
    "page": 4,
    "subpages": [
      2,
      9
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Status icons"
    ],
    "label": "Popout on hover",
    "context": "",
    "target": "",
    "match": "Popout on hover",
    "keywords": "Show a details popout when hovering the status icons"
  },
  {
    "page": 4,
    "subpages": [
      2,
      10
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Clock"
    ],
    "label": "Background",
    "context": "taskbar clock: draw a background behind the clock",
    "target": "",
    "match": "Background",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      2,
      10
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Clock"
    ],
    "label": "Show date",
    "context": "",
    "target": "",
    "match": "Show date",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      2,
      10
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Clock"
    ],
    "label": "Show icon",
    "context": "",
    "target": "",
    "match": "Show icon",
    "keywords": ""
  },
  {
    "page": 4,
    "subpages": [
      2,
      10
    ],
    "path": [
      "Panels",
      "Taskbar",
      "Clock"
    ],
    "label": "Show seconds",
    "context": "",
    "target": "",
    "match": "Show seconds",
    "keywords": ""
  },
  {
    "page": 5,
    "subpages": [],
    "path": [
      "Apps"
    ],
    "label": "Apps",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 5,
    "subpages": [
      1
    ],
    "path": [
      "Apps",
      "All apps"
    ],
    "label": "All apps",
    "context": "",
    "target": "",
    "match": "",
    "keywords": "Browse installed apps, set favourites and hidden"
  },
  {
    "page": 6,
    "subpages": [],
    "path": [
      "Services"
    ],
    "label": "Services",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 6,
    "subpages": [
      1
    ],
    "path": [
      "Services",
      "Notifications"
    ],
    "label": "Notifications",
    "context": "",
    "target": "",
    "match": "",
    "keywords": "Notifications, toasts, timeouts"
  },
  {
    "page": 6,
    "subpages": [],
    "path": [
      "Services"
    ],
    "label": "Media refresh",
    "context": "",
    "target": "",
    "match": "Media refresh",
    "keywords": "How often the media position updates (ms)"
  },
  {
    "page": 6,
    "subpages": [],
    "path": [
      "Services"
    ],
    "label": "System stats refresh",
    "context": "",
    "target": "",
    "match": "System stats refresh",
    "keywords": "CPU, memory and GPU update interval (seconds)"
  },
  {
    "page": 6,
    "subpages": [],
    "path": [
      "Services"
    ],
    "label": "Wi-Fi rescan",
    "context": "",
    "target": "",
    "match": "Wi-Fi rescan",
    "keywords": "How often available networks are rescanned (seconds)"
  },
  {
    "page": 6,
    "subpages": [],
    "path": [
      "Services"
    ],
    "label": "Lyrics backend",
    "context": "",
    "target": "",
    "match": "Lyrics backend",
    "keywords": "Source used to fetch synced lyrics"
  },
  {
    "page": 6,
    "subpages": [],
    "path": [
      "Services"
    ],
    "label": "Default player",
    "context": "",
    "target": "",
    "match": "Default player",
    "keywords": "Preferred media player when several are open"
  },
  {
    "page": 6,
    "subpages": [],
    "path": [
      "Services"
    ],
    "label": "Volume step",
    "context": "",
    "target": "",
    "match": "Volume step",
    "keywords": "Amount the volume changes per scroll (%)"
  },
  {
    "page": 6,
    "subpages": [],
    "path": [
      "Services"
    ],
    "label": "Brightness step",
    "context": "",
    "target": "",
    "match": "Brightness step",
    "keywords": "Amount the brightness changes per scroll (%)"
  },
  {
    "page": 6,
    "subpages": [],
    "path": [
      "Services"
    ],
    "label": "Max volume",
    "context": "",
    "target": "",
    "match": "Max volume",
    "keywords": "Upper limit for output volume (%)"
  },
  {
    "page": 6,
    "subpages": [],
    "path": [
      "Services"
    ],
    "label": "Visualiser bars",
    "context": "",
    "target": "",
    "match": "Visualiser bars",
    "keywords": "Number of bars in the audio visualisers"
  },
  {
    "page": 6,
    "subpages": [],
    "path": [
      "Services"
    ],
    "label": "Smart colour scheme",
    "context": "",
    "target": "",
    "match": "Smart colour scheme",
    "keywords": "Derive theme mode and variant from the wallpaper"
  },
  {
    "page": 6,
    "subpages": [],
    "path": [
      "Services"
    ],
    "label": "GPU",
    "context": "",
    "target": "",
    "match": "GPU",
    "keywords": ""
  },
  {
    "page": 6,
    "subpages": [
      1
    ],
    "path": [
      "Services",
      "Notifications"
    ],
    "label": "Show in fullscreen",
    "context": "",
    "target": "",
    "match": "Show in fullscreen",
    "keywords": "Whether notifications appear over fullscreen apps"
  },
  {
    "page": 6,
    "subpages": [
      1
    ],
    "path": [
      "Services",
      "Notifications"
    ],
    "label": "Expire automatically",
    "context": "",
    "target": "",
    "match": "Expire automatically",
    "keywords": "Dismiss notifications after their timeout"
  },
  {
    "page": 6,
    "subpages": [
      1
    ],
    "path": [
      "Services",
      "Notifications"
    ],
    "label": "Open expanded",
    "context": "",
    "target": "",
    "match": "Open expanded",
    "keywords": "Show notifications expanded by default"
  },
  {
    "page": 6,
    "subpages": [
      1
    ],
    "path": [
      "Services",
      "Notifications"
    ],
    "label": "Default timeout",
    "context": "",
    "target": "",
    "match": "Default timeout",
    "keywords": "Time before a notification dismisses (ms)"
  },
  {
    "page": 6,
    "subpages": [
      1
    ],
    "path": [
      "Services",
      "Notifications"
    ],
    "label": "Group preview count",
    "context": "",
    "target": "",
    "match": "Group preview count",
    "keywords": "Notifications shown per group before collapsing"
  },
  {
    "page": 6,
    "subpages": [
      1
    ],
    "path": [
      "Services",
      "Notifications"
    ],
    "label": "Visible toasts",
    "context": "",
    "target": "",
    "match": "Visible toasts",
    "keywords": "Maximum number of toasts shown at once"
  },
  {
    "page": 6,
    "subpages": [
      1
    ],
    "path": [
      "Services",
      "Notifications"
    ],
    "label": "Charging changes",
    "context": "",
    "target": "",
    "match": "Charging changes",
    "keywords": ""
  },
  {
    "page": 6,
    "subpages": [
      1
    ],
    "path": [
      "Services",
      "Notifications"
    ],
    "label": "Game mode changes",
    "context": "",
    "target": "",
    "match": "Game mode changes",
    "keywords": ""
  },
  {
    "page": 6,
    "subpages": [
      1
    ],
    "path": [
      "Services",
      "Notifications"
    ],
    "label": "Do not disturb changes",
    "context": "",
    "target": "",
    "match": "Do not disturb changes",
    "keywords": ""
  },
  {
    "page": 6,
    "subpages": [
      1
    ],
    "path": [
      "Services",
      "Notifications"
    ],
    "label": "Audio output changes",
    "context": "",
    "target": "",
    "match": "Audio output changes",
    "keywords": ""
  },
  {
    "page": 6,
    "subpages": [
      1
    ],
    "path": [
      "Services",
      "Notifications"
    ],
    "label": "Audio input changes",
    "context": "",
    "target": "",
    "match": "Audio input changes",
    "keywords": ""
  },
  {
    "page": 6,
    "subpages": [
      1
    ],
    "path": [
      "Services",
      "Notifications"
    ],
    "label": "Caps lock changes",
    "context": "",
    "target": "",
    "match": "Caps lock changes",
    "keywords": ""
  },
  {
    "page": 6,
    "subpages": [
      1
    ],
    "path": [
      "Services",
      "Notifications"
    ],
    "label": "Num lock changes",
    "context": "",
    "target": "",
    "match": "Num lock changes",
    "keywords": ""
  },
  {
    "page": 6,
    "subpages": [
      1
    ],
    "path": [
      "Services",
      "Notifications"
    ],
    "label": "Keyboard layout changes",
    "context": "",
    "target": "",
    "match": "Keyboard layout changes",
    "keywords": ""
  },
  {
    "page": 6,
    "subpages": [
      1
    ],
    "path": [
      "Services",
      "Notifications"
    ],
    "label": "VPN changes",
    "context": "",
    "target": "",
    "match": "VPN changes",
    "keywords": ""
  },
  {
    "page": 6,
    "subpages": [
      1
    ],
    "path": [
      "Services",
      "Notifications"
    ],
    "label": "Now playing",
    "context": "",
    "target": "",
    "match": "Now playing",
    "keywords": ""
  },
  {
    "page": 7,
    "subpages": [],
    "path": [
      "Language & region"
    ],
    "label": "Language & region",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 7,
    "subpages": [],
    "path": [
      "Language & region"
    ],
    "label": "UI language",
    "context": "",
    "target": "uiLanguage",
    "match": "UI language",
    "keywords": "The language used in the shell UI"
  },
  {
    "page": 7,
    "subpages": [],
    "path": [
      "Language & region"
    ],
    "label": "Enable weather",
    "context": "",
    "target": "weatherEnabled",
    "match": "Enable weather",
    "keywords": ""
  },
  {
    "page": 7,
    "subpages": [],
    "path": [
      "Language & region"
    ],
    "label": "Weather provider",
    "context": "",
    "target": "weatherProvider",
    "match": "Weather provider",
    "keywords": ""
  },
  {
    "page": 7,
    "subpages": [],
    "path": [
      "Language & region"
    ],
    "label": "Weather location",
    "context": "",
    "target": "weatherLocation",
    "match": "Weather location",
    "keywords": ""
  },
  {
    "page": 7,
    "subpages": [],
    "path": [
      "Language & region"
    ],
    "label": "Weather city",
    "context": "",
    "target": "weatherCitySearch",
    "match": "Weather city",
    "keywords": "Enter a name and select a city from the results"
  },
  {
    "page": 7,
    "subpages": [],
    "path": [
      "Language & region"
    ],
    "label": "Refresh weather",
    "context": "",
    "target": "weatherRefresh",
    "match": "Refresh weather",
    "keywords": ""
  },
  {
    "page": 7,
    "subpages": [],
    "path": [
      "Language & region"
    ],
    "label": "Temperature",
    "context": "",
    "target": "",
    "match": "Temperature",
    "keywords": "Units for weather temperatures"
  },
  {
    "page": 7,
    "subpages": [],
    "path": [
      "Language & region"
    ],
    "label": "System temperatures",
    "context": "",
    "target": "",
    "match": "System temperatures",
    "keywords": "Units for CPU and GPU temperatures"
  },
  {
    "page": 7,
    "subpages": [],
    "path": [
      "Language & region"
    ],
    "label": "Data sizes",
    "context": "",
    "target": "",
    "match": "Data sizes",
    "keywords": "Units for data sizes and network speeds"
  },
  {
    "page": 7,
    "subpages": [],
    "path": [
      "Language & region"
    ],
    "label": "Clock format",
    "context": "",
    "target": "",
    "match": "Clock format",
    "keywords": "How times are shown across the shell"
  },
  {
    "page": 8,
    "subpages": [],
    "path": [
      "Keyboard shortcuts"
    ],
    "label": "Keyboard shortcuts",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  },
  {
    "page": 9,
    "subpages": [],
    "path": [
      "About"
    ],
    "label": "About",
    "context": "",
    "target": "",
    "match": "",
    "keywords": ""
  }
];
// End catalogue

var aliases = [
    ["тен", "shadow"], ["отступ", "gap"], ["гэп", "gap"], ["геп", "gap"],
    ["рамк", "border"], ["скругл", "rounding"], ["радиус", "radius"], ["угл", "corner"],
    ["масш", "scale"], ["монитор", "screen"], ["экран", "screen"],
    ["ворксп", "workspace"], ["рабоч", "workspace"], ["стол", "workspace"],
    ["секунд", "seconds"], ["дат", "date"], ["час", "clock"], ["врем", "clock"],
    ["тем", "theme"], ["обо", "wallpaper"], ["прозрач", "transparency"], ["размыт", "blur"],
    ["прокрут", "scroll"], ["автоскрол", "autoscroll"], ["колес", "middle"],
    ["окн", "window"], ["окон", "window"], ["неактив", "border"],
    ["панел", "panel"], ["трей", "tray"], ["знач", "icon"], ["икон", "icon"],
    ["уведом", "notification"], ["звук", "audio"], ["громк", "volume"],
    ["микроф", "input"], ["язык", "language"], ["сеть", "network"], ["сетев", "network"],
    ["скорос", "refresh"], ["частот", "refresh"], ["размер", "size"], ["интенс", "intensity"],
    ["толщ", "width"], ["цвет", "colour"], ["блют", "bluetooth"], ["интерф", "interface"],
    ["клав", "keyboard"], ["сочет", "shortcut"], ["хотке", "shortcut"], ["погод", "weather"], ["акцент", "colour"],
    ["город", "city"], ["провайдер", "provider"], ["местополож", "location"],
    ["внутрен", "inner"], ["внешн", "outer"], ["прилож", "app"], ["ярк", "brightness"]
];

function normalise(value) {
    return String(value ?? "").normalize("NFKC").toLowerCase().replace(/ё/g, "е")
        .replace(/[\s.,;:/_&()\[\]{}+-]+/g, " ").trim();
}

function find(query, translate) {
    var raw = normalise(query);
    if (!raw) return [];
    var tokens = raw.split(/\s+/).map(token => {
        var alias = aliases.find(a => token.startsWith(a[0]));
        return alias ? [token, alias[1]] : [token];
    });
    var result = [];
    for (var entry of catalogue) {
        var label = translate(entry.label, entry.context);
        var path = entry.path.map(p => translate(p, "")).join(" › ");
        var heading = normalise(entry.label + " " + label);
        var haystack = normalise(heading + " " + path + " " + entry.path.join(" ") + " "
            + entry.keywords + " " + translate(entry.keywords, ""));
        if (!tokens.every(alternatives => alternatives.some(t => haystack.includes(t)))) continue;
        var score = heading === raw ? 0 : heading.startsWith(raw) ? 1
            : tokens.every(a => a.some(t => heading.includes(t))) ? 2 : 3;
        result.push(Object.assign({}, entry, {label:label, description:path, score:score}));
    }
    result.sort((a, b) => a.score - b.score || a.page - b.page);
    return result.slice(0, 60);
}
