# Nikkei Asia Scraper

Nikkei Asia (https://asia.nikkei.com/) のニュース記事をスクレイピングするツールです。
指定した日付の記事一覧を取得し、CSVおよびMarkdown形式で保存します。

## 必要要件

- R (および `Rscript` コマンド)
- 以下のRパッケージ (スクリプト実行時に自動インストールを試みます):
  - `rvest`
  - `jsonlite`
  - `dplyr`
  - `httr`
  - `rmarkdown`
  - `lubridate`

## 使い方

### 1. 日付を指定してニュースを取得

指定した日付のニュース記事一覧を取得します。

```bash
Rscript scrape_date.R <YYYYMMDD>
```

例: 2026年2月15日のニュースを取得する場合
```bash
Rscript scrape_date.R 20260215
```

**出力ファイル:**
- `nikkei_news_20260215.csv`: ヘッドライン一覧 (タイトル, リンク, 日付)
- `nikkei_news_20260215.md`: 詳細レポート (全文取得が有効な場合)

### 2. 全文取得の設定 (オプション)

記事の全文を取得するには、Nikkei Asiaの購読アカウントのCookieが必要です。

**方法 A: 環境変数**
`NIKKEI_COOKIE` という名前の環境変数にCookieの値を設定してください。

**方法 B: cookie.txt**
プロジェクトのルートディレクトリに `cookie.txt` というファイルを作成し、その中にCookieの値を貼り付けてください。

Cookieの取得方法は `instructions_cookie.md` (もしあれば) を参照するか、ブラウザの開発者ツールでリクエストヘッダーの `Cookie` 値をコピーしてください。

## スクリプトの仕組み

- **scrape_date.R**:
  - `https://asia.nikkei.com/latestheadlines?date=YYYY-MM-DD` にアクセスします。
  - ページ内の `__NEXT_DATA__` (JSONデータ) を解析し、記事情報を抽出します。
  - 指定された日付の記事をフィルタリングして保存します。

## 注意事項

- 短時間に大量のリクエストを送るとブロックされる可能性があります。スクリプトには待機時間が設定されていますが、過度な使用は控えてください。
- サイトの構造変更によりスクリプトが動作しなくなる可能性があります。
