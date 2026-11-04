#!/usr/bin/env python3
"""Reuse a recorded candidate; do not regenerate a valid expensive first pass."""

import argparse
import json
from pathlib import Path

from experiment import HERE, evaluate_semantic8, explain_edits, token_edits


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("filename")
    parser.add_argument("--think", action="store_true")
    args = parser.parse_args()
    path = (HERE / args.filename).resolve()
    if path.parent != HERE:
        raise ValueError("Only recorded files in this experiment directory are allowed")
    result = json.loads(path.read_text())
    # Recompute only the deterministic positioning if its implementation changed.
    edits = token_edits(result["original"], result["corrected_candidate"])
    classified, evidence = explain_edits(result["original"], edits, None if args.think else False)
    result["token_edits"] = edits
    result["classified_edits"] = classified
    result["explanation_evidence"] = evidence
    if result["name"].endswith("semantic8"):
        result["evaluation"] = evaluate_semantic8(classified)
    output = HERE / (path.stem + ("-classified-think.json" if args.think else "-classified.json"))
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(output), "seconds": evidence["seconds"] if evidence else 0, "edits": classified, "evaluation": result.get("evaluation")}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
