import 'swiss_event_sample.dart';

class SwissEventBridge implements SwissEventNativeApi {
  SwissEventBridge();
  @override
  SwissEventExecutionKind get executionKind =>
      SwissEventExecutionKind.nativeLibrary;
  @override
  SwissEventNativeSample readUtc(DateTime utc) => throw SwissEventReadFailure(
    'native_detail_api_unavailable',
    'Native detail API is unavailable on this platform',
    utc: utc.toUtc(),
  );
}
