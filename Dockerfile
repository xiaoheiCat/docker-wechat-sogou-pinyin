FROM jlesage/baseimage-gui:ubuntu-20.04-v4

# 构建参数，用于指定目标平台
ARG TARGETPLATFORM
ARG BUILDPLATFORM
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

# 多架构支持：准备搜狗输入法安装包
RUN mkdir -p /tmp/packages
COPY temp-packages/ /tmp/packages/

# 安装中文拼音输入法
RUN echo "keyboard-configuration keyboard-configuration/layoutcode string cn" | debconf-set-selections
RUN \
    # 安装 fcitx 输入法框架
    apt install -y fcitx fcitx-config-gtk fcitx-frontend-all && \
    # 卸载原有 ibus 输入法框架
    apt purge -y ibus && \
    # 根据目标平台安装对应架构的搜狗拼音输入法
    if [ "$TARGETPLATFORM" = "linux/amd64" ]; then \
        dpkg --ignore-depends=lsb-core -i /tmp/packages/sogou-pinyin-amd64.deb; \
    elif [ "$TARGETPLATFORM" = "linux/arm64" ]; then \
        dpkg --ignore-depends=lsb-core -i /tmp/packages/sogou-pinyin-arm64.deb; \
    else \
        echo "Unsupported platform: $TARGETPLATFORM"; \
        exit 1; \
    fi && \
    # 解决可能缺少的依赖
    apt install libqt5qml5 libqt5quick5 libqt5quickwidgets5 qml-module-qtquick2 && \
    apt install libgsettings-qt1 && \
    apt -f install && \
    # 设置默认输入法为 fcitx 并将搜狗输入法设为默认配置文件
    cp /usr/share/applications/fcitx.desktop /etc/xdg/autostart/ && \
    im-config -n fcitx && \
    mkdir -p /config/xdg/config/fcitx && \
    # 创建完整的fcitx配置文件
    echo -e "[Hotkey]\n# Trigger Input Method\nTriggerKey=CTRL_SPACE\n# Enumerate Input Method\nEnumerateForwardKeys=CTRL_SHIFT_KEY\nEnumerateBackwardKeys=SHIFT_CTRL_KEY\n# Skip the first input method\nEnumerateSkipFirst=False\n# Toggle embedded preedit\nTogglePreedit=CTRL_ALT_KEY\n# Remind Mode Input Method Switch\nRemindModeDisableKeys=CTRL_SPACE\n# Switch to first input method\nSwitchToFirstMethodKey=SHIFT_KEY\n# Switch between first and second input method\nSwitchToSecondMethodKey=ALT_SHIFT_KEY\n\n[Program]\n# Delay in milliseconds for switching between windows\nDelayTimeBeforeFirstIMMethod=25\n# Delay in milliseconds for switching input method\nDelayTimeBeforeSwitchIM=50\n# Share Input Method State Among Windows\nShareStateAmongAllWindows=True\n# Show Input Method Hint After Input method activated\nShowInputMethodHint=True\n# Show Input Method Hint When trigger input method\nShowInputMethodHintTriggerOnly=False\n# Show Input Method Hint Delay in milliseconds\nShowInputMethodHintDelay=500\n# Show first input method indicator\nShowFirstInputMethodIndicator=True\n# Show Current Input Method Name\nShowCurrentInputMethod=True\n# Show Input Method Name When switch input method\nShowInputMethodNameWhenSwitchInFocus=False\n# Show compact input method indicator\nShowCompactInputMethodIndicator=False\n# Show emoji icon on input method indicator\nShowEmojiOnPanel=False\n# Use custom font\nUseCustomFont=False\n# Font for input method indicator\nCustomFont=\n\n[Appearance]\n# Show Input Method Preedit in Application\nShowPreeditInApplication=True\n# Show Input Method Preedit in the top of screen\nShowPreeditInTopWindow=False\n# Show input method panel when preedit is empty\nShowInputMethodPanelWhenPreeditEmpty=False\n# Show input method panel after input method changed\nShowInputMethodPanelAfterChangedOnly=True\n# Center input method panel\nCenterInputMethodPanel=False\n# Show input method panel position relative to the cursor\nShowInputMethodPanelRelativeToCursor=True\n# Show input method panel position\nShowInputMethodPanelPosition=0\n# Input method panel is always horizontal\nHorizontalInputMethodPanel=False\n# Force to show input method panel on the screen of the cursor\nShowInputMethodPanelOnFocusedScreen=True\n# Show Input Method Panel when only one input method\nShowInputMethodPanelWhenOnlyOne=False\n# Show compact input method panel\nShowCompactInputMethodPanel=False\n# Input Method Panel Margin\nInputMethodPanelMargin=0\n# Show the version of Fcitx\nShowFcitxVersion=True\n# Show first input method indicator\nShowFirstInputMethodIndicator=True\n# Show Input Method Name When switch input method\nShowInputMethodNameWhenSwitchInFocus=False\n# Show compact input method indicator\nShowCompactInputMethodIndicator=False\n\n[Behavior]\n# Active By Default\nActiveByDefault=True\n# Share Input State\nShareInputState=All\n# Show Input Method When Inactive\nShowInputMethodWhenInactive=True\n# Show Input Method After Input method activated\nShowInputMethodAfterActivated=True\n# Auto save period in seconds\nAutoSavePeriod=5\n# Show Input Method Hint After Input method activated\nShowInputMethodHint=True\n# Show Input Method Hint When trigger input method\nShowInputMethodHintTriggerOnly=False\n# Show Input Method Hint Delay in milliseconds\nShowInputMethodHintDelay=500\n# Show first input method indicator\nShowFirstInputMethodIndicator=True\n# Show Current Input Method Name\nShowCurrentInputMethod=True\n# Show Input Method Name When switch input method\nShowInputMethodNameWhenSwitchInFocus=False\n# Show compact input method indicator\nShowCompactInputMethodIndicator=False\n# Show emoji icon on input method indicator\nShowEmojiOnPanel=False\n# Use custom font\nUseCustomFont=False\n# Font for input method indicator\nCustomFont=" > /config/xdg/config/fcitx/config && \
    echo -e "[Profile]\n# Input Method List\nIMList=fcitx-keyboard-us:True,sogoupinyin:True\n# Group List\nGroups=\n# Group Name\nGroup0Name=\n# Group Input Method List\nGroup0IMList=\n# Default Input Method\nDefaultIM=sogoupinyin\n# Default Input Method for Group0\nGroup0DefaultIM=\n# Input Method Order\nIMOrder=" > /config/xdg/config/fcitx/profile && \
    # 清理工作
    apt clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/packages

# 生成微信图标
RUN APP_ICON_URL=https://res.wx.qq.com/a/wx_fed/assets/res/NTI4MWU5.ico && \
    install_app_icon.sh "$APP_ICON_URL"
    
# 设置应用名称
RUN set-cont-env APP_NAME "微信中文版"

# 根据目标平台下载并安装对应的微信安装包
RUN if [ "$TARGETPLATFORM" = "linux/amd64" ]; then \
        curl -o /tmp/wechat.deb "https://dldir1v6.qq.com/weixin/Universal/Linux/WeChatLinux_x86_64.deb"; \
    elif [ "$TARGETPLATFORM" = "linux/arm64" ]; then \
        curl -o /tmp/wechat.deb "https://dldir1v6.qq.com/weixin/Universal/Linux/WeChatLinux_arm64.deb"; \
    else \
        echo "Unsupported platform: $TARGETPLATFORM"; \
        exit 1; \
    fi && \
    dpkg -i /tmp/wechat.deb 2>&1 | tee /tmp/wechat_install.log && \
    rm /tmp/wechat.deb

ENV XMODIFIERS="@im=fcitx"
ENV GTK_IM_MODULE="fcitx"
ENV QT_IM_MODULE="fcitx"
ENV XIM_PROGRAM="fcitx"
ENV XIM=fcitx

# 复制增强版启动脚本
COPY startapp-enhanced.sh /startapp-enhanced.sh
RUN chmod +x /startapp-enhanced.sh

# 创建标准启动脚本（使用增强版）
RUN echo '#!/bin/sh' > /startapp.sh && \
    echo 'exec /startapp-enhanced.sh' >> /startapp.sh && \
    chmod +x /startapp.sh

VOLUME /root/.xwechat
VOLUME /root/xwechat_files
VOLUME /root/downloads

# 配置微信版本号
RUN set-cont-env APP_VERSION "$(grep -o 'Unpacking wechat ([0-9.]*)' /tmp/wechat_install.log | sed 's/Unpacking wechat (\(.*\))/\1/')"
