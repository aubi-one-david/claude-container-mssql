#!/usr/bin/env python3
"""
Compact a Claude Code session file by truncating large tool results.

Usage:
    compact-session.py <session.jsonl> [--max-content-size 1000] [--keep-last N] [--dry-run]

This reduces file size while preserving conversation flow.
"""

import json
import argparse
import sys
from pathlib import Path


def truncate_content(obj, max_size=1000, path="", in_tool_result=False):
    """Recursively truncate large string content in nested structures.

    Only truncates content in tool_result blocks to preserve:
    - thinking blocks (have cryptographic signatures)
    - user messages
    - assistant text responses
    """
    if isinstance(obj, str):
        # Only truncate strings inside tool_result content
        if in_tool_result and len(obj) > max_size:
            half = max_size // 2
            return f"{obj[:half]}\n\n... [TRUNCATED {len(obj) - max_size} chars] ...\n\n{obj[-half:]}"
        return obj
    elif isinstance(obj, dict):
        # Check if this is a thinking block (has signature) - never truncate
        if obj.get('type') == 'thinking' and 'signature' in obj:
            return obj
        # Check if this is a tool_result block
        is_tool_result = obj.get('type') == 'tool_result'
        return {k: truncate_content(v, max_size, f"{path}.{k}", in_tool_result or is_tool_result)
                for k, v in obj.items()}
    elif isinstance(obj, list):
        return [truncate_content(item, max_size, f"{path}[]", in_tool_result) for item in obj]
    return obj


def compact_session(input_path, output_path, max_content_size=1000, keep_last=None, dry_run=False):
    """Compact a session file."""
    lines = []

    with open(input_path, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                lines.append(json.loads(line))

    original_count = len(lines)

    # Keep only last N messages if specified
    if keep_last and len(lines) > keep_last:
        # Always keep the first line (usually file-history-snapshot)
        first_line = lines[0] if lines[0].get('type') == 'file-history-snapshot' else None
        lines = lines[-keep_last:]
        if first_line:
            lines.insert(0, first_line)

    # Truncate large content
    compacted = []
    for line in lines:
        compacted.append(truncate_content(line, max_content_size))

    # Calculate sizes
    original_size = Path(input_path).stat().st_size
    compacted_json = '\n'.join(json.dumps(line, ensure_ascii=False) for line in compacted)
    new_size = len(compacted_json.encode('utf-8'))

    print(f"Original: {original_size / 1024 / 1024:.1f} MB ({original_count} messages)")
    print(f"Compacted: {new_size / 1024 / 1024:.1f} MB ({len(compacted)} messages)")
    print(f"Reduction: {(1 - new_size / original_size) * 100:.1f}%")

    if dry_run:
        print("\n[DRY RUN] No changes written")
        return

    # Backup original
    backup_path = Path(input_path).with_suffix('.jsonl.bak')
    if not backup_path.exists():
        Path(input_path).rename(backup_path)
        print(f"Backup: {backup_path}")

    # Write compacted
    with open(output_path, 'w') as f:
        f.write(compacted_json)
        f.write('\n')

    print(f"Written: {output_path}")


def main():
    parser = argparse.ArgumentParser(description='Compact a Claude Code session file')
    parser.add_argument('input', help='Input .jsonl session file')
    parser.add_argument('-o', '--output', help='Output file (default: overwrite input)')
    parser.add_argument('--max-content-size', type=int, default=1000,
                        help='Max size for content fields before truncation (default: 1000)')
    parser.add_argument('--keep-last', type=int, help='Keep only last N messages')
    parser.add_argument('--dry-run', action='store_true', help='Show what would happen without writing')

    args = parser.parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"Error: {input_path} not found", file=sys.stderr)
        sys.exit(1)

    output_path = args.output or args.input

    compact_session(input_path, output_path, args.max_content_size, args.keep_last, args.dry_run)


if __name__ == '__main__':
    main()
