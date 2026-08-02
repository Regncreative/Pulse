# PulseMCP.exe launcher

Thin native launcher that starts the private Node runtime shipped with Pulse:

```text
PulseMCP.exe
  → runtime\node.exe  mcp\main.js  [args...]
```

Built by `tools/scripts/package_pulsemcp.ps1` during beta packaging.
End users never need a system Node.js install.
