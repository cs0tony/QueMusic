// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2025-2026 QueMusic Contributors
//
// 主窗口场景生命周期：关闭按钮与系统级关闭的分流（托盘销毁 / 真实退出）、
// 会话与窗口几何保存、托盘唤起。
// 场景整体由 AppRoot 创建与销毁——销毁时原生窗口与界面 QML 对象全部释放，
// 播放引擎/队列/托盘/桌面部件常驻 AppRoot，后台播放不中断。
import QtQuick
import QueMusic 1.0

QtObject {
    id: root

    property Window targetWindow
    property SystemTrayManager tray

    function closeToTray(): bool {
        return Options.settings.closeToManage && tray && tray.available
    }

    // 保存窗口几何与最大化状态（销毁到托盘 / 真实退出前调用）
    function saveGeometry(): void {
        if (!targetWindow)
            return
        Options.settings.winMax = targetWindow.visibility === Window.Maximized
        if (Options.settings.rememberWindow
                && targetWindow.visibility !== Window.Maximized
                && targetWindow.visibility !== Window.FullScreen) {
            Options.settings.winX = targetWindow.x
            Options.settings.winY = targetWindow.y
            Options.settings.winW = targetWindow.width
            Options.settings.winH = targetWindow.height
        }
    }

    // 保存播放会话（上次播放歌曲 / 队列 / 历史）+ 窗口几何
    function saveSession(): void {
        saveGeometry()
        Options.app.savePlaybackSession()
    }

    // 关闭（X 按钮 / Alt+F4 / 任务栏关闭）：托盘开启则销毁整个场景后台播放，否则保存会话退出
    function toClosing(): void {
        if (closeToTray()) {
            destroyToTray()
            return
        }
        saveSession()
        if (tray)
            tray.quitApplication()
    }

    // 关闭到托盘：保存会话后销毁整个主窗口场景（不是隐藏——任务栏项/句柄/渲染表面
    // 与全部界面 QML 对象一并释放）。播放引擎存活于 AppRoot，音乐继续；
    // 托盘恢复时 AppRoot 重新创建场景，SMTC 与窗口属性随新窗口重新挂接
    function destroyToTray(): void {
        if (!targetWindow || !targetWindow.visible)
            return
        if (!Options.trayTipShown) {
            Options.trayTipShown = true
            if (tray)
                tray.showMessage("QueMusic", "窗口已关闭，音乐将在后台继续播放，点击托盘图标可恢复",
                                 SystemTrayManager.Information)
        }
        saveSession()
        Options.app.destroyMainWindow()
    }

    // 场景存活时的托盘唤起：最小化则还原，再置前激活
    function restoreWindow(): void {
        if (!targetWindow)
            return
        if (targetWindow.visibility === Window.Minimized)
            targetWindow.showNormal()
        targetWindow.raise()
        targetWindow.requestActivate()
    }
}
