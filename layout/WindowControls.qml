// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2025-2026 QueMusic Contributors
//
// 主窗口生命周期：托盘销毁/恢复、关闭前保存会话与窗口几何、退出流程。
import QtQuick
import QueMusic 1.0

QtObject {
    id: root

    property Window targetWindow
    property SystemTrayManager tray

    property bool forceQuit: false
    property int restoreVisibility: 0
    property bool trayTipShown: false
    property bool nativeWindowDestroyed: false   // 原生窗口已销毁，恢复时需重绑 SMTC

    signal sessionClosing()

    function closeToTray(): bool {
        return Options.settings.closeToManage && !forceQuit && tray && tray.available
    }

    function toClosing(): void {
        if (closeToTray()) {
            destroyToTray()
            return
        }
        const q = Playback.queue
        const p = Playback.player
        const idx = q ? q.playListIndex : -1
        if (q && q.count > 0 && idx >= 0) {
            const item = q.get(idx)
            Options.lastSongs.name = Playback.musicTitle
            Options.lastSongs.artist = Playback.musicArtist
            Options.lastSongs.cover = (p && p.urlStr) || "qrc:/QueMusic/resources/app/musicpic.png"
            Options.lastSongs.hash = item.path
            Options.lastSongs.source = item.source
        }
        if (Options.settings.rememberWindow && targetWindow
                && targetWindow.visibility !== Window.Maximized
                && targetWindow.visibility !== Window.FullScreen) {
            Options.settings.winX = targetWindow.x
            Options.settings.winY = targetWindow.y
            Options.settings.winW = targetWindow.width
            Options.settings.winH = targetWindow.height
        }
        Playback.saveQueue()
        Playback.flush()
        sessionClosing()
        if (tray)
            tray.quitApplication()
    }

    // 关闭窗口：实际销毁原生窗口（任务栏项/句柄/渲染表面一并释放）而不是隐藏。
    // QML 场景与播放引擎保留在内存中，音乐继续在后台播放；
    // 从托盘恢复时 show() 会自动重建原生窗口（QWindowKit 会随 WinId 变化自动重新挂接）
    function destroyToTray(): void {
        if (!targetWindow || !targetWindow.visible)
            return
        restoreVisibility = targetWindow.visibility
        nativeWindowDestroyed = true
        if (tray)
            tray.destroyWindow(targetWindow)
        if (!trayTipShown) {
            trayTipShown = true
            if (tray)
                tray.showMessage("QueMusic", "窗口已关闭，音乐将在后台继续播放，点击托盘图标可恢复",
                                 SystemTrayManager.Information)
        }
    }

    function restoreWindow(): void {
        if (!targetWindow)
            return
        if (!targetWindow.visible) {
            if (restoreVisibility === Window.Maximized)
                targetWindow.showMaximized()
            else if (restoreVisibility === Window.FullScreen)
                targetWindow.showFullScreen()
            else
                targetWindow.showNormal()
            // 原生窗口重建后 HWND 已变，SMTC 需要重新绑定到新窗口；
            // show() 返回时平台窗口已创建，此时重绑可立即拿到有效句柄
            if (nativeWindowDestroyed) {
                nativeWindowDestroyed = false
                if (Options.smtc)
                    Options.smtc.rebindWindow()
            }
        } else if (targetWindow.visibility === Window.Minimized) {
            targetWindow.showNormal()
        }
        targetWindow.raise()
        targetWindow.requestActivate()
    }

    function quitApp(): void {
        forceQuit = true
        toClosing()
    }
}
