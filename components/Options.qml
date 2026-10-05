// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2025-2026 QueMusic Contributors
//
pragma Singleton
import QtQuick
import QueMusic 1.0
import QWindowKit 1.0

QtObject {
    // 跨文件共享对象：AppRoot（常驻根）注入引擎/队列/托盘/SMTC，主窗口场景注入界面组件
    property QueueModel queue
    property AudioEngine mainMedia     // 播放引擎（常驻：窗口销毁后继续播放）
    property SystemTrayManager tray    // 系统托盘（常驻：场景销毁后仍可恢复/退出）
    property QtObject app              // 常驻根 AppRoot 本身：主窗口场景销毁/重建控制
    property QWarn warn
    property QAlertDialog dialog
    property WindowAgent agent
    property DesktopPlayer desktop
    property SmtcBridge smtc

    // 关闭到托盘的气泡提示只弹一次（跨场景生效）
    property bool trayTipShown: false
    // 桌面部件模式：0.无 1.小窗播放器 2.桌面歌词（跨场景存活，与 AppRoot 里的桌面部件 Loader 对应）
    property int desktopPlayerMode: 0

    // window 上移过来的状态
    property int exitIndex: 0          // 要求主界面切到的页
    property bool homeLoaded: false    // 首页是否已加载过
    property bool recordingShortCut: false
    readonly property string version: "0.5.1"
    readonly property int versionCode: 51
    readonly property int pluginApi: 10

    // 配置存储，后续也可以存储在服务器数据库中
    // 使用存储仅需把 QtObject 换成 Settings
    property OptionsSettings settings: OptionsSettings {}

    // 最后播放的歌曲（关闭软件时保存，下次打开首页显示）
    property OptionsLastSongs lastSongs: OptionsLastSongs {}

    // 快捷键（持久化到 ShortCuts 配置组）
    property OptionsShortCuts shortCuts: OptionsShortCuts {}

    signal changeOptions()
}
