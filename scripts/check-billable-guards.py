#!/usr/bin/env python3
"""Fail if a billable resource in the lab profile is not gated behind a flag.

The lab is budgeted at $0/month. Billable components are not banned outright --
keeping them in the code is how the production shape stays reviewable -- but
each must be behind a `count` or `for_each` guard whose variable defaults to
false or an empty collection.

This is a static check on the configuration, so it needs no AWS credentials and
runs on pull requests from forks, where the deployed-resource audit cannot.

Usage:  check-billable-guards.py terraform/lab/03-network [...]
Exit:   0 clean, 1 an unguarded billable resource, 2 a guard defaults to on.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Resource types that always accrue charges while they exist.
BILLABLE = {
    "aws_nat_gateway": "~$32/month each",
    "aws_eip": "~$3.60/month each (charged even when attached)",
    "aws_eks_cluster": "~$73/month each",
    "aws_eks_node_group": "instance hours",
    "aws_db_instance": "instance hours",
    "aws_rds_cluster": "instance hours",
    "aws_elasticache_cluster": "instance hours",
    "aws_elasticache_replication_group": "instance hours",
    "aws_opensearch_domain": "instance hours",
    "aws_lb": "~$16/month each",
    "aws_alb": "~$16/month each",
    "aws_ec2_transit_gateway": "~$36/month plus per-attachment",
    "aws_wafv2_web_acl": "~$5/month plus per-rule and per-request",
    "aws_cloudfront_distribution": "per-request",
    "aws_config_configuration_recorder": "per configuration item",
    "aws_guardduty_detector": "per event after the 30-day trial",
    "aws_securityhub_account": "per check after the 30-day trial",
    "aws_instance": "instance hours",
    "aws_vpc_endpoint": "interface endpoints ~$7.30/month each; gateway endpoints are free",
}

RESOURCE_RE = re.compile(r'^\s*resource\s+"([a-z0-9_]+)"\s+"([A-Za-z0-9_-]+)"\s*\{')
GUARD_RE = re.compile(r'^\s*(count|for_each)\s*=\s*(.+)$')
VAR_REF_RE = re.compile(r"var\.([a-z0-9_]+)")
LOCAL_REF_RE = re.compile(r"local\.([a-z0-9_]+)")

# `count = var.enable_x ? var.az_count : 0` -- only the condition decides
# whether the resource exists at all. var.az_count is the size, not the switch.
TERNARY_RE = re.compile(r"^(?P<cond>.+?)\?(?P<rest>.+)$")


def guard_condition(expr: str) -> str:
    """Reduce a guard expression to the part that decides existence."""
    m = TERNARY_RE.match(expr)
    return m.group("cond").strip() if m else expr.strip()


def local_value(directory: Path, name: str) -> str | None:
    """Resolve a locals entry to its expression text."""
    for tf in sorted(directory.glob("*.tf")):
        text = tf.read_text()
        for block in re.findall(r"locals\s*\{(.*?)\n\}", text, re.S):
            m = re.search(
                r"^\s*" + re.escape(name) + r"\s*=\s*(.+?)(?=\n\s*[a-z0-9_]+\s*=|\Z)",
                block,
                re.S | re.M,
            )
            if m:
                return " ".join(m.group(1).split())
    return None


def block_body(lines: list[str], start: int) -> tuple[str, int]:
    """Return the text of the resource block beginning at `start`, brace-matched."""
    depth = 0
    out: list[str] = []
    for i in range(start, len(lines)):
        line = lines[i]
        # Ignore braces inside comments and strings well enough for HCL bodies.
        stripped = line.split("#", 1)[0]
        depth += stripped.count("{") - stripped.count("}")
        out.append(line)
        if depth <= 0 and i > start:
            return "\n".join(out), i
    return "\n".join(out), len(lines) - 1


def variable_default(directory: Path, name: str) -> str | None:
    """Find the default value of a variable declared anywhere in the directory."""
    pattern = re.compile(
        r'variable\s+"' + re.escape(name) + r'"\s*\{(.*?)\n\}', re.S
    )
    for tf in sorted(directory.glob("*.tf")):
        m = pattern.search(tf.read_text())
        if not m:
            continue
        d = re.search(r"^\s*default\s*=\s*(.+?)$", m.group(1), re.M)
        return d.group(1).strip() if d else None
    return None


def check(directory: Path) -> int:
    status = 0

    for tf in sorted(directory.glob("*.tf")):
        lines = tf.read_text().splitlines()
        i = 0
        while i < len(lines):
            m = RESOURCE_RE.match(lines[i])
            if not m:
                i += 1
                continue

            rtype, rname = m.group(1), m.group(2)
            body, end = block_body(lines, i)
            i = end + 1

            if rtype not in BILLABLE:
                continue

            # Gateway VPC endpoints are free; only interface endpoints bill.
            if rtype == "aws_vpc_endpoint" and 'vpc_endpoint_type   = "Gateway"' in body.replace("=", "   =", 1):
                continue
            if rtype == "aws_vpc_endpoint" and re.search(
                r'vpc_endpoint_type\s*=\s*"Gateway"', body
            ):
                continue

            guard = None
            for line in body.splitlines():
                g = GUARD_RE.match(line)
                if g:
                    guard = g.group(2).strip()
                    break

            location = f"{tf}:{lines.index(m.group(0)) + 1 if m.group(0) in lines else '?'}"

            if guard is None:
                print(
                    f"::error file={tf}::Billable resource "
                    f'{rtype}.{rname} ({BILLABLE[rtype]}) has no count or for_each guard'
                )
                status = 1
                continue

            # Only the deciding part of the expression matters, and it may
            # reach the variable through a local.
            condition = guard_condition(guard)
            for local_name in LOCAL_REF_RE.findall(condition):
                resolved = local_value(directory, local_name)
                if resolved:
                    condition += " " + guard_condition(resolved)

            refs = VAR_REF_RE.findall(condition)
            if not refs:
                print(
                    f"::error file={tf}::{rtype}.{rname} is guarded by "
                    f'"{guard}", which resolves to no variable, so it cannot be switched off'
                )
                status = 1
                continue

            for var in refs:
                default = variable_default(directory, var)
                if default is None:
                    print(
                        f"::error file={tf}::{rtype}.{rname} is guarded by "
                        f"var.{var}, which has no default -- it must default to off"
                    )
                    status = max(status, 2)
                elif default not in ("false", "[]", "{}", "0", "null"):
                    print(
                        f"::error file={tf}::{rtype}.{rname} is guarded by "
                        f"var.{var}, but that defaults to {default} -- the lab would be billed"
                    )
                    status = max(status, 2)
                else:
                    print(
                        f"  ok  {rtype}.{rname} gated by var.{var} = {default} "
                        f"({BILLABLE[rtype]})"
                    )

    return status


def main() -> int:
    targets = [Path(a) for a in sys.argv[1:]] or [Path("terraform/lab")]
    status = 0

    for target in targets:
        directories = (
            [target] if list(target.glob("*.tf")) else sorted(p for p in target.iterdir() if p.is_dir())
        )
        for d in directories:
            if not list(d.glob("*.tf")):
                continue
            print(f"\n== {d}")
            status = max(status, check(d))

    print()
    if status == 0:
        print("PASSED - every billable resource is gated off by default.")
    else:
        print("FAILED - see the errors above.")
    return status


if __name__ == "__main__":
    sys.exit(main())
