# Nikkei Asia News Scraper

Nikkei Asia (https://asia.nikkei.com/) からトップニュース記事を取得し、CSVファイルに保存するRスクリプトです。

## 機能

* **トップニュース取得**: Nikkei Asiaのトップページから最新のヘッドラインや注目記事を取得します (`scrape_nikkei.R`)。
* **日付指定取得**: 指定した日付の記事を検索して取得します (`scrape_date.R`)。
* 取得した記事のタイトルとリンクを整形します。
* 上位10件の記事を抽出し、コンソールに表示およびCSVファイル (`nikkei_news_top10.csv`) に保存します。

## 必要条件

* R (R実行環境)

## セットアップ

スクリプトを実行する前に、必要なRパッケージをインストールしてください。
RコンソールまたはRStudioなどで以下のコマンドを実行します：

```r
install.packages(c("rvest", "jsonlite", "dplyr", "httr", "rmarkdown", "lubridate"))
```

## 使い方

### 1. トップニュースの取得

ターミナル（またはコマンドプロンプト）で以下のコマンドを実行してスクリプトを起動します：

```bash
Rscript scrape_nikkei.R
```

出力: `nikkei_news_top10.csv`

### 2. 日付を指定してニュースを取得

特定の日付（YYYYMMDD形式）のニュースを取得するには、`scrape_date.R` を使用します。引数として日付を指定してください。

```bash
Rscript scrape_date.R <YYYYMMDD>
```

**例：2026年1月1日のニュースを取得する場合**

```bash
Rscript scrape_date.R 20260101
```

**出力:**
* `nikkei_news_20260101.csv`: 記事のヘッドライン一覧
* `nikkei_news_20260101.md`: 記事の全文レポート（`NIKKEI_COOKIE`環境変数が設定されている場合）

※ 全文取得には `NIKKEI_COOKIE` 環境変数の設定が必要です。詳細は `instructions_cookie.md` を参照してください。

## 出力ファイル

スクリプトが正常に終了すると、カレントディレクトリに以下のファイルが生成されます：

* `nikkei_news_top10.csv`: トップニュースのタイトルとURL。
* `nikkei_news_<YYYYMMDD>.csv`: 指定日のニュース一覧。
* `nikkei_news_<YYYYMMDD>.md`: 指定日のニュース全文レポート。
