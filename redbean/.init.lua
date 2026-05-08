-- redbean/.init.lua — redbean's startup script for the Doomstick kit.
--
-- redbean is Justine Tunney's single-file APE webserver (Cosmopolitan Libc,
-- same family as llamafile). One binary, six OSes, AMD64 + ARM64. We use it
-- as a tiny local platform layer for tools that need a real HTTP server (as
-- opposed to file:// pages): DOOM static hosting + USB-resident DOOM saves
-- today, Piper TTS + EmbeddingGemma RAG in future drops.
--
-- This file lives next to redbean.com on the USB at <USB>/ai-kit/redbean/.
-- start-doom.{sh,bat,command} also stages a copy at the USB root so redbean
-- finds it on its CWD. Launched as:
--     sh redbean.com -p 8768 -D <USB-root> -L <USB-root>/ai-kit/redbean.log
--   -p 8768       redbean listens on this port
--   -D <root>     redbean's docroot — start-doom.sh passes the USB root so
--                 /doom/ resolves to <USB>/doom/index.html. Static files
--                 outside the registered routes below get served via Route().
--
-- v0.6 adds saves:
--   GET  /list                     → JSON list of all populated slots
--   POST /save?slot=N[&name=...]   → body = raw .dsg bytes, persists to SQLite
--   GET  /load?slot=N              → returns raw .dsg bytes
--
-- v0.7 adds TTS (this file's newest subject):
--   POST /tts                      → body = utf-8 text, response = audio/wav
--                                   Backed by Sherpa-ONNX + Supertonic int8
--                                   (native C++, no Python on host).
--
-- /rag still queues as a 501 stub for the next /do.

local sqlite3 = require("lsqlite3")  -- bundled with redbean fullbuild

local PORT          = 8768
local VERSION       = "redbean-3.0.0"
-- Path is relative to redbean's CWD — start-doom.sh does `cd "$ROOT"` before
-- launching redbean, so this lands at <USB-root>/ai-kit/redbean/saves.db.
local DB_PATH       = "ai-kit/redbean/saves.db"
local MAX_SLOT      = 5            -- DOOM exposes 6 save slots (0..5)
local MAX_SAVE_SIZE = 1024 * 1024  -- 1 MB — DOOM saves are ~10–50 KB

-- TTS — v0.7. Caps text body to keep generation latency bounded; Supertonic
-- runs at ~3-5× real-time on CPU, so 4 KB of text (~30s of speech) caps
-- one request at ~6-10s of compute. Longer requests are out of scope here.
local MAX_TTS_TEXT  = 4096

local TTS_DIR_BY_OS = {
   LINUX   = { subdir = "linux", exe = "sherpa-onnx-offline-tts"     },
   MAC     = { subdir = "mac",   exe = "sherpa-onnx-offline-tts"     },
   WINDOWS = { subdir = "win",   exe = "sherpa-onnx-offline-tts.exe" },
}

local SUPERTONIC_DIR = "ai-kit/sherpa-tts/models/supertonic"
-- Files inside the sherpa-onnx-supertonic-tts-int8-2026-03-06 archive.
-- Names are dictated by the archive contents — don't rename without
-- updating the build script too.
local SUPERTONIC_FILES = {
   { flag = "supertonic-text-encoder",       name = "text_encoder.int8.onnx"       },
   { flag = "supertonic-duration-predictor", name = "duration_predictor.int8.onnx" },
   { flag = "supertonic-vector-estimator",   name = "vector_estimator.int8.onnx"   },
   { flag = "supertonic-vocoder",            name = "vocoder.int8.onnx"            },
   { flag = "supertonic-tts-json",           name = "tts.json"                     },
   { flag = "supertonic-unicode-indexer",    name = "unicode_indexer.bin"          },
   { flag = "supertonic-voice-style",        name = "voice.bin"                    },
}

-- Per-request counter for temp WAV filenames. redbean handles requests in
-- a single Lua state per worker, sequentially — no concurrent collisions
-- within one worker. If forked workers ever appear, switch to pid+counter.
local tts_seq = 0

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------

local function json(status, tbl)
   if status then SetStatus(status) end
   SetHeader("Content-Type", "application/json")
   Write(EncodeJson(tbl))
end

local function json_err(status, msg)
   json(status, { error = msg })
end

-- Open (and lazily-init) the saves DB. Returns the handle or nil+errmsg.
-- We open per-request — DOOM saves are infrequent (player-driven) and the
-- per-call cost is microseconds. Keeps lifecycle dead simple.
local function db_open()
   local db, _, err = sqlite3.open(DB_PATH)
   if not db then return nil, "sqlite open failed: " .. tostring(err) end
   local rc = db:exec([[
      CREATE TABLE IF NOT EXISTS saves (
         slot       INTEGER PRIMARY KEY,
         name       TEXT NOT NULL DEFAULT '',
         data       BLOB NOT NULL,
         updated_at TEXT NOT NULL
      );
   ]])
   if rc ~= sqlite3.OK then
      db:close()
      return nil, "sqlite schema init failed: rc=" .. tostring(rc)
   end
   return db
end

local function parse_slot()
   local s = GetParam("slot")
   if not s then return nil, "missing slot param" end
   local n = tonumber(s)
   if not n or n ~= math.floor(n) or n < 0 or n > MAX_SLOT then
      return nil, "slot must be integer 0.." .. MAX_SLOT
   end
   return n
end

local function now_iso()
   return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

----------------------------------------------------------------------
-- handlers
----------------------------------------------------------------------

-- /health — liveness probe. start-doom.sh polls this to know redbean is up
-- before opening the browser. Future dashboard tiles can hit this too.
local function HealthHandler()
   json(nil, {
      status  = "ok",
      port    = PORT,
      version = VERSION,
      saves   = "live",
      tts     = "live",
      rag     = "deferred",
   })
end

-- GET /list — enumerate populated save slots (no body bytes).
-- Formats the slots array manually because Lua tables are ambiguous to
-- EncodeJson when empty: an empty Lua table serializes as `{}`, but the
-- client expects `[]`.
local function ListHandler()
   local db, err = db_open()
   if not db then return json_err(500, err) end

   local rows = {}
   for r in db:nrows([[
      SELECT slot, name, length(data) AS bytes, updated_at
      FROM saves ORDER BY slot
   ]]) do
      rows[#rows+1] = EncodeJson({
         slot       = r.slot,
         name       = r.name,
         bytes      = r.bytes,
         updated_at = r.updated_at,
      })
   end
   db:close()
   SetHeader("Content-Type", "application/json")
   Write('{"slots":[' .. table.concat(rows, ",") .. ']}')
end

-- POST /save?slot=N[&name=...] — body is the raw .dsg blob.
local function SaveHandler()
   if GetMethod() ~= "POST" then
      SetStatus(405) ; SetHeader("Allow", "POST") ; return
   end
   local slot, perr = parse_slot()
   if perr then return json_err(400, perr) end

   local body = GetBody()
   if not body or #body == 0 then return json_err(400, "empty body") end
   if #body > MAX_SAVE_SIZE then
      return json_err(413, "save exceeds " .. MAX_SAVE_SIZE .. " bytes")
   end

   local name = GetParam("name") or ""
   local db, derr = db_open()
   if not db then return json_err(500, derr) end

   local stmt = db:prepare([[
      INSERT INTO saves (slot, name, data, updated_at) VALUES (?, ?, ?, ?)
      ON CONFLICT(slot) DO UPDATE SET
         name=excluded.name, data=excluded.data, updated_at=excluded.updated_at
   ]])
   if not stmt then
      db:close()
      return json_err(500, "prepare failed")
   end
   stmt:bind_values(slot, name, body, now_iso())
   local rc = stmt:step()
   stmt:finalize()
   db:close()

   if rc ~= sqlite3.DONE then
      return json_err(500, "write failed: rc=" .. tostring(rc))
   end
   json(nil, { status = "ok", slot = slot, bytes = #body })
end

-- GET /load?slot=N — returns raw .dsg bytes.
local function LoadHandler()
   local slot, perr = parse_slot()
   if perr then return json_err(400, perr) end

   local db, derr = db_open()
   if not db then return json_err(500, derr) end

   local stmt = db:prepare("SELECT data FROM saves WHERE slot=?")
   if not stmt then
      db:close()
      return json_err(500, "prepare failed")
   end
   stmt:bind_values(slot)
   local rc = stmt:step()
   if rc == sqlite3.ROW then
      local data = stmt:get_value(0)
      stmt:finalize()
      db:close()
      SetHeader("Content-Type", "application/octet-stream")
      Write(data)
   else
      stmt:finalize()
      db:close()
      json_err(404, "no save in slot " .. slot)
   end
end

-- 501 Not Implemented — routes that exist as protocol promises but haven't
-- shipped their handler yet. Helpful to clients that probe.
local function NotImplemented(name, lands_in)
   SetStatus(501)
   SetHeader("Content-Type", "application/json")
   Write(EncodeJson({
      error = "not implemented",
      route = name,
      note  = "lands in " .. lands_in,
   }))
end

----------------------------------------------------------------------
-- /tts handler (v0.7) — Sherpa-ONNX + Supertonic int8
----------------------------------------------------------------------

-- Resolve the per-OS sherpa binary and verify all Supertonic assets exist.
-- Returns (sherpa_bin_path, model_paths_table) or (nil, err_msg).
-- model_paths_table maps each --supertonic-* flag to its on-disk path,
-- in argv order — caller can iterate to build the execve argv.
local function tts_resolve()
   local os_name = GetHostOs()
   local layout  = TTS_DIR_BY_OS[os_name]
   if not layout then
      return nil, "unsupported host OS for TTS: " .. tostring(os_name)
   end

   local sherpa_bin = "ai-kit/sherpa-tts/" .. layout.subdir .. "/" .. layout.exe
   if unix.access(sherpa_bin, unix.F_OK) == nil then
      return nil, "sherpa binary missing: " .. sherpa_bin
   end

   local resolved = {}
   for _, entry in ipairs(SUPERTONIC_FILES) do
      local p = SUPERTONIC_DIR .. "/" .. entry.name
      if unix.access(p, unix.F_OK) == nil then
         return nil, "supertonic asset missing: " .. p
      end
      resolved[#resolved+1] = { flag = entry.flag, path = p }
   end
   return sherpa_bin, resolved
end

-- POST /tts — body is utf-8 text, response is audio/wav.
local function TtsHandler()
   if GetMethod() ~= "POST" then
      SetStatus(405) ; SetHeader("Allow", "POST") ; return
   end

   local body = GetBody()
   if not body or #body == 0 then return json_err(400, "empty body") end
   if #body > MAX_TTS_TEXT then
      return json_err(413, "text exceeds " .. MAX_TTS_TEXT .. " bytes")
   end

   local sherpa_bin, model = tts_resolve()
   if not sherpa_bin then return json_err(503, model) end

   tts_seq = tts_seq + 1
   local out_wav = string.format("ai-kit/redbean/tts-out-%d.wav", tts_seq)

   -- Build argv. Trailing positional arg is the text to synthesize. Sherpa
   -- treats it as a single C string — no shell, no expansion, so user
   -- bodies are safe to pass verbatim. argv[1] is conventionally the
   -- program name.
   local argv = { sherpa_bin }
   for _, m in ipairs(model) do
      argv[#argv+1] = "--" .. m.flag .. "=" .. m.path
   end
   argv[#argv+1] = "--lang=en"
   argv[#argv+1] = "--output-filename=" .. out_wav
   argv[#argv+1] = body

   -- Build env for the child. Sherpa's Linux/macOS releases ship .so/.dylib
   -- files next to the binary; default loader paths don't include the
   -- exe's directory, so we set LD_LIBRARY_PATH (Linux) and
   -- DYLD_LIBRARY_PATH (macOS) explicitly. Windows .exe is statically
   -- linked, no env tweak needed there. We forward only the env vars
   -- sherpa might care about — keeps the surface tight, no risk of
   -- assuming `unix.environ()` is available in this redbean build.
   local sherpa_dir = sherpa_bin:match("^(.+)/[^/]+$") or "."
   local env = {
      "LD_LIBRARY_PATH="   .. sherpa_dir,
      "DYLD_LIBRARY_PATH=" .. sherpa_dir,
   }
   for _, k in ipairs({ "PATH", "HOME", "TMPDIR", "LANG", "LC_ALL" }) do
      local v = os.getenv(k)
      if v then env[#env+1] = k .. "=" .. v end
   end

   -- Fork + execve. Blocking on wait() is acceptable here — Supertonic on
   -- CPU is faster-than-realtime, so 4 KB of text completes in ~1-3s.
   -- Same pattern (sync subprocess) as future /rag ingestion will need.
   local pid, ferr = unix.fork()
   if not pid then return json_err(500, "fork failed: " .. tostring(ferr)) end
   if pid == 0 then
      unix.execve(sherpa_bin, argv, env)
      unix.exit(127)  -- only reached if execve itself fails
   end
   local _, status = unix.wait(pid)
   if status ~= 0 then
      return json_err(500, "tts subprocess failed: status=" .. tostring(status))
   end

   local f = io.open(out_wav, "rb")
   if not f then return json_err(500, "wav not produced at " .. out_wav) end
   local wav = f:read("*a")
   f:close()
   os.remove(out_wav)

   if not wav or #wav == 0 then return json_err(500, "empty wav") end

   SetHeader("Content-Type", "audio/wav")
   SetHeader("Content-Length", tostring(#wav))
   Write(wav)
end

----------------------------------------------------------------------
-- dispatch
----------------------------------------------------------------------

function OnHttpRequest()
   local path = GetPath()

   if     path == "/health" then HealthHandler()
   elseif path == "/save"   then SaveHandler()
   elseif path == "/load"   then LoadHandler()
   elseif path == "/list"   then ListHandler()
   elseif path == "/tts"    then TtsHandler()
   elseif path == "/rag"    then NotImplemented("/rag", "v0.7+ (EmbeddingGemma RAG layer)")
   else
      -- Default: serve static files from the docroot configured via -D.
      Route()
   end
end
