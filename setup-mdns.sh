#!/bin/bash

# WSL2 mirrorモードでmDNS (.local) 名前解決を設定するスクリプト
# mDNS (Multicast DNS) を使用して .local ドメインの名前解決を可能にします

set -e

echo "========================================"
echo "mDNS (.local) 名前解決のセットアップ"
echo "========================================"
echo ""

# rootユーザーでの実行確認
if [ "$EUID" -ne 0 ]; then
  echo "エラー: このスクリプトは管理者権限で実行する必要があります"
  echo "sudo ./setup-mdns.sh を実行してください"
  exit 1
fi

# WSL2のバージョンを確認
WSL_VERSION=$(wsl.exe -l -v 2>/dev/null | grep -i ubuntu | awk '{print $3}' || echo "unknown")
echo "検出されたWSLバージョン: $WSL_VERSION"
echo ""

# パッケージリストを更新
echo "[1/4] パッケージリストを更新中..."
apt-get update -qq

# Avahiとlibnss-mdnsをインストール
echo "[2/4] avahi-daemon と libnss-mdns をインストール中..."
apt-get install -y avahi-daemon libnss-mdns

# /etc/nsswitch.conf を設定
echo "[3/4] /etc/nsswitch.conf を設定中..."
if ! grep -q "mdns_minimal" /etc/nsswitch.conf; then
    # hostsの行を編集してmdns_minimalを追加
    sed -i 's/^\(hosts:.*\)files\(.*\)dns/\1files mdns_minimal [NOTFOUND=return]\2dns/' /etc/nsswitch.conf
    echo "  - mdns_minimal を追加しました"
else
    echo "  - mdns_minimal は既に設定されています"
fi

# avahi-daemonの設定
echo "[4/4] avahi-daemon サービスを設定中..."

# avahi-daemon.confの設定を確認/更新
if [ -f /etc/avahi/avahi-daemon.conf ]; then
    # use-ipv4とuse-ipv6が有効になっていることを確認
    sed -i 's/^#use-ipv4=yes/use-ipv4=yes/' /etc/avahi/avahi-daemon.conf
    sed -i 's/^#use-ipv6=yes/use-ipv6=yes/' /etc/avahi/avahi-daemon.conf
fi

# avahi-daemonを起動
service avahi-daemon start || systemctl start avahi-daemon 2>/dev/null || true

echo ""
echo "========================================"
echo "セットアップが完了しました！"
echo "========================================"
echo ""
echo "これで .local ドメインの名前解決が可能になりました。"
echo ""
echo "使用例:"
echo "  ping hostname.local"
echo "  ssh user@hostname.local"
echo ""
echo "注意事項:"
echo "  - WSL2 mirrorモードを使用している場合、このスクリプトが正常に動作します"
echo "  - 名前解決が遅い場合は、Windows側でDNSトンネリングを無効化してください"
echo "    (.wslconfig ファイルで dnsTunneling=false を設定)"
echo ""
echo "詳細: https://learn.microsoft.com/en-us/windows/wsl/troubleshooting"
echo ""
