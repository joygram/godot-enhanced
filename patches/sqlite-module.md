# SQLite engine module (0.3.2) — design

- Goal: SQLite on web without dlink side module (iOS Safari stalled loading `side.wasm`)
- Module: `modules/sqlite` = [godot-sqlite](https://github.com/2shady4u/godot-sqlite) sources linked into the engine
- API: same `SQLite` class as the GDExtension → game code unchanged
- Default off (`is_enabled() = False`) → editors / desktop keep the GDExtension (same class name would clash)
- On: `module_sqlite_enabled=yes`, used only for web static templates (threads + nothreads)
- dlink templates: unchanged, GDExtension as before

## Project side

- Export preset `variant/extensions_support=false` → `index.wasm` only, no `side.wasm` / `libgdsqlite`
- Remove `.gdextension` from the web export (class comes from the engine)

## Needs 0.3.3

- 0.3.2 static templates: `Module.FS` / `Module.GL` not exported → custom loaders crash
- 0.3.3: `FS`, `GL` in `EXPORTED_RUNTIME_METHODS` for static builds
