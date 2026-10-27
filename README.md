# ELRS VTX Widget for EdgeTX

An EdgeTX widget to display VTX band and channel information retrieved from an ELRS (ExpressLRS) TX module.

![Screen](images/ELRSVTX.bmp)

Version 1.1: ELRS 4.x compatible

> ## Breaking changes: ELRS 4.0
>
> On radios running ExpressLRS 4.0 or later, version 1.0 of this widget stopped working. Update the widget to 1.1 or newer. Reference for the ELRS 4.x Lua protocol changes: [EasyVTXch ELRS 4 commit](https://github.com/Saqoosha/EasyVTXch/commit/6c863d814450d1431c5d3f7b97cdf729a4d722b5)
>
> If you had version 1.0 installed, delete the bytecode cache first (EdgeTX keeps compiled copies):
>
> ```
> /WIDGETS/ELRSVTX/main.luac
> ```

---

## English

### Overview
This project aims to create an EdgeTX Lua widget that communicates with an ELRS module to fetch and display its current VTX band and channel settings.

### Background
When you change the VTX channel in ExpressLRS Lua or EasyVTXch(https://github.com/Saqoosha/EasyVTXch) Lua, that data is stored in the ELRS TX module. This data is transmitted when the ELRS TX establishes a link with the drone, causing the VTX channel to change. The motivation for creating this widget was to provide a convenient way to view that data without having to launch ExpressLRS Lua every time you start up the transmitter.

### Features
*   **ELRS Communication:** Directly queries the ELRS module for VTX band and channel data.
*   **EdgeTX Widget:** Designed to run as a standalone widget on EdgeTX radios.
*   **Customizable Display:** Allows configuration of text color, text size, and display position.

### ELRS 4.x compatibility notes
*   Parameter responses larger than one CRSF frame arrive **chunked**; the widget reassembles them and requests each continuation chunk before advancing to the next field (ELRS 4.x behavior).
*   The VTX band field is named `Band/Enable` on ELRS 4.x (it was `Band` on 3.x); the widget accepts both.
*   When the band is Disabled, ELRS 4.x sends the VTX Administrator folder without a dynamic name. The widget then reads the current state from the `Band/Enable` and `Channel` child fields and displays `OFF`.

### Installation
Store `main.lua` in the following path on the transmitter's SD card:
```/WIDGETS/ELRSVTX/main.lua```

### Configuration
The widget offers several configuration options to customize its appearance. These settings can be accessed through the EdgeTX radio's widget settings menu.

![Configuration Settings](images/ELRSVTXSetting.bmp)

Note: The BOLD font size for TextSize is the same as STD, and the same applies to XXS and XS.

---

## 日本語

### 概要
ELRS (ExpressLRS) TXモジュールからVTXに送るバントとチャネル設定を取得し表示するEdgeTXのウィジェットです。

### 背景
ExpressLRS LuaあるいはEasyVTXch(https://github.com/Saqoosha/EasyVTXch) LuaなどでVTXチャネルを変更するとELRS TXモジュールに、そのデータは記憶されます。そのデータはELRS TXがドローンとのリンクが確立した際に送付されVTXチャネルが変更されます。そのため送信機を立ち上げた時にExpressLRS Luaを起動することなく、そのデータが確認できると便利だというのが、このウィジェット作成の動機です。

### 機能
*   **ELRS通信:** ELRなS TXモジュールに直接問い合わせてVTXのバンドとチャネルデータを取得します。
*   **EdgeTXウィジェット:** EdgeTX送信機上でウィジェットとして動作するように設計されています。
*   **カスタマイズ可能な表示:** 文字色、文字サイズ、表示位置などを設定可能です。

### ELRS 4.x 対応について
*   ELRS 4.x では、1 フレームに入りきらないパラメータ応答が**複数の CRSF フレーム**に分割されて送られてきます。ウィジェットは分割応答を再組立てし、各断片を取得してから次のフィールドへ進みます。
*   VTX バンドフィールドの名前は ELRS 4.x で `Band` から `Band/Enable` に変更されました（ 3.x では `Band` ）。どちらにも対応しています。
*   バンドが Disabled の場合、ELRS 4.x は VTX Administrator フォルダの動的名を送りません。その場合は `Band/Enable` と `Channel` のフィールド値から状態を取得し `OFF` を表示します。

### 導入
送信機のSDカードの以下のパスにmain.luaを保管します。
```/WIDGETS/ELRSVTX/main.lua```

旧バージョンからの更新時は、EdgeTXが保持するキャッシュを削除してください:
```/WIDGETS/ELRSVTX/main.luac```

### 設定
このウィジェットは、表示をカスタマイズするためのいくつかの設定オプションを提供します。これらの設定は、EdgeTX送信機のウィジェット設定メニューからアクセスできます。

![設定画面](images/ELRSVTXSetting.bmp)

注: TextSizeのBOLDはSTDと同じ、XXSとXSも同じになります。
