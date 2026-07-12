#!/usr/bin/env python3
"""Unit tests for svg-scope's pure `scope()` function.

Run directly (`python3 tests/test_svg_scope.py`) or via `tests/run.sh`.
"""
import os
import unittest
from importlib.machinery import SourceFileLoader

# svg-scope has no .py extension; load it by path.
_HERE = os.path.dirname(os.path.abspath(__file__))
svgscope = SourceFileLoader('svgscope', os.path.join(_HERE, '..', 'svg-scope')).load_module()
scope = svgscope.scope


class TestScope(unittest.TestCase):
    def test_id_is_prefixed(self):
        out = scope('<svg id="gd1"></svg>', 'p-')
        self.assertIn('id="p-gd1"', out)
        self.assertNotIn('id="gd1"', out)

    def test_reference_rewired_to_match_id(self):
        svg = '<defs><marker id="gd1_a"/></defs><g marker-end="url(#gd1_a)"/>'
        out = scope(svg, 'p-')
        self.assertIn('id="p-gd1_a"', out)
        self.assertIn('url(#p-gd1_a)', out)

    def test_href_reference_rewired(self):
        out = scope('<g id="e0"/><use href="#e0"/><use xlink:href="#e0"/>', 'p-')
        self.assertIn('href="#p-e0"', out)
        self.assertIn('xlink:href="#p-e0"', out)

    def test_css_id_selector_rewired(self):
        out = scope('<svg id="gd1"><style>#gd1 .n{fill:red}</style></svg>', 'p-')
        self.assertIn('#p-gd1 .n', out)

    def test_hex_colors_preserved(self):
        # #0f0 (leading digit) and #ABC (letter, but not an id) must be untouched.
        svg = '<svg id="x"><style>.n{fill:#0f0;stroke:#ABC123;color:#fff}</style></svg>'
        out = scope(svg, 'p-')
        self.assertIn('fill:#0f0', out)
        self.assertIn('stroke:#ABC123', out)
        self.assertIn('color:#fff', out)

    def test_unknown_hash_reference_untouched(self):
        # A #ref whose name is not a declared id must be left alone.
        out = scope('<svg id="real"/><a href="#nowhere"/>', 'p-')
        self.assertIn('href="#nowhere"', out)

    def test_keyframes_and_animation_ref_both_prefixed(self):
        svg = ('<svg id="s"><style>@keyframes dash{to{x:0}} '
               '.e{animation:dash 1s linear}</style></svg>')
        out = scope(svg, 'p-')
        self.assertIn('@keyframes p-dash', out)
        self.assertIn('animation:p-dash 1s linear', out)

    def test_distinct_prefixes_produce_distinct_output(self):
        svg = '<svg id="gd1"><g id="edge0"/></svg>'
        a, b = scope(svg, 'm1-'), scope(svg, 'm2-')
        self.assertNotEqual(a, b)
        self.assertIn('id="m1-gd1"', a)
        self.assertIn('id="m2-gd1"', b)
        # No id from a collides with one from b.
        import re
        ids_a = set(re.findall(r'id="([^"]+)"', a))
        ids_b = set(re.findall(r'id="([^"]+)"', b))
        self.assertEqual(ids_a & ids_b, set())

    def test_no_ids_left_unchanged(self):
        svg = '<svg><rect fill="#fff"/></svg>'
        self.assertEqual(scope(svg, 'p-'), svg)

    def test_prefix_is_deterministic(self):
        svg = '<svg id="gd1"/>'
        self.assertEqual(scope(svg, 'p-'), scope(svg, 'p-'))


if __name__ == '__main__':
    unittest.main()
