import 'package:flutter/material.dart';

import '../english_ui_text.dart';
import 'numeric_score_candidate_comparison.dart';

/// Research-only presentation. Never replaces the app's canonical score cards.
class ResearchNumericComparisonButton extends StatelessWidget {
  const ResearchNumericComparisonButton({super.key, required this.comparison});

  final Map<String, Object?> comparison;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const Key('research-numeric-comparison-open'),
    icon: const Icon(Icons.science_outlined),
    label: const EnglishUiText('研究：点数の仮案を比較'),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const EnglishUiText('点数の仮案を比較', style: TextStyle(fontSize: 20)),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: ResearchNumericComparisonPanel(
                      comparison: comparison,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const EnglishUiText('閉じる'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ResearchNumericComparisonPanel extends StatefulWidget {
  const ResearchNumericComparisonPanel({super.key, required this.comparison});

  final Map<String, Object?> comparison;

  @override
  State<ResearchNumericComparisonPanel> createState() =>
      _ResearchNumericComparisonPanelState();
}

class _ResearchNumericComparisonPanelState
    extends State<ResearchNumericComparisonPanel> {
  String _selected = NumericScoreCandidateComparison.candidateB;

  static const _names = {
    'overall': '総合',
    'love': '恋愛',
    'work': '仕事',
    'money': '金運',
    'mental': '心',
    'health': '健康',
    'people': '対人',
    'actionDecision': '行動',
  };

  Map _candidate(String id) {
    final candidates = widget.comparison['candidates'];
    if (candidates is List) {
      for (final item in candidates) {
        if (item is Map && item['candidate_version'] == id) return item;
      }
    }
    return const {};
  }

  Map _area(String id, String key) {
    final areas = _candidate(id)['areas'];
    final area = areas is Map ? areas[key] : null;
    return area is Map ? area : const {};
  }

  String _score(Object? value) => value is num ? value.toString() : '保留';

  String _candidateScore(String id, String key) {
    final area = _area(id, key);
    final value = area['candidate_score'];
    final delta = area['score_delta'];
    if (value is! num) return '保留';
    if (delta is! num || delta == 0) return '$value（±0）';
    return '$value（${delta > 0 ? '+' : ''}$delta）';
  }

  @override
  Widget build(BuildContext context) {
    final baseline = widget.comparison['baseline_numeric_areas'];
    final selectedOverall = _area(_selected, 'overall');
    final selectedName = _selected == NumericScoreCandidateComparison.candidateA
        ? 'A'
        : 'B';
    final missing = _names.keys
        .where((key) => _area(_selected, key)['candidate_score'] == null)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EnglishUiText(
          '未検証の研究用です。元の点数は変更しません。'
          '点数が上がっても、当たりやすくなったことを意味しません。',
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('research-numeric-candidate-selector'),
          initialValue: _selected,
          isExpanded: true,
          decoration: const InputDecoration(label: EnglishUiText('詳しく見る仮案')),
          items: const [
            DropdownMenuItem(
              value: NumericScoreCandidateComparison.candidateA,
              child: EnglishUiText('A：良悪の材料が多い3群'),
            ),
            DropdownMenuItem(
              value: NumericScoreCandidateComparison.candidateB,
              child: EnglishUiText('B：全ての方向群を残す'),
            ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _selected = value);
          },
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 18,
            horizontalMargin: 8,
            columns: const [
              DataColumn(label: EnglishUiText('項目')),
              DataColumn(label: EnglishUiText('元の点数'), numeric: true),
              DataColumn(label: EnglishUiText('仮案A（差）'), numeric: true),
              DataColumn(label: EnglishUiText('仮案B（差）'), numeric: true),
            ],
            rows: [
              for (final entry in _names.entries)
                DataRow(
                  cells: [
                    DataCell(EnglishUiText(entry.value)),
                    DataCell(
                      EnglishUiText(
                        _score(
                          baseline is Map && baseline[entry.key] is Map
                              ? (baseline[entry.key] as Map)['score']
                              : null,
                        ),
                      ),
                    ),
                    DataCell(
                      EnglishUiText(
                        _candidateScore(
                          NumericScoreCandidateComparison.candidateA,
                          entry.key,
                        ),
                      ),
                    ),
                    DataCell(
                      EnglishUiText(
                        _candidateScore(
                          NumericScoreCandidateComparison.candidateB,
                          entry.key,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        EnglishUiText(
          '仮案$selectedNameの総合：'
          '${_score(selectedOverall['candidate_score'])}点',
          key: const Key('research-selected-overall'),
        ),
        const SizedBox(height: 8),
        EnglishUiText(
          _selected == NumericScoreCandidateComparison.candidateA
              ? 'Aは、良い面と難しい面の材料が多い天体の上位3群を使います。'
              : 'Bは、方向性がある全ての天体群を使い、4群以上は3÷群数で調整します。'
                    '全群を残す設計理由から、この比較画面の初期表示に選んでいます。',
        ),
        const SizedBox(height: 8),
        EnglishUiText(
          missing == 0
              ? '総合は6分野の丸め前平均です。行動運と正規の体感は変更していません。'
              : '$missing項目は必要な根拠が足りないため保留です。'
                    '欠けた点数は推測しません。',
        ),
        const SizedBox(height: 8),
        const EnglishUiText(
          '一般向けの採用判断は保留です。仮JSONの研究比較欄にも'
          '元の点数・仮案・差・計算の根拠を分けて残します。',
        ),
      ],
    );
  }
}
