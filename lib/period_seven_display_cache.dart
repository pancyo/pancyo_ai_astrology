part of 'main.dart';

/// Session-only display cache. Nothing here reads or writes a file or prefs.
/// Keys include the complete calculation inputs and injected job identities.
class PeriodSevenDisplaySessionCache {
  static const maximumSummaries = 12;
  static const maximumPendingPeriods = 2;
  static final _summaries = <Object, PeriodSevenSummary>{};
  static final _pending = <Object, _PeriodSevenPendingDisplay>{};

  static int get completedCount => _summaries.length;
  static int get pendingCount => _pending.length;

  /// Also available to isolate independent widget-test sessions.
  static void clear() {
    _summaries.clear();
    _pending.clear();
  }

  static PeriodSevenSummary? _read(Object key) {
    final value = _summaries.remove(key);
    if (value != null) _summaries[key] = value;
    return value;
  }

  static void _put(Object key, PeriodSevenSummary value) {
    _summaries.remove(key);
    _summaries[key] = value;
    _pending.remove(key);
    while (_summaries.length > maximumSummaries) {
      _summaries.remove(_summaries.keys.first);
    }
  }

  static _PeriodSevenPendingDisplay _resume(Object key) {
    final value = _pending.remove(key) ?? _PeriodSevenPendingDisplay();
    _pending[key] = value;
    while (_pending.length > maximumPendingPeriods) {
      _pending.remove(_pending.keys.first);
    }
    return value;
  }

  static void _retainPending(Object key, _PeriodSevenPendingDisplay value) {
    _pending.remove(key);
    _pending[key] = value;
    while (_pending.length > maximumPendingPeriods) {
      _pending.remove(_pending.keys.first);
    }
  }
}

bool _periodSevenDisplayWasCancelled(Object error) =>
    error is WeeklyDailyConsultExportCancelled ||
    error is MonthlyDailyConsultExportCancelled ||
    error is PeriodSevenDisplayCancelled;

/// Loads a full, validated period. Only the lightweight display path is split;
/// official export jobs and their formats are not changed.
Future<PeriodSevenSummary?> _loadPeriodSevenDisplay({
  required LongRangeMode mode,
  required DateTime first,
  required AstroProfile profile,
  required UserProfileDetails details,
  required HouseSystem houseSystem,
  required String sourceName,
  required bool highPrecision,
  required bool Function() isCurrent,
  required void Function(VoidCallback?) onCancel,
  required void Function(int, int, int?) onProgress,
  WeeklyDailyConsultExportStarter? startWeeklyJob,
  MonthlyDailyConsultExportStarter? startMonthlyJob,
  PeriodSevenDisplayStarter? startDisplayJob,
}) async {
  if (!isCurrent()) return null;
  if (mode == LongRangeMode.year ||
      (mode == LongRangeMode.month && first.day != 1)) {
    throw ArgumentError(
      'A complete display week or calendar month is required.',
    );
  }
  final key = periodSevenDisplayCacheKey(
    mode: mode,
    first: first,
    profile: profile,
    details: details,
    houseSystem: houseSystem,
    sourceName: sourceName,
    highPrecision: highPrecision,
    startWeeklyJob: startWeeklyJob,
    startMonthlyJob: startMonthlyJob,
    startDisplayJob: startDisplayJob,
  );
  final dayCount = mode == LongRangeMode.month
      ? DateTime.utc(first.year, first.month + 1, 0).day
      : 7;
  final total = dayCount * 7;
  final cached = PeriodSevenDisplaySessionCache._read(key);
  if (cached != null) {
    onProgress(total, total, null);
    return cached;
  }
  final legacyInjected =
      startDisplayJob == null &&
      (mode == LongRangeMode.week
          ? startWeeklyJob != null
          : startMonthlyJob != null);
  if (legacyInjected) {
    final summary = await _periodSevenFromInjectedExport(
      mode: mode,
      first: first,
      profile: profile,
      details: details,
      houseSystem: houseSystem,
      sourceName: sourceName,
      highPrecision: highPrecision,
      startWeeklyJob: startWeeklyJob,
      startMonthlyJob: startMonthlyJob,
      isCurrent: isCurrent,
      onCancel: onCancel,
      onProgress: onProgress,
    );
    if (!isCurrent() || summary == null) return null;
    PeriodSevenDisplaySessionCache._put(key, summary);
    return summary;
  }

  final pending = PeriodSevenDisplaySessionCache._resume(key);
  final ranges = mode == LongRangeMode.month
      ? <(int, int)>[(0, 15), (15, dayCount - 15)]
      : <(int, int)>[(0, 7)];
  var activePart = -1;
  for (var index = 0; index < ranges.length; index++) {
    if (!isCurrent()) return null;
    final (offset, count) = ranges[index];
    final part = mode == LongRangeMode.month ? index + 1 : null;
    final request = PeriodSevenDisplayRequest(
      startDateJst: first.add(Duration(days: offset)),
      endDateJst: first.add(Duration(days: offset + count - 1)),
      profile: profile,
      details: details,
      requestedHouseSystem: houseSystem,
      sourceName: sourceName,
      requireHighPrecision: highPrecision,
      generatedAt: pending.generatedAt,
    );
    if (pending.parts.containsKey(index)) {
      onProgress((offset + count) * 7, total, part);
      continue;
    }
    onProgress(offset * 7, total, part);
    activePart = index;
    final operation = (startDisplayJob ?? PeriodSevenDisplayJob.start)(
      request,
      (done, partTotal) {
        if (isCurrent() && activePart == index && partTotal == count * 7) {
          onProgress(offset * 7 + done.clamp(0, partTotal), total, part);
        }
      },
    );
    final future = operation.result;
    if (!isCurrent()) {
      operation.cancel();
      await future;
      return null;
    }
    onCancel(operation.cancel);
    final result = await future;
    if (!isCurrent()) return null;
    activePart = -1;
    validatePeriodSevenDisplayResult(result: result, request: request);
    // Result.fromData owns immutable, validated days. Keep no export wrapper,
    // event enumeration, encoded JSON or transient worker payload in the cache.
    pending.parts[index] = result.days;
    PeriodSevenDisplaySessionCache._retainPending(key, pending);
    onCancel(null);
    onProgress((offset + count) * 7, total, part);
  }
  if (!isCurrent()) return null;
  late PeriodSevenSummary summary;
  try {
    summary = PeriodSevenSummary.fromDisplayDays(
      mode: mode,
      startDateJst: first,
      days: [
        for (var index = 0; index < ranges.length; index++)
          ...pending.parts[index]!,
      ],
      profile: profile,
      details: details,
      requestedHouseSystem: houseSystem,
      sourceName: sourceName,
      requireHighPrecision: highPrecision,
    );
  } catch (_) {
    // A cross-part boundary failure must not permanently poison retry. The
    // verified first half stays available; recalculate the last part next time.
    pending.parts.remove(ranges.length - 1);
    rethrow;
  }
  if (!isCurrent()) return null;
  PeriodSevenDisplaySessionCache._put(key, summary);
  return summary;
}

class _PeriodSevenPendingDisplay {
  final generatedAt = DateTime.now().toUtc();
  final parts = <int, List<Map<String, Object?>>>{};
}

Object periodSevenDisplayCacheKey({
  required LongRangeMode mode,
  required DateTime first,
  required AstroProfile profile,
  required UserProfileDetails details,
  required HouseSystem houseSystem,
  required String sourceName,
  required bool highPrecision,
  WeeklyDailyConsultExportStarter? startWeeklyJob,
  MonthlyDailyConsultExportStarter? startMonthlyJob,
  PeriodSevenDisplayStarter? startDisplayJob,
}) => (
  mode,
  DateTime.utc(first.year, first.month, first.day),
  PeriodReadingContextRequest.profileIdentity(profile),
  jsonEncode(details.toJson()),
  houseSystem,
  sourceName,
  highPrecision,
  startWeeklyJob,
  startMonthlyJob,
  startDisplayJob,
  PeriodSevenSummary.aggregationVersion,
);

/// Keeps the existing injected export jobs as a compatibility/test adapter.
/// The production display path uses the lightweight worker below instead.
Future<PeriodSevenSummary?> _periodSevenFromInjectedExport({
  required LongRangeMode mode,
  required DateTime first,
  required AstroProfile profile,
  required UserProfileDetails details,
  required HouseSystem houseSystem,
  required String sourceName,
  required bool highPrecision,
  required WeeklyDailyConsultExportStarter? startWeeklyJob,
  required MonthlyDailyConsultExportStarter? startMonthlyJob,
  required bool Function() isCurrent,
  required void Function(VoidCallback?) onCancel,
  required void Function(int, int, int?) onProgress,
}) async {
  final generatedAt = DateTime.now().toUtc();
  late Map<String, Object?> data;
  void progress(int done, int total) => onProgress(done, total, null);
  if (mode == LongRangeMode.week) {
    final request = WeeklyDailyConsultExportRequest(
      startDate: DateTime.utc(first.year, first.month, first.day, 3),
      profile: profile,
      details: details,
      requestedHouseSystem: houseSystem,
      sourceName: sourceName,
      requireHighPrecision: highPrecision,
      generatedAt: generatedAt,
    );
    final operation = startWeeklyJob!(request, progress);
    final future = operation.result;
    if (!isCurrent()) {
      operation.cancel();
      await future;
      return null;
    }
    onCancel(operation.cancel);
    final result = await future;
    if (!isCurrent()) return null;
    if (result.requestIdentity != request.identity) {
      throw StateError('The display week belongs to different inputs.');
    }
    data = result.data;
    _weeklyValidateWrapper(data);
  } else {
    final request = MonthlyDailyConsultExportRequest(
      startDate: DateTime.utc(first.year, first.month, 1, 3),
      profile: profile,
      details: details,
      requestedHouseSystem: houseSystem,
      sourceName: sourceName,
      requireHighPrecision: highPrecision,
      generatedAt: generatedAt,
    );
    final operation = startMonthlyJob!(request, progress);
    final future = operation.result;
    if (!isCurrent()) {
      operation.cancel();
      await future;
      return null;
    }
    onCancel(operation.cancel);
    final result = await future;
    if (!isCurrent()) return null;
    if (result.requestIdentity != request.identity) {
      throw StateError('The display month belongs to different inputs.');
    }
    data = result.data;
    _monthlyValidateWrapper(data);
  }
  if (data['generated_at'] != generatedAt.toIso8601String()) {
    throw StateError('The display generation time differs from its request.');
  }
  onCancel(null);
  return PeriodSevenSummary.fromDailyV4(
    mode: mode,
    startDateJst: first,
    days: [
      for (final day in _monthlyList(data['days'], 'display days'))
        _monthlyMap(day, 'display daily-v4'),
    ],
    profile: profile,
    details: details,
    requestedHouseSystem: houseSystem,
    sourceName: sourceName,
    requireHighPrecision: highPrecision,
  );
}
