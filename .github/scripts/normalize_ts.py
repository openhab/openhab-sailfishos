#!/usr/bin/env python3
"""
Normalize Qt Linguist .ts files to the canonical Qt (lupdate/Linguist) format.

Qt writes:   <context>            at column 0
               <name>/<message>    indented 4 spaces
                 <source>/<translation>  indented 8 spaces

Crowdin re-serializes XML and shifts everything one level deeper (4/8/12),
which produces huge whitespace-only diffs. Running this on the Crowdin PR
branch converts its output back to Qt's format, so the PR shows only real
translation changes and `main` stays in the format lupdate/Linguist produce.

Run manually:  python3 normalize_ts.py translations/*.ts
In CI:         called by fix-crowdin-indentation.yml
"""

import sys
import re
import lxml.etree as etree


def normalize_ts(filepath):
    with open(filepath, 'rb') as f:
        raw = f.read()

    # lxml cannot round-trip DOCTYPE – strip and re-add it
    content = re.sub(rb'<!DOCTYPE[^>]*>\n', b'', raw)

    try:
        parser = etree.XMLParser(remove_blank_text=True)
        root = etree.fromstring(content, parser)
    except etree.XMLSyntaxError as e:
        print(f"  SKIP (invalid XML): {filepath}: {e}", file=sys.stderr)
        return False

    # etree.indent gives us clean 4-space-per-level indentation:
    #   <TS>            0
    #     <context>     4
    #       <name>      8
    #         <source>  12
    etree.indent(root, space='    ')

    result = etree.tostring(root, encoding='utf-8', xml_declaration=True).decode('utf-8')

    # normalize XML declaration quotes
    result = result.replace(
        "<?xml version='1.0' encoding='utf-8'?>",
        '<?xml version="1.0" encoding="utf-8"?>'
    )

    # Qt's quirk: the first level under <TS> is NOT indented (<context> sits at
    # column 0). Dedent every tag line by exactly one level (4 spaces) so we get
    # Qt's 0/4/8 layout instead of etree's 4/8/12. Only lines that start with
    # 4+ spaces followed by a '<' are touched, so element text is never harmed.
    lines = result.split('\n')
    dedented = []
    for line in lines:
        if line.startswith('    '):
            dedented.append(line[4:])
        else:
            dedented.append(line)
    result = '\n'.join(dedented)

    # Re-insert DOCTYPE TS after the XML declaration
    result = result.replace(
        '<?xml version="1.0" encoding="utf-8"?>\n',
        '<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE TS>\n'
    )

    # Qt writes empty content elements with an explicit closing tag
    # (<translation type="unfinished"></translation>), but lxml self-closes
    # them (<translation type="unfinished"/>). Expand the content elements so
    # untranslated strings don't produce spurious diffs. Meta elements such as
    # <location .../> keep their self-closing form (Qt writes them that way).
    result = re.sub(
        r'<(translation|source|comment|oldsource|oldcomment|translatorcomment)'
        r'((?:\s[^>]*)?)/>',
        r'<\1\2></\1>',
        result
    )

    # Exactly one trailing newline
    result = result.rstrip('\n') + '\n'

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(result)

    return True


if __name__ == '__main__':
    paths = sys.argv[1:]
    if not paths:
        print("Usage: normalize_ts.py file1.ts [file2.ts ...]")
        sys.exit(1)
    for p in paths:
        print(f"  Normalizing: {p}")
        normalize_ts(p)
    print(f"Done. {len(paths)}/{len(paths)} file(s) processed.")
