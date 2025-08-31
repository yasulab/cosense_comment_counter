#!/usr/bin/env ruby

require 'dotenv/load'
require 'json'
require 'uri'
require 'net/http'
require 'optparse'

class CosenseAnalyzer
  # APIエンドポイント
  COSENSE_API = 'https://scrapbox.io/api'

  # 出力フォーマット用定数
  SEPARATOR_WIDTH = 60
  SEPARATOR_LINE  = "=" * SEPARATOR_WIDTH
  SUB_SEPARATOR   = "-" * SEPARATOR_WIDTH

  def initialize
    # Cookie認証用のSIDのみを環境変数から取得
    @sid     = ENV['COSENSE_SID'].to_s.empty? ? nil : ENV['COSENSE_SID']
    @options = {}
  end

  def run(args)
    parse_options(args)

    # ページ指定がある場合は解析
    if @options[:page]
      analyze_from_page(@options[:page])
    else
      # ページ指定がない場合はエラー
      puts "❌ エラー: ページが指定されていません"
      puts ""
      puts "使用方法:"
      puts "  #{$0} --page プロジェクト/ページ名 --keyword リンク抽出キーワード"
      puts ""
      puts "例:"
      puts "  #{$0} --page yasulab/README --keyword Ruby"
      puts ""
      puts "詳細は --help を参照してください"
      exit 1
    end
  end

  private

  def parse_options(args)
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} --page PROJECT/PAGE [options]"
      opts.separator ""
      opts.separator "Options:"

      opts.on("--page PROJECT/PAGE", "まとめページを指定 (例: yasulab/README)") { @options[:page]     = it }
      opts.on("--keyword KEYWORD",   "リンクをフィルタリングするキーワード")               { @options[:keyword]  = it }
      opts.on("--username USERNAME", "特定ユーザー名をページ毎にカウントして表示")         { @options[:username] = it }
      opts.on("--first",       "最初のリンクのみ分析")       { @options[:first]       = true }
      opts.on("--check-links", "リンク先の有効性をチェック") { @options[:check_links] = true }
      opts.on("-h", "--help",  "このヘルプを表示")           { puts opts; exit }
    end

    parser.parse!(args)
  rescue OptionParser::InvalidOption => e
    puts "エラー: #{e.message}"
    puts parser
    exit 1
  end

  def analyze_from_page(page_spec)
    # PROJECT/PAGE 形式からプロジェクトとページを抽出
    if page_spec =~ /^([^\/]+)\/(.+)$/
      @project = $1
      page = $2
      analyze_page(page)
    else
      puts "❌ 無効な形式: #{page_spec}"
      puts "   形式: PROJECT/PAGE (例: yasulab/README)"
      exit 1
    end
  end

  def analyze_page(page_title)
    data = fetch_page_data(page_title)
    return unless data

    # リンク抽出とコメント集計を実行
    display_links(data)
  end


  def fetch_page_data(page_title)
    url = build_api_url(@project, page_title)

    puts @sid.nil? ?
      "📖 公開モードで '#{@project}' にアクセス中..." :
      "🔐 認証モードで '#{@project}' にアクセス中..."

    response = make_api_request(url)
    handle_api_response(response, page_info: "#{@project}/#{page_title}")
  end

  def display_links(data)
    # APIの links フィールドを使用（必須）
    unless data['links']
      puts "❌ エラー: APIレスポンスに links フィールドがありません"
      puts "   このページはリンク集計に対応していない可能性があります"
      exit 1
    end

    if data['links'].empty?
      puts "⚠️  警告: このページにはリンクが含まれていません"
      return
    end

    links = extract_links_from_api(data['links'])

    # キーワードフィルタリング
    if @options[:keyword]
      links = filter_links(links, @options[:keyword])
    end

    # --check-links オプションがある場合はリンクチェックのみ
    if @options[:check_links]
      check_links_validity(links)
      return
    end

    # コメント集計
    puts "\n📊 コメント集計モードで実行中...\n"
    page_results = fetch_all_page_data(links)

    # --username オプションがある場合は特別な表示
    if @options[:username]
      display_user_breakdown(@options[:username], page_results)
    else
      # 通常のコメント集計
      comment_counts = count_comments(page_results)
      display_comment_counts(comment_counts, page_results)
    end
  end

  def filter_links(links, keyword)
    # 全角括弧を半角括弧に正規化してマッチング
    normalized_keyword = normalize_brackets(keyword)

    links.select do |link|
      normalized_name = normalize_brackets(link[:name])
      normalized_project = link[:project] ? normalize_brackets(link[:project]) : nil

      # 大文字小文字を無視してマッチング
      normalized_name.downcase.include?(normalized_keyword.downcase) ||
      (normalized_project && normalized_project.downcase.include?(normalized_keyword.downcase))
    end
  end

  def normalize_brackets(text)
    # 全角括弧を半角括弧に変換
    text.gsub('（', '(').gsub('）', ')')
  end

  def normalize_page_name(name)
    # Cosense の URL パターンに合わせてページ名を正規化
    # Cosense はすべてのスペースをアンダースコアに変換する
    name.gsub(' ', '_')
  end

  def check_links_validity(links)
    puts SEPARATOR_LINE
    puts "🔍 リンク有効性チェック"
    puts SEPARATOR_LINE
    puts "チェック対象: #{links.size} ページ"
    puts ""

    valid_count   = 0
    invalid_count = 0

    links.each_with_index do |link, idx|
      # ページ名を正規化（スペースをアンダースコアに）
      page_name = normalize_page_name(link[:name])

      # URLをデバッグ表示
      url = build_api_url(@project, page_name)
      puts "#{(idx + 1).to_s.rjust(2)}. Page: #{page_name}"
      puts "\tURL: #{url}"

      begin
        response = make_api_request(url)

        if response.code == '200'
          data = JSON.parse(response.body)
          lines_count = data['lines'].size

          # 有効性の判定（100行以上なら正常、1行ならタイトルのみ、その間は疑わしい）
          if lines_count >= 100
            valid_count += 1
            status = "✅ OK"
            detail = "(#{lines_count} lines)"
          elsif lines_count == 1
            invalid_count += 1
            status = "⚠️  EMPTY"
            detail = "(title only - wrong URL?)"
          else
            invalid_count += 1
            status = "⚠️  SUSPICIOUS"
            detail = "(#{lines_count} lines - possibly wrong URL)"
          end
        else
          invalid_count += 1
          status = "❌ ERROR"
          detail = "(#{response.code})"
        end
      rescue => e
        invalid_count += 1
        status = "❌ ERROR"
        detail = "(network)"
      end

      # 結果表示
      puts "\t→ #{status} #{detail}"
      puts ""

      # レート制限対策
      sleep 0.1
    end

    puts ""
    puts SUB_SEPARATOR
    puts "📊 結果サマリー:"
    puts "  ✅ 有効: #{valid_count} ページ"
    puts "  ❌ 無効: #{invalid_count} ページ"
    puts "  成功率: #{(valid_count.to_f / links.size * 100).round(1)}%"
    puts SEPARATOR_LINE
  end

  def extract_links_from_api(links_array)
    # API の links フィールドから取得したリンクを処理
    links_array.map do |link_name|
      { type: :internal, name: link_name }
    end
  end

  # 全角文字幅を考慮したフォーマット
  def format_username_with_width(username, target_width)
    # 全角文字数をカウント（日本語、中国語、記号など）
    full_width_chars = username.scan(/[^\x00-\x7F]/).size
    half_width_chars = username.length - full_width_chars

    # 表示幅を計算（全角=2, 半角=1）
    display_width = full_width_chars * 2 + half_width_chars

    # パディングを計算
    padding = target_width - display_width
    padding = 0 if padding < 0

    username + (" " * padding)
  end

  # バーグラフを生成する共通メソッド
  def generate_bar_graph(value, max_value, width = 30)
    return "" if max_value <= 0
    bar_length = (value.to_f / max_value * width).round
    "█" * bar_length
  end

  # ランキング行をフォーマットする共通メソッド
  def format_ranking_line(rank, username, count, max_count)
    rank_str = "#{rank.to_s.rjust(2)}."
    username_display = format_username_with_width(username, 20)
    count_str = count.to_s.rjust(3)
    bar = generate_bar_graph(count, max_count)
    "#{rank_str} #{username_display}: #{count_str} #{bar}"
  end

  # 統計情報を計算する共通メソッド
  def calculate_statistics(page_results, comment_counts)
    total_pages   = page_results.size
    success_pages = page_results.count { |r| !r[:error] }
    failed_pages  = page_results.count { |r| r[:error] }
    total_comments    = comment_counts.map { |_, count| count }.sum
    unique_commenters = comment_counts.size
    success_rate = total_pages > 0 ? (success_pages.to_f / total_pages * 100).round(1) : 0

    {
      total_pages:    total_pages,
      success_pages:  success_pages,
      failed_pages:   failed_pages,
      total_comments:    total_comments,
      unique_commenters: unique_commenters,
      success_rate: success_rate
    }
  end

  # コメントカウンター機能（アイコンベース - 発言回数をカウント）
  def extract_commenters(page_data)
    commenters = []

    # 各行のテキストから [username.icon] パターンを抽出
    page_data['lines'].each do |line|
      text = line['text']

      # [username.icon] パターンを検索
      # 例: [yasulab.icon]
      text.scan(/\[([^\[\]]+)\.icon\]/) do |match|
        username = match[0]

        #【オプション】任意のアイコン名を除外（絵文字用のアイコンなど）
        #next if username =~ /^(done|warning|check|think|pray|memo|secret|who|google|gemini|chatgpt)/i

        commenters << username
      end
    end

    commenters
  end

  def fetch_page_data_for_link(link)
    # 他プロジェクトリンクの場合はプロジェクトを使用
    target_project =
      if link[:type] == :cross_project
        link[:project]
      else
        @project
      end

    # ページ名を正規化（Cosense の URL パターンに合わせる）
    page_name = normalize_page_name(link[:name])

    url = build_api_url(target_project, page_name)

    begin
      response = make_api_request(url)
      # サイレントモード: エラーメッセージを表示しない
      handle_api_response(response, page_info: nil)
    rescue => e
      nil  # ネットワークエラー
    end
  end

  def fetch_all_page_data(links)
    results = []

    # 最初のページのみ処理
    target_links = @options[:first] ? [links.first] : links
    target_links.each_with_index do |link, idx|
      # プログレス表示
      print "\r📖 ページ取得中: #{idx + 1}/#{target_links.size}"

      # APIでページデータ取得
      page_data = fetch_page_data_for_link(link)

      if page_data
        commenters = extract_commenters(page_data)

        results << {
          link: link,
          data: page_data,
          commenters: commenters
        }
      else
        results << {
          link: link,
          error: true
        }
      end

      # レート制限対策
      sleep 0.2
    end

    puts "\r📖 ページ取得完了: #{target_links.size}/#{target_links.size}     \n"
    results
  end

  def count_comments(page_results)
    all_commenters = []

    page_results.each do |result|
      next if result[:error]
      all_commenters.concat(result[:commenters])
    end

    # Ruby 2.7+ の tally メソッドで集計
    comment_counts = all_commenters.tally

    # ソート（コメント数降順）
    comment_counts.sort_by { |user, count| -count }
  end

  def display_user_breakdown(username, page_results)
    puts SEPARATOR_LINE
    puts "🔍 ユーザー別詳細: #{username}"
    puts SEPARATOR_LINE

    total_count = 0
    page_results.each_with_index do |result, idx|
      next if result[:error]

      # このページでのユーザーのコメント行を抽出
      user_lines = []
      result[:data]['lines'].each_with_index do |line, line_idx|
        text = line['text']
        # [username.icon] パターンをチェック
        if text.include?("[#{username}.icon]")
          count = text.scan(/\[#{Regexp.escape(username)}\.icon\]/).size
          user_lines << {
            line_num: line_idx + 1,
            text: text,
            count: count
          }
        end
      end

      user_comments = user_lines.sum { |l| l[:count] }
      total_count  += user_comments

      # ページタイトルを短縮表示（最大40文字）
      # + を スペース に置換して読みやすくする
      title = result[:data]['title']
      title = title.gsub('+', ' ')
      title = title.length > 40 ? "#{title[0..37]}..." : title

      puts "#{(idx + 1).to_s.rjust(2)}. #{title}"
      puts "\t#{username}: #{user_comments}"

      # 詳細行を表示（コメントがある場合のみ）
      if user_lines.any?
        puts "\t詳細:"
        user_lines.each do |line_info|
          # 行の内容を短縮表示（60文字）
          text_preview = line_info[:text].length > 60 ?
                        "#{line_info[:text][0..57]}..." :
                        line_info[:text]
          puts "\t\tL#{line_info[:line_num]}: #{text_preview}"
          if line_info[:count] > 1
            puts "\t\t\t(#{line_info[:count]}回出現)"
          end
        end
      end

      puts ""
    end

    puts SUB_SEPARATOR
    puts "📊 合計: #{username} のコメント数 = #{total_count}"
    puts SEPARATOR_LINE
  end

  def display_comment_counts(comment_counts, page_results)
    puts SEPARATOR_LINE
    puts "📊 コメント集計結果"
    puts SEPARATOR_LINE

    # 統計情報を計算
    stats = calculate_statistics(page_results, comment_counts)

    puts "📄 解析ページ数: #{stats[:success_pages]}/#{stats[:total_pages]} (#{stats[:success_rate]}% 成功)"
    puts "💬 総コメント数: #{stats[:total_comments]}"
    puts "👥 コメンター数: #{stats[:unique_commenters]}"
    puts "⚠️ エラーページ数: #{stats[:failed_pages]}" if stats[:failed_pages] > 0
    puts SUB_SEPARATOR

    # ランキング表示
    if comment_counts.empty?
      puts "コメントが見つかりませんでした"
    else
      puts "🏆 コメンターランキング:"
      puts ""

      # 全員を表示
      max_count = comment_counts.first[1]
      comment_counts.each_with_index do |(user, count), idx|
        puts format_ranking_line(idx + 1, user, count, max_count)
      end
    end

    # エラーページの詳細（ある場合）
    error_pages = page_results.select { |r| r[:error] }
    if error_pages.any?
      puts SUB_SEPARATOR
      puts "📝 取得できなかったページ:"
      error_pages.first(5).each do |result|
        # シンプルにページ名を表示
        puts "\t- #{result[:link][:name]}"
      end
      if error_pages.size > 5
        puts "\t... 他 #{error_pages.size - 5} ページ"
      end
    end

    puts SEPARATOR_LINE

    # 結果をファイルに保存（常にresult.txt）
    File.write('result.txt', capture_output(comment_counts, page_results))
    puts "\n💾 結果を result.txt に保存しました"
  end

  def capture_output(comment_counts, page_results)
    output = []
    output << SEPARATOR_LINE
    output << "📊 コメント集誈結果"
    output << SEPARATOR_LINE

    # 統計情報を計算
    stats = calculate_statistics(page_results, comment_counts)

    output << "📄 解析ページ数: #{stats[:success_pages]}/#{stats[:total_pages]} (#{stats[:success_rate]}% 成功)"
    output << "💬 総コメント数: #{stats[:total_comments]}"
    output << "👥 コメンター数: #{stats[:unique_commenters]}"
    output << SUB_SEPARATOR

    if comment_counts.empty?
      output << "コメントが見つかりませんでした"
    else
      output << "🏆 コメンターランキング:"
      output << ""
      max_count = comment_counts.first[1]
      comment_counts.each_with_index do |(user, count), idx|
        output << format_ranking_line(idx + 1, user, count, max_count)
      end
    end

    # エラーページの詳細（ある場合）
    error_pages = page_results.select { |r| r[:error] }
    if error_pages.any?
      output << SUB_SEPARATOR
      output << "📝 取得できなかったページ:"
      error_pages.first(5).each do |result|
        output << "\t- #{result[:link][:name]}"
      end
      if error_pages.size > 5
        output << "\t... 他 #{error_pages.size - 5} ページ"
      end
    end

    output << SEPARATOR_LINE
    output.join("\n") + "\n"
  end

  private

  # API URLを構築する共通メソッド
  def build_api_url(project, page_name)
    "#{COSENSE_API}/pages/#{project}/#{URI.encode_www_form_component(page_name)}"
  end

  # Cosense (旧: Scrapbox) API への HTTPリクエストを実行する共通メソッド
  def make_api_request(url)
    uri     = URI(url)
    http    = Net::HTTP.new(uri.host, uri.port).tap { it.use_ssl = true }
    request = Net::HTTP::Get.new(uri)
    request['Accept']     = 'application/json'
    request['User-Agent'] = 'cosense-comment-counter/0.1.0'
    request['Cookie']     = "connect.sid=#{@sid}" if @sid

    http.request(request)
  end

  def handle_api_response(response, page_info: nil)
    return JSON.parse(response.body) if response.code == '200'

    # page_info が提供されている場合のみエラーメッセージを表示
    if page_info
      case response.code
      when '401'
        if @sid
          puts "❌ 認証エラー: Cookieが無効または期限切れです"
          puts "  → docs/USER_SETUP_GUIDE.md を参照してCookieを更新してください"
        else
          puts "❌ アクセス拒否: このページは非公開です"
          puts "  → 認証が必要な場合は COSENSE_SID を設定してください"
        end
      when '404'
        puts "❌ ページが見つかりません: #{page_info}"
      else
        puts "❌ エラー: #{response.code} #{response.message}"
        puts response.body if response.code != '403'  # 403以外はボディも表示
      end
    end

    nil
  end
end

# メイン処理
if __FILE__ == $0
  analyzer = CosenseAnalyzer.new
  analyzer.run(ARGV)
end
