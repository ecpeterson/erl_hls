"""Validate shared endpoint metadata without importing a test entry point."""
from pathlib import Path
import re


IDENTIFIER = re.compile(r'[A-Za-z_][A-Za-z0-9_]*\Z')


def require(condition: bool, reason: str) -> None:
    """Reject malformed or mismatched evidence even when assertions are disabled."""
    if not condition:
        raise ValueError(reason)


def bundle_file(bundle: Path, name: object) -> Path:
    """Resolve one existing file confined to the selected compiled release."""
    require(isinstance(name, str) and bool(name), 'missing bundle file name')
    relative = Path(name)
    require(not relative.is_absolute() and '..' not in relative.parts,
            'nonrelative bundle file: ' + name)
    path = (bundle / relative).resolve(strict=True)
    require(path.is_relative_to(bundle) and path.is_file(), 'escaping bundle file: ' + name)
    return path


def pins(value: object) -> list[tuple[str, int]]:
    """Validate finite pin widths and names before generating mechanical HDL wiring."""
    require(isinstance(value, list) and 0 < len(value) <= 128, 'invalid pin inventory')
    result = []
    for item in value:
        require(isinstance(item, dict), 'invalid pin record')
        name, width = item.get('name'), item.get('width')
        require(isinstance(name, str) and IDENTIFIER.fullmatch(name) is not None,
                'invalid pin name')
        require(type(width) is int and 1 <= width <= 8192, 'invalid pin width: ' + name)
        result.append((name, width))
    require(len({name for name, _ in result}) == len(result), 'duplicate pin name')
    require(sum(width for _, width in result) <= 32768, 'oversize sampled interface')
    return result
