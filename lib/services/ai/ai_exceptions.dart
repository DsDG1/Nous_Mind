/// Sealed exception hierarchy for AI analysis failures. The UI layer maps
/// each subtype to a user-facing Chinese SnackBar message so callers do
/// not need to inspect the underlying transport / parse details.
library;

/// Base class for every AI analyzer exception. Carries a Chinese
/// message that the UI surfaces verbatim.
sealed class AiAnalysisException implements Exception {
  AiAnalysisException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The API key is missing, empty, or rejected by the server (401/403).
class AiAuthException extends AiAnalysisException {
  AiAuthException(super.message);
}

/// The server returned HTTP 429 — the user is calling too fast, or the
/// per-account quota has been temporarily exhausted.
class AiRateLimitException extends AiAnalysisException {
  AiRateLimitException(super.message);
}

/// The server returned a 5xx or any other non-success status code.
class AiServerException extends AiAnalysisException {
  AiServerException(super.message);
}

/// The request never reached the server — timeout, DNS failure, broken
/// socket, etc.
class AiNetworkException extends AiAnalysisException {
  AiNetworkException(super.message);
}

/// The server responded but the body could not be parsed (malformed
/// JSON, missing fields, etc.).
class AiParseException extends AiAnalysisException {
  AiParseException(super.message);
}

/// On-device OCR failed — model not downloaded, native crash, or empty
/// result that cannot be retried.
class AiOcrException extends AiAnalysisException {
  AiOcrException(super.message);
}

/// Thrown when the per-user daily ceiling is hit. Mapped to a Chinese
/// SnackBar by the UI layer; the analyzer itself only enforces it
/// defensively so a misconfigured UI cannot silently blow the budget.
class AiUsageLimitException extends AiAnalysisException {
  AiUsageLimitException(super.message);
}

/// Thrown by the [AiUsageGuard] when the in-process cooldown window
/// has not elapsed yet. Distinct from [AiRateLimitException] (which
/// mirrors the server's 429) because this is a purely client-side
/// anti-spam signal.
class AiCooldownException extends AiAnalysisException {
  AiCooldownException(super.message);
}
