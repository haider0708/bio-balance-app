import 'dart:async';

import 'package:biobalance/core/widgets/paged_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a page that lands after a refresh is dropped, not mixed into the new list',
    () async {
      final slow = Completer<PageResult<int>>();
      var calls = 0;
      final controller = PagedController<int>((cursor) {
        calls++;
        // The first request is slow; the refresh asks again and gets its answer at once.
        return calls == 1
            ? slow.future
            : Future.value(const PageResult([10, 11], null));
      });
      await controller.refresh();
      expect(controller.items, [10, 11]);
      // The old answer finally arrives: it must change nothing.
      slow.complete(const PageResult([1, 2, 3], 'next'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.items, [10, 11]);
      expect(controller.hasMore, isFalse);
      controller.dispose();
    },
  );

  test(
    'a failed page keeps its rows, shows the error, and loads again on demand',
    () async {
      var fail = false;
      final controller = PagedController<int>((cursor) async {
        if (fail) throw StateError('x');
        return PageResult(
          cursor == null ? [1] : [2],
          cursor == null ? 'a' : null,
        );
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.items, [1]);
      fail = true;
      await controller.load();
      expect(controller.error, isNotNull);
      expect(controller.items, [1]);
      fail = false;
      await controller.load();
      expect(controller.error, isNull);
      expect(controller.items, [1, 2]);
      controller.dispose();
    },
  );
}
