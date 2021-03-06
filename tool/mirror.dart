/**
 * Note: there is a LOT of hard-coded paths here. Ideally, mirrors and markdown
 * would be available without linking into Dart SDK internals
 * DARTBUG: TBD!!!
 * TODO: file a dart bug on accessing these guys...
 */

import 'dart:async';
import 'dart:io';
import 'dart:uri';
import 'package:bot/bot.dart';
import '/usr/local/Cellar/dart-editor/22378/dart-sdk/lib/_internal/compiler/implementation/mirrors/mirrors.dart' as mirrors;
import '/usr/local/Cellar/dart-editor/22378/dart-sdk/lib/_internal/compiler/implementation/mirrors/dart2js_mirror.dart' as dart2js;
import '/usr/local/Cellar/dart-editor/22378/dart-sdk/lib/_internal/dartdoc/lib/markdown.dart' as md;
import 'package:html5lib/dom.dart' as dom;
import 'package:html5lib/parser.dart';
import 'package:html5lib/dom_parsing.dart';
import 'util.dart' as util;

const _libPath = r'/usr/local/Cellar/dart-editor/22378/dart-sdk/';
const _htmlToHack = r'web/index_source.html';

void main() {
  final htmlFile = new File(_htmlToHack);
  assert(htmlFile.existsSync());

  List<mirrors.ClassMirror> classes;

  _getTargetClasses()
  .then((List<mirrors.ClassMirror> value) {
    classes = value;

    return htmlFile.readAsString();
  })
  .then((String originalContent) {

    final parser = new HtmlParser(originalContent, generateSpans: true);
    final document = parser.parse();

    for(final componentClass in classes) {

      final classSimpleName = componentClass.simpleName;

      final mirrors.CommentInstanceMirror classComment = componentClass.metadata
          .firstWhere((m) => m is mirrors.CommentInstanceMirror && m.isDocComment,
          orElse: () => null);

      if(classComment == null) {
        print('- $classSimpleName - no comment');
      } else {
        print('+ ${componentClass.simpleName} - has doc comments');
        _writeClassComment(document, componentClass.simpleName, classComment.trimmedText);
      }
    }

    // Now document has been updated
    final updatedContent = document.outerHtml;
    if(updatedContent != originalContent) {
      // we should write!
      print("+ Updating $_htmlToHack");
      return htmlFile.writeAsString(updatedContent);
    } else {
      print('- No changes to $_htmlToHack');
    }
  });
}

Future<List<mirrors.ClassMirror>> _getTargetClasses() {
  final currentLibraryPath = Directory.current.path;
  final libPath = new Uri(_libPath);
  final packageRoot = new Uri(r'packages/');

  final componentPaths = util.getDartLibraryPaths().toList();

  return dart2js.analyze(componentPaths, libPath, packageRoot, null, null,
      ['--preserve-comments'])
      .then((mirrors.MirrorSystem mirrors) {

        final componentLibraries = mirrors.libraries.values.where((lm) {
          final uri = lm.location.sourceUri;
          return uri.scheme == 'file' && uri.path.startsWith(currentLibraryPath);
        }).toList();

        return componentLibraries.expand((lm) {
          return lm.classes.values;
        }).toList();
      });
}

void _writeClassComment(dom.Document doc, String className,
                        String markdownCommentContent) {

  final htmlContent = _getHtmlFromMarkdown(className, markdownCommentContent);
  assert(htmlContent != null);

  // find the rigth quote block...right?

  final bq = _getBlockQuoteElement(doc, className);

  if(bq != null) {
    bq.innerHtml = htmlContent;
    print(' * updated blockquote');
  }
}

dom.Element _getBlockQuoteElement(dom.Document doc, String className) {
  return doc.queryAll('blockquote')
      .firstWhere((e) => _isRightBlockQuote(e, className), orElse: () => null);
}

bool _isRightBlockQuote(dom.Element element, String className) {
  if(element.attributes['class'] != 'comments') {
    return false;
  }

  final parent = element.parent;
  if(parent == null) {
    return false;
  }

  if(parent.children.indexOf(element) != 1) {
    return false;
  }

  // this should be an h2
  final firstChild = parent.children.first;

  return firstChild.tagName == 'h2' && firstChild.innerHtml == className;
}

String _getHtmlFromMarkdown(String className, String markdown) {
  final md.Resolver resolver = (name) {
    if(name == className) {
      return new md.Element.text('strong', name);
    } else {
      final anchor = new md.Element.text('a', name);
      anchor.attributes['href'] = '#${name.toLowerCase()}';
      return anchor;
    }
  };

  final document = new md.Document(linkResolver: resolver);

  final lines = Util.splitLines(markdown).toList();

  document.parseRefLinks(lines);
  final blocks = document.parseLines(lines);

  return md.renderToHtml(blocks);
}
