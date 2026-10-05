// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2025-2026 QueMusic Contributors
//
// 主窗口场景：由 AppRoot（常驻根）创建/销毁/重建。开启「最小化托盘」后关闭窗口
// 会销毁整个场景（原生窗口 + 界面 QML 对象全部释放），播放核心存活于 AppRoot 后台继续。
import QtQuick
import QueMusic 1.0
import QtCore
import QWindowKit 1.0
import QtQuick.Controls.Basic

Window {
    id: window
    width: 1140
    height: 720
    minimumWidth: 810
    minimumHeight: 540
    color: Style.primaryColor
    title: "QueMusic"

    // 常驻对象桥接：引擎/队列实际存活于 AppRoot（经 Options 注入），
    // 以同名属性暴露后，本文件内所有既有 mainMedia / playListModel 引用无需改动
    readonly property AudioEngine mainMedia: Options.mainMedia
    readonly property QueueModel playListModel: Options.queue

    // 托盘唤起（场景存活时）：最小化还原/置前；场景已销毁时由 AppRoot 重建
    function restoreFromTray(): void {
        win.restoreWindow()
    }
    function saveGeometry(): void {
        win.saveGeometry()
    }

    Component.onCompleted: {
        Options.warn = mainWarn
        Options.dialog = globalDialog
        Options.agent = windowAgent
        Options.desktop = desktopPlayer
        windowAgent.setup(window);
        // dark-mode / extra-margins / title-bar-height 是 Windows 专有属性
        if(!window.isMacOS) {
            // dwm-blur acrylic-material mica mica-alt
            windowAgent.setWindowAttribute("dark-mode", false);
            if(Options.settings.noWindowKit) {
                windowAgent.setWindowAttribute("extra-margins", 3);
                windowAgent.setWindowAttribute("title-bar-height", 40);
            }
        }
        MusicApi.songSource = Options.settings.mainMusicSource;
        MusicApi.downloadPath = Options.settings.downloadFolder;
        MusicApi.soundQuality = Options.settings.soundQuality;

        if(Options.settings.rememberWindow && Options.settings.winW > 0) {
            window.x = Options.settings.winX;
            window.y = Options.settings.winY;
            window.width = Options.settings.winW;
            window.height = Options.settings.winH;
        }

        if (Options.settings.winMax)
            window.showMaximized()
        else
            window.visible = true;

        // 场景重建或首次启动：把 SMTC 绑定到当前原生窗口（HWND 变化时必需）
        Options.smtc.targetWindow = window;
        Options.smtc.rebindWindow();

        Style.changeUi();
        Style.changeTheme();
    }

    Binding {
        target: MusicApi
        property: "soundQuality"
        value: Options.settings.soundQuality
    }
    Binding {
        target: MusicApi
        property: "downloadPath"
        value: Options.settings.downloadFolder
    }



    readonly property bool isMacOS: Qt.platform.os === "osx"

    // 标题栏是窗口拖拽区：插件挂进去的对象要标记可命中，否则点击会被拖拽吞掉
    function syncTitleBarHitTest(): void {
        const kids = barRightWidgets.children;
        for (let i = 0; i < kids.length; ++i)
            windowAgent.setHitTestVisible(kids[i], true);
    }

    function doSearch(text: string): void {
        MusicApi.searchSongsResults.clear();
        mainContent.contentIndexed(6);
        Options.settings.searchList = Options.settings.searchList.filter(value => value !== text);
        Options.settings.searchList.splice(0, 0, text);
        MusicApi.searchSongs(text, MusicApi.nowIndex, 1, 20);
        Options.exitIndex = 1;
    }

    // 首次加载内容临时存储，防止重新加载浪费内存
    property QtObject completedStart: QtObject {
        property bool homeLoaded: false
        property bool playlistLoaded: false
    }

    // 系统级关闭（Alt+F4、任务栏右键"关闭窗口"）与关闭按钮行为保持一致
    onClosing: function(close) {
        if(win.closeToTray()) {
            close.accepted = false;
            win.destroyToTray();
            return;
        }
        // 未开启托盘时也要走保存与会话收尾，不能直接放行
        close.accepted = false;
        win.toClosing();
    }

    WindowControls {
        id: win
        targetWindow: window
        tray: Options.tray
    }
    signal getKeys(var keys)
    signal exit()

    signal message(string title,string text,int type)

    Shortcut {
        sequence: "Esc"
        context: Qt.ApplicationShortcut
        enabled: !Options.recordingShortCut
        onActivated: {
            window.exit();
            console.log("Exit");
            if(Options.exitIndex > 0) {
                Options.exitIndex -= 1;
            }
            mainLayout.forceActiveFocus();
        }
    }
    // 键位与开关都走设置页（Options.shortCuts / globalShortcut*）
    Instantiator {
        model: [
            { k: "volumeUp",      a: function() { Playback.stepVolume(Playback.volumeStep); mainWarn.tiped("音量 " + Math.round(Options.settings.musicVolume * 100) + "%", 0) } },
            { k: "volumeDown",    a: function() { Playback.stepVolume(-Playback.volumeStep); mainWarn.tiped("音量 " + Math.round(Options.settings.musicVolume * 100) + "%", 0) } },
            { k: "seekBack",      a: function() { Playback.seekBack() } },
            { k: "seekForward",   a: function() { Playback.seekForward() } },
            { k: "mute",          a: function() { Playback.toggleMute(); mainWarn.tiped(Playback.muted ? "已静音" : "取消静音", 0) } },
            { k: "abLoop",        a: function() {
                Playback.setAbPoint(Playback.abA < 0 || Playback.abArmed ? 0 : 1);
                mainWarn.tiped(Playback.abArmed ? "A-B 循环已启用" : "已设置 A-B 起点", 1);
            } },
            { k: "favorite",      a: function() { musicControlMin.toggleFavorite() } },
            { k: "playerOptions", a: function() { musicControlMin.openPlayerOptions() } },
            { k: "play",          a: function() { Playback.togglePlay() } },
            { k: "back",          a: function() { Playback.previous() } },
            { k: "forward",       a: function() { Playback.next(false) } },
            { k: "playList",      a: function() { playList.visible ? playList.close() : playList.open() } },
            { k: "musicControl",  a: function() {
                if (mainLayout.state === "") {
                    controlMaxLoader.active = true;
                } else {
                    window.playermined();
                    minedAnimation.start();
                    mainLayout.state = "";
                }
            } }
        ]
        delegate: Shortcut {
            readonly property string flag: "globalShortcut" + modelData.k.charAt(0).toUpperCase() + modelData.k.slice(1)
            sequence: Options.shortCuts[modelData.k]
            context: Qt.ApplicationShortcut
            enabled: Options.settings.openShortCut && Options.shortCuts[flag]
            onActivated: modelData.a()
        }
    }

    FontLoader {
        id: iconFont
        source: "qrc:/QueMusic/resources/fonts/feather.ttf"
    }
    FontLoader {
        id: textFont
        source: "qrc:/QueMusic/resources/fonts/poppins.ttf"
    }

    WindowAgent {
        id: windowAgent
    }

    // 顶部栏 - 与qwindowkit和window耦合，难抽为组件
    Rectangle {
        id: titleBar
        x: 0
        y: 0
        z: 10
        width: window.width
        height: 60
        color: "transparent"
        property bool toBarLyric: musicControlMax.y === 0

        // 此组件创建时，将此组件与 qwindowkit 绑定，标题栏事件由此传入
        Component.onCompleted: windowAgent.setTitleBar(titleBar);

        Item {
            id: appTitleBlock
            x: 10
            y: 10
            width: 180
            height: 40
            Component.onCompleted: windowAgent.setHitTestVisible(appTitleBlock, true)
        }

        Row {
            id: barLeftWidgets
            y: 12
            Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            anchors {
                left: parent.left
                leftMargin: sidebar.width + 16
            }
            spacing: 5

            QWKButton {
                id: returnButton
                source: Style.darkis ? "qrc:/QueMusic/resources/window-bar/returnd.svg" : "qrc:/QueMusic/resources/window-bar/return.svg"
                onClicked: {
                    window.exit()
                    console.log("Exit")
                    if(Options.exitIndex > 0) {
                        Options.exitIndex -= 1
                    }
                }
                Component.onCompleted: windowAgent.setHitTestVisible(returnButton, true);
            }

            TextField {
                id: mainSearchInput
                x: 20
                y: 0
                height: 36
                width: 160
                leftPadding: 16
                placeholderText: "搜索"
                color: Style.textColor
                font.pixelSize: Style.settings.textmain
                verticalAlignment: Text.AlignVCenter
                selectionColor: Style.containColor
                focus: false
                onReleased: searchCard.open();
                onAccepted: {
                    if(text.trim() == "") {
                        mainWarn.tiped("请输入搜索内容", 0);
                        return;
                    }
                    window.doSearch(text);
                    searchCard.close();
                }
                Component.onCompleted: windowAgent.setHitTestVisible(mainSearchInput, true);
                background: Rectangle {
                    height: 36
                    width: 201
                    radius: 18
                    color: Style.primaryColor
                }
            }
            SButton {
                id: searchButton
                width: 36
                height: 36
                radius: 18
                iconCharacter: "\uf100"
                buttonColor: "transparent"
                onClicked: {
                    if(mainSearchInput.text.trim() == "") {
                        mainWarn.tiped("请输入搜索内容", 0);
                        return;
                    }
                    window.doSearch(mainSearchInput.text);
                    searchCard.close();
                }
                Component.onCompleted: windowAgent.setHitTestVisible(searchButton, true);
            }
        }

        Row {
            id: barRightWidgets
            anchors {
                right: parent.right
                rightMargin: 16
            }
            spacing: 0
            y: 10 - musicControlMax.hideHeight
            height: 40

            // 扩展点：标题栏（窗口按钮之前）
            PluginSlot { slotName: "titlebar"; target: barRightWidgets }

            // 全屏开关
            QWKButton {
                id: fullScreenButton
                largeicon: true
                property int prevVisibility: Window.Maximized
                buttonColor: window.visibility === Window.FullScreen ? Style.containColor : "transparent"
                source: Style.darkis || titleBar.toBarLyric ? "qrc:/QueMusic/resources/window-bar/airplayd.svg" : "qrc:/QueMusic/resources/window-bar/airplay.svg"
                onClicked: {
                    if (window.visibility === Window.FullScreen) {
                        if (prevVisibility === Window.Maximized)
                            window.showMaximized();
                        else
                            window.showNormal();
                    } else {
                        prevVisibility = window.visibility;
                        window.showFullScreen();
                    }
                }
                Component.onCompleted: windowAgent.setHitTestVisible(fullScreenButton, true);
            }

            QWKButton {
                id: settingButton
                largeicon: true
                source: Style.darkis || titleBar.toBarLyric ? "qrc:/QueMusic/resources/window-bar/settingd.svg" : "qrc:/QueMusic/resources/window-bar/setting.svg"
                onClicked: {
                    settingsView.active = true;
                }
                Component.onCompleted: windowAgent.setHitTestVisible(settingButton, true);
            }

            QWKButton {
                id: minButton
                source: Style.darkis || titleBar.toBarLyric ? "qrc:/QueMusic/resources/window-bar/minimized.svg" : "qrc:/QueMusic/resources/window-bar/minimize.svg"
                onClicked: window.showMinimized();
                Component.onCompleted: {
                    if(window.isMacOS) {
                        visible = false;
                    } else {
                        windowAgent.setSystemButton(WindowAgent.Minimize, minButton);
                    }
                }
            }

            QWKButton {
                readonly property string maximized: Style.darkis || titleBar.toBarLyric ? "qrc:/QueMusic/resources/window-bar/maximized.svg" : "qrc:/QueMusic/resources/window-bar/maximize.svg"
                readonly property string restored: Style.darkis || titleBar.toBarLyric ? "qrc:/QueMusic/resources/window-bar/restored.svg" : "qrc:/QueMusic/resources/window-bar/restore.svg"
                id: maxButton
                source: window.visibility === Window.Maximized ? restored : maximized
                onClicked: {
                    if (window.visibility === Window.Maximized) {
                        window.showNormal();
                    } else {
                        window.showMaximized();
                    }
                }
                Component.onCompleted: {
                    if(window.isMacOS) {
                        visible = false;
                    } else {
                        windowAgent.setSystemButton(WindowAgent.Maximize, maxButton);
                    }
                }
            }

            QWKButton {
                readonly property string hover: Style.darkis ? "qrc:/QueMusic/resources/window-bar/close.svg" : "qrc:/QueMusic/resources/window-bar/closed.svg"
                readonly property string unhover: Style.darkis || titleBar.toBarLyric ? "qrc:/QueMusic/resources/window-bar/closed.svg" : "qrc:/QueMusic/resources/window-bar/close.svg"
                id: closeButton
                source: closeButton.hovered ? hover : unhover
                hoverColor: "#ee4848"
                onClicked: win.toClosing();
                Component.onCompleted: {
                    if(window.isMacOS) {
                        visible = false;
                    } else {
                        windowAgent.setSystemButton(WindowAgent.Close, closeButton);
                    }
                }
            }
        }
    }

    Item {
        id: mainLayout
        anchors.fill: parent
        z: 5
        property int maxLyricType: 0

        Connections {
            target: Style
            function onChangeTheme(): void {
                windowAgent.setWindowAttribute("dwm-blur", false);
                if(Style.settings.backmode === 0) {
                    backGround.visible = false;
                    sidebar.baseColor = Style.primaryColor;
                    window.color = Style.primaryColor;
                    mainContent.color = Style.secondaryColor;
                } else if(Style.settings.backmode === 1) {
                    backGround.visible = false;
                    sidebar.baseColor = Style.primaryBlurColor;
                    window.color = Style.containColor;
                    mainContent.color = Style.blurOverlayColor;
                } else if(Style.settings.backmode === 2) {
                    backGround.visible = true;
                    sidebar.baseColor = Style.blurOverlayColor;
                    window.color = Style.primaryColor;
                    mainContent.color = Style.blurOverlayColor;
                    backGround.source = "qrc:/QueMusic/resources/pic/cloudRainbow.png";
                } else if(Style.settings.backmode === 3) {
                    backGround.visible = true;
                    sidebar.baseColor = Style.blurOverlayColor;
                    window.color = Style.primaryColor;
                    mainContent.color = Style.blurOverlayColor;
                    switch(Style.settings.backpic) {
                        case 0:
                            backGround.source = "qrc:/QueMusic/resources/pic/back1.jpg";
                            break;
                        case 1:
                            backGround.source = "qrc:/QueMusic/resources/pic/back3.jpg";
                            break;
                        case 2:
                            backGround.source = Style.settings.backgroundImage;
                            break;
                    }
                } else if(Style.settings.backmode === 4) {
                    backGround.visible = false;
                    sidebar.baseColor = Style.primaryBlurColor;
                    window.color = "transparent";
                    mainContent.color = Style.primaryBlurColor;
                    windowAgent.setWindowAttribute("dwm-blur", true);
                }
            }
        }
        Image {
            id: backGround
            z: 0
            x: 0
            y: 0
            width: parent.width
            height: parent.height
            visible: false
            asynchronous: true
            fillMode: Image.PreserveAspectCrop

        }

        LeftSideBar {
            z: 2
            id: sidebar
            x: 0
            y: 0
            height: parent.height - 78
            width: 210
        }

        MainContent {
            z: 1
            id: mainContent
            x: sidebar.width
            y: 0
            width: parent.width - x
            height: parent.height - 78
        }

        PlayerControl {
            id: musicControlMin
            x: 0
            width: parent.width
            height: 78
            z: 4
        }

        PlayerMaxCenter {
            id: musicControlMax
            width: mainLayout.width
            height: mainLayout.height
            y: 100//mainLayout.height
            visible: false
            z: 3
        }

        NumberAnimation {
            id: openMaxLyric
            duration: 420
            target: musicControlMax
            property: "y"
            from: mainLayout.height
            to: 0
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [ 0.30, 0.08, 0.00, 1.00, 1, 1 ]
            onStarted: {
                musicControlMax.visible = true;
                barLeftWidgets.y = -48;
            }
        }
        NumberAnimation {
            id: closeMaxLyric
            duration: 420
            target: musicControlMax
            property: "y"
            to: mainLayout.height
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [ 0.50, 0.08, 0.00, 1.00, 1, 1 ]
            onStarted: barLeftWidgets.y = 12;
            onFinished: {
                musicControlMax.visible = false;
                musicControlMax.hideHeight = 0;
            }
        }

        // 封面主题色：状态常驻 AppRoot（取色器也在那边），
        // 窗口销毁期间换歌，恢复界面后颜色也是最新的
        Item {
            id: coverColor
            width: 800
            height: 600
            property color color1: Options.app.coverColor1
            property color color2: Options.app.coverColor2
            property color color3: Options.app.coverColor3
            property bool thirdColors: Options.app.coverThirdColors
        }
    }

    Loader {
        id: settingsView
        anchors.fill: parent
        active: false
        asynchronous: true
        visible: false
        z: 6
        sourceComponent: SettingsView {}
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        onLoaded: {
            visible = true;
            settingAnime.running = true;
        }
    }

    Loader {
        active: Options.settings.displayFps
        visible: active
        anchors.top: mainLayout.top
        anchors.right: mainLayout.right
        anchors.topMargin: 68
        anchors.rightMargin: 16
        width: 78
        height: 24
        sourceComponent: Item {
            id: fpsCounter
            z: 99
            visible: true
            property int frames: 0
            property real fps: 0
            Rectangle {
                anchors.fill: parent
                radius: 12
                color: Style.shadowColor
                opacity: 0.75
            }
            Text {
                anchors.centerIn: parent
                text: fpsCounter.fps.toFixed(0) + " FPS"
                color: Style.fontColor
                font.pixelSize: 11
                font.bold: true
            }
            Timer {
                interval: 500
                repeat: true
                running: fpsCounter.visible
                onTriggered: {
                    fpsCounter.fps = fpsCounter.frames * 2;
                    fpsCounter.frames = 0;
                }
            }
            Connections {
                // 关闭帧率显示时不挂每帧回调，避免白耗 JS 调用
                enabled: Options.settings.displayFps
                target: window
                function onAfterRendering(): void { fpsCounter.frames++ }
            }
        }
    }

    Loader {
        active: Options.settings.debug
        visible: active
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: 68
        anchors.leftMargin: 220
        width: 260
        height: 92
        sourceComponent: Item {
            id: debugHud
            z: 99
            property string info: ""
            Rectangle {
                anchors.fill: parent
                radius: 12
                color: Style.shadowColor
                opacity: 0.75
            }
            Text {
                anchors.fill: parent
                anchors.margins: 10
                text: debugHud.info
                color: Style.fontColor
                font.pixelSize: 11
                font.family: TextFont.name
            }
            Timer {
                interval: 500
                repeat: true
                running: debugHud.visible
                onTriggered: {
                    debugHud.info = "调试模式"
                            + "\n媒体状态: " + mainMedia.mediaStatus
                            + "\n进度: " + Math.floor(mainMedia.position / 1000) + "s / " + Math.floor(mainMedia.duration / 1000) + "s"
                            + "\n队列: " + playListModel.count + " 首"
                            + "\n音量: " + Math.round(Options.settings.musicVolume * 100) + "%"
                }
            }
        }
    }

    NumberAnimation {
        id: settingAnime
        target: settingsView
        property: "opacity"
        duration: 240
        from: 0
        to: 1
        easing.type: Easing.OutCubic
        onFinished: {
            closeMaxLyric.running = true;
            mainLayout.visible = false;
        }
    }
    NumberAnimation {
        id: settingOutAnime
        target: settingsView
        property: "opacity"
        duration: 240
        from: 1
        to: 0
        easing.type: Easing.OutCubic
        onStarted: mainLayout.visible = true;
        onFinished: {
            settingsView.visible = false;
            settingsView.active = false;
        }
    }

    // 播放引擎 / 播放事件接线（CoverHelper、WebDavCache、MusicApi 的 Connections）
    // 与取色器均常驻 AppRoot，不随本场景销毁；这里仅保留频谱取波形（渲染需要本窗口）

    GetWave {
        id: getWave
        engine: mainMedia
        renderWindow: window
        enabled: Style.settings.waveDisplay && musicControlMax.visible
        bands: 128
    }

    // 播放引擎（AudioEngine）、播放队列（QueueModel）、系统托盘（SystemTrayManager）、
    // SMTC 桥（SmtcBridge）均常驻 AppRoot，不再由本场景持有

    SearchCard {
        id: searchCard
        onSearchIndex: (index) => {
            const name = Options.settings.searchList[index];
            mainSearchInput.text = name;
            window.doSearch(name);
            searchCard.close();
        }
    }

    DesktopPlayer {
        id: desktopPlayer
    }

    QAlertDialog {
        id: globalDialog
        title: "Dialog"
        message: "呃呃呃呃呃呃喵？(>-<)"
        isInput: false
        blurSource: mainLayout.visible ? mainLayout : settingsView

        property var dialogCallback: null

        function openSimpleDialog(title: string, text: string, callBack: var): void {
            globalDialog.title = title;
            globalDialog.message = text;
            globalDialog.isInput = false;
            globalDialog.dialogCallback = callBack || null;
            globalDialog.open();
        }

        onConfirm: {
            if (globalDialog.dialogCallback) {
                const cb = globalDialog.dialogCallback;
                globalDialog.dialogCallback = null;
                cb();
            }
        }
    }
    QWarn {
        id: mainWarn
        Connections {
            target: Style
            function onWarned(text: string, type: int): void {
                mainWarn.tiped(text,type);
            }
        }
    }
    QMessage {
        id: mainMessage
        function openSimpleDialog(title: string, text: string, callBack: var): void {
            mainMessage.dialog(title,text,"\uf11a");
        }
    }
    QOptionDialog {
        id: picWatch
        property string source: "qrc:/QueMusic/resources/app/musicpic.png"
        property string fileName: "Picture.png"
        title: "查看图片"
        cancelText: "保存"
        cancelIcon: "\uf00f"
        onCancel: {
            const sysPicPath = StandardPaths.writableLocation(StandardPaths.PicturesLocation)
            if(imageWatch.status === Image.Ready) {
                imageWatch.grabToImage(function(result) {
                    result.saveToFile(sysPicPath + "/" + picWatch.fileName);
                    console.log("图片已保存！");
                    mainWarn.tiped("已保存至系统图片文件夹",1);
                },Qt.size(512,512))
            } else {
                mainWarn.tiped("图片尚未加载完成，请稍候", 0);
            }
        }
        function dialog(_source: string, _title: string): void {
            source = _source;
            fileName = _title + ".png";
            picWatch.open();
        }

        options: Column {
                    width: parent.width
                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        id: imageWatch
                        source: picWatch.source
                        width: 256
                        height: 256
                        cache: false
                        sourceSize.width: 512
                        sourceSize.height: 512
                        fillMode: Image.PreserveAspectCrop
                        MouseArea {
                            id: dragImageArea
                            anchors.fill: imageWatch
                            drag.target: dragImage
                        }
                    }
                    Item {
                        id: dragImage
                        Drag.active: dragImageArea.drag.active
                        Drag.dragType: Drag.Automatic
                        Drag.supportedActions: Qt.CopyAction
                        Drag.imageSource: imageWatch.source
                        Drag.imageSourceSize: Qt.size(64, 64)
                        Drag.mimeData: { "text/uri-list": imageWatch.source }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        height: 40
                        text: picWatch.fileName
                        font.pixelSize: Style.settings.textH2
                        color: Style.textColor
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
    }
    Loader {
        id: textWatch
        anchors.fill: parent
        active: false
        asynchronous: true
        visible: status == Loader.Ready
        source: "qrc:/QueMusic/components/QTextWindow.qml"
    }

    // 扩展点：整窗覆盖层（插件自己定位，默认不吃鼠标事件）
    Item {
        id: pluginOverlay
        anchors.fill: parent
        z: 20
        PluginSlot { slotName: "window.overlay"; target: pluginOverlay }
    }

    PluginHost {
        onPluginLoaded: window.syncTitleBarHitTest()
    }
}