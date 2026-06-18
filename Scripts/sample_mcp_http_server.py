#!/usr/bin/env python3
import argparse
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PROTOCOL_VERSION = "2025-06-18"
SESSION_ID = "cerberus-sample-http-session"


def compact_json(value):
    return json.dumps(value, separators=(",", ":"), sort_keys=True)


def text_content(text):
    return [{"type": "text", "text": text}]


def rpc_result(message_id, payload):
    return {"jsonrpc": "2.0", "id": message_id, "result": payload}


def rpc_error(message_id, code, message):
    return {"jsonrpc": "2.0", "id": message_id, "error": {"code": code, "message": message}}


def tool_schema():
    return {
        "type": "object",
        "properties": {
            "message": {"type": "string", "description": "message to echo"}
        }
    }


def tools():
    return [
        {
            "name": "echo",
            "title": "Echo",
            "description": "Return the provided message.",
            "inputSchema": tool_schema()
        },
        {
            "name": "sample",
            "title": "Sampling demo",
            "description": "Return through a POST SSE response that asks the client for sampling review.",
            "inputSchema": tool_schema()
        },
        {
            "name": "elicit",
            "title": "Elicitation demo",
            "description": "Return through a POST SSE response that asks the client for elicitation review.",
            "inputSchema": tool_schema()
        }
    ]


def sampling_request(message_id, text):
    return {
        "jsonrpc": "2.0",
        "id": message_id,
        "method": "sampling/createMessage",
        "params": {
            "messages": [
                {"role": "user", "content": {"type": "text", "text": text}}
            ],
            "maxTokens": 64
        }
    }


def elicitation_request(message_id, message):
    return {
        "jsonrpc": "2.0",
        "id": message_id,
        "method": "elicitation/create",
        "params": {
            "message": message,
            "requestedSchema": {
                "type": "object",
                "properties": {
                    "name": {"type": "string", "title": "Name"},
                    "count": {"type": "integer", "title": "Count", "default": 1},
                    "enabled": {"type": "boolean", "title": "Enabled", "default": True},
                    "mode": {"type": "string", "title": "Mode", "enum": ["quick", "full"], "enumNames": ["Quick", "Full"]}
                },
                "required": ["name"]
            }
        }
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "CerberusSampleMCPHTTP/0.1"

    def log_message(self, format, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), format % args))

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Mcp-Session-Id", SESSION_ID)
        self.end_headers()
        self.write_sse(sampling_request(3001, "background sample"), event_id="sample-1")
        self.write_sse(elicitation_request(3002, "collect sample fields"), event_id="elicit-1")

    def do_POST(self):
        try:
            message = self.read_json()
        except Exception as exc:
            self.send_json(rpc_error(None, -32700, str(exc)), status=400)
            return

        message_id = message.get("id")
        method = message.get("method")
        params = message.get("params") or {}

        if message_id is not None and "method" not in message:
            self.send_accepted()
        elif method == "initialize":
            self.send_json(rpc_result(message_id, {
                "protocolVersion": PROTOCOL_VERSION,
                "serverInfo": {"name": "cerberus-sample-http", "version": "0.1.0"},
                "capabilities": {"tools": {}, "resources": {}, "prompts": {}}
            }))
        elif method == "notifications/initialized":
            self.send_accepted()
        elif method == "tools/list":
            self.send_json(rpc_result(message_id, {"tools": tools()}))
        elif method == "tools/call":
            self.handle_tool_call(message_id, params)
        elif method == "resources/list":
            self.send_json(rpc_result(message_id, {
                "resources": [
                    {
                        "uri": "sample://http-status",
                        "name": "http-status",
                        "title": "HTTP Status",
                        "description": "Sample Streamable HTTP server status.",
                        "mimeType": "text/plain"
                    }
                ]
            }))
        elif method == "resources/read":
            self.send_json(rpc_result(message_id, {
                "contents": [{"uri": params.get("uri", "sample://http-status"), "mimeType": "text/plain", "text": "http sample server ok"}]
            }))
        elif method == "prompts/list":
            self.send_json(rpc_result(message_id, {
                "prompts": [
                    {
                        "name": "summarize",
                        "title": "Summarize",
                        "description": "Summarize provided text.",
                        "arguments": [{"name": "topic", "description": "topic to summarize", "required": True}]
                    }
                ]
            }))
        elif method == "prompts/get":
            topic = (params.get("arguments") or {}).get("topic", "cerberus")
            self.send_json(rpc_result(message_id, {
                "description": "Sample summary prompt.",
                "messages": [{"role": "user", "content": {"type": "text", "text": f"Summarize {topic} in one sentence."}}]
            }))
        else:
            self.send_json(rpc_error(message_id, -32601, f"method not found: {method}"))

    def handle_tool_call(self, message_id, params):
        name = params.get("name", "")
        arguments = params.get("arguments") or {}
        message = arguments.get("message", "hello from http")

        if name == "echo":
            self.send_json(rpc_result(message_id, {"content": text_content(f"http echo: {message}")}))
        elif name == "sample":
            self.send_sse([
                sampling_request(2001, message),
                rpc_result(message_id, {"content": text_content("sampling request sent")})
            ])
        elif name == "elicit":
            self.send_sse([
                elicitation_request(2002, message),
                rpc_result(message_id, {"content": text_content("elicitation request sent")})
            ])
        else:
            self.send_json(rpc_error(message_id, -32602, f"unknown tool: {name}"))

    def read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        return json.loads(body.decode("utf-8") or "{}")

    def send_accepted(self):
        self.send_response(202)
        self.send_header("Mcp-Session-Id", SESSION_ID)
        self.end_headers()

    def send_json(self, payload, status=200):
        data = compact_json(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Mcp-Session-Id", SESSION_ID)
        self.end_headers()
        self.wfile.write(data)

    def send_sse(self, messages):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Mcp-Session-Id", SESSION_ID)
        self.end_headers()
        for index, message in enumerate(messages, 1):
            self.write_sse(message, event_id=f"post-{index}")

    def write_sse(self, message, event_id):
        payload = f"id: {event_id}\ndata: {compact_json(message)}\n\n".encode("utf-8")
        self.wfile.write(payload)
        self.wfile.flush()


def main():
    parser = argparse.ArgumentParser(description="Sample MCP Streamable HTTP server for cerberus.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8766)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"sample MCP HTTP server listening on http://{args.host}:{args.port}/mcp", file=sys.stderr)
    server.serve_forever()


if __name__ == "__main__":
    main()
