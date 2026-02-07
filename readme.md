# Zig WebGL2 Voxels

Minimal Zig-to-WASM voxel renderer using greedy meshing and a small JavaScript WebGL2 wrapper.

## Requirements

- Zig (0.11+ recommended)
- Node.js (for the tiny dev server)

## Build

```bash
zig build -Dtarget=wasm32-freestanding
```

This outputs:
- `zig-out/bin/voxels.wasm`
- `zig-out/web/` (static files)

## Run

```bash
node zig-out/web/server.js
```

Then open `http://localhost:8080/web/`.

## Controls

- Click the canvas to lock the mouse
- WASD to move
- Space / Shift to move up/down
- Mouse to look
