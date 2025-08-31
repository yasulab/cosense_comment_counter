#!/usr/bin/env ruby
# frozen_string_literal: true

# result.txt を Cosense (旧: Scrapbox) のテーブル形式に変換するスクリプト

def parse_result_file(filename)
  unless File.exist?(filename)
    puts "エラー: #{filename} が見つかりません"
    exit 1
  end

  content = File.read(filename, encoding: 'UTF-8')
  
  # ランキング部分を抽出
  ranking_section = content.match(/🏆 コメンターランキング:(.+?)={10,}/m)
  
  unless ranking_section
    puts "エラー: ランキングセクションが見つかりません"
    exit 1
  end
  
  ranking_text = ranking_section[1]
  
  # 各行をパース
  rankings = []
  ranking_text.each_line do |line|
    next if line.strip.empty?
    
    # 形式: " 1. yasulab              : 30 ████████"
    if match = line.match(/^\s*(\d+)\.\s+(.+?)\s*:\s*(\d+)\s*/)
      rank = match[1].to_i
      name = match[2].strip
      comments = match[3].to_i
      rankings << { rank: rank, name: name, comments: comments }
    end
  end
  
  rankings
end

def convert_to_cosense_table(rankings, output_file)
  lines = []
  
  # テーブルヘッダー
  lines << "table:コメントランキング"
  lines << "rank\tname\tcomments"
  
  # データ行
  rankings.each do |entry|
    lines << "#{entry[:rank]}\t#{entry[:name]}\t#{entry[:comments]}"
  end
  
  # ファイルに書き込み
  File.write(output_file, lines.join("\n"), encoding: 'UTF-8')
  
  puts "✅ #{output_file} に変換結果を保存しました"
  puts "📊 変換したエントリ数: #{rankings.size}"
end

def main
  input_file  = 'result.txt'
  output_file = 'cosense.txt'
  
  # コマンドライン引数の処理
  input_file  = ARGV[0] if ARGV.length > 0
  output_file = ARGV[1] if ARGV.length > 1
  
  puts "📁 入力ファイル: #{input_file}"
  puts "📝 出力ファイル: #{output_file}"
  puts ""
  
  # 変換実行
  rankings = parse_result_file(input_file)
  
  if rankings.empty?
    puts "警告: ランキングデータが見つかりませんでした"
    exit 1
  end
  
  convert_to_cosense_table(rankings, output_file)
  
  # プレビュー表示
  puts "\n📋 変換結果のプレビュー (最初の10行):"
  puts "-" * 40
  lines = File.readlines(output_file, encoding: 'UTF-8')
  lines[0..11].each { |line| puts line }
  if lines.size > 12
    puts "... (残り #{lines.size - 12} 行)"
  end
end

# スクリプト実行
main if __FILE__ == $0
