import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_js/flutter_js.dart';

void main() {
  test('test javascript runtime and fetch', () async {
    final runtime = getJavascriptRuntime();
    print('Runtime created.');
    
    final result = await runtime.evaluateAsync("""
      (async () => {
        return "hello from js";
      })()
    """);
    
    print('Evaluating...');
    final resolved = await runtime.handlePromise(result);
    print('Resolved: ${resolved.stringResult}');
    runtime.dispose();
  });
}
