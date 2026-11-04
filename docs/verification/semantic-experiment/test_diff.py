"""Offline tests for positioning only; these make no grammar-quality claim."""

import unittest

from experiment import token_edits, utf16_length


def apply(source, edits):
    value = source.encode("utf-16-le")
    for edit in reversed(edits):
        start = 2 * edit["start"]
        end = start + 2 * edit["length"]
        assert value[start:end].decode("utf-16-le") == edit["quote"]
        value = value[:start] + edit["suggestion"].encode("utf-16-le") + value[end:]
    return value.decode("utf-16-le")


class DiffTests(unittest.TestCase):
    def check_pair(self, source, corrected):
        edits = token_edits(source, corrected)
        self.assertEqual(apply(source, edits), corrected)
        for left, right in zip(edits, edits[1:]):
            self.assertLessEqual(left["start"] + left["length"], right["start"])
        return edits

    def test_replacements(self):
        self.check_pair("She go home with her freind.", "She goes home with her friend.")

    def test_punctuation_insertion(self):
        self.check_pair("We ate then left", "We ate, then left.")

    def test_word_insertion(self):
        self.check_pair("We went school.", "We went to school.")

    def test_double_quote_insertion(self):
        self.check_pair("She said hello.", 'She said "hello".')

    def test_deletion(self):
        self.check_pair("I I went home.", "I went home.")

    def test_repeated_word(self):
        edits = self.check_pair("They work. She work.", "They work. She works.")
        self.assertEqual(edits[0]["occurrence"], 2)

    def test_utf16(self):
        edits = self.check_pair("🙂 It are fine.", "🙂 It is fine.")
        self.assertEqual(edits[0]["start"], utf16_length("🙂 It "))

    def test_cross_line(self):
        edits = self.check_pair("She\ndon't like tea.", "She\ndoesn't like tea.")
        self.assertEqual(edits[0]["line"], 2)


if __name__ == "__main__":
    unittest.main()
