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
