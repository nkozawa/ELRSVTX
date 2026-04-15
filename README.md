# ELRS VTX Admin Widget for EdgeTX

An EdgeTX widget to display VTX band and channel information retrieved from an ELRS (ExpressLRS) TX module.
![Screen](images/ELRSVTX.bmp)
---

## English

### Project Overview
This project aims to create an EdgeTX Lua widget that communicates with an ELRS module to fetch and display its current VTX band and channel settings. This information, often presented in the format "F:X:Y" (e.g., F:4:1), is crucial for pilots to quickly verify their video transmission setup directly on their EdgeTX radio screen.

### Features
*   **ELRS Communication:** Directly queries the ELRS module for VTX band and channel data.
*   **EdgeTX Widget:** Designed to run as a standalone widget on EdgeTX radios.
*   **Customizable Display:** Allows configuration of text color, text size, and display position.


### Installation
Store `main.lua` in the following path on the transmitter's SD card:
```/WIDGETS/ELRSVTX/main.lua```

### Configuration
The widget offers several configuration options to customize its appearance. These settings can be accessed through the EdgeTX radio's widget settings menu.
![Configuration Settings](images/ELRSVTXSetting.bmp)



---

## 日本語

### 概要
ELRS (ExpressLRS) TXモジュールからVTXに送るバンドとチャネル設定を取得し表示するEdgeTXのウィジェットです。

### 機能
*   **ELRS通信:** ELRS TXモジュールに直接問い合わせてVTXのバンドとチャネルデータを取得します。
*   **EdgeTXウィジェット:** EdgeTXラジオ上でウィジェットとして動作するように設計されています。
*   **カスタマイズ可能な表示:** 文字色、文字サイズ、表示位置などを設定可能です。

### 導入
送信機のSDカードの以下のパスにmain.luaを保管します。
```/WIDGETS/ELRSVTX/main.lua```

### 設定
このウィジェットは、表示をカスタマイズするためのいくつかの設定オプションを提供します。これらの設定は、EdgeTX送信機のウィジェット設定メニューからアクセスできます。
![設定画面](images/ELRSVTXSetting.bmp)


