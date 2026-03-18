const express   = require("express");
const http      = require("http");
const WebSocket = require("ws");
const pty       = require("node-pty");
const path      = require("path");

const app    = express();
const server = http.createServer(app);
const wss    = new WebSocket.Server({ noServer: true });

const PORT = process.env.PORT || 3000;

// ── Static assets ─────────────────────────────────────────────────────────────
app.use(express.static(path.join(__dirname, "public")));

// ── MkDocs documentation (served at /docs/) ───────────────────────────────────
const docsDir = process.env.DOCS_DIR || path.join(__dirname, "docs");
app.use("/docs", express.static(docsDir));

// ── Spawn a bash shell ────────────────────────────────────────────────────────
function spawnShell() {
  return pty.spawn("bash", [], {
    name: "xterm-256color",
    cols: 120,
    rows: 40,
    cwd:  "/app/labs",
    env:  {
      ...process.env,
      TERM:     "xterm-256color",
      LANG:     "en_US.UTF-8",
      SHELL:    "/bin/bash",
      LABS:     "/app/labs",
      HOME:     "/root",
    },
  });
}

// ── Upgrade handler ───────────────────────────────────────────────────────────
server.on("upgrade", (request, socket, head) => {
  wss.handleUpgrade(request, socket, head, (ws) => {
    wss.emit("connection", ws, request);
  });
});

// ── WebSocket session handler ─────────────────────────────────────────────────
wss.on("connection", (ws) => {
  let shell;
  try {
    shell = spawnShell();
  } catch (e) {
    ws.send(JSON.stringify({ type: "output", data: `\r\n\x1b[31mFailed to start shell: ${e.message}\x1b[0m\r\n` }));
    ws.close();
    return;
  }

  shell.onData((data) => {
    try { ws.send(JSON.stringify({ type: "output", data })); } catch (_) {}
  });

  shell.onExit(({ exitCode }) => {
    try {
      ws.send(JSON.stringify({ type: "exit", exitCode }));
      ws.close();
    } catch (_) {}
  });

  ws.on("message", (msg) => {
    try {
      const message = JSON.parse(msg);
      switch (message.type) {
        case "input":  shell.write(message.data); break;
        case "resize":
          if (message.cols && message.rows) shell.resize(message.cols, message.rows);
          break;
      }
    } catch (_) {}
  });

  ws.on("close", () => { try { shell.kill(); } catch (_) {} });
});

// ── Start ─────────────────────────────────────────────────────────────────────
server.listen(PORT, "0.0.0.0", () => {
  console.log("");
  console.log("╔══════════════════════════════════════════════════════════╗");
  console.log("║   GitHub Actions Labs – Interactive Terminal Ready       ║");
  console.log("║                                                          ║");
  console.log(`║   Open: http://localhost:${PORT}                            ║`);
  console.log("╚══════════════════════════════════════════════════════════╝");
  console.log("");
});
