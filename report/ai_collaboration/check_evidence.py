#!/usr/bin/env python3
"""检查协作证据 CSV 的路径与本地文件存在性；不会判断对话真假或实验 PASS。"""
import argparse
import csv
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--repo-root', default='.', help='Git 仓库根目录')
    ap.add_argument('--index', default='report/ai_collaboration/evidence_index.csv')
    args = ap.parse_args()
    root = Path(args.repo_root).resolve()
    idx = (root / args.index).resolve()
    if not idx.is_relative_to(root):
        raise SystemExit('[FAIL] index path escapes repository')
    if not idx.is_file():
        raise SystemExit('[FAIL] index missing: ' + str(idx))
    missing = []
    invalid = []
    count = 0
    with idx.open(encoding='utf-8-sig', newline='') as f:
        for row in csv.DictReader(f):
            count += 1
            rel = row.get('repo_relative_path', '')
            path = (root / rel).resolve()
            if not rel or not path.is_relative_to(root):
                invalid.append((row['case_id'], rel))
            elif not path.is_file():
                missing.append((row['case_id'], rel))
    print(f'[INFO] evidence entries={count}, missing_local={len(missing)}, invalid_paths={len(invalid)}')
    for cid, path in invalid:
        print(f'[FAIL] invalid path {cid}: {path}')
    for cid, path in missing:
        print(f'[MISSING] {cid}: {path}')
    if invalid:
        raise SystemExit(2)
    if missing:
        raise SystemExit(1)
    print('[PASS] all indexed repository files exist')
    print('[NOTE] This does NOT verify the AI dialogue contents or tests.')


if __name__ == '__main__':
    main()
