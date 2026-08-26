#!/usr/bin/env python3
"""
Normalize Qt Linguist .ts files to Crowdin's indentation format.
Crowdin exports: context=4sp, name/message=8sp, source/translation=12sp

Run manually:  python3 normalize_ts.py translations/*.ts
In CI:         called automatically by fix-crowdin-indentation.yml
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

    # 4-space indent matches Crowdin's export format:
    #   <context>            (4 sp)
    #     <name>             (8 sp)
    #     <message>          (8 sp)
    #       <source>         (12 sp)
    #       <translation>    (12 sp)
    etree.indent(root, space='    ')

    result = etree.tostring(root, encoding='utf-8', xml_declaration=True).decode('utf-8')

    # lxml uses single quotes in the declaration – normalize to double quotes
    result = result.replace(
        "<?xml version='1.0' encoding='utf-8'?>",
        '<?xml version="1.0" encoding="utf-8"?>'
    )

    # Re-insert DOCTYPE TS
    result = result.replace(
        '<?xml version="1.0" encoding="utf-8"?>\n',
        '<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE TS>\n'
    )

    # Ensure exactly one trailing newline
    result = result.rstrip('\n') + '\n'

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(result)

    return True


if __name__ == '__main__':
    paths = sys.argv[1:]
    if not paths:
        print("Usage: normalize_ts.py file1.ts [file2.ts ...]")
        sys.exit(1)
    changed = 0
    for p in paths:
        print(f"  Normalizing: {p}")
        if normalize_ts(p):
            changed += 1
    print(f"Done. {changed}/{len(paths)} file(s) processed.")
