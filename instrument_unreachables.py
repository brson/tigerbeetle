#!/usr/bin/env python3
"""
Instrument all 'unreachable' statements in Zig std library with unique IDs.

This script:
1. Scans all .zig files in ../zig/lib/std
2. Finds every 'unreachable' statement
3. Replaces each with instrumented code that prints a unique ID
4. Creates a mapping file to track ID -> file:line
"""

import os
import re
import sys
from pathlib import Path
from typing import List, Tuple

# Pattern to match 'unreachable' as a statement (not in comments or strings)
# This is a simple pattern - it may need refinement
UNREACHABLE_PATTERN = re.compile(r'\bunreachable\b')

def find_zig_files(std_dir: Path) -> List[Path]:
    """Find all .zig files in the std directory."""
    return sorted(std_dir.rglob('*.zig'))

def is_in_string_or_identifier(line: str, pos: int) -> bool:
    """Check if position is inside a string literal or identifier."""
    # Check for @"..." identifier syntax
    if pos >= 2 and line[pos-2:pos] == '@"':
        return True

    # Count quotes before this position to see if we're in a string
    # This is a simple heuristic - not perfect but good enough
    before = line[:pos]
    # Count unescaped quotes
    quote_count = 0
    i = 0
    while i < len(before):
        if before[i] == '"' and (i == 0 or before[i-1] != '\\'):
            quote_count += 1
        i += 1

    # If odd number of quotes, we're inside a string
    return quote_count % 2 == 1

def process_file(file_path: Path, std_dir: Path, start_id: int) -> Tuple[str, List[Tuple[int, int, str]], int]:
    """
    Process a single file to find and instrument unreachables.

    Returns:
        - Modified file content
        - List of (id, line_number, context) tuples
        - Next available ID
    """
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    lines = content.split('\n')
    modified_lines = []
    unreachables = []
    current_id = start_id

    for line_num, line in enumerate(lines, 1):
        # Skip comments (simple check - not perfect but good enough)
        stripped = line.lstrip()
        if stripped.startswith('//'):
            modified_lines.append(line)
            continue

        # Check if line contains 'unreachable'
        matches = list(UNREACHABLE_PATTERN.finditer(line))
        if not matches:
            modified_lines.append(line)
            continue

        # Process each unreachable on this line
        new_line = line
        offset = 0
        for match in matches:
            # Skip if this unreachable is inside a string or identifier
            if is_in_string_or_identifier(line, match.start()):
                continue
            # Get some context (surrounding code)
            context_start = max(0, line_num - 2)
            context_end = min(len(lines), line_num + 1)
            context = ' | '.join(lines[context_start:context_end]).strip()
            if len(context) > 200:
                context = context[:200] + '...'

            # Record this unreachable
            rel_path = file_path.relative_to(std_dir)
            unreachables.append((current_id, line_num, str(rel_path), context))

            # Create instrumentation using @panic() which works in all contexts
            # @panic() has noreturn type like unreachable and works in expressions
            instrumentation = f'@panic("UNREACH_{current_id}")'

            # Replace this unreachable
            match_start = match.start() + offset
            match_end = match.end() + offset

            # Simple replacement - @panic() works in all contexts where unreachable works
            new_line = new_line[:match_start] + instrumentation + new_line[match_end:]
            offset += len(instrumentation) - (match_end - match_start)

            current_id += 1

        modified_lines.append(new_line)

    return '\n'.join(modified_lines), unreachables, current_id

def main():
    # Find the zig std directory
    script_dir = Path(__file__).parent
    zig_dir = script_dir / '../zig'
    std_dir = zig_dir / 'lib' / 'std'

    if not std_dir.exists():
        print(f"Error: Zig std directory not found at {std_dir}", file=sys.stderr)
        sys.exit(1)

    print(f"Scanning {std_dir}...")
    zig_files = find_zig_files(std_dir)
    print(f"Found {len(zig_files)} .zig files")

    # Process all files
    all_unreachables = []
    current_id = 0
    modified_files = []

    for file_path in zig_files:
        try:
            modified_content, unreachables, current_id = process_file(file_path, std_dir, current_id)
            if unreachables:
                modified_files.append((file_path, modified_content))
                all_unreachables.extend(unreachables)
                print(f"  {file_path.relative_to(std_dir)}: {len(unreachables)} unreachables")
        except Exception as e:
            print(f"Error processing {file_path}: {e}", file=sys.stderr)

    print(f"\nTotal unreachables found: {len(all_unreachables)}")

    # Ask for confirmation before modifying files
    print("\nThis will modify the Zig std library source files.")
    print("Make sure you have a clean git tree so you can revert if needed.")
    response = input("Continue? [y/N]: ")

    if response.lower() != 'y':
        print("Aborted.")
        sys.exit(0)

    # Write mapping file
    mapping_file = script_dir / 'unreachable_map.csv'
    with open(mapping_file, 'w', encoding='utf-8') as f:
        f.write('ID,File,Line,Context\n')
        for id, line_num, rel_path, context in all_unreachables:
            # Escape context for CSV
            context = context.replace('"', '""')
            f.write(f'{id},{rel_path},{line_num},"{context}"\n')

    print(f"\nWrote mapping to {mapping_file}")

    # Write modified files
    for file_path, modified_content in modified_files:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(modified_content)

    print(f"\nInstrumented {len(modified_files)} files with {len(all_unreachables)} unreachables")
    print("\nNext steps:")
    print("1. Build the instrumented Zig: cd ../zig && just zig-build")
    print("2. Rebuild tb_client: cd .. && ./zig/zig build clients:rust -Dtarget=x86_64-windows")
    print("3. Run the test: just test-rust-win-loop")
    print("4. Look for UNREACH_<id> in the output and check unreachable_map.csv")

if __name__ == '__main__':
    main()
