[English](INSTALL.en.md) · [На главную](README.md) · [Установка на NixOS](INSTALL.nixos.md)

# Установка Hyprstack на Arch Linux и производные

<a id="arch"></a>

Инструкция для Arch Linux, CachyOS, EndeavourOS и Manjaro с systemd.
Hyprstack устанавливает оболочку и конфигурацию Hyprland для текущего пользователя.
Терминал, браузер и файловый менеджер выбираете вы.

Выполняйте установку в терминале текущего рабочего стола: браузер с инструкцией
можно оставить открытым. Выходить из сеанса нужно после настройки, перед первым
запуском Hyprstack. Для уже работающего Hyprland скрипт подготовит отдельную
команду применения — см. шаг 4.

**Все команды этой инструкции рассчитаны на Bash.** Если используете Fish, Zsh
или другую оболочку, сначала запустите Bash в текущем терминале:

```sh
bash
```

Оболочку входа менять не нужно. Кроме установки пакетов и включения системной
службы сети, команды выполняются **без `sudo`**.

## 1. Зависимости

Требуются **Hyprland 0.56.2**, **Quickshell ≥ 0.3.1** с модулями Hyprland,
PAM и Polkit, **Qt ≥ 6.9**. Для сборки: C++23, CMake ≥ 3.22, Python ≥ 3.10.
Заголовки Hyprland должны совпадать с установленным композитором по ABI.
Проверьте версии в репозиториях:

```bash
pacman -Si hyprland quickshell qt6-base
```

Продолжайте, только если доступен Hyprland **0.56.2** и выполнены требования
выше. Если в вашей ветке дистрибутива другие версии, сначала подготовьте
совместимый набор пакетов; пропускать проверку ABI нельзя.

Обновите систему и установите зависимости сборки и функций окружения:

```bash
sudo pacman -Syu --needed base-devel git cmake ninja pkgconf gettext \
  hyprland quickshell nlohmann-json qt6-base qt6-declarative qt6-shadertools \
  qt6-svg qt6-imageformats qt6-wayland qt5ct qt6ct libqalculate lm_sensors \
  pixman libdrm libinput systemd-libs wayland libxkbcommon pango cairo \
  python python-pillow fuzzel wl-clipboard cliphist grim slurp wf-recorder \
  swappy libnotify brightnessctl networkmanager pipewire pipewire-audio \
  pipewire-pulse wireplumber polkit libcap hyprlock hyprpicker xdg-utils \
  xdg-user-dirs libxml2 adwaita-icon-theme dbus glib2 gsettings-desktop-schemas \
  xdg-desktop-portal-gtk xdg-desktop-portal-hyprland
```

Здесь `fuzzel` нужен для выбора emoji и истории буфера, `grim`/`slurp`/`swappy`
— для снимков экрана, `wf-recorder` — для записи. `qt5ct`/`qt6ct` и desktop portal
нужны для оформления приложений и интеграции с рабочим столом.
Для смены цветов уже открытых KDE-приложений вместо `qt6ct` можно использовать
[qt6ct-kde](https://aur.archlinux.org/packages/qt6ct-kde).

**Пользовательские приложения устанавливаются отдельно, по вашему выбору.**
Если терминал и браузер уже установлены, используйте их. Например, для Foot
и Chromium:

```bash
sudo pacman -S --needed foot chromium
```

Kitty и Firefox также подходят, но для работы Hyprstack не обязательны.
Файловый менеджер выбирается через системную ассоциацию `xdg-open`.
`pavucontrol` нужен только для сочетания **Ctrl+Alt+V**, `btop` — для
**Ctrl+Shift+Escape**; установите их, если нужны эти действия.

## 2. Сборка

```bash
git clone https://github.com/hase9awa/hyprstack-shell.git
cd hyprstack-shell
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$HOME/.local" \
  -DCMAKE_INSTALL_DATADIR="${XDG_DATA_HOME:-$HOME/.local/share}"
cmake --build build --parallel 2
cmake --install build
export PATH="$HOME/.local/bin:$PATH"
```

При нехватке памяти замените `--parallel 2` на `--parallel 1`.
Программы устанавливаются в `~/.local/bin`, данные — в пользовательский XDG-каталог.

Добавьте `~/.local/bin` в `PATH` своего профиля входа, если его там ещё нет:

| Оболочка входа | Настройка |
| --- | --- |
| Bash | Добавьте `export PATH="$HOME/.local/bin:$PATH"` в `~/.bash_profile` |
| Zsh | Добавьте ту же строку в `~/.zprofile` |
| Fish | Выполните из текущего Bash: `fish -c 'fish_add_path "$HOME/.local/bin"'` |

## 3. Сеть и звук

Сеть в панели управляется через **NetworkManager**, звук — через
**PipeWire/WirePlumber**. Сначала проверьте существующую настройку:

```bash
systemctl is-active NetworkManager.service
wpctl status
```

Если сеть и звук уже работают через эти компоненты, переходите к шагу 4.
На свежей системе без настроенного менеджера сети включите NetworkManager:

```bash
sudo systemctl enable --now NetworkManager.service
```

Если интерфейс уже обслуживает другой менеджер сети, сначала настройте переход
по [инструкции NetworkManager](https://wiki.archlinux.org/title/NetworkManager#Enable_NetworkManager).
Два менеджера не должны управлять одним интерфейсом.

PipeWire использует пользовательские службы и активацию через сокеты.
Если вы только установили его пакеты, повторите `wpctl status` после первого
входа на шаге 5. Если он по-прежнему не подключается, выполните своим пользователем:

```bash
systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service
```

Подробнее: [PipeWire](https://wiki.archlinux.org/title/PipeWire#Installation),
[запуск WirePlumber](https://pipewire.pages.freedesktop.org/wireplumber/daemon/running.html).

<a id="config"></a>

## 4. Первоначальная настройка

Оставаясь в текущем рабочем столе, из каталога исходников выполните:

```bash
bash configure.sh
```

Скрипт спросит команды **уже установленных** терминала и браузера. Нажмите Enter,
чтобы принять предложенный вариант, или впишите свой. Выбор терминала применяется
к **Super+Enter**, запуску консольных приложений из меню и системному монитору.
Можно передать выбор сразу; пример для Foot и Chromium:

```bash
bash configure.sh --terminal foot --browser chromium
```

Скрипт устанавливает `hypr/`, `hyprstack/`, начальную тему и две пользовательские
службы. Если конфиги уже существуют, он сохраняет их в
`~/.config/hyprstack-backup.*` и выводит точный путь. При другом `XDG_CONFIG_HOME`
копия находится в нём. **На чистой установке резервная копия не создаётся.**
Для последующих обновлений используйте [update.sh](MAINTENANCE.md#обновление):
повторная первоначальная настройка заменяет конфигурацию целиком.

**Если Hyprland уже запущен**, скрипт сохранит выбор и XDG-пути для применения
после выхода. Завершите сеанс, войдите в TTY (**Ctrl+Alt+F3**) и выполните только:

```bash
bash ~/.local/state/hyprstack-setup/apply.sh
```

Эта команда не требует возвращаться в каталог исходников, вспоминать переменные
или переписывать блоки из инструкции. Переключения в TTY без завершения Hyprland
недостаточно: скрипт не заменяет конфигурацию работающего композитора.
Подготовить команду заранее можно и явно: `bash configure.sh --prepare`.

## 5. Первый запуск и проверка

После сообщения **«Конфигурация готова»** завершите текущий графический сеанс
и выберите **Hyprland** в менеджере входа. Если менеджера входа нет, войдите
в TTY и выполните `start-hyprland`.

Перезагрузка сама по себе не переключает рабочий стол: при входе в KDE, GNOME
или Niri автозапуск Hyprstack не выполняется. Проект использует
`~/.config/hypr/hyprland.lua` (с учётом `XDG_CONFIG_HOME`);
создавать `hyprland.conf` для этой установки не нужно.

В новом сеансе **Super+Enter** открывает выбранный терминал, **Super+W** — браузер,
**Super+D** — меню приложений. Выполните:

```bash
~/.local/bin/hyprstack-doctor
hyprctl configerrors
```

Диагностика должна пройти без `FAIL`, а `hyprctl configerrors` — не показать ошибок.
Если панель не появилась:

```bash
hyprctl version
hyprctl configerrors
systemctl --user status hyprstack-session.service --no-pager
journalctl --user -u hyprstack-session.service -b --no-pager
```

Если `hyprctl version` не подключается к композитору, проверьте выбранный сеанс.
Для проверки всей цепочки запуска выполните `~/.local/bin/hyprstack-session start`.
Команда `hyprstack shell` запускает только интерфейс и сама по себе
не проверяет пользовательскую службу и автозапуск.

### Что запускается автоматически

| Компонент | Кто запускает | Нужно ли включать вручную |
| --- | --- | --- |
| NetworkManager | Системный systemd | Один раз, если сеть ещё не настроена; шаг 3 |
| PipeWire и WirePlumber | Пользовательский systemd | Обычно готовы после установки; проверка в шаге 3 |
| `hyprstack-session.service` | Конфигурация Hyprland при входе | Нет; `enable` и отдельный автозапуск не нужны |
| `hyprstack-vpn.service` | Кнопка подключения VPN | Нет; остановленная служба при выключенном VPN — нормальное состояние |
| Панель, уведомления, блокировка, агент Polkit | Сеанс Hyprstack | Отдельные службы устанавливать не нужно |

Если прежняя панель, демон уведомлений или агент Polkit запускаются вашими
отдельными пользовательскими службами, отключите их автозапуск в сеансе Hyprland.
В перенесённую конфигурацию не добавляйте второй экземпляр этих компонентов.

## Дополнительные возможности

| Пакет | Для чего |
| --- | --- |
| `bluez` | Bluetooth; после установки включите `sudo systemctl enable --now bluetooth.service` |
| `upower` | Сведения о батарее |
| `power-profiles-daemon` | Профили питания; `sudo systemctl enable --now power-profiles-daemon.service` |
| `ddcutil` | Яркость внешних экранов с DDC/CI |
| `wtype` | Ввод emoji в активное приложение |

Тема синхронизируется с поддерживаемыми терминалами, включая Kitty и Foot.
**Fish — командная оболочка внутри терминала**: фон и ANSI-палитру задаёт терминал,
а подсветку Fish и тему приглашения настраивают отдельно.
[Поддерживаемые приложения и ограничения](CONFIGURATION.md#цвета-терминала-и-командная-оболочка).

VPN настраивается в **Настройки → Сеть → Настройки VPN**. Ядра sing-box/Xray
загружаются по необходимости; для TUN один раз выдаются сетевые права через Polkit.
[Протоколы, импорт и маршрутизация](CONFIGURATION.md#vpn-и-прокси).

[Настройки и клавиши](CONFIGURATION.md) · [Обновление и диагностика](MAINTENANCE.md)
