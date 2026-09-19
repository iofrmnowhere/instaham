 java.lang.Exception: ══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞═════════════════
The following TestFailure was thrown running a test:
Expected: a value less than <2000>
Actual: <5099>
Which: is not a value less than <2000>
Time-to-first-stable-frame must be < 2 000 ms on target device
When the exception was thrown, this was the stack:
#4 main.<anonymous closure> (file:///C:/Users/Adrian%20Jared%20Sido/OneDrive/Documents/Instaham_Proj/instaham/integration_test/benchmark_test.dart:39:5)
<asynchronous suspension>
#5 testWidgets.<anonymous closure>.<anonymous closure> (package:flutter_test/src/widget_tester.dart:192:15)
<asynchronous suspension>
#6 TestWidgetsFlutterBinding._runTestBody (package:flutter_test/src/binding.dart:1952:5)
<asynchronous suspension>
#7 TestWidgetsFlutterBinding._createTestCompletionHandler.<anonymous closure> (package:flutter_test/src/binding.dart:1706:12)
<asynchronous suspension>
This was caught by the test expectation on the following line:
file:///C:/Users/Adrian%20Jared%20Sido/OneDrive/Documents/Instaham_Proj/instaham/integration_test/benchmark_test.dart line 39
The test description was:
Metric 1 — Time-to-first-stable-frame (<2 000 ms target)
═════════════════════════════════════════════════════════════════
at dev.flutter.plugins.integration_test.FlutterTestRunner.run(FlutterTestRunner.java:84)
at org.junit.runners.Suite.runChild(Suite.java:128)
at org.junit.runners.Suite.runChild(Suite.java:27)
at org.junit.runners.ParentRunner$3.run(ParentRunner.java:290)
at org.junit.runners.ParentRunner$1.schedule(ParentRunner.java:71)
at org.junit.runners.ParentRunner.runChildren(ParentRunner.java:288)
at org.junit.runners.ParentRunner.access$000(ParentRunner.java:58)
at org.junit.runners.ParentRunner$2.evaluate(ParentRunner.java:268)
at org.junit.runners.ParentRunner.run(ParentRunner.java:363)
at org.junit.runner.JUnitCore.run(JUnitCore.java:137)
at org.junit.runner.JUnitCore.run(JUnitCore.java:115)
at androidx.test.internal.runner.TestExecutor.execute(TestExecutor.java:56)
at androidx.test.runner.AndroidJUnitRunner.onStart(AndroidJUnitRunner.java:395)
at android.app.Instrumentation$InstrumentationThread.run(Instrumentation.java:2411) 