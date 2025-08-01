# Raspberry Pi Monitor Dashboard with Claude Code Usage Tracker

🚀 **リアルタイム監視ダッシュボード** - Raspberry Pi のシステム状況と Claude Code の使用量を同時に監視

![License: GPL-3.0](ttps://img.shields.io/badge/License-GPLv3-blue.svg)
![Platform: Linux](https://img.shields.io/badge/Platform-Linux-green.svg)
![Shell: Bash](https://img.shields.io/badge/Shell-Bash-orange.svg)

## ✨ 特徴

### 🖥️ システム監視
- **CPU/GPU温度** - リアルタイム温度監視（閾値による色分け）
- **リソース使用率** - CPU、メモリ、ディスク使用率
- **ネットワーク統計** - 送受信データ量、IPアドレス
- **システム情報** - 稼働時間、ロードアベレージ
- **プロセス監視** - CPU使用率上位プロセス

### 🤖 Claude Code 使用量監視
- **セッション追跡** - 正確な5時間セッション制限の監視
- **トークン使用量** - 入力・出力・キャッシュトークンの詳細集計
- **コスト計算** - リアルタイムでの使用料金計算（USD）
- **使用率警告** - 制限接近時の段階的アラート
- **メッセージ数** - セッション内のメッセージ数カウント

## 🎯 表示例

```
===== Raspberry Pi リアルタイム監視ダッシュボード =====
更新間隔: 3秒 | 終了: Ctrl+C
システム: Raspberry Pi 5 Model B Rev 1.0 | Raspberry Pi OS | 6.12.34+rpt-rpi-2712 | aarch64

─────────────────────────────────────────────────────────────────────────
 時刻: 2025-08-01 09:15:30 | 稼働: 2 days
─────────────────────────────────────────────────────────────────────────
 CPU温度: 56°C | GPU: 56.5°C | 4M | 0MHz
 CPU: 12.5% | メモリ: 21.7% | ディスク: 3%
 ロードアベレージ: 0.68, 0.42, 0.19
─────────────────────────────────────────────────────────────────────────
 ネットワーク: wlan0: ↓1110MB ↑1197MB
 IPアドレス: wlan0: 192.168.1.100/24 tailscale0: 100.111.106.20/32
─────────────────────────────────────────────────────────────────────────
 Claude Code: セッション: 45672tk $13.7016 23msg 起動22回
 ⚠️ 使用率85% 制限接近
─────────────────────────────────────────────────────────────────────────
 CPU使用率上位プロセス:
   jun          11.9% claude
   jun           1.4% /home/jun/.vscode-server/cli/s
   jun           1.2% /home/jun/.vscode-server/cli/s
   jun           0.9% /home/jun/.vscode-server/cli/s
   jun           0.9% /home/jun/.vscode-server/cli/s
─────────────────────────────────────────────────────────────────────────
```

## 📦 インストール

### 必要な環境
- **OS**: Linux (Raspberry Pi OS推奨)
- **Shell**: Bash 4.0+
- **依存関係**: なし（標準Unixコマンドのみ使用）

### インストール手順

1. **リポジトリのクローン**
```bash
git clone https://github.com/yourusername/raspberry-pi-claude-monitor.git
cd raspberry-pi-claude-monitor
```

2. **実行権限の付与**
```bash
chmod +x claude-pi-monitor.sh
```

3. **実行**
```bash
./claude-pi-monitor.sh
```

## 🚀 使用方法

### 基本的な使用方法

```bash
# デフォルト（3秒間隔）で起動
./claude-pi-monitor.sh

# 更新間隔を指定（秒）
./claude-pi-monitor.sh 5

# バックグラウンド実行
nohup ./claude-pi-monitor.sh &
```

### 終了方法
- **Ctrl+C** - 監視を停止

### カスタマイズ

スクリプト内の設定値を変更することで、以下をカスタマイズできます：

- **温度閾値**: CPU/GPU温度の警告レベル
- **Claude Code制限値**: セッション制限の推定値
- **更新間隔**: デフォルトの更新間隔
- **表示項目**: 監視したい項目の追加・削除

## 🎨 アラート設定

### CPU温度アラート
- 🟢 **60°C未満**: 正常（緑）
- 🟡 **60-70°C**: 注意（黄）
- 🔴 **70°C以上**: 警告（赤）

### Claude Code使用率アラート
- ✅ **60%未満**: 正常
- 📊 **60-80%**: 注意レベル
- ⚠️ **80-99%**: 制限接近警告
- 🚨 **100%**: セッション制限到達

## 🛠️ トラブルシューティング

### よくある問題

**Q: Claude Code使用量が表示されない**
```bash
# Claude Codeの設定ディレクトリが存在するか確認
ls -la ~/.claude/projects/
```

**Q: 権限エラーが発生する**
```bash
# 実行権限を確認・付与
chmod +x claude-pi-monitor.sh
```

**Q: GPU情報が表示されない**
```bash
# vcgencmdが利用可能か確認（Raspberry Pi専用）
which vcgencmd
```

### デバッグモード

一時ファイルの内容を確認したい場合：
```bash
# 一時ファイルの確認
ls /tmp/claude_usage_* /tmp/session_msgs_*
```

## 🤝 貢献

プルリクエスト、Issue報告、改善提案を歓迎します！

### 開発に参加する

1. **Fork** このリポジトリ
2. **Feature branch** を作成 (`git checkout -b feature/amazing-feature`)
3. **Commit** 変更内容 (`git commit -m 'Add amazing feature'`)
4. **Push** to branch (`git push origin feature/amazing-feature`)
5. **Pull Request** を作成

## 📋 TODO / 今後の予定

- [ ] Web UI版の開発
- [ ] より多くのシステム統計情報の追加
- [ ] 設定ファイル対応
- [ ] ログ出力機能
- [ ] Docker対応
- [ ]他のSBC（Single Board Computer）対応

## 📄 ライセンス

このプロジェクトは **MIT License** の下で公開されています。詳細は [LICENSE](LICENSE) ファイルを参照してください。

## 🙏 謝辞

- Claude Code Usage Monitor の仕組みを参考にしました: [Maciek-roboblog/Claude-Code-Usage-Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor)
- Raspberry Pi コミュニティの皆様

## 📞 サポート

問題や質問がありましたら、[Issues](https://github.com/yourusername/raspberry-pi-claude-monitor/issues) にて報告してください。

---

⭐ このプロジェクトが役に立ったら、ぜひ **Star** をお願いします！

**Made with ❤️ for Raspberry Pi & Claude Code users**
