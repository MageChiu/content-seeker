import '../../domain/runtime/runtime_session_state.dart';

class RuntimeState {
  final RuntimeSessionState session;
  final bool initialized;

  const RuntimeState({
    this.session = const RuntimeSessionState.idle(),
    this.initialized = false,
  });

  RuntimeState copyWith({
    RuntimeSessionState? session,
    bool? initialized,
  }) {
    return RuntimeState(
      session: session ?? this.session,
      initialized: initialized ?? this.initialized,
    );
  }
}
