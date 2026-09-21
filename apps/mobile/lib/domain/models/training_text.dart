import 'package:html/dom.dart';
import 'package:html/parser.dart' show parseFragment;

class TrainingText {
  static String plain(String html) {
    final output = StringBuffer();
    void visit(Node node) {
      if (node is Text) {
        output.write(node.text);
        return;
      }
      if (node is Element &&
          ['script', 'style', 'iframe', 'object'].contains(node.localName)) {
        return;
      }
      if (node is Element && node.localName == 'li') output.write('• ');
      for (final child in node.nodes) {
        visit(child);
      }
      if (node is Element &&
          [
            'p',
            'h2',
            'h3',
            'li',
            'br',
            'blockquote',
          ].contains(node.localName)) {
        output.write('\n');
      }
    }

    visit(parseFragment(html));
    return output.toString().trim();
  }
}
