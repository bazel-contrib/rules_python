import importlib.resources
import os
from xml.etree import ElementTree

import tests.sphinx_docs as sphinx_docs
from absl.testing import absltest


class SphinxDocsOutputTest(absltest.TestCase):
    def test_directory_artifact_relative_xref(self):
        page1_path = importlib.resources.files(sphinx_docs).joinpath(
            "docs/_build/html/generated_directory/dir_page1.html"
        )
        self.assertTrue(os.path.exists(str(page1_path)), f"Not found at {page1_path}")
        with open(str(page1_path)) as f:
            xml = f.read()
        doc_elem = ElementTree.fromstring(xml)
        actual = None
        for elem in doc_elem.iter():
            if "href" in elem.attrib:
                if "".join(elem.itertext()).strip() == "Dir Page 2":
                    actual = elem.attrib["href"]
                    break
        self.assertEqual("dir_page2.html", actual)

    def test_custom_sphinx_docs_library_info_provider(self):
        page_path = importlib.resources.files(sphinx_docs).joinpath(
            "docs/_build/html/custom/custom_page.html"
        )
        self.assertTrue(os.path.exists(str(page_path)), f"Not found at {page_path}")

    def test_custom_sphinx_docs_library_info_deps(self):
        # The dep's own prefix applies; the parent's prefix does not.
        page_path = importlib.resources.files(sphinx_docs).joinpath(
            "docs/_build/html/custom_dep/custom_dep_page.html"
        )
        self.assertTrue(os.path.exists(str(page_path)), f"Not found at {page_path}")


if __name__ == "__main__":
    absltest.main()
