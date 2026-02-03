# Nikkei Asia News Scraper

Nikkei Asia (https://asia.nikkei.com/) からトップニュース記事を取得し、CSVファイルに保存するRスクリプトです。

## 機能

* Nikkei Asiaのトップページから最新のヘッドラインや注目記事を取得します。
* 取得した記事のタイトルとリンクを整形します。
* 上位10件の記事を抽出し、コンソールに表示およびCSVファイル (`nikkei_news_top10.csv`) に保存します。

## 必要条件

* R (R実行環境)

## セットアップ

スクリプトを実行する前に、必要なRパッケージをインストールしてください。
RコンソールまたはRStudioなどで以下のコマンドを実行します：

```r
install.packages(c("rvest", "jsonlite", "dplyr"))
```

## 使い方

ターミナル（またはコマンドプロンプト）で以下のコマンドを実行してスクリプトを起動します：

```bash
Rscript scrape_nikkei.R
```

## 出力

スクリプトが正常に終了すると、カレントディレクトリに以下のファイルが生成されます：

* `nikkei_news_top10.csv`: 記事のタイトルとURLが保存されたCSVファイル。

---

# NotebookLM 自動連携 (New)

Web上からソース全文をダウンロードしてNotebookLMに読み込ませる一連の動作を自動化するためのツールを追加しました。

## 事前準備

1.  **Python**: Python環境が必要です。
2.  **R**: スクレイピング用のR環境が必要です（上記のセットアップ済みであること）。
3.  **Googleアカウント**: NotebookLMへのアクセス権が必要です。

## 設定

1.  **.envファイルの作成**:
    `.env.example` をコピーして `.env` を作成します。
    ```bash
    cp .env.example .env
    ```
    `.env` ファイルをテキストエディタで開き、以下の項目を設定してください：
    *   `NIKKEI_COOKIE`: Nikkei AsiaのセッションCookie（取得方法は `instructions_cookie.md` を参照）。
    *   `NOTEBOOK_URL`: 読み込ませたいNotebookLMのノートブックのURL（例: `https://notebooklm.google.com/notebook/xxxxxxxx`）。

## 自動化ツールの実行（ワンボタン動作）

### Windowsの場合
`run.bat` をダブルクリックしてください。

### Mac/Linuxの場合
ターミナルで `run.sh` を実行してください：
```bash
bash run.sh
```

## 動作の流れ

1.  スクリプトが `scrape_nikkei.R` を実行し、記事全文を含むPDF (`nikkei_full_report.pdf`) を生成します。
2.  ブラウザ（Chromium）が起動し、NotebookLMにアクセスします。
3.  **初回実行時**: Googleログイン画面が表示された場合、手動でログインしてください。ログインが完了すると、セッション情報が保存され、次回以降は自動ログインされます。
4.  スクリプトが自動でファイルをアップロードしようと試みます。
    *   ※GoogleのUI変更等により自動アップロードが失敗した場合でも、ファイル選択ダイアログなどが開いた状態になるか、ブラウザが開いたままになるため、手動でドラッグ＆ドロップして完了できます。
