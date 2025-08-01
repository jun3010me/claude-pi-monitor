#!/bin/bash

# Raspberry Pi リアルタイム監視ダッシュボード
# 使用方法: ./monitor_dashboard.sh [更新間隔(秒)] 
# 例: ./monitor_dashboard.sh 5

# 更新間隔（デフォルト3秒）
REFRESH_INTERVAL=${1:-3}

# 色の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# CPU温度を取得
get_cpu_temp() {
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        temp=$(cat /sys/class/thermal/thermal_zone0/temp)
        temp_c=$((temp/1000))
        if [ $temp_c -gt 70 ]; then
            echo -e "${RED}${temp_c}°C${NC}"
        elif [ $temp_c -gt 60 ]; then
            echo -e "${YELLOW}${temp_c}°C${NC}"
        else
            echo -e "${GREEN}${temp_c}°C${NC}"
        fi
    else
        echo "N/A"
    fi
}

# GPU情報を取得
get_gpu_info() {
    if command -v vcgencmd &> /dev/null; then
        gpu_temp=$(vcgencmd measure_temp 2>/dev/null | cut -d'=' -f2 | cut -d"'" -f1)
        gpu_mem=$(vcgencmd get_mem gpu 2>/dev/null | cut -d'=' -f2)
        gpu_freq=$(vcgencmd measure_clock gpu 2>/dev/null | cut -d'=' -f2)
        if [ ! -z "$gpu_temp" ]; then
            gpu_freq_mhz=$((gpu_freq/1000000))
            echo "${gpu_temp}°C | ${gpu_mem} | ${gpu_freq_mhz}MHz"
        else
            echo "N/A"
        fi
    else
        echo "vcgencmd not available"
    fi
}

# CPU使用率を取得
get_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1
}

# メモリ使用率を取得
get_memory_usage() {
    free | awk 'NR==2{printf "%.1f%%", $3*100/$2}'
}

# ディスク使用率を取得
get_disk_usage() {
    df -h / | awk 'NR==2{print $5}'
}

# ロードアベレージを取得
get_load_average() {
    uptime | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//'
}

# ネットワーク統計を取得
get_network_stats() {
    # 受信・送信バイト数を取得（eth0またはwlan0）
    interface=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ ! -z "$interface" ]; then
        rx_bytes=$(cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo "0")
        tx_bytes=$(cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo "0")
        rx_mb=$((rx_bytes/1024/1024))
        tx_mb=$((tx_bytes/1024/1024))
        echo "${interface}: ↓${rx_mb}MB ↑${tx_mb}MB"
    else
        echo "N/A"
    fi
}

# システム情報を取得（起動時に1回だけ）
get_system_info() {
    model=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0' || echo "Unknown")
    os_info=$(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
    kernel=$(uname -r)
    arch=$(uname -m)
    echo "$model | $os_info | $kernel | $arch"
}

# プロセス情報を取得
get_top_processes() {
    ps aux --sort=-%cpu --no-headers | head -5 | awk '{printf "%-12s %5.1f%% %-30s\n", $1, $3, substr($11,1,30)}'
}

# IPアドレスを取得
get_ip_address() {
    ip addr show | grep -E 'inet [0-9]' | grep -v '127.0.0.1' | awk '{print $NF ": " $2}' | head -3 | tr '\n' ' ' | sed 's/ $//'
}

# 現在のセッション開始時刻を特定
get_session_start_time() {
    local projects_dir="$HOME/.claude/projects"
    local current_session=""
    local session_start=""
    
    # 現在アクティブなセッションIDを取得（最新のファイルから）
    local latest_file=$(find "$projects_dir" -name "*.jsonl" -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -f "$latest_file" ]; then
        # 最新ファイルから現在のセッションIDを取得
        current_session=$(tail -1 "$latest_file" | sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p')
        
        if [ ! -z "$current_session" ]; then
            # そのセッションの最初のメッセージの時刻を取得
            session_start=$(grep '"sessionId":"'$current_session'"' "$latest_file" | head -1 | sed -n 's/.*"timestamp":"\([^"]*\)".*/\1/p')
        fi
    fi
    
    echo "$session_start"
}

# 時刻が5時間以内かチェック
is_within_session() {
    local timestamp="$1"
    local session_start="$2"
    
    if [ -z "$session_start" ] || [ -z "$timestamp" ]; then
        echo "0"
        return
    fi
    
    # 簡易チェック：同じ日付で、時刻が5時間以内
    local msg_time=$(echo "$timestamp" | sed 's/T/ /' | cut -d'.' -f1)
    local start_time=$(echo "$session_start" | sed 's/T/ /' | cut -d'.' -f1)
    
    if [ "$msg_time" \> "$start_time" ]; then
        echo "1"
    else
        echo "0"
    fi
}

# Claude Code使用統計を取得（セッション対応版）
get_claude_usage() {
    local projects_dir="$HOME/.claude/projects"
    local config_file="$HOME/.claude.json"
    
    if [ ! -d "$projects_dir" ]; then
        echo "N/A"
        return
    fi
    
    # セッション開始時刻を取得
    local session_start=$(get_session_start_time)
    
    local total_input=0
    local total_output=0
    local messages=0
    
    # 全てのJSONLファイルから現在セッションの使用状況を集計
    local temp_file="/tmp/claude_usage_$$"
    
    for file in "$projects_dir"/*/*.jsonl; do
        if [ -f "$file" ]; then
            # セッション開始以降のアシスタントメッセージのみ抽出（サブシェル回避）
            tail -50 "$file" | grep '"type":"assistant"' | grep '"usage":{' > "/tmp/session_msgs_$$" 2>/dev/null || true
            
            if [ -f "/tmp/session_msgs_$$" ]; then
                while IFS= read -r line; do
                    # タイムスタンプを取得
                    timestamp=$(echo "$line" | sed -n 's/.*"timestamp":"\([^"]*\)".*/\1/p')
                    
                    # セッション開始以降のメッセージかチェック
                    if [ "$(is_within_session "$timestamp" "$session_start")" = "1" ]; then
                        echo "$line" >> "$temp_file"
                    fi
                done < "/tmp/session_msgs_$$"
                rm -f "/tmp/session_msgs_$$"
            fi
        fi
    done
    
    # 一時ファイルから集計（リアルタイム更新保証）
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        while IFS= read -r line; do
            # 基本的なトークン数抽出（正規表現）
            input=$(echo "$line" | sed -n 's/.*"input_tokens":\([0-9]*\).*/\1/p')
            output=$(echo "$line" | sed -n 's/.*"output_tokens":\([0-9]*\).*/\1/p')
            cache_create=$(echo "$line" | sed -n 's/.*"cache_creation_input_tokens":\([0-9]*\).*/\1/p')
            cache_read=$(echo "$line" | sed -n 's/.*"cache_read_input_tokens":\([0-9]*\).*/\1/p')
            
            # デフォルト値設定
            input=${input:-0}
            output=${output:-0}
            cache_create=${cache_create:-0}
            cache_read=${cache_read:-0}
            
            # 集計
            total_input=$((total_input + input + cache_create + cache_read))
            total_output=$((total_output + output))
            messages=$((messages + 1))
        done < "$temp_file"
        
        rm -f "$temp_file"
    fi
    
    # 常に一時ファイルをクリーンアップ
    rm -f "$temp_file" "/tmp/session_msgs_$$" 2>/dev/null
    
    echo "$total_input,$total_output,$messages"
}

# Claude Code使用状況の詳細表示
get_claude_detailed_usage() {
    local usage_data=$(get_claude_usage)
    local config_file="$HOME/.claude.json"
    
    if [ "$usage_data" = "N/A" ]; then
        echo "データなし"
        return
    fi
    
    local input_tokens=$(echo "$usage_data" | cut -d',' -f1)
    local output_tokens=$(echo "$usage_data" | cut -d',' -f2)
    local messages=$(echo "$usage_data" | cut -d',' -f3)
    local total_tokens=$((input_tokens + output_tokens))
    
    # 概算コスト計算（整数演算）
    local cost_cents=$((input_tokens * 3 + output_tokens * 15))  # セント単位
    local cost_dollars=$((cost_cents / 10000))
    local cost_remainder=$((cost_cents % 10000))
    
    # 起動回数（jq不使用）
    local startups=$(sed -n 's/.*"numStartups": *\([0-9]*\).*/\1/p' "$config_file" 2>/dev/null || echo "0")
    
    printf "セッション: %dtk $%d.%04d %dmsg 起動%d回" "$total_tokens" "$cost_dollars" "$cost_remainder" "$messages" "$startups"
}

# Claude Code プラン別使用率計算
get_claude_plan_usage() {
    local usage_data=$(get_claude_usage)
    
    if [ "$usage_data" = "N/A" ]; then
        echo "N/A,N/A,N/A"
        return
    fi
    
    local input_tokens=$(echo "$usage_data" | cut -d',' -f1)
    local output_tokens=$(echo "$usage_data" | cut -d',' -f2)
    local messages=$(echo "$usage_data" | cut -d',' -f3)
    local total_tokens=$((input_tokens + output_tokens))
    
    
    # Claude Code プラン別制限値（5時間セッション）
    local pro_limit=45          # Pro: ~45 messages/session (短い会話基準)
    local max_5x_limit=225      # MAX 5x: ~225 messages/session (5倍)  
    local max_20x_limit=900     # MAX 20x: ~900 messages/session (20倍)
    
    # 各プランの使用率計算（プロンプト数ベース）
    local pro_percent=0
    local max5x_percent=0
    local max20x_percent=0
    
    if [ $messages -gt 0 ]; then
        pro_percent=$((messages * 100 / pro_limit))
        max5x_percent=$((messages * 100 / max_5x_limit))
        max20x_percent=$((messages * 100 / max_20x_limit))
        
        # 100%を超える場合もそのまま表示（制限超過の警告として）
    fi
    
    echo "$pro_percent,$max5x_percent,$max20x_percent"
}

# プラン別使用率の色付き表示
format_usage_status() {
    local percent=$1
    local plan_name=$2
    
    # 数値チェック（空の場合は0に設定）
    if [ -z "$percent" ] || [ "$percent" = "" ]; then
        percent=0
    fi
    
    # 数値でない場合も0に設定
    case "$percent" in
        ''|*[!0-9]*) percent=0 ;;
    esac
    
    if [ $percent -ge 100 ]; then
        printf "${RED}🚨${plan_name}:${percent}%%${NC}"
    elif [ $percent -gt 80 ]; then
        printf "${YELLOW}⚠️${plan_name}:${percent}%%${NC}"
    elif [ $percent -gt 60 ]; then
        printf "${BLUE}📊${plan_name}:${percent}%%${NC}"
    elif [ $percent -gt 0 ]; then
        printf "${GREEN}✅${plan_name}:${percent}%%${NC}"
    else
        printf "${GREEN}✅${plan_name}:0%%${NC}"
    fi
}

# シンプルな文字列フォーマット（色なし）
format_simple() {
    local text="$1"
    local width="$2"
    printf "%-${width}.${width}s" "$text"
}

# トラップを設定（Ctrl+Cで終了）
trap 'echo -e "\n${GREEN}監視を終了します${NC}"; exit 0' INT

# システム情報を一度取得
SYSTEM_INFO=$(get_system_info)

# ターミナルをクリア
clear

echo -e "${CYAN}===== Raspberry Pi リアルタイム監視ダッシュボード =====${NC}"
echo -e "${WHITE}更新間隔: ${REFRESH_INTERVAL}秒 | 終了: Ctrl+C${NC}"
echo -e "${BLUE}システム: ${SYSTEM_INFO}${NC}"
echo ""

# メインループ
while true; do
    # 現在時刻
    current_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 稼働時間
    uptime_info=$(uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')
    
    # 各種情報を取得
    cpu_temp=$(get_cpu_temp)
    gpu_info=$(get_gpu_info)
    cpu_usage=$(get_cpu_usage)
    memory_usage=$(get_memory_usage)
    disk_usage=$(get_disk_usage)
    load_avg=$(get_load_average)
    network_stats=$(get_network_stats)
    ip_info=$(get_ip_address)
    
    # Claude Code使用量（毎回最新データを取得）
    claude_usage=$(get_claude_detailed_usage)
    claude_plan_usage=$(get_claude_plan_usage)
    
    # 画面をクリアして上に移動
    tput cup 5 0
    tput ed
    
    # ダッシュボード表示（シンプルデザイン）
    echo -e "${WHITE}─────────────────────────────────────────────────────────────────────────${NC}"
    
    # 時刻・稼働時間行
    printf " ${YELLOW}時刻${NC}: %s | ${YELLOW}稼働${NC}: %s\n" "$current_time" "$uptime_info"
    
    echo -e "${WHITE}─────────────────────────────────────────────────────────────────────────${NC}"
    
    # CPU温度・GPU行  
    printf " ${RED}CPU温度${NC}: %s | ${PURPLE}GPU${NC}: %s\n" "$cpu_temp" "$gpu_info"
    
    # CPU・メモリ・ディスク行
    printf " ${GREEN}CPU${NC}: %s | ${BLUE}メモリ${NC}: %s | ${CYAN}ディスク${NC}: %s\n" "${cpu_usage}%" "$memory_usage" "$disk_usage"
    
    # ロードアベレージ行
    printf " ${YELLOW}ロードアベレージ${NC}: %s\n" "$load_avg"
    
    echo -e "${WHITE}─────────────────────────────────────────────────────────────────────────${NC}"
    
    # ネットワーク行
    printf " ${CYAN}ネットワーク${NC}: %s\n" "$network_stats"
    
    # IPアドレス行
    printf " ${GREEN}IPアドレス${NC}: %s\n" "$ip_info"
    
    echo -e "${WHITE}─────────────────────────────────────────────────────────────────────────${NC}"
    
    # Claude Code使用状況（リアルタイム更新）
    printf " ${PURPLE}Claude Code${NC}: %s ${CYAN}[更新: %s]${NC}\n" "$claude_usage" "$(date '+%H:%M:%S')"
    
    # プラン別使用率表示
    if [ "$claude_plan_usage" != "N/A,N/A,N/A" ]; then
        pro_percent=$(echo "$claude_plan_usage" | cut -d',' -f1)
        max5x_percent=$(echo "$claude_plan_usage" | cut -d',' -f2)
        max20x_percent=$(echo "$claude_plan_usage" | cut -d',' -f3)
        
        # 制限値の表示
        printf " ${CYAN}制限値${NC}: Pro:45msg MAX5x:225msg MAX20x:900msg (5時間)\n"
        
        printf " 使用率: "
        format_usage_status "$pro_percent" "Pro"
        printf " "
        format_usage_status "$max5x_percent" "MAX5x"
        printf " "
        format_usage_status "$max20x_percent" "MAX20x"
        printf "\n"
    fi
    
    echo -e "${WHITE}─────────────────────────────────────────────────────────────────────────${NC}"
    
    # プロセスヘッダー
    printf " ${PURPLE}CPU使用率上位プロセス${NC}:\n"
    
    # プロセス一覧を表示
    get_top_processes | while IFS= read -r line; do
        printf "   %s\n" "$line"
    done
    
    echo -e "${WHITE}─────────────────────────────────────────────────────────────────────────${NC}"
    
    # 指定秒数待機
    sleep $REFRESH_INTERVAL
done
