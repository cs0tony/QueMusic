// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2025-2026 QueMusic Contributors
//
// 常驻根：播放引擎 / 播放队列 / 托盘 / SMTC / 桌面部件 / 播放逻辑接线都活在这里。
// 主窗口场景（MainWindow.qml）销毁重建不影响它们——「关闭窗口实际销毁窗口、后台继续播放」的基石。
// 注意：根是 QtObject（无默认属性），所有子对象一律写成 property 值对象（与 Playback.qml 同构）。
import QtQuick
import QtMultimedia
import QueMusic 1.0

QtObject {
    id: appRoot

    // ── 播放核心（跨场景存活）────────────────────────────────────
    readonly property AudioEngine mainMedia: AudioEngine {
        // 封面初值；noTitle / onMedia 由引擎提供，专辑等元数据直接读 albumTitle / mediaDate / mediaType
        urlStr: "qrc:/QueMusic/resources/app/musicpic.png"

        source: ""
        volume: Playback.outVolume
        deviceId: Options.settings.useDefaultDevice || appRoot.musicDevices.audioOutputs.length <= Options.settings.audioDevice
                  ? "" : String(appRoot.musicDevices.audioOutputs[Options.settings.audioDevice].id)

        onMetaDataChanged: {
            if (appRoot.mainMedia.source.toString().startsWith("http"))
                return
            if (tagTitle)
                Playback.musicTitle = tagTitle
            if (artist)
                Playback.musicArtist = artist
        }

        onMediaStatusChanged: {
            if (mediaStatus === AudioEngine.LoadedMedia)
                Playback.autoSkipCount = 0;
            if(mediaStatus === AudioEngine.EndOfMedia) {
                if(Playback.sleepMode === 2) {
                    Playback.sleepEnd();
                    return;
                }
                switch(Options.settings.cycleIndex) {
                    case 0:
                        Playback.next(false);
                        break;
                    case 1:
                        // 重播同样会刷新缓冲，走淡出/淡入
                        Playback.swap(function() {
                            appRoot.mainMedia.position = 0;
                            appRoot.mainMedia.play();
                        })
                        break;
                    case 2:
                        Playback.next(true);
                        break;
                    case 3:
                        // 停止不再淡回，直接复位音量乘数
                        Playback.swap(function() { appRoot.mainMedia.stop() }, false);
                        break;
                }
            }
        }

        onErrorOccurred: {
            if(appRoot.playListModel.count < 2) return;
            if (Playback.autoSkipCount >= 2) {
                Playback.autoSkipCount = 0;
                Style.warned("连续多首无法播放，已停止自动跳过", 0);
                return;
            }
            Playback.autoSkipCount += 1;
            Style.warned("当前歌曲无法播放，已自动跳过",0);
            if(Options.settings.cycleIndex === 2) {
                Playback.next(true);
            } else {
                Playback.next(false);
            }
        }

        // 新音轨真正起播后再淡回，避免音频设备重开的瞬间已经有音量
        onPlayingChanged: {
            if (playing)
                Playback.finishSwap();
        }

        onSourceChanged: {
            Playback.clearAb();
        }
        onPlaybackStateChanged: {
            if (appRoot.mainMedia.playbackState === AudioEngine.PlayingState)
                Playback.noteNowPlaying();
        }
    }
    readonly property QueueModel playListModel: QueueModel {
        playListIndex: -1
    }
    readonly property MediaDevices musicDevices: MediaDevices {}

    // ── 系统媒体控件桥（持久）：窗口销毁期间 SMTC 仍能控制后台播放 ──
    readonly property SmtcBridge smtcBridge: SmtcBridge {
        player: appRoot.mainMedia
        queue: appRoot.playListModel
    }

    // ── 系统托盘（持久）：场景销毁后恢复/退出/控制播放的唯一入口 ──
    readonly property SystemTrayManager systemTray: SystemTrayManager {
        iconSource: "qrc:/QueMusic/resources/icon.ico"
        title: "QueMusic"
        playing: appRoot.mainMedia.playbackState === AudioEngine.PlayingState
        nowPlaying: Playback.musicTitle !== "QueMusic"
                    ? Playback.musicTitle + (Playback.musicArtist && Playback.musicArtist !== "Artist"
                                           ? " - " + Playback.musicArtist : "")
                    : ""

        onShowWindowRequested: appRoot.restoreMainWindow()
        onPlayPauseRequested: Playback.togglePlay()
        onPreviousRequested: Playback.previous()
        onNextRequested: Playback.next(false)
        onQuitRequested: appRoot.quitApp()
        onActivated: (reason) => {
            // 左键单击 / 双击托盘图标：恢复主界面
            if(reason === SystemTrayManager.Trigger || reason === SystemTrayManager.DoubleClick)
                appRoot.restoreMainWindow();
        }
    }

    // ── 封面取色（持久）：关闭窗口期间换歌，恢复界面后主题色也是对的 ──
    property color coverColor1: "#00ee66"
    property color coverColor2: "#00b1ee"
    property color coverColor3: "#9d4edd"
    property bool coverThirdColors: true

    // 一轮取色完成（界面侧据此重放主题色过渡动画）
    signal coverColorsExtracted()

    // 取色在工作线程完成，结果回填常驻状态；界面侧只读绑定
    property ColorExtractor colorExtractor: ColorExtractor {
        onColorsExtracted: (colors) => {
            appRoot.coverColor1 = colors.length > 0 ? colors[0] : "#00b1ee";
            appRoot.coverColor2 = colors.length > 1 ? colors[1] : "#9d4edd";
            appRoot.coverColor3 = colors.length > 2 ? colors[2]
                              : (colors.length === 2 ? colors[0] : "#00ea64");
            appRoot.coverThirdColors = colors.length >= 3 || colors.length < 2;
            appRoot.coverColorsExtracted();
        }

        onColorsExtractedAsString: (colors) => {
            console.log("颜色字符串:", colors);
        }
    }

    // ── 封面兜底查找（持久）──
    readonly property CoverHelper coverHelper: CoverHelper {
        onLocalCoverReady: (path, coverUrl) => {
            if (path !== Playback.localLyricsRequestPath)
                return;
            const localCover = coverUrl || appRoot.coverHelper.findLocalCover(path);
            appRoot.mainMedia.urlStr = localCover || "qrc:/QueMusic/resources/app/musicpic.png";
            if (localCover)
                appRoot.colorExtractor.extractColorsFromUrl(localCover);
        }
    }

    // ── 桌面部件（持久）：桌面歌词 / 小窗播放器不随主窗口销毁 ──
    readonly property Loader desktopPlayerLoader: Loader {
        active: false
        asynchronous: true
        visible: status == Loader.Ready
        source: "qrc:/QueMusic/components/DesktopPlayerWindow.qml"
    }
    readonly property Loader desktopLyricsLoader: Loader {
        active: false
        asynchronous: true
        visible: status == Loader.Ready
        source: "qrc:/QueMusic/components/DesktopLyrics.qml"
    }

    // ── 自动检查更新（持久，每次进程只查一次）──
    function silentUpdateCheck(): void {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                const remote = parseInt(xhr.responseText.trim().substring(0, 3));
                if (remote > Options.versionCode)
                    Style.warned("发现新版本 v" + remote + "，请在设置-关于中查看", 1);
            }
        }
        xhr.open("GET", "https://raw.githubusercontent.com/BroNekoX/QueMusic/main/doc/updater.txt");
        xhr.send();
    }
    property Timer autoUpdateTimer: Timer {
        interval: 3000
        onTriggered: appRoot.silentUpdateCheck()
    }

    // ── 播放事件接线（原 main.qml 的 Connections，全部属于播放逻辑）──
    // WebDAV 缓存落地：按本地文件那套回填（标签/同名歌词/同目录封面）
    property Connections webDavCacheHook: Connections {
        target: WebDavCache
        function onCached(url: string, localPath: string): void {
            if (appRoot.mainMedia.source.toString() !== url)
                return;
            Playback.localLyricsRequestPath = localPath;
            MusicApi.readLocalMetadataAsync(localPath);
        }
    }

    property Connections musicApiHook: Connections {
        target: MusicApi
        function onUrlplay(playurl: string, title: string, artist: string, cover: string,
                           solve: string, hash: string, source: int): void {
            appRoot.mainMedia.noTitle = title;
            Playback.musicTitle = title;
            Playback.musicArtist = artist;
            Playback.musicHash = hash;
            Playback.musicSource = source;
            appRoot.mainMedia.urlStr = cover;
            appRoot.colorExtractor.extractColorsFromUrl(solve);
            // 淡出静音排空设备缓冲后再换源：上一首仍在播放，直接换 source 会截断波形产生爆音
            Playback.swap(function() {
                appRoot.mainMedia.source = playurl;
                appRoot.mainMedia.play();
            });

            const listIndex = Playback.indexOfPath(hash);
            if (listIndex < 0) {
                appRoot.playListModel.append({ name: title, path: hash, songer: artist, source: source });
                appRoot.playListModel.playListIndex = appRoot.playListModel.count - 1;
            } else {
                appRoot.playListModel.playListIndex = listIndex;
            }
        }
        // 提示统一走 Style 信号：窗口场景在时由 QWarn 弹出，场景销毁期间自动静默
        function onWarned(text: string, type: int): void {
            Style.warned(text, type);
        }
        function onLocalLyricsReady(filePath: string, lyrics: var, translate: var): void {
            if (filePath !== Playback.localLyricsRequestPath)
                return;
            MusicApi.lyricsData = lyrics;
            MusicApi.lyricsTranslate = translate || [];
        }
        function onLocalLyricsFailed(filePath: string): void {
            if (filePath !== Playback.localLyricsRequestPath)
                return;
            if ((MusicApi.lyricsData || []).length > 1) // 已有歌词（如内嵌 SYLT）就保留，别退回占位
                return;
            MusicApi.setLocalLyrics();
        }
        function onLocalMetadataReady(filePath: string, meta: var): void {
            if (filePath !== Playback.localLyricsRequestPath)
                return;
            if (meta.title)
                Playback.musicTitle = meta.title;
            if (meta.artist)
                Playback.musicArtist = meta.artist;
            // 专辑名由引擎自身解析的 albumTitle 提供（只读），此处不再赋值
            const hasMetaLyrics = meta.lyrics && meta.lyrics.length > 0;
            MusicApi.lyricsData = meta.lyrics || [];
            MusicApi.lyricsTranslate = meta.translate || [];
            if (!hasMetaLyrics)
                MusicApi.setLocalLyrics();
            MusicApi.readLocalLyricsAsync(filePath, meta.title || appRoot.mainMedia.noTitle,
                                          meta.artist || "", meta.duration || 0, !hasMetaLyrics);
            if (meta.cover) {
                appRoot.mainMedia.urlStr = meta.cover;
                appRoot.colorExtractor.extractColorsFromUrl(meta.cover);
            } else {
                appRoot.coverHelper.findEmbeddedCoverAsync(filePath);
            }
        }
    }

    // ── 主窗口场景生命周期 ──
    property Component mainWindowComponent: MainWindow {}
    property QtObject mainWindow: null

    function createMainWindow(): void {
        if (appRoot.mainWindow)
            return
        appRoot.mainWindow = mainWindowComponent.createObject(appRoot)
    }

    // 实际销毁整个主窗口场景（原生窗口 + 全部界面 QML 对象一起释放），
    // 引擎/队列/托盘/桌面部件存活于本常驻根，播放不受影响
    function destroyMainWindow(): void {
        if (!appRoot.mainWindow)
            return
        appRoot.mainWindow.destroy()
        appRoot.mainWindow = null
        console.log("[AppRoot] 主窗口场景已销毁，后台播放继续")
    }

    // 托盘恢复：场景在则唤起窗口（最小化还原/置前）；场景已销毁则重新创建
    // （几何与最大化状态由 MainWindow 完成时按设置恢复，SMTC 亦随之重绑新窗口）
    function restoreMainWindow(): void {
        if (appRoot.mainWindow) {
            appRoot.mainWindow.restoreFromTray()
            return
        }
        appRoot.createMainWindow()
        console.log("[AppRoot] 主窗口场景已重建")
    }

    // 播放会话保存（上次播放歌曲 + 队列 + 历史）：销毁到托盘 / 真实退出前调用
    function savePlaybackSession(): void {
        const q = appRoot.playListModel
        const idx = q.playListIndex
        if (q.count > 0 && idx >= 0) {
            const item = q.get(idx)
            Options.lastSongs.name = Playback.musicTitle
            Options.lastSongs.artist = Playback.musicArtist
            Options.lastSongs.cover = appRoot.mainMedia.urlStr || "qrc:/QueMusic/resources/app/musicpic.png"
            Options.lastSongs.hash = item.path
            Options.lastSongs.source = item.source
        }
        Playback.saveQueue()
        Playback.flush()
    }

    // 托盘菜单退出：窗口在则连几何一起保存，然后结束进程
    function quitApp(): void {
        if (appRoot.mainWindow)
            appRoot.mainWindow.saveGeometry()
        appRoot.savePlaybackSession()
        Qt.quit()
    }

    Component.onCompleted: {
        // 注入常驻对象（跨场景有效，只做一次）
        Options.mainMedia = appRoot.mainMedia
        Options.queue = appRoot.playListModel
        Options.smtc = appRoot.smtcBridge
        Options.tray = appRoot.systemTray
        Options.app = appRoot
        Playback.player = appRoot.mainMedia
        Playback.queue = appRoot.playListModel

        // 会话恢复 / 历史加载 / 封面缓存维护都是磁盘与网络 I/O，全部移出首帧
        Qt.callLater(function() {
            Playback.loadHistory()
            Playback.restoreSession()

            if(Options.settings.cacheUrl)
                appRoot.coverHelper.setCacheDir(Options.settings.cacheUrl);
            appRoot.coverHelper.pruneCache(Options.settings.cacheSize);

            if(Options.settings.autoUpdate)
                appRoot.autoUpdateTimer.start();
        })

        appRoot.createMainWindow()
    }
}
