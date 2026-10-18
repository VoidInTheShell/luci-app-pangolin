#!/usr/bin/env python3
"""Resolve product release versions without changing upstream source pins."""
import argparse
import json
from pathlib import Path
import re


def resolve(base, ref, number, attempt):
    if not re.fullmatch(r'[1-9][0-9]*\.[0-9]+\.[0-9]+', base):
        raise ValueError('VERSION must contain a stable MAJOR.MINOR.PATCH')
    if ref.startswith('refs/tags/'):
        tag = ref.removeprefix('refs/tags/')
        if tag != 'v' + base:
            raise ValueError('Stable tag must exactly match v<VERSION>')
        return dict(tag=tag, version=base, revision='0', prerelease=False)
    if number < 1 or attempt < 1:
        raise ValueError('Run number and attempt must be positive')
    return dict(tag=f'v{base}-dev.{number}.{attempt}',
                version=f'{base}_pre{number}', revision=str(attempt), prerelease=True)


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--ref', required=True)
    p.add_argument('--run-number', type=int, required=True)
    p.add_argument('--run-attempt', type=int, required=True)
    p.add_argument('--output', type=Path)
    args = p.parse_args()
    result = resolve((Path(__file__).resolve().parents[1] / 'VERSION').read_text().strip(),
                     args.ref, args.run_number, args.run_attempt)
    if args.output:
        with args.output.open('a', encoding='utf-8') as f:
            for key, value in result.items():
                f.write(f'{key}={str(value).lower() if isinstance(value, bool) else value}\n')
    print(json.dumps(result))
