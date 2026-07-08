# MCP

This is archived design/reference material only.

The shipped vision-only app surface does not register MCP integrations, start MCP listeners, expose MCP OAuth, or provide settings to enable MCP. Current app runtime capabilities are limited to:

- `screen.snapshot`
- `screen.ocr`
- `screen.barcodes`
- `screen.ui_elements`

MCP code has been removed from `cerberusCore`; do not reintroduce it without a new product decision.
