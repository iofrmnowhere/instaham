/// Base class for domain failures in INSTAHAM.
sealed class AppFailure {
  final String message;

  const AppFailure(this.message);
}

final class ImageLoadFailure extends AppFailure {
  const ImageLoadFailure(super.message);
}

final class InferenceFailure extends AppFailure {
  const InferenceFailure(super.message);
}

final class EligibilityFailure extends AppFailure {
  final String failureKey;

  const EligibilityFailure(super.message, this.failureKey);
}

final class ModelLoadFailure extends AppFailure {
  const ModelLoadFailure(super.message);
}
