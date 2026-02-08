# Nikkei Asia News Scraper

Nikkei Asia (https://asia.nikkei.com/) からトップニュース記事や特定のトピックの記事を取得し、保存するRスクリプトです。

## 機能

1. **トップニュースの取得 (`scrape_nikkei.R`)**:
   * Nikkei Asiaのトップページから最新のヘッドラインや注目記事を取得します。
   * 上位10件の記事をCSVファイル (`nikkei_news_top10.csv`) に保存します。
   * Cookieが設定されている場合、全文を取得してPDFレポート (`nikkei_full_report.pdf`) を生成します。

2. **トピック記事の取得 (`scrape_topic.R`)**:
   * 指定したトピックページ（例: politics/japan-election）から最新の記事を取得します。
   * 記事数や取得元のURLを変更可能です。
   * 取得した記事の全文をMarkdownファイル (`nikkei_topic_YYYY-MM-DD.md`) に保存します。

## 必要条件

* R (R実行環境)

## セットアップ

スクリプトを実行する前に、必要なRパッケージをインストールしてください。
スクリプト内で自動的にインストールされますが、手動でインストールする場合は以下のコマンドを実行します：

```r
install.packages(c("rvest", "jsonlite", "dplyr", "httr", "rmarkdown"))
```

## 使い方

### トップニュースの取得

ターミナル（またはコマンドプロンプト）で以下のコマンドを実行します：

```bash
Rscript scrape_nikkei.R
```

出力:
* `nikkei_news_top10.csv`
* `nikkei_full_report.pdf` (または .md)

### 特定のトピックの記事を取得する

1. `scrape_topic.R` をテキストエディタで開きます。
2. ファイル上部の `TARGET_URL` 変数に取得したいトピックのURLを設定します。また `ARTICLE_COUNT` で取得数を変更できます。

```r
# --- Configuration ---
# You can change these variables to scrape different topics or change the number of articles
TARGET_URL <- "https://asia.nikkei.com/politics/japan-election"
ARTICLE_COUNT <- 20
# ---------------------
```

3. 以下のコマンドを実行します：

```bash
Rscript scrape_topic.R
```

出力:
* `nikkei_topic_YYYY-MM-DD.md`: 記事のタイトル、リンク、全文を含むMarkdownファイル。
* `nikkei_topic_YYYY-MM-DD.csv`: 記事リストのCSVファイル。

## 全文取得について

記事の全文を取得するには、Nikkei AsiaのセッションCookieが必要です。
環境変数 `NIKKEI_COOKIE` にCookieの値を設定してからスクリプトを実行してください。
詳細は `instructions_cookie.md` を参照してください。
