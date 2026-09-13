// Required for Flutter's `integration_test` package to run on Android. Without this class,
// the androidTest APK has no JUnit4 test to discover: `flutter build apk` compiles the Dart
// integration test into the app APK via -Ptarget, but something must still run it as an
// Android instrumentation test, and FlutterTestRunner (from the integration_test plugin) is
// that bridge. Confirmed missing 2026-09-12 -- a Firebase Test Lab run against
// integration_test/benchmark_test.dart completed in 1 second with "OK (0 tests)" because this
// file did not exist; logcat showed TestRequestBuilder scanning the androidTest APK's
// classpath and finding no test classes at all.
//
// Pattern matches the template Flutter itself ships at
// packages/integration_test/example/android/app/src/androidTest/.../FlutterActivityTest.java,
// adapted to Kotlin (this project's MainActivity is Kotlin, not Java) and targeting this
// project's own MainActivity rather than the generic FlutterActivity.
package com.instaham.instaham

import androidx.test.rule.ActivityTestRule
import dev.flutter.plugins.integration_test.FlutterTestRunner
import org.junit.Rule
import org.junit.runner.RunWith

@RunWith(FlutterTestRunner::class)
class MainActivityTest {
    @Rule
    @JvmField
    val rule = ActivityTestRule(MainActivity::class.java, true, false)
}
