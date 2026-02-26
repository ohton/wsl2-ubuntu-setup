#!/bin/bash

set -e

# 色の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ログ関数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# クリーンアップ関数
cleanup() {
    if [ -n "$TEMP_MOUNT" ] && mountpoint -q "$TEMP_MOUNT" 2>/dev/null; then
        log_info "一時マウントをクリーンアップしています..."
        sudo umount "$TEMP_MOUNT" 2>/dev/null || true
    fi
    if [ -n "$TEMP_MOUNT" ] && [ -d "$TEMP_MOUNT" ]; then
        sudo rmdir "$TEMP_MOUNT" 2>/dev/null || true
    fi
    if [ -n "$TEMP_CREDS" ] && [ -f "$TEMP_CREDS" ]; then
        sudo rm -f "$TEMP_CREDS" 2>/dev/null || true
    fi
}

trap cleanup EXIT

# 必要なパッケージのチェックとインストール
check_dependencies() {
    log_info "必要なパッケージを確認しています..."
    local packages_to_install=()
    
    if ! command -v autofs &> /dev/null; then
        packages_to_install+=("autofs")
    fi
    
    if ! command -v mount.cifs &> /dev/null; then
        packages_to_install+=("cifs-utils")
    fi
    
    if ! command -v smbclient &> /dev/null; then
        packages_to_install+=("smbclient")
    fi
    
    # 共有ライブラリの確認
    if ! ldconfig -p | grep -q libcap-ng; then
        packages_to_install+=("libcap-ng0")
    fi
    
    if ! dpkg -l | grep -q keyutils; then
        packages_to_install+=("keyutils")
    fi
    
    if [ ${#packages_to_install[@]} -gt 0 ]; then
        log_info "以下のパッケージをインストールします: ${packages_to_install[*]}"
        sudo apt update
        sudo apt install -y "${packages_to_install[@]}"
        log_success "パッケージのインストールが完了しました"
    else
        log_success "必要なパッケージはすべてインストール済みです"
    fi
}

# ホストの疎通確認
check_host() {
    local host=$1
    log_info "ホスト $host の疎通確認中..."
    
    # pingで確認
    if ping -c 1 -W 2 "$host" &> /dev/null; then
        log_success "ホスト $host に到達可能です"
        return 0
    fi
    
    # nmblookupで確認（mdns）
    if command -v nmblookup &> /dev/null; then
        if nmblookup "$host" &> /dev/null; then
            log_success "ホスト $host を名前解決できました"
            return 0
        fi
    fi
    
    log_error "ホスト $host に到達できません"
    return 1
}

# 共有リストの取得
list_shares() {
    local host=$1
    local username=$2
    local password=$3
    
    local result
    if [ -n "$username" ] && [ -n "$password" ]; then
        result=$(smbclient -L "//$host" -U "$username%$password" -N 2>/dev/null | grep "Disk" | awk '{print $1}' || true)
    else
        result=$(smbclient -L "//$host" -N 2>/dev/null | grep "Disk" | awk '{print $1}' || true)
    fi
    
    echo "$result"
}

# 接続テスト
test_connection() {
    local host=$1
    local share=$2
    local username=$3
    local password=$4
    
    log_info "接続テストを実行中..."
    
    if smbclient "//$host/$share" -U "$username%$password" -c "ls" &> /dev/null; then
        log_success "接続テストが成功しました"
        return 0
    else
        log_error "接続テストが失敗しました"
        return 1
    fi
}

# 一時マウントテスト
test_mount() {
    local host=$1
    local share=$2
    local creds_file=$3
    
    TEMP_MOUNT=$(mktemp -d)
    log_info "一時マウントテストを実行中 ($TEMP_MOUNT)..."
    
    # デバッグ情報
    log_info "マウントコマンド: mount -t cifs //$host/$share $TEMP_MOUNT"
    log_info "認証情報ファイル: $creds_file"
    
    local mount_error=$(mktemp)
    # verboseモードで実行
    if sudo mount -t cifs "//$host/$share" "$TEMP_MOUNT" -o "credentials=$creds_file,iocharset=utf8,vers=3.0" -v 2>"$mount_error"; then
        log_success "マウントテストが成功しました"
        
        # 読み取りテスト
        if sudo ls "$TEMP_MOUNT" &> /dev/null; then
            log_success "読み取りテストが成功しました"
        else
            log_warning "読み取りテストが失敗しました"
        fi
        
        sudo umount "$TEMP_MOUNT"
        rm -f "$mount_error"
        return 0
    else
        log_error "マウントテストが失敗しました"
        if [ -s "$mount_error" ]; then
            log_error "エラー詳細:"
            cat "$mount_error" | while IFS= read -r line; do
                echo "  $line"
            done
            
            # カーネルログの確認
            log_info "カーネルログの最新エントリを確認しています..."
            dmesg | tail -n 20 | grep -i "cifs\|smb" || echo "  関連するログが見つかりませんでした"
        fi
        rm -f "$mount_error"
        
        # トラブルシューティングヒント
        echo
        log_info "トラブルシューティング:"
        echo "  1. 手動でマウントを試す:"
        echo "     sudo mount -t cifs //$host/$share /mnt -o username=$USERNAME,password=***,vers=3.0"
        echo "  2. SMBバージョンを変更して試す:"
        echo "     vers=2.0, vers=2.1, vers=3.0, vers=3.1.1"
        echo "  3. カーネルログを確認: dmesg | grep -i cifs"
        
        return 1
    fi
}

# 既存設定のチェック
check_existing_config() {
    local mount_point=$1
    local parent_dir=$(dirname "$mount_point")
    local mount_name=$(basename "$mount_point")
    
    # マウントポイントが既にマウント中かチェック
    if mountpoint -q "$mount_point" 2>/dev/null; then
        log_warning "マウントポイント $mount_point は既にマウントされています"
        read -p "続行しますか？ [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # 既存のautofs設定をチェック（親ディレクトリ単位）
    if [ -d "/etc/auto.master.d" ]; then
        local existing_configs=$(grep -r "^$(echo "$parent_dir" | sed 's/[\/&]/\\&/g') " /etc/auto.master.d/ 2>/dev/null | cut -d: -f1 || true)
        if [ -n "$existing_configs" ]; then
            log_info "同じ親ディレクトリ ($parent_dir) の設定が既に存在します:"
            echo "$existing_configs"
            log_info "新しいマウント名 ($mount_name) はこの設定に追加されます"
        fi
    fi
    
    return 0
}

# マウント名の重複チェック
check_mount_name_conflict() {
    local map_file=$1
    local mount_name=$2
    
    if [ ! -f "$map_file" ]; then
        return 0
    fi
    
    if grep -q "^$mount_name " "$map_file" 2>/dev/null; then
        log_error "マウント名 '$mount_name' は既に '$map_file' に存在します"
        return 1
    fi
    
    return 0
}

# autofs設定の生成・追記
create_autofs_config() {
    local host=$1
    local share=$2
    local mount_point=$3
    local creds_file=$4
    local host_id=$5
    
    local parent_dir=$(dirname "$mount_point")
    local mount_name=$(basename "$mount_point")
    
    # 親ディレクトリから安全な名前を作成
    local parent_safe=$(echo "$parent_dir" | sed 's/^[/]//; s/[/]/-/g' | tr '.:' '--')
    [ -z "$parent_safe" ] && parent_safe="root"
    
    local master_file="/etc/auto.master.d/${parent_safe}.autofs"
    local map_file="/etc/auto.cifs-${parent_safe}"
    
    log_info "autofs設定を生成中..."
    log_info "マウント親ディレクトリ: $parent_dir"
    log_info "マスターファイル: $master_file"
    log_info "マップファイル: $map_file"
    
    # マウント名の重複チェック
    if ! check_mount_name_conflict "$map_file" "$mount_name"; then
        return 1
    fi
    
    # マスターファイルが存在しない場合のみ作成
    if [ ! -f "$master_file" ]; then
        echo "$parent_dir $map_file" | sudo tee "$master_file" > /dev/null
        log_success "マスターファイルを作成しました: $master_file"
    else
        log_info "マスターファイルは既に存在します: $master_file"
    fi
    
    # 新しいエントリをマップファイルに追記
    local new_entry="$mount_name -fstype=cifs,rw,iocharset=utf8,vers=3.0,credentials=$creds_file ://$host/$share"
    echo "$new_entry" | sudo tee -a "$map_file" > /dev/null
    sudo chmod -x "$map_file"
    log_success "マップファイルにエントリを追記しました: $map_file"
    
    # 親ディレクトリ作成
    if [ ! -d "$parent_dir" ]; then
        sudo mkdir -p "$parent_dir"
        log_success "親ディレクトリを作成しました: $parent_dir"
    fi
    
    echo "$master_file|$map_file|$mount_name"
}

# autofs設定の部分削除（ロールバック用）
rollback_config() {
    local master_file=$1
    local map_file=$2
    local mount_name=$3
    
    log_warning "設定をロールバックしています..."
    
    # マップファイルから該当エントリを削除
    if [ -f "$map_file" ]; then
        local line_count=$(sudo wc -l < "$map_file")
        local entry_count=$(sudo grep -c "^$mount_name " "$map_file" || true)
        
        # エントリを削除
        sudo sed -i "/^$mount_name /d" "$map_file"
        log_info "マップファイルからエントリを削除しました: $map_file"
        
        # マップファイルが空になった場合はマスターファイルも削除
        local remaining=$(sudo wc -l < "$map_file" || echo 0)
        if [ "$remaining" -eq 0 ]; then
            sudo rm -f "$map_file"
            log_info "マップファイルが空になったため削除しました: $map_file"
            
            if [ -f "$master_file" ]; then
                sudo rm -f "$master_file"
                log_info "マスターファイルを削除しました: $master_file"
            fi
        fi
    fi
}

# メイン処理
main() {
    echo "========================================"
    echo "  autofs CIFS マウント設定スクリプト"
    echo "========================================"
    echo
    
    # 依存関係チェック
    check_dependencies
    echo
    
    # ステップ1: ホスト入力
    local ORIGINAL_HOST=""
    while true; do
        read -p "マウント対象のホスト名を入力してください (例: hostname.local): " HOST
        if [ -z "$HOST" ]; then
            log_error "ホスト名を入力してください"
            continue
        fi
        
        if check_host "$HOST"; then
            ORIGINAL_HOST="$HOST"
            break
        else
            read -p "ホストに到達できません。IPアドレスを直接入力しますか？ [y/N]: " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                read -p "IPアドレスを入力してください: " HOST
                if [ -n "$HOST" ]; then
                    break
                fi
            fi
        fi
    done
    
    # ホスト識別名の決定とIPアドレスオプション
    if [[ "$HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # IPアドレスが直接入力された場合
        read -p "設定ファイル名用の識別名を入力してください (例: hostname): " HOST_ID
        if [ -z "$HOST_ID" ]; then
            log_warning "識別名が入力されませんでした。IPアドレスをそのまま使用します"
            HOST_ID=$(echo "$HOST" | tr '.' '-')
        fi
    else
        # ホスト名の場合、IPアドレスを取得
        HOST_ID="${HOST%%.*}"
        local RESOLVED_IP=$(getent hosts "$HOST" | awk '{ print $1 }' | head -n 1)
        
        if [ -n "$RESOLVED_IP" ]; then
            log_info "ホスト名 $HOST のIPアドレス: $RESOLVED_IP"
            read -p "パフォーマンス向上のため、IPアドレスを使用しますか？ [y/N]: " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "設定にIPアドレス $RESOLVED_IP を使用します"
                HOST="$RESOLVED_IP"
            else
                log_info "設定にホスト名 $ORIGINAL_HOST を使用します"
            fi
        else
            log_warning "IPアドレスを取得できませんでした。ホスト名を使用します"
        fi
    fi
    echo
    
    # ステップ2: 認証情報入力
    read -p "ユーザー名を入力してください: " USERNAME
    read -s -p "パスワードを入力してください: " PASSWORD
    echo
    echo
    
    # 共有リストの表示
    log_info "共有ディレクトリのリストを取得中..."
    SHARES=$(list_shares "$HOST" "$USERNAME" "$PASSWORD")
    if [ -n "$SHARES" ]; then
        log_info "利用可能な共有:"
        echo "$SHARES" | while read -r share; do
            echo "  - $share"
        done
        echo
    else
        log_warning "共有リストを取得できませんでした（続行できます）"
        echo
    fi
    
    # ステップ3: 共有ディレクトリ入力
    while true; do
        read -p "マウントする共有ディレクトリ名を入力してください (例: books): " SHARE
        if [ -z "$SHARE" ]; then
            log_error "共有ディレクトリ名を入力してください"
            continue
        fi
        
        if test_connection "$HOST" "$SHARE" "$USERNAME" "$PASSWORD"; then
            break
        else
            log_error "共有ディレクトリへの接続に失敗しました"
            read -p "別の共有ディレクトリ名を試しますか？ [y/N]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_error "処理を中止します"
                exit 1
            fi
        fi
    done
    echo
    
    # 一時認証情報ファイルの作成
    TEMP_CREDS=$(mktemp)
    cat > "$TEMP_CREDS" << EOF
username=$USERNAME
password=$PASSWORD
EOF
    chmod 600 "$TEMP_CREDS"
    
    log_info "認証情報ファイルを作成しました"
    
    # ステップ4: 一時マウントテスト
    if ! test_mount "$HOST" "$SHARE" "$TEMP_CREDS"; then
        log_error "マウントテストに失敗しました。処理を中止します。"
        exit 1
    fi
    echo
    
    # ステップ5: マウント先入力
    while true; do
        read -p "マウント先のパスを入力してください (例: /Volumes/books): " MOUNT_POINT
        if [ -z "$MOUNT_POINT" ]; then
            log_error "マウント先のパスを入力してください"
            continue
        fi
        
        # 絶対パスチェック
        if [[ ! "$MOUNT_POINT" = /* ]]; then
            log_error "絶対パスで入力してください"
            continue
        fi
        
        # ルート直下のマウントポイント警告
        if [ "$(dirname "$MOUNT_POINT")" = "/" ]; then
            log_warning "ルート直下へのマウントは推奨されません"
            log_info "推奨: /mnt/books, /media/books, /Volumes/books など"
            read -p "続行しますか？ [y/N]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                continue
            fi
        fi
        
        if check_existing_config "$MOUNT_POINT"; then
            break
        fi
    done
    echo
    
    # 認証情報ファイルの作成
    local safe_name=$(echo "${HOST_ID}-${SHARE}" | tr '.:' '--')
    local creds_file="/etc/creds/${safe_name}"
    
    sudo mkdir -p /etc/creds
    sudo tee "$creds_file" > /dev/null << EOF
username=$USERNAME
password=$PASSWORD
EOF
    sudo chmod 600 "$creds_file"
    log_success "認証情報ファイルを作成しました: $creds_file"
    echo
    
    # ステップ6: autofs設定の生成
    # ログ出力が混ざらないよう関数の最終行のみ取得
    CONFIG_FILES=$(create_autofs_config "$HOST" "$SHARE" "$MOUNT_POINT" "$creds_file" "$HOST_ID" | tail -n 1)
    if [ -z "$CONFIG_FILES" ]; then
        log_error "autofs設定の生成に失敗しました"
        sudo rm -f "$creds_file"
        exit 1
    fi
    
    MASTER_FILE=$(echo "$CONFIG_FILES" | cut -d'|' -f1)
    MAP_FILE=$(echo "$CONFIG_FILES" | cut -d'|' -f2)
    MOUNT_NAME=$(echo "$CONFIG_FILES" | cut -d'|' -f3)
    echo
    
    # autofsの有効化と再起動
    log_info "autofsサービスを設定中..."
    if ! sudo systemctl is-enabled autofs &> /dev/null; then
        sudo systemctl enable autofs
        log_success "autofsサービスを有効化しました"
    fi
    
    if sudo systemctl restart autofs; then
        log_success "autofsサービスを再起動しました"
    else
        log_error "autofsサービスの再起動に失敗しました"
        rollback_config "$MASTER_FILE" "$MAP_FILE" "$MOUNT_NAME"
        sudo rm -f "$creds_file"
        exit 1
    fi
    echo
    
    # 動作確認
    log_info "設定の動作確認中..."
    sleep 2
    
    if ls "$MOUNT_POINT" &> /dev/null; then
        log_success "マウントが成功しました！"
        echo
        echo "========================================"
        echo -e "${GREEN}設定完了！${NC}"
        echo "========================================"
        echo "マウントポイント: $MOUNT_POINT"
        echo "リモート: //$HOST/$SHARE"
        echo
        echo "作成・更新されたファイル:"
        echo "  マスター: $MASTER_FILE"
        echo "  マップ  : $MAP_FILE"
        echo "  認証情報: $creds_file"
        echo
        echo "マップファイルの内容例:"
        echo "  $(sudo tail -n 1 "$MAP_FILE")"
        echo
        echo "確認コマンド:"
        echo "  ls $MOUNT_POINT"
        echo "  df -h | grep $MOUNT_POINT"
        echo "  cat $MAP_FILE"
        echo
    else
        log_warning "自動マウントに失敗しました"
        echo "手動で確認してください:"
        echo "  sudo systemctl status autofs"
        echo "  sudo journalctl -u autofs -n 50"
        echo "  ls $MOUNT_POINT"
    fi
}

# スクリプト実行
main
