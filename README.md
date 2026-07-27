# ぱんちょ式 超本格占星術占い

ぱんちょ式 超本格占星術占いは、出生図と現在の星の流れをもとに、毎日・月間・年間・カスタム鑑定を表示するFlutterアプリです。

英語表記は `pancyo Astrology`、短縮表示名は `ぱんちょ式星占い` です。

## 開発メモ

- Android版の星計算はSwiss Ephemeris Free Edition/AGPLを優先して使います。
- Web/ネイティブライブラリ未読込時はアプリ内の簡易計算へフォールバックします。
- 占いは端末内の占星術計算とルールベース文章で完結します。
- プロフィール未入力時は、仮データとして1980/9/24・12:00・北海道札幌市を使います。
- ライセンスと星データの採用方針は `docs/開発方針.md` にまとめています。
- 採用したデータやライブラリの記録は `docs/ライセンス台帳.md` にまとめます。
- 星計算の精度強化設計は `docs/星計算精度強化設計.md` にまとめています。
- Swiss Ephemerisの実装方針は `docs/本格化ロードマップ.md` にまとめています。
- ソース公開前の確認項目は `docs/ソース公開準備.md` にまとめています。
- 公開前の確認項目は `docs/リリース前チェックリスト.md` にまとめています。
- Swiss Ephemerisを使うため、ソース公開とAGPL対応を前提に整備します。

## ライセンス

このプロジェクトは、Android版の星計算にSwiss Ephemeris Free Editionを使うため、GNU Affero General Public License version 3 or laterとして公開する前提で整備しています。

- アプリ本体のライセンス本文: `LICENSE`
- 著作権表記と採用ライブラリの注意: `NOTICE.md`
- Swiss Ephemeris公式サイト: https://www.astro.com/swisseph/
- Swiss Ephemeris公式ソース: https://github.com/aloistr/swisseph
- アプリ本体の対応ソース: https://github.com/pancyo/pancyo_ai_astrology

現在は追加エフェメリスファイルを同梱していません。追加ファイルを配布する場合は、配布元、ライセンス、容量、チェックサムを記録してから有効化します。

## バージョン

現在の表示バージョンは `0.3.31` です。
Android内部のversionCodeは配布ごとに更新しますが、アプリ内には原則表示しません。
