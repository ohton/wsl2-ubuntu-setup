# WSL2 Ubuntu Setup

WSL2のUbuntu環境をセットアップするためのスクリプト集です。

## 含まれるスクリプト

- `install-packages.sh` - packages.jsonに基づいてapt/snapパッケージをインストール
- `setup-git.sh` - Gitのグローバル設定を対話的に行う
- `setup-volta.sh` - Volta (Node.jsバージョンマネージャー) をインストール
- `setup-mdns.sh` - mDNS (.local) 名前解決を設定
- `setup-autofs.sh` - SMB共有をautofsでオンデマンド自動マウント
- `packages.json` - インストールするパッケージのリスト

## 注意事項

- スクリプトは`sudo`権限を必要とします

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

### 3. Voltaのセットアップ

Volta (Node.jsバージョンマネージャー) をインストールします。

```bash
./setup-volta.sh
```

このスクリプトは以下を実行します:
- Voltaのインストール
- オプションでNode.js (最新LTSまたは指定バージョン) のインストール
- オプションでYarn (パッケージマネージャー) のインストール

**注意:** インストール後、変更を有効にするためにシェルを再起動するか、`source ~/.bashrc` を実行してください。

### 4. mDNS (.local) 名前解決のセットアップ

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

### 5. SMB共有の自動マウント (autofs)

WindowsやNAS上のSMB共有をautofsでオンデマンドにマウントします。mDNSが遅い場合はIPを使うこともできます。

```bash
sudo ./setup-autofs.sh
```

プロンプトに従って以下を入力します:
- ホスト名（例: `hostname.local`）またはIPの使用選択
- ユーザー名／パスワード
- 共有名の選択（例: `books`）
- マウント先のディレクトリ（例: `/Volumes/books`）

設定後の確認:

```bash
# マウントはディレクトリへアクセスしたときに自動で発生します
ls /Volumes/books
```

#### 生成されるファイル

- `/etc/auto.master.d/<MOUNT_PARENT>.autofs` - マスター設定（マウント親ディレクトリ単位、例: `/Volumes /etc/auto.cifs-volumes`）
- `/etc/auto.cifs-<MOUNT_PARENT>` - マップ設定（複数のマウント定義を管理）
- `/etc/creds/<HOST_ID>-<SHARE>` - 認証情報（権限600）

内部仕様:
- SMBバージョンは`vers=3.0`、文字コードは`iocharset=utf8`
- masterとmapはマウント親ディレクトリ単位で1つ管理され、複数の共有をマウントする場合はmapファイルに追記されます
- autofsのSUNマップではUNCに`://host/share`形式を使用します（`//host/share`だとデコードで1本スラッシュになるため）

#### トラブルシューティング

```bash
# autofsのデバッグ起動（一時）
sudo automount -f -v -d

# サービスログを確認
sudo journalctl -u autofs --no-pager -n 100

# カーネルメッセージの末尾
dmesg | tail -n 50
```

クリーンアップ（設定の削除）:

```bash
# 特定のマウント設定を削除する場合
# 例：/Volumes/books の CIFS マウントを削除
sudo sed -i "/^books /d" /etc/auto.cifs-volumes  # mapファイルからエントリを削除
sudo systemctl restart autofs

# 親ディレクトリ配下のすべてのマウント設定を削除する場合（例：/Volumes全体）
sudo rm /etc/auto.master.d/volumes.autofs \
  /etc/auto.cifs-volumes
sudo rm /etc/creds/hostname-books \
  /etc/creds/hostname-video
# 等（認証情報ファイルはすべて削除）
sudo systemctl restart autofs
```
