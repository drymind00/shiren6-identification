# シレン6 識別補助ツール

『風来のシレン6 とぐろ島探検録』の未識別アイテムを、ダンジョン・カテゴリ・店で確認した価格から絞り込むローカルWebツールです。

公開版: [シレン6 識別補助ツール](https://shiren6-identification-ytanaka.vercel.app/apps/shiren6-identification/)

## 機能

- ダンジョン、カテゴリ、買値・売値、通常・祝福・呪いで候補を絞り込み
- 杖の回数、壺の容量、武器・盾の強化値を価格候補に反映
- 確認済みの候補をチェックして一覧の下へ移動
- チェックだけをまとめて解除

## 起動

PowerShellで次を実行します。

```powershell
.\tools\start_shiren6_identification_tool.ps1
```

ブラウザで `http://localhost:8765/apps/shiren6-identification/` を開きます。詳細な使い方は [アプリのREADME](apps/shiren6-identification/README.md) を参照してください。

## データについて

アイテムデータは `outputs/shiren6_notion_import/` に含まれます。出現情報の更新には、[シレン6 アイテム一覧データ](https://tsuemaki-daisuki.vercel.app/exported_reports.js) を参照するスクリプトを使用します。

ゲーム内容・データの正確性は、実際のゲーム内表示と照合してください。
