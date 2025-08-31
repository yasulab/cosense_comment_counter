# 📊 Cosense Comment Counter

Cosense (旧: Scrapbox) のページに含まれるコメントを自動集計し、誰がどれだけ活発に議論に参加しているかを可視化するツールです。

## 🎯 なぜこのツールが必要か

### 解決する問題

**手動でコメントを数えるのは大変...**
- 「このページでは誰が一番発言してる？」
- 「このプロジェクトの活発な参加者は誰？」
- 「このトピック関連で、全体の議論量は？」

このツールは、Cosense の `[username.icon]` パターンを自動認識し、**数秒で集計**します。

### 実際の出力例

```
📊 コメント集計結果
============================================================
📄 解析ページ数: 123/123 (100.0% 成功)
💬 総コメント数: 45,678
👥 コメンター数: 90
------------------------------------------------------------
🏆 コメンターランキング:

 1. person A       : 300 ██████████████████████████████
 2. person B       : 279 ████████████████████████████
 3. person C       : 191 ███████████████████████
 4. person D       : 134 █████████████████████
 5. person E       : 102 ██████████████████

 ...
```

## 🚀 クイックスタート

### 必要なもの

- Ruby 2.7 以上
- Bundler

### インストール

```bash
# リポジトリをクローン
git clone https://github.com/yasulab/cosense_comment_counter.git
cd cosense_comment_counter

# 依存関係をインストール
bundle install
```

### 基本的な使い方

```bash
# 公開ページのコメントを集計
bundle exec ruby main.rb --page yasulab/README

# キーワードでフィルタリング（例：Ruby 関連のページのみ）
bundle exec ruby main.rb --page yasulab/README --keyword "Ruby"
```

## 📖 詳細な使い方

### コマンドラインオプション

| オプション | 説明 | 例 |
|-----------|------|-----|
| `--page PROJECT/PAGE` | **必須** 解析するページを指定 | `--page yasulab/README` |
| `--keyword KEYWORD` | リンクをフィルタリングするキーワード | `--keyword "Ruby"` |
| `--username USERNAME` | 特定ユーザーの詳細を表示 | `--username yasulab` |
| `--check-links` | リンク先の有効性チェック（デバッグ用） | `--check-links` |
| `--first` | 最初のリンクのみ解析（デバッグ用） | `--first` |

### 使用例

#### 1. 基本的な集計

```bash
# yasulab プロジェクトの「README」ページを解析
bundle exec ruby main.rb --page yasulab/README
```

#### 2. キーワードフィルタリング

```bash
# "Ruby" を含むページのみ集計
bundle exec ruby main.rb --page yasulab/README --keyword "Ruby"
```

#### 3. 特定ユーザーの詳細表示

```bash
# yasulab さんのコメントを各ページごとに詳細表示
bundle exec ruby main.rb --page yasulab/README --username yasulab

# 出力例：
# 1. ページタイトル
#    yasulab: 5
#    詳細:
#      L42: [yasulab.icon] このアイデアいいですね！
#      L78: [yasulab.icon] 実装してみました
```

#### 4. リンクの有効性チェック

```bash
# リンク先のページが実際に存在するか確認 (DEBUG)
bundle exec ruby main.rb --page yasulab/README --check-links
```

### 結果の保存と変換

集計結果は自動的に `result.txt` に保存されます。

Cosense のテーブル形式に変換する場合：

```bash
# result.txt を Cosense テーブル形式に変換
bundle exec ruby convert_result_to_cosense.rb

# 出力: cosense.txt
# table:コメントランキング
# rank	name	comments
# 1	foobar	282
# 2	foobaz	179
# ...
```

## 🔐 プライベートページへのアクセス

プライベートな Cosense プロジェクトにアクセスする場合は、Cookie 認証が必要です。

### 設定手順

1. **Cookie を取得**
   - ブラウザで対象の Cosense プロジェクトにログイン
   - 開発者ツール → Application → Cookies → `connect.sid` をコピー

2. **環境変数を設定**

   `.env` ファイルを作成：
   ```env
   COSENSE_SID=s:xxxxxxxx...  # コピーした connect.sid の値
   ```

3. **動作確認**
   ```bash
   bundle exec ruby main.rb --page private-project/page-name
   ```

詳細な設定手順は [docs/USER_SETUP_GUIDE.md](docs/USER_SETUP_GUIDE.md) を参照してください。

## 🔧 技術的な仕組み

### コメント認識の仕組み

このツールは Cosense の **アイコン記法** `[username.icon]` を検出してコメントをカウントします。

```
[yasulab.icon] これは yasulab のコメントです
[person A.icon] これは person A のコメントです
```

**重要**: `@yasulab` のようなメンション記法はカウント対象外です。コメント数は発言者のアイコン表示数でカウントします。

### 処理フロー

1. **ページ取得**: 指定されたまとめページの API データを取得
2. **リンク抽出**: ページ内のリンク（`links` フィールド）を抽出
3. **フィルタリング**: キーワードが指定されていれば、該当するリンクのみに絞り込み
4. **個別取得**: 各リンク先のページデータを順次取得
5. **コメント抽出**: 各ページから `[username.icon]` パターンを検出
6. **集計**: ユーザーごとにコメント数を集計
7. **結果表示**: ランキング形式で表示し、ファイルに保存

### API レート制限対策

- リクエスト間に 0.2 秒の遅延を挿入
- 大量のページを処理する場合は自動的に調整

## 🆘 トラブルシューティング

### よくあるエラーと対処法

#### ❌ ページが見つかりません

```
❌ ページが見つかりません: project/page_name
```

**原因**: ページ名の指定が間違っている  
**対処**: 
- スペースはアンダースコアに自動変換されます
- ブラウザで実際のページ URL を確認してください

#### ❌ 認証エラー

```
❌ 認証エラー: Cookieが無効または期限切れです
```

**原因**: プライベートページで Cookie が期限切れ  
**対処**: 
1. ブラウザで再ログイン
2. 新しい `connect.sid` を取得
3. `.env` ファイルを更新

#### ❌ エラー: 429 Too Many Requests

**原因**: API レート制限  
**対処**: 
- しばらく待ってから再実行
- `--first` オプションでテスト実行

## 📊 出力形式

### 標準出力

- 絵文字を使った視覚的な表示
- バーグラフでコメント数を可視化
- 全角文字（日本語名）にも対応した整形

### ファイル出力

- `result.txt`: 標準出力と同じ形式
- `cosense.txt`: Cosense テーブル形式（変換スクリプト使用時）

## 📝 ライセンス

MIT License - 詳細は [LICENSE](LICENSE) ファイルを参照してください。

## 🙏 謝辞

- [Cosense](https://scrapbox.io/) チーム - 素晴らしいコラボレーションツールの提供
- [Cosense](https://scrapbox.io/) コミュニティ - 多くの試行錯誤とドキュメント公開

## 📚 関連ドキュメント

- [プライベートページ設定ガイド](docs/USER_SETUP_GUIDE.md)
- [Cosense 公式ヘルプ](https://scrapbox.io/help-jp/)
- [Scrapbox API (非公式)](https://scrapbox.io/scrapboxlab/API)

---

**注意**: このツールは Cosense (旧: Scrapbox) の非公式ツールです。API の仕様変更により動作しなくなる可能性があります。
