import importlib.resources
from xml.etree import ElementTree

from absl.testing import absltest, parameterized

import tests.sphinx_stardoc as sphinx_stardoc


class SphinxOutputTest(parameterized.TestCase):
    def setUp(self):
        super().setUp()
        self._docs = {}
        self._xmls = {}

    def assert_xref(self, doc, *, text, href):
        # Find an element with an 'href' attribute whose string content (including
        # descendants like <span>) equals `text`. [@href] filters out ancestor
        # elements like <li> or <p> which also match [.='{text}'].
        match = self._doc_element(doc).find(f".//*[@href][.='{text}']")
        if not match:
            self.fail(f"No element found with {text=}")
        actual = match.attrib.get("href", "<UNSET>")
        self.assertEqual(
            href,
            actual,
            msg=f"Unexpected href for {text=}: "
            + ElementTree.tostring(match).decode("utf8"),
        )

    def _read_doc(self, doc):
        doc += ".html"
        if doc not in self._docs:
            self._docs[doc] = (
                importlib.resources.files(sphinx_stardoc)
                .joinpath("docs/_build/html")
                .joinpath(doc)
                .read_text()
            )
        return self._docs[doc]

    def _doc_element(self, doc):
        xml = self._read_doc(doc)
        if doc not in self._xmls:
            self._xmls[doc] = ElementTree.fromstring(xml)
        return self._xmls[doc]

    @parameterized.named_parameters(
        # fmt: off
        ("short_func", "myfunc", "function.html#myfunc"),
        ("short_func_arg", "myfunc.arg1", "function.html#myfunc.arg1"),
        ("short_rule", "my_rule", "rule.html#my_rule"),
        ("short_rule_attr", "my_rule.ra1", "rule.html#my_rule.ra1"),
        ("short_provider", "LangInfo", "provider.html#LangInfo"),
        ("short_tag_class", "myext.mytag", "module_extension.html#myext.mytag"),
        ("full_norepo_func", "//lang:function.bzl%myfunc", "function.html#myfunc"),
        (
            "full_norepo_func_arg",
            "//lang:function.bzl%myfunc.arg1",
            "function.html#myfunc.arg1",
        ),
        ("full_norepo_rule", "//lang:rule.bzl%my_rule", "rule.html#my_rule"),
        (
            "full_norepo_rule_attr",
            "//lang:rule.bzl%my_rule.ra1",
            "rule.html#my_rule.ra1",
        ),
        (
            "full_norepo_provider",
            "//lang:provider.bzl%LangInfo",
            "provider.html#LangInfo",
        ),
        ("full_norepo_aspect", "//lang:aspect.bzl%myaspect", "aspect.html#myaspect"),
        ("full_norepo_target", "//lang:relativetarget", "target.html#relativetarget"),
        (
            "full_repo_func",
            "@testrepo//lang:function.bzl%myfunc",
            "function.html#myfunc",
        ),
        (
            "full_repo_func_arg",
            "@testrepo//lang:function.bzl%myfunc.arg1",
            "function.html#myfunc.arg1",
        ),
        ("full_repo_rule", "@testrepo//lang:rule.bzl%my_rule", "rule.html#my_rule"),
        (
            "full_repo_rule_attr",
            "@testrepo//lang:rule.bzl%my_rule.ra1",
            "rule.html#my_rule.ra1",
        ),
        (
            "full_repo_provider",
            "@testrepo//lang:provider.bzl%LangInfo",
            "provider.html#LangInfo",
        ),
        (
            "full_repo_aspect",
            "@testrepo//lang:aspect.bzl%myaspect",
            "aspect.html#myaspect",
        ),
        (
            "full_repo_target",
            "@testrepo//lang:relativetarget",
            "target.html#relativetarget",
        ),
        (
            "tag_class_attr_using_attr_role",
            "myext.mytag.ta1",
            "module_extension.html#myext.mytag.ta1",
        ),
        (
            "tag_class_attr_using_attr_role_just_attr_name",
            "ta1",
            "module_extension.html#myext.mytag.ta1",
        ),
        ("file_without_repo", "//lang:rule.bzl", "rule.html"),
        ("file_with_repo", "@testrepo//lang:rule.bzl", "rule.html"),
        ("package_absolute", "//lang", "target.html"),
        ("package_basename", "lang", "target.html"),
        ("relative_doc_link", "Rule documentation", "rule.html"),
        # fmt: on
    )
    def test_xrefs(self, text, href):
        self.assert_xref("xrefs", text=text, href=href)

    def _find_flag_body(self, flag_id):
        doc = self._doc_element("target")
        for dl in doc.findall(".//dl[@class='bzl flag']"):
            if dl.find(f"dt[@id='{flag_id}']") is not None:
                return dl.find("dd")
        self.fail(f"No flag found with id={flag_id!r}")

    def _assert_flag_fields(self, flag_id, expected_fields, expected_paragraphs):
        dd = self._find_flag_body(flag_id)
        self.assertEqual(["dl", "p"], [child.tag for child in dd])
        field_list = dd.find("dl")
        self.assertIsNotNone(field_list)
        dts = ["".join(dt.itertext()) for dt in field_list.findall("dt")]
        dds = ["".join(d.itertext()).strip() for d in field_list.findall("dd")]
        self.assertEqual(expected_fields, list(zip(dts, dds, strict=True)))
        paragraphs = ["".join(p.itertext()).strip() for p in dd.findall("p")]
        self.assertEqual(expected_paragraphs, paragraphs)

    def test_flag_without_scope(self):
        dd = self._find_flag_body("myflag")
        self.assertIsNone(dd.find("dl"))

    def test_flag_with_scope(self):
        self._assert_flag_fields(
            "scopedflag",
            [("Scope:", "universal")],
            ["Some doc about scopedflag"],
        )

    def test_flag_with_scope_and_existing_field_list(self):
        self._assert_flag_fields(
            "scopedflag_with_fields",
            [("Scope:", "project"), ("Default:", "True")],
            ["Some doc about scopedflag_with_fields"],
        )


if __name__ == "__main__":
    absltest.main()
