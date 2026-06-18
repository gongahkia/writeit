#!/usr/bin/env python3
import json
import sys

PROTOCOL_VERSION = "2025-06-18"
server_request_id = 1000


def send(message):
    sys.stdout.write(json.dumps(message, separators=(",", ":"), sort_keys=True) + "\n")
    sys.stdout.flush()


def result(message_id, payload):
    send({"jsonrpc": "2.0", "id": message_id, "result": payload})


def error(message_id, code, message):
    send({"jsonrpc": "2.0", "id": message_id, "error": {"code": code, "message": message}})


def text_content(text):
    return [{"type": "text", "text": text}]


def next_server_request_id():
    global server_request_id
    server_request_id += 1
    return server_request_id


def read_message():
    line = sys.stdin.readline()
    if not line:
        return None
    return json.loads(line)


def read_response(expected_id):
    while True:
        message = read_message()
        if message is None:
            raise RuntimeError("client closed stdin")
        if message.get("id") == expected_id:
            if "error" in message:
                raise RuntimeError(message["error"].get("message", "client request failed"))
            return message.get("result", {})


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
            "description": "Ask the MCP client to review a sampling request and response.",
            "inputSchema": tool_schema()
        },
        {
            "name": "elicit",
            "title": "Elicitation demo",
            "description": "Ask the MCP client to collect flat primitive fields.",
            "inputSchema": tool_schema()
        }
    ]


def handle_tool_call(params):
    name = params.get("name", "")
    arguments = params.get("arguments") or {}
    message = arguments.get("message", "hello from stdio")

    if name == "echo":
        return {"content": text_content(f"stdio echo: {message}")}

    if name == "sample":
        request_id = next_server_request_id()
        send({
            "jsonrpc": "2.0",
            "id": request_id,
            "method": "sampling/createMessage",
            "params": {
                "messages": [
                    {"role": "user", "content": {"type": "text", "text": message}}
                ],
                "maxTokens": 64
            }
        })
        sampling = read_response(request_id)
        sampled_text = (sampling.get("content") or {}).get("text", "")
        return {"content": text_content(f"sampling response: {sampled_text}")}

    if name == "elicit":
        request_id = next_server_request_id()
        send({
            "jsonrpc": "2.0",
            "id": request_id,
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
        })
        elicitation = read_response(request_id)
        return {"content": text_content("elicitation response: " + json.dumps(elicitation, sort_keys=True))}

    raise ValueError(f"unknown tool: {name}")


def handle(message):
    message_id = message.get("id")
    method = message.get("method")
    params = message.get("params") or {}

    if method == "initialize":
        result(message_id, {
            "protocolVersion": PROTOCOL_VERSION,
            "serverInfo": {"name": "cerberus-sample-stdio", "version": "0.1.0"},
            "capabilities": {"tools": {}, "resources": {}, "prompts": {}}
        })
    elif method == "notifications/initialized":
        return
    elif method == "tools/list":
        result(message_id, {"tools": tools()})
    elif method == "tools/call":
        result(message_id, handle_tool_call(params))
    elif method == "resources/list":
        result(message_id, {
            "resources": [
                {
                    "uri": "sample://status",
                    "name": "status",
                    "title": "Status",
                    "description": "Sample stdio server status.",
                    "mimeType": "text/plain"
                }
            ]
        })
    elif method == "resources/read":
        result(message_id, {"contents": [{"uri": params.get("uri", "sample://status"), "mimeType": "text/plain", "text": "stdio sample server ok"}]})
    elif method == "prompts/list":
        result(message_id, {
            "prompts": [
                {
                    "name": "summarize",
                    "title": "Summarize",
                    "description": "Summarize provided text.",
                    "arguments": [{"name": "topic", "description": "topic to summarize", "required": True}]
                }
            ]
        })
    elif method == "prompts/get":
        topic = (params.get("arguments") or {}).get("topic", "cerberus")
        result(message_id, {
            "description": "Sample summary prompt.",
            "messages": [{"role": "user", "content": {"type": "text", "text": f"Summarize {topic} in one sentence."}}]
        })
    else:
        error(message_id, -32601, f"method not found: {method}")


def main():
    while True:
        message = read_message()
        if message is None:
            return
        try:
            handle(message)
        except Exception as exc:
            error(message.get("id"), -32000, str(exc))


if __name__ == "__main__":
    main()
