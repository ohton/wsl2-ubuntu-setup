# WSL2 Ubuntu Setup

WSL2のUbuntu環境をセットアップするためのスクリプト集です。

## 使用方法

### 1. パッケージのインストール

`packages.json`に記述されたソフトウェアをインストールします。

```bash
./install-packages.sh
```

#### packages.jsonの編集

必要なパッケージを`packages.json`に追加・編集してください:

```json
{
  "apt": {
    "packages": [
      "jq",
      "fzf"
    ]
  },
  "snap": {
    "packages": [
      "your-snap-package"
    ]
  }
}
```

### 2. Gitのセットアップ

Git のを設定します。

```bash
./setup-git.sh
```

プロンプトに従って以下を入力してください:
- Gitユーザー名
- Gitメールアドレス
- デフォルトブランチ名(default: main)
- デフォルトエディタ(default: vim)

### 3. mDNS (.local) 名前解決のセットアップ

WSL2 mirrorモードで `.local` ドメインの名前解決を有効にします。

```bash
sudo ./setup-mdns.sh
```

このスクリプトは以下を実行します:
- `avahi-daemon` と `libnss-mdns` のインストール
- `/etc/nsswitch.conf` の設定
- mDNSサービスの起動

**重要:** WSL2 mirrorモードで `.local` 名前解決が遅い場合、Windowsの `.wslconfig` ファイルでDNSトンネリングを無効化してください。

`.wslconfig` ファイルの場所: `%USERPROFILE%\.wslconfig`

```ini
[experimental]
dnsTunneling=false
```

詳細については[Microsoft公式ドキュメント](https://learn.microsoft.com/en-us/windows/wsl/troubleshooting#networking-considerations-with-dns-tunneling)を参照してください。

## 含まれるスクリプト

- `install-packages.sh` - packages.jsonに基づいてapt/snapパッケージをインストール
- `setup-git.sh` - Gitのグローバル設定を対話的に行う
- `setup-mdns.sh` - mDNS (.local) 名前解決を設定
- `packages.json` - インストールするパッケージのリスト

## 注意事項

- スクリプトは`sudo`権限を必要とします
- 初回実行時は`apt update`が実行されます
