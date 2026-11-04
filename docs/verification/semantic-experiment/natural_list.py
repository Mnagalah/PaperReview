#!/usr/bin/env python3
"""Bounded direct, unstructured semantic check; no example or answer key."""

import json

from experiment import HERE, ROOT, request


def main():
    original = json.loads((ROOT / "docs/verification/semantic-8case-result.json").read_text())["input"]
    prompt = "你是英语老师。逐句检查以下英语文本的语法、用词、拼写、标点和大小写。逐项列出所有明确错误、建议和简短中文理由。不要润色，正确的句子不要修改。"
    evidence = request([
        {"role": "system", "content": prompt},
        {"role": "user", "content": original},
    ])
    result = {"original": original, "evidence": evidence}
    path = HERE / "natural-list-semantic8.json"
    path.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"output": str(path), "seconds": evidence["seconds"], "content": evidence["content"]}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
