FROM --platform=linux/amd64 jlesage/baseimage-gui:ubuntu-20.04-v4

COPY sogou-pinyin.deb /tmp
ENV DEBIAN_FRONTEND=noninteractive

# 中国替换APT源为清华源
RUN cp /etc/apt/sources.list /etc/apt/sources.list.bak && \
    sed -i 's@/archive.ubuntu.com/@/mirrors.aliyun.com/@g' /etc/apt/sources.list && \
    sed -i 's@/security.ubuntu.com/@/mirrors.aliyun.com/@g' /etc/apt/sources.list && \
    apt update && \
    apt install curl -y && \
    COUNTRY_CODE=$(curl -s --connect-timeout 3 --max-time 5 https://ifconfig.co/country-iso | tr -d '[:space:]' | awk '{print toupper($0)}') || COUNTRY_CODE=CN; \
    if [ "$COUNTRY_CODE" != "CN" ]; then \
        mv -f /etc/apt/sources.list.bak /etc/apt/sources.list && \
        apt update; \
    fi

# 安装必要依赖
RUN \
    # 安装系统语言包、字体等依赖
    apt install -y locales language-pack-zh-hans fonts-noto-cjk-extra curl \
    && locale-gen zh_CN.UTF-8 \
    && apt install -y shared-mime-info desktop-file-utils libxcb1 libxcb-icccm4 libxcb-image0 \
    libxcb-keysyms1 libxcb-randr0 libxcb-render0 libxcb-render-util0 libxcb-shape0 \
    libxcb-shm0 libxcb-sync1 libxcb-util1 libxcb-xfixes0 libxcb-xkb1 libxcb-xinerama0 \
    libxcb-xkb1 libxcb-glx0 libatk1.0-0 libatk-bridge2.0-0 libc6 libcairo2 libcups2 \
    libdbus-1-3 libfontconfig1 libgbm1 libgcc1 libgdk-pixbuf2.0-0 libglib2.0-0 \
    libgtk-3-0 libnspr4 libnss3 libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 libx11-6 \
    libxcomposite1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 \
    libxss1 libxtst6 libatomic1 libxcomposite1 libxrender1 libxrandr2 libxkbcommon-x11-0 \
    libfontconfig1 libdbus-1-3 libnss3 libx11-xcb1 libasound2 lsb-release

# 安装中文拼音输入法
RUN echo "keyboard-configuration keyboard-configuration/layoutcode string cn" | debconf-set-selections
RUN \
    # 安装 fcitx 输入法框架
    apt install -y fcitx fcitx-config-gtk fcitx-frontend-all && \
    # 卸载原有 ibus 输入法框架
    apt purge -y ibus && \
    # 安装搜狗拼音输入法 (需将 linux/amd64 搜狗拼音输入法 deb 安装包提前放置在构建目录下)
    dpkg --ignore-depends=lsb-core -i /tmp/sogou-pinyin.deb && \
    # 解决可能缺少的依赖
    apt install libqt5qml5 libqt5quick5 libqt5quickwidgets5 qml-module-qtquick2 && \
    apt install libgsettings-qt1 && \
    apt -f install && \
    # 设置默认输入法为 fcitx 并将搜狗输入法设为默认配置文件
    cp /usr/share/applications/fcitx.desktop /etc/xdg/autostart/ && \
    im-config -n fcitx && \
    mkdir -p /config/xdg/config/fcitx && \
    echo -e "[Profile]\nDefaultIMList=sogoupinyin\nfcitx-keyboard-us:False" > /config/xdg/config/fcitx/profile && \
    # 清理工作
    apt clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -r /tmp/sogou-pinyin.deb

# 生成微信图标
RUN APP_ICON_URL=https://res.wx.qq.com/a/wx_fed/assets/res/NTI4MWU5.ico && \
    install_app_icon.sh "$APP_ICON_URL"
    
# 设置应用名称
RUN set-cont-env APP_NAME "微信中文版"

# 下载微信安装包
RUN curl -O "https://dldir1v6.qq.com/weixin/Universal/Linux/WeChatLinux_x86_64.deb" && \
    dpkg -i WeChatLinux_x86_64.deb 2>&1 | tee /tmp/wechat_install.log && \
    rm WeChatLinux_x86_64.deb

# Input method environment variables for both X11 and Wayland
# XMODIFIERS: Specifies input method server for X11 applications
ENV XMODIFIERS="@im=fcitx"
# GTK_IM_MODULE: Input method module for GTK applications
ENV GTK_IM_MODULE="fcitx"
# QT_IM_MODULE: Input method module for Qt applications
ENV QT_IM_MODULE="fcitx"
# INPUT_METHOD: Fallback input method specification
ENV INPUT_METHOD="fcitx"
# GTK_IM_MODULE_FILE: Path to GTK input method configuration file
ENV GTK_IM_MODULE_FILE="/etc/gtk-3.0/settings.ini"
# QT_QPA_PLATFORMTHEME: Qt platform theme for consistent appearance
ENV QT_QPA_PLATFORMTHEME="gtk3"

RUN echo '#!/bin/sh' > /startapp.sh && \
    echo 'export DISPLAY=${DISPLAY:-:1}' >> /startapp.sh && \
    echo 'export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp}' >> /startapp.sh && \
    echo '# Ensure proper display server setup for Wayland compatibility' >> /startapp.sh && \
    echo '# Enhanced Wayland detection: check both WAYLAND_DISPLAY and XDG_SESSION_TYPE' >> /startapp.sh && \
    echo 'if [ -n "$WAYLAND_DISPLAY" ] || [ "$XDG_SESSION_TYPE" = "wayland" ]; then' >> /startapp.sh && \
    echo '    export GDK_BACKEND=x11' >> /startapp.sh && \
    echo '    export QT_QPA_PLATFORM=xcb' >> /startapp.sh && \
    echo 'fi' >> /startapp.sh && \
    echo '# Configure fcitx for both X11 and Wayland' >> /startapp.sh && \
    echo 'mkdir -p /config/fcitx' >> /startapp.sh && \
    echo '# Ensure socket directory exists with proper permissions' >> /startapp.sh && \
    echo 'mkdir -p /tmp/fcitx-socket-$(id -u)' >> /startapp.sh && \
    echo 'chmod 755 /tmp/fcitx-socket-$(id -u)' >> /startapp.sh && \
    echo 'export FCITX_SOCKET=/tmp/fcitx-socket-$(id -u)' >> /startapp.sh && \
    echo 'nohup fcitx -d --replace &>/dev/null &' >> /startapp.sh && \
    echo '(while true; do [ "$(fcitx-remote)" = "1" ] && { fcitx-remote -s sogoupinyin &>/dev/null; break; }; sleep 0.3; done) &' >> /startapp.sh && \
    echo 'exec /usr/bin/wechat' >> /startapp.sh && \
    chmod +x /startapp.sh

VOLUME /root/.xwechat
VOLUME /root/xwechat_files
VOLUME /root/downloads

# 配置微信版本号
RUN set-cont-env APP_VERSION "$(grep -o 'Unpacking wechat ([0-9.]*)' /tmp/wechat_install.log | sed 's/Unpacking wechat (\(.*\))/\1/')"
