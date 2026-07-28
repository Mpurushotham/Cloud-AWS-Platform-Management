"""Sample platform workload.

Deliberately small. Its job is to prove the platform end to end — request
arrives at API Gateway, is authorised by IAM, reaches Lambda, reads and writes
DynamoDB, and emits structured logs and metrics — not to be an interesting
application.
"""

import decimal
import json
import os
import time
import uuid

import boto3
from botocore.exceptions import ClientError

TABLE_NAME = os.environ["TABLE_NAME"]
ENVIRONMENT = os.environ.get("ENVIRONMENT", "lab")

# Created at module scope so the connection is reused across warm invocations.
_table = boto3.resource("dynamodb").Table(TABLE_NAME)


def _json_default(value):
    """Make DynamoDB's numeric type serialisable.

    boto3's resource API returns every number as decimal.Decimal, which
    json.dumps rejects. Items written in this process are plain ints, so the
    failure only appears on the read path -- which is exactly the kind of bug
    that survives a write-only smoke test.
    """
    if isinstance(value, decimal.Decimal):
        return int(value) if value % 1 == 0 else float(value)
    raise TypeError(f"cannot serialise {type(value).__name__}")


def _log(level, message, **fields):
    """Emit a single-line JSON record so CloudWatch Logs Insights can query it."""
    print(json.dumps({"level": level, "message": message, **fields}, default=_json_default))


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {
            "content-type": "application/json",
            # This API returns JSON to programmatic clients only, but the
            # headers cost nothing and keep the response safe if a browser
            # ever renders it.
            "x-content-type-options": "nosniff",
            "cache-control": "no-store",
        },
        "body": json.dumps(body, default=_json_default),
    }


def health(_event):
    return _response(200, {"status": "ok", "environment": ENVIRONMENT})


def create_item(event):
    try:
        payload = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "body must be valid JSON"})

    name = payload.get("name")
    if not isinstance(name, str) or not name.strip():
        return _response(400, {"error": "field 'name' is required"})

    item = {
        "pk": str(uuid.uuid4()),
        "name": name.strip()[:256],
        "created_at": int(time.time()),
        # TTL attribute — DynamoDB expires lab records automatically so the
        # table cannot grow past the free tier while nobody is watching.
        "expires_at": int(time.time()) + 7 * 24 * 3600,
    }

    _table.put_item(Item=item)
    _log("info", "item created", pk=item["pk"])
    return _response(201, item)


def list_items(_event):
    # Scan is acceptable only because this table is bounded by TTL and holds a
    # handful of demo records. Any real workload would query by partition key.
    result = _table.scan(Limit=25)
    return _response(200, {"items": result.get("Items", []), "count": result.get("Count", 0)})


ROUTES = {
    "GET /health": health,
    "POST /items": create_item,
    "GET /items": list_items,
}


def lambda_handler(event, context):
    route = event.get("routeKey", "")
    handler = ROUTES.get(route)

    if handler is None:
        return _response(404, {"error": "no such route", "route": route})

    try:
        return handler(event)
    except ClientError as exc:
        # Log the AWS error code for diagnosis, but never return it to the
        # caller — service errors can disclose resource names and ARNs.
        _log(
            "error",
            "aws call failed",
            code=exc.response["Error"]["Code"],
            route=route,
            request_id=context.aws_request_id,
        )
        return _response(502, {"error": "upstream service error"})
    except Exception:  # noqa: BLE001 — last resort, must not leak a stack trace
        _log("error", "unhandled exception", route=route, request_id=context.aws_request_id)
        return _response(500, {"error": "internal error"})
