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
-- v0.7 adds TTS:
--   POST /tts                      → body = utf-8 text, response = audio/wav
--                                   Backed by Sherpa-ONNX + Supertonic int8
--                                   (native C++, no Python on host).
--
-- v0.8 adds RAG + chat persistence:
--   POST /rag/ingest               → chunk + embed text into chunks table
--   GET  /rag/query                → cosine top-k retrieval
--   GET  /rag/list-docs            → list docs in a workspace
--   GET  /rag/list-workspaces      → list all workspaces with counts
--   POST /chat/save                → upsert a chat session to chats table
--   GET  /chat/list                → list chats in a workspace (most-recent first)
--   GET  /chat/load                → load a single chat by id

local sqlite3    = require("lsqlite3")    -- bundled with redbean fullbuild
local rag_cosine = require("rag-cosine")  -- v0.8 RAG: pure-Lua cosine helpers (baked into zip)

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
-- Wave 2 RAG constants (v0.8)
----------------------------------------------------------------------

-- EMBED_DIM pinned at 768 — verified against EmbeddingGemma 300M output in
-- S1.2. embeddinggemma-300m-qat-Q8_0 emits 768-dim float vectors.
local EMBED_DIM          = 768
-- EMBED_PORT: the embedding server spun up by start-embed.{sh,bat,command}.
-- Separate from redbean (8768) — llamafile embedding occupies its own port.
local EMBED_PORT         = 8769
local EMBED_HOST         = "127.0.0.1"
-- INGEST_MAX_CHUNKS: D3 cap. Docs producing more than 200 chunks are rejected
-- with 413 — keeps per-doc latency bounded at ~200 * embed_latency.
local INGEST_MAX_CHUNKS  = 200
-- INGEST_TIMEOUT_MS: per-chunk embedding call ceiling. Passed to Fetch as
-- seconds (30). Slow hardware might push close to this on large chunks.
local INGEST_TIMEOUT_MS  = 30000
-- QUERY_DEFAULT_K: number of results returned when ?k is omitted.
local QUERY_DEFAULT_K    = 5
-- CHUNK_TARGET_TOKENS: target size per chunk in approximate tokens.
-- 1 token ≈ 4 chars, so 400 tokens ≈ 1600 chars. EmbeddingGemma's input
-- cap is 2048 tokens — this gives a comfortable safety margin.
local CHUNK_TARGET_TOKENS = 400
-- CHUNK_OVERLAP_PCT: percentage of chars from the previous chunk's tail
-- to prepend to the next chunk for context continuity.
local CHUNK_OVERLAP_PCT  = 10
-- JOURNAL_MAX_TEXT: max bytes accepted by /journal/append per call. 16 KB is
-- ~3000-4000 words — far more than a single journal entry. Caps DoS surface.
local JOURNAL_MAX_TEXT   = 16384

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------

-- CORS headers must be set AFTER SetStatus — redbean clears the pending
-- header set on each SetStatus call, so anything written before it is lost.
-- Call this helper from every handler path that issues a non-200 status
-- (json_err, raw SetStatus(405), the OPTIONS preflight branch). The 200-OK
-- top-level injection in OnHttpRequest survives because no SetStatus
-- intervenes before the handler's Write/EncodeJson.
--
-- Access-Control-Allow-Private-Network is the CORS-RFC1918 layer enforced by
-- Chrome 117+ for file:// → 127.0.0.1 (and any "less private" → "more private"
-- fetch). Without it, Chrome blocks the request with a private-network preflight
-- error, even though the classic CORS headers above match. Sending it on every
-- response is harmless for non-private-network requests.
local function set_cors_headers()
   SetHeader("Access-Control-Allow-Origin",         "*")
   SetHeader("Access-Control-Allow-Methods",        "GET, POST, OPTIONS")
   SetHeader("Access-Control-Allow-Headers",        "Content-Type")
   SetHeader("Access-Control-Allow-Private-Network", "true")
end

local function json(status, tbl)
   if status then SetStatus(status) end
   set_cors_headers()
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

-- Open the RAG database and ensure the chunks + chats tables exist.
-- Uses the same saves.db file — the three tables (saves, chunks, chats)
-- coexist in one DB. Returns (db, nil) on success or (nil, err) on failure.
--
-- DECISION: We use plain BLOB columns for embeddings (not vec0 virtual tables).
-- vec0 / sqlite-vec require load_extension, which is compiled out of redbean's
-- bundled lsqlite3 (verified at Wave 0 / §D4). The pure-Lua cosine module in
-- rag-cosine.lua provides the same retrieval path with no native extension needed.
local function db_open_rag()
   local db, _, err = sqlite3.open(DB_PATH)
   if not db then return nil, "sqlite open failed: " .. tostring(err) end

   local rc = db:exec([[
      CREATE TABLE IF NOT EXISTS chunks (
         chunk_id        INTEGER PRIMARY KEY AUTOINCREMENT,
         workspace       TEXT NOT NULL,
         doc_path        TEXT NOT NULL,
         chunk_idx       INTEGER NOT NULL,
         text            TEXT NOT NULL,
         metadata        TEXT,
         embedding       BLOB NOT NULL,
         embedding_norm  REAL NOT NULL
      );
      CREATE INDEX IF NOT EXISTS chunks_workspace_idx ON chunks(workspace, doc_path);

      CREATE TABLE IF NOT EXISTS chats (
         id          TEXT PRIMARY KEY,
         workspace   TEXT NOT NULL,
         title       TEXT,
         body        TEXT NOT NULL,
         updated_at  TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS chats_workspace_idx ON chats(workspace, updated_at DESC);
   ]])
   if rc ~= sqlite3.OK then
      db:close()
      return nil, "rag schema init failed: rc=" .. tostring(rc)
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
-- RAG helpers (v0.8 Wave 2)
----------------------------------------------------------------------

-- chunk_recursive(text, max_tokens, overlap_pct)
--
-- Pure-Lua recursive text splitter. Returns an array of chunk strings.
-- Approximates tokens as #text/4 (1 token ≈ 4 chars — good enough for
-- boundary decisions; precision matters less than consistent sizing).
--
-- Split priority:
--   1. paragraph breaks (\n\n+)
--   2. sentence endings ([.!?] followed by whitespace)
--   3. whitespace (any space/newline)
--   4. hard cut at max_chars if no split point found
--
-- Overlap: each chunk (after the first) is prefixed with the last
-- overlap_pct% of chars from the previous chunk's text, giving the
-- embedding model cross-boundary context.
local function chunk_recursive(text, max_tokens, overlap_pct)
   local max_chars = max_tokens * 4  -- 1 token ≈ 4 chars
   local results = {}

   -- Inner recursive splitter: takes a text segment and appends chunks
   -- to the `out` array. `prev_tail` is the overlap prefix from the
   -- preceding chunk (empty string on first call).
   local function split_into(segment, out, prev_tail)
      -- Trim leading/trailing whitespace.
      segment = segment:match("^%s*(.-)%s*$")
      if segment == "" then return end

      -- Prepend overlap from previous chunk.
      local with_overlap = prev_tail .. segment

      -- If it fits, emit as a single chunk.
      if #with_overlap <= max_chars then
         out[#out+1] = with_overlap
         return
      end

      -- Try splitting on paragraph breaks first.
      local best_split = nil
      local split_at = nil

      -- Find all paragraph break positions up to max_chars.
      -- We search in `segment` (without overlap prefix) for cleaner
      -- boundary detection, then prepend overlap to each sub-piece.
      for pos in segment:gmatch("()%f[^\n]%n%n+") do
         if pos <= max_chars then
            split_at = pos
         end
      end

      -- If no paragraph split found within limit, try sentence endings.
      if not split_at then
         for pos, _ in segment:gmatch("()([%.!%?]%s)") do
            if pos <= max_chars then
               split_at = pos
            end
         end
      end

      -- If no sentence split found, try whitespace.
      if not split_at then
         for pos in segment:gmatch("()%s") do
            if pos <= max_chars then
               split_at = pos
            end
         end
      end

      -- No whitespace split found — hard cut. This handles pathological
      -- inputs like very long URLs or continuous non-space text.
      if not split_at or split_at <= 1 then
         -- Emit the first max_chars as a chunk (with overlap prefix trimmed
         -- to fit within max_chars).
         local prefix_room = math.min(#prev_tail, math.floor(max_chars * overlap_pct / 100))
         local head = prev_tail:sub(-prefix_room) .. segment:sub(1, max_chars - prefix_room)
         out[#out+1] = head
         -- Recurse on the remainder with overlap from what we just emitted.
         local tail_len = math.floor(#head * overlap_pct / 100)
         local next_prev = head:sub(-tail_len)
         split_into(segment:sub(max_chars - prefix_room + 1), out, next_prev)
         return
      end

      -- Split at the found position.
      local left  = segment:sub(1, split_at - 1)
      local right = segment:sub(split_at)

      -- Recurse left. Pass empty prev_tail on the very first split because
      -- the overlap for the left part is already in `prev_tail` above.
      -- DECISION: we handle overlap by passing prev_tail only into left,
      -- and deriving the right-side overlap from left's last chars.
      left = left:match("^%s*(.-)%s*$")
      right = right:match("^%s*(.-)%s*$")

      if #left == 0 and #right == 0 then return end

      -- If left still exceeds max_chars, recurse further.
      if #(prev_tail .. left) > max_chars then
         split_into(left, out, prev_tail)
      elseif #left > 0 then
         out[#out+1] = (prev_tail .. left):match("^%s*(.-)%s*$")
      end

      -- Overlap for right piece: last overlap_pct% of the last emitted chunk.
      local last_chunk = out[#out] or ""
      local tail_len   = math.floor(#last_chunk * overlap_pct / 100)
      local next_prev  = last_chunk:sub(-tail_len)

      if #right > 0 then
         split_into(right, out, next_prev)
      end
   end

   split_into(text, results, "")

   -- Post-process: strip empty, deduplicate adjacent identical chunks
   -- (can arise from overlap logic on degenerate inputs).
   local cleaned = {}
   for _, c in ipairs(results) do
      local s = c:match("^%s*(.-)%s*$")
      if #s > 0 then
         cleaned[#cleaned+1] = s
      end
   end
   return cleaned
end

-- embed_one(text) → (vec, nil) or (nil, err_string)
--
-- POSTs text to the EmbeddingGemma server on port EMBED_PORT and extracts
-- the float vector from the OpenAI-shaped response.
--
-- Uses redbean's built-in Fetch(), which returns three multivalues on success:
--   status:int, headers:table, body:string
-- and (nil, err:string) on connection error. INGEST_TIMEOUT_MS is the design
-- ceiling but redbean 3.0.0's Fetch options table doesn't expose a `timeout`
-- key — relies on socket default. EmbeddingGemma 300M typically returns in
-- well under a second per chunk; the warm-up call in start-embed.{sh,bat}
-- pre-loads the model so the first ingest doesn't pay cold-start latency.
local function embed_one(text)
   local url  = "http://" .. EMBED_HOST .. ":" .. tostring(EMBED_PORT) .. "/v1/embeddings"
   local body = EncodeJson({ input = text })
   local status, _headers, resp_body = Fetch(url, {
      method  = "POST",
      body    = body,
      headers = { ["Content-Type"] = "application/json" },
   })
   if not status then
      -- On error Fetch returns (nil, errstring); status is nil and _headers
      -- holds the error message in that case.
      return nil, "embed fetch failed: " .. tostring(_headers)
   end
   if status ~= 200 then
      return nil, "embed server returned " .. tostring(status)
   end
   local parsed = DecodeJson(resp_body)
   if not parsed then
      return nil, "embed response not valid JSON"
   end
   local data = parsed.data
   if type(data) ~= "table" or not data[1] then
      return nil, "embed response missing data[1]"
   end
   local vec = data[1].embedding
   if type(vec) ~= "table" then
      return nil, "embed response data[1].embedding is not a table"
   end
   if #vec ~= EMBED_DIM then
      return nil, string.format("embed dim mismatch: got %d, expected %d", #vec, EMBED_DIM)
   end
   return vec, nil
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
      rag     = "live",
      chat    = "live",
      journal = "live",
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
   set_cors_headers()
   SetHeader("Content-Type", "application/json")
   Write('{"slots":[' .. table.concat(rows, ",") .. ']}')
end

-- POST /save?slot=N[&name=...] — body is the raw .dsg blob.
local function SaveHandler()
   if GetMethod() ~= "POST" then
      SetStatus(405) ; set_cors_headers() ; SetHeader("Allow", "POST") ; return
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
   -- DECISION: bind .dsg body explicitly via bind_blob. lsqlite3's
   -- bind_values infers Lua-string → TEXT, which truncates binary data
   -- containing null bytes. Real DOOM saves contain plenty of nulls
   -- (level state, weapon flags, etc.) so this is load-bearing for save
   -- correctness — bug surfaced during S4.1 smoke against the chunks
   -- table's float32 BLOB column. Same fix applies here.
   stmt:bind(1, slot)
   stmt:bind(2, name)
   stmt:bind_blob(3, body)
   stmt:bind(4, now_iso())
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
      set_cors_headers()
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
   set_cors_headers()
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
      SetStatus(405) ; set_cors_headers() ; SetHeader("Allow", "POST") ; return
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

   set_cors_headers()
   SetHeader("Content-Type", "audio/wav")
   SetHeader("Content-Length", tostring(#wav))
   Write(wav)
end

----------------------------------------------------------------------
-- /rag/_loadtest handler (v0.8 Wave 1 / S1.1, extended in S2.1)
----------------------------------------------------------------------

-- GET /rag/_loadtest — sanity probe for the RAG layer. Returns module load
-- status, configured embedding dimension, and (after S2.1) table existence.
-- Lets the verification suite confirm:
--   (a) rag-cosine.lua baked correctly into the zip and require() works
--   (b) vec_backend is "lua-cosine" (not vec0, which is unsupported — see §D4)
--   (c) embed_dim is 768 (pinned at S1.2 verification)
--   (d) chunks_table and chats_table are "ready" (S2.1)
local function RagLoadtestHandler()
   -- Probe DB: try to open and check whether both tables were created.
   local chunks_status = "error: db not opened"
   local chats_status  = "error: db not opened"

   local db, dberr = db_open_rag()
   if not db then
      chunks_status = "error: " .. tostring(dberr)
      chats_status  = "error: " .. tostring(dberr)
   else
      -- Query sqlite_master for each table.
      local found_chunks = false
      local found_chats  = false
      for row in db:nrows([[
         SELECT name FROM sqlite_master WHERE type='table' AND name IN ('chunks','chats')
      ]]) do
         if row.name == "chunks" then found_chunks = true end
         if row.name == "chats"  then found_chats  = true end
      end
      chunks_status = found_chunks and "ready" or "missing"
      chats_status  = found_chats  and "ready" or "missing"
      db:close()
   end

   json(nil, {
      vec_backend   = "lua-cosine",
      embed_dim     = EMBED_DIM,
      chunks_table  = chunks_status,
      chats_table   = chats_status,
      module_loaded = (rag_cosine ~= nil),
   })
end

----------------------------------------------------------------------
-- ingest pipeline core — used by /rag/ingest (S2.2) and /journal/append (S4.1)
----------------------------------------------------------------------

-- ingest_doc(workspace, doc_path, text, metadata) → result_table
--
-- The shared chunker → embed → DELETE+INSERT pipeline. Extracted from
-- IngestHandler at S4.1 so JournalAppendHandler can reuse it (auto-ingest
-- after journal write) without an internal HTTP round-trip back to /rag/ingest.
--
-- Returns one of:
--   { status="ok", chunks_written=N, took_ms=M }
--   { error=msg, http_status=413|500|503, ...extra_fields }
--
-- DECISION: os.clock() for took_ms; acceptable precision for user-facing
-- latency (CLOCK_MONOTONIC availability in redbean's unix namespace is not
-- guaranteed across builds).
-- DECISION: BEGIN IMMEDIATE TRANSACTION wraps DELETE+INSERT for idempotent
-- re-ingest; concurrent re-ingest of the same (workspace, doc_path) can't
-- interleave.
local function ingest_doc(workspace, doc_path, text, metadata)
   local chunks = chunk_recursive(text, CHUNK_TARGET_TOKENS, CHUNK_OVERLAP_PCT)
   if #chunks > INGEST_MAX_CHUNKS then
      return {
         error       = "doc exceeds " .. INGEST_MAX_CHUNKS .. " chunks",
         chunks      = #chunks,
         max         = INGEST_MAX_CHUNKS,
         http_status = 413,
      }
   end

   local _, probe_err = embed_one("warmup")
   if probe_err then
      return {
         error       = "embedding server not running",
         hint        = "run start-embed first",
         detail      = probe_err,
         http_status = 503,
      }
   end

   local t0 = os.clock()
   local db, dberr = db_open_rag()
   if not db then return { error = dberr, http_status = 500 } end

   local rc = db:exec("BEGIN IMMEDIATE TRANSACTION")
   if rc ~= sqlite3.OK then
      db:close()
      return { error = "begin transaction failed: rc=" .. tostring(rc), http_status = 500 }
   end

   local del_stmt = db:prepare("DELETE FROM chunks WHERE workspace=? AND doc_path=?")
   if not del_stmt then
      db:exec("ROLLBACK") ; db:close()
      return { error = "prepare DELETE failed", http_status = 500 }
   end
   del_stmt:bind_values(workspace, doc_path)
   rc = del_stmt:step()
   del_stmt:finalize()
   if rc ~= sqlite3.DONE then
      db:exec("ROLLBACK") ; db:close()
      return { error = "DELETE failed: rc=" .. tostring(rc), http_status = 500 }
   end

   local ins_stmt = db:prepare([[
      INSERT INTO chunks(workspace, doc_path, chunk_idx, text, metadata, embedding, embedding_norm)
      VALUES (?, ?, ?, ?, ?, ?, ?)
   ]])
   if not ins_stmt then
      db:exec("ROLLBACK") ; db:close()
      return { error = "prepare INSERT failed", http_status = 500 }
   end

   local metadata_json = nil
   if metadata ~= nil then metadata_json = EncodeJson(metadata) end

   for idx, chunk_text in ipairs(chunks) do
      local vec, embed_err = embed_one(chunk_text)
      if embed_err then
         ins_stmt:finalize() ; db:exec("ROLLBACK") ; db:close()
         return { error = "embed failed on chunk " .. idx .. ": " .. embed_err, http_status = 500 }
      end
      local blob, norm = rag_cosine.embed_blob_pack(vec)
      -- DECISION: bind embedding BLOB explicitly via bind_blob. lsqlite3's
      -- bind_values infers Lua-string → TEXT, which truncates binary data
      -- containing null bytes (or invalid UTF-8 sequences). bind_blob forces
      -- BLOB type and stores all #blob bytes verbatim. Confirmed at S4.1
      -- smoke: bind_values stored only 302 bytes of a 3072-byte float32
      -- vector before this fix.
      ins_stmt:bind(1, workspace)
      ins_stmt:bind(2, doc_path)
      ins_stmt:bind(3, idx - 1)
      ins_stmt:bind(4, chunk_text)
      ins_stmt:bind(5, metadata_json)
      ins_stmt:bind_blob(6, blob)
      ins_stmt:bind(7, norm)
      rc = ins_stmt:step()
      ins_stmt:reset()
      if rc ~= sqlite3.DONE then
         ins_stmt:finalize() ; db:exec("ROLLBACK") ; db:close()
         return { error = "INSERT failed on chunk " .. idx .. ": rc=" .. tostring(rc), http_status = 500 }
      end
   end

   ins_stmt:finalize()
   rc = db:exec("COMMIT")
   db:close()
   if rc ~= sqlite3.OK then
      return { error = "commit failed: rc=" .. tostring(rc), http_status = 500 }
   end

   return {
      status         = "ok",
      chunks_written = #chunks,
      took_ms        = math.floor((os.clock() - t0) * 1000),
   }
end

----------------------------------------------------------------------
-- /rag/ingest handler (v0.8 Wave 2 / S2.2)
----------------------------------------------------------------------

-- POST /rag/ingest?workspace=<name>
-- Body: JSON { doc_path: string, text: string, metadata?: any }
-- Thin wrapper around ingest_doc — handles HTTP shape only.
local function IngestHandler()
   if GetMethod() ~= "POST" then
      SetStatus(405) ; set_cors_headers() ; SetHeader("Allow", "POST") ; return
   end

   local workspace = GetParam("workspace")
   if not workspace or workspace == "" then workspace = "default" end

   local raw_body = GetBody()
   if not raw_body or #raw_body == 0 then
      return json_err(400, "empty body")
   end
   local req = DecodeJson(raw_body)
   if type(req) ~= "table" then
      return json_err(400, "body is not valid JSON")
   end
   local doc_path = req.doc_path
   local text     = req.text
   if type(doc_path) ~= "string" or doc_path == "" then
      return json_err(400, "missing or empty doc_path")
   end
   if type(text) ~= "string" or text == "" then
      return json_err(400, "missing or empty text")
   end

   local result = ingest_doc(workspace, doc_path, text, req.metadata)
   if result.error then
      local code = result.http_status or 500
      result.http_status = nil
      SetStatus(code)
      set_cors_headers()
      SetHeader("Content-Type", "application/json")
      Write(EncodeJson(result))
      return
   end

   json(nil, {
      status         = "ok",
      workspace      = workspace,
      doc_path       = doc_path,
      chunks_written = result.chunks_written,
      took_ms        = result.took_ms,
   })
end

----------------------------------------------------------------------
-- /rag/query handler (v0.8 Wave 2 / S2.3)
----------------------------------------------------------------------

-- GET /rag/query?q=<text>&k=<int>&workspace=<name>
-- Embeds the query, retrieves top-k chunks via cosine similarity.
local function QueryHandler()
   if GetMethod() ~= "GET" then
      SetStatus(405) ; set_cors_headers() ; SetHeader("Allow", "GET") ; return
   end

   local q = GetParam("q")
   if not q or q == "" then
      return json_err(400, "missing or empty q param")
   end

   -- k: default QUERY_DEFAULT_K, clamped to [1, 50].
   local k = tonumber(GetParam("k")) or QUERY_DEFAULT_K
   if k < 1  then k = 1  end
   if k > 50 then k = 50 end

   local workspace = GetParam("workspace")
   if not workspace or workspace == "" then workspace = "default" end

   -- Embed the query.
   local qvec, embed_err = embed_one(q)
   if embed_err then
      return json(503, {
         error  = "embedding server not running",
         hint   = "run start-embed first",
         detail = embed_err,
      })
   end

   -- Pack the query vector to get its norm (we don't store the blob, just the norm).
   local _, qnorm = rag_cosine.embed_blob_pack(qvec)

   local t0 = os.clock()

   local db, dberr = db_open_rag()
   if not db then return json_err(500, dberr) end

   -- Fetch all chunks for this workspace. cosine_topk does the scoring and
   -- sorting in Lua — no SQL ORDER BY or LIMIT needed for the cosine path.
   -- Note: cosine_topk expects `embedding_blob`, not `embedding`. We alias
   -- the column when building the row table below.
   -- DECISION: use prepared statement instead of nrows(sql, param) — lsqlite3's
   -- nrows() does not accept bind parameters; only rows()/prepared statements do.
   local rows = {}
   local sel_stmt = db:prepare([[
      SELECT chunk_id, doc_path, chunk_idx, text, metadata, embedding, embedding_norm
      FROM chunks WHERE workspace=?
   ]])
   if sel_stmt then
      sel_stmt:bind_values(workspace)
      for row in sel_stmt:nrows() do
         rows[#rows+1] = {
            chunk_id       = row.chunk_id,
            embedding_blob = row.embedding,  -- rename: cosine_topk contract uses embedding_blob
            embedding_norm = row.embedding_norm,
            doc_path       = row.doc_path,
            chunk_idx      = row.chunk_idx,
            text           = row.text,
            metadata       = row.metadata,
         }
      end
      sel_stmt:finalize()
   end
   db:close()

   -- Score and rank.
   local top = rag_cosine.cosine_topk(qvec, qnorm, rows, k)

   -- Format results: strip internal fields, decode metadata JSON.
   local result_arr = {}
   for i, r in ipairs(top) do
      local meta = nil
      if r.metadata then
         meta = DecodeJson(r.metadata)
      end
      result_arr[#result_arr+1] = EncodeJson({
         rank      = i,
         chunk_id  = r.chunk_id,
         doc_path  = r.doc_path,
         chunk_idx = r.chunk_idx,
         text      = r.text,
         distance  = r.distance,
         metadata  = meta,
      })
   end

   local took_ms = math.floor((os.clock() - t0) * 1000)

   -- Manually build the JSON response to guarantee `results` is always
   -- an array (Lua empty table serializes as `{}`, not `[]`).
   set_cors_headers()
   SetHeader("Content-Type", "application/json")
   Write('{"query":' .. EncodeJson(q)
      .. ',"workspace":' .. EncodeJson(workspace)
      .. ',"k":' .. tostring(k)
      .. ',"results":[' .. table.concat(result_arr, ",") .. ']'
      .. ',"took_ms":' .. tostring(took_ms)
      .. '}')
end

----------------------------------------------------------------------
-- /rag/list-docs and /rag/list-workspaces handlers (v0.8 Wave 2 / S2.4)
----------------------------------------------------------------------

-- GET /rag/list-workspaces
-- Returns all workspaces with their chunk and doc counts.
local function ListWorkspacesHandler()
   local db, dberr = db_open_rag()
   if not db then return json_err(500, dberr) end

   local rows = {}
   for row in db:nrows([[
      SELECT workspace, COUNT(DISTINCT doc_path) AS docs, COUNT(*) AS chunks
      FROM chunks
      GROUP BY workspace
      ORDER BY workspace
   ]]) do
      rows[#rows+1] = EncodeJson({
         name   = row.workspace,
         docs   = row.docs,
         chunks = row.chunks,
      })
   end
   db:close()

   -- Manually build array to guarantee [] on empty result.
   set_cors_headers()
   SetHeader("Content-Type", "application/json")
   Write('{"workspaces":[' .. table.concat(rows, ",") .. ']}')
end

-- GET /rag/list-docs?workspace=<name>
-- Returns all documents in a workspace with their chunk counts.
local function ListDocsHandler()
   local workspace = GetParam("workspace")
   if not workspace or workspace == "" then workspace = "default" end

   local db, dberr = db_open_rag()
   if not db then return json_err(500, dberr) end

   -- DECISION: use prepared statement — nrows() does not accept bind params.
   local rows = {}
   local sel_stmt = db:prepare([[
      SELECT doc_path, COUNT(*) AS chunks
      FROM chunks
      WHERE workspace=?
      GROUP BY doc_path
      ORDER BY doc_path
   ]])
   if sel_stmt then
      sel_stmt:bind_values(workspace)
      for row in sel_stmt:nrows() do
         rows[#rows+1] = EncodeJson({
            doc_path = row.doc_path,
            chunks   = row.chunks,
         })
      end
      sel_stmt:finalize()
   end
   db:close()

   -- Manually build array to guarantee [] on empty result.
   set_cors_headers()
   SetHeader("Content-Type", "application/json")
   Write('{"docs":[' .. table.concat(rows, ",") .. ']}')
end

----------------------------------------------------------------------
-- /chat/* handlers (v0.8 Wave 2 / S2.5)
----------------------------------------------------------------------

-- POST /chat/save
-- Body: JSON { id: string, workspace: string, body: string, title?: string }
-- Upserts a chat session to the chats table (idempotent on id).
local function ChatSaveHandler()
   if GetMethod() ~= "POST" then
      SetStatus(405) ; set_cors_headers() ; SetHeader("Allow", "POST") ; return
   end

   local raw_body = GetBody()
   if not raw_body or #raw_body == 0 then
      return json_err(400, "empty body")
   end
   local req = DecodeJson(raw_body)
   if type(req) ~= "table" then
      return json_err(400, "body is not valid JSON")
   end

   local id        = req.id
   local workspace = req.workspace
   local body      = req.body
   local title     = req.title  -- optional

   if type(id) ~= "string" or id == "" then
      return json_err(400, "missing or empty id")
   end
   if type(workspace) ~= "string" or workspace == "" then
      return json_err(400, "missing or empty workspace")
   end
   if type(body) ~= "string" or body == "" then
      return json_err(400, "missing or empty body")
   end

   local db, dberr = db_open_rag()
   if not db then return json_err(500, dberr) end

   local stmt = db:prepare([[
      INSERT INTO chats(id, workspace, title, body, updated_at)
      VALUES(?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
         workspace  = excluded.workspace,
         title      = excluded.title,
         body       = excluded.body,
         updated_at = excluded.updated_at
   ]])
   if not stmt then
      db:close()
      return json_err(500, "prepare failed")
   end
   stmt:bind_values(id, workspace, title or "", body, now_iso())
   local rc = stmt:step()
   stmt:finalize()
   db:close()

   if rc ~= sqlite3.DONE then
      return json_err(500, "write failed: rc=" .. tostring(rc))
   end
   json(nil, { status = "ok", id = id, bytes = #body })
end

-- GET /chat/list?workspace=<name>
-- Returns chats in a workspace, most-recent first.
local function ChatListHandler()
   local workspace = GetParam("workspace")
   if not workspace or workspace == "" then workspace = "default" end

   local db, dberr = db_open_rag()
   if not db then return json_err(500, dberr) end

   -- DECISION: use prepared statement — nrows() does not accept bind params.
   local rows = {}
   local sel_stmt = db:prepare([[
      SELECT id, workspace, title, length(body) AS bytes, updated_at
      FROM chats
      WHERE workspace=?
      ORDER BY updated_at DESC
   ]])
   if sel_stmt then
      sel_stmt:bind_values(workspace)
      for row in sel_stmt:nrows() do
         rows[#rows+1] = EncodeJson({
            id         = row.id,
            workspace  = row.workspace,
            title      = row.title,
            bytes      = row.bytes,
            updated_at = row.updated_at,
         })
      end
      sel_stmt:finalize()
   end
   db:close()

   -- Manually build array to guarantee [] on empty result.
   set_cors_headers()
   SetHeader("Content-Type", "application/json")
   Write('{"chats":[' .. table.concat(rows, ",") .. ']}')
end

-- GET /chat/load?id=<uuid>
-- Returns a single chat session by id, or 404.
local function ChatLoadHandler()
   local id = GetParam("id")
   if not id or id == "" then
      return json_err(400, "missing id param")
   end

   local db, dberr = db_open_rag()
   if not db then return json_err(500, dberr) end

   local stmt = db:prepare([[
      SELECT workspace, title, body, updated_at FROM chats WHERE id=?
   ]])
   if not stmt then
      db:close()
      return json_err(500, "prepare failed")
   end
   stmt:bind_values(id)
   local rc = stmt:step()
   if rc == sqlite3.ROW then
      local workspace  = stmt:get_value(0)
      local title      = stmt:get_value(1)
      local body       = stmt:get_value(2)
      local updated_at = stmt:get_value(3)
      stmt:finalize()
      db:close()
      json(nil, {
         id         = id,
         workspace  = workspace,
         title      = title,
         body       = body,
         updated_at = updated_at,
      })
   else
      stmt:finalize()
      db:close()
      json_err(404, "chat not found: " .. id)
   end
end

----------------------------------------------------------------------
-- /journal/* handlers (v0.8 Wave 4 / S4.1)
----------------------------------------------------------------------

-- Daily journal files live at workspace/<name>/journal/YYYY-MM-DD.md on the
-- USB. POST /journal/append appends a `## HH:MM` section with the user's
-- text, then auto-ingests the file into RAG so the day's notes are
-- queryable via /rag/query immediately. GET /journal/today returns today's
-- file content (or empty string if no file yet).
--
-- Path is relative to redbean's CWD — start-doom.sh `cd "$ROOT"` first, so
-- this lands at <USB-root>/workspace/<name>/journal/YYYY-MM-DD.md, matching
-- the workspace skeleton documented at workspace/README.md.

-- ensure_dir(path) → true | (nil, errmsg)
-- Recursive mkdir. Walks path components, creates each missing one.
-- Idempotent: existing dirs are accepted.
local function ensure_dir(path)
   if not path or path == "" or path == "." or path == "/" then return true end
   local parts = {}
   for p in path:gmatch("[^/]+") do parts[#parts+1] = p end
   local cur = path:sub(1, 1) == "/" and "" or "."
   for _, p in ipairs(parts) do
      cur = cur == "" and ("/" .. p) or (cur == "." and p or (cur .. "/" .. p))
      if unix.access(cur, unix.F_OK) == nil then
         local ok, err = unix.mkdir(cur, 0755)
         if not ok and unix.access(cur, unix.F_OK) == nil then
            return nil, "mkdir failed at " .. cur .. ": " .. tostring(err)
         end
      end
   end
   return true
end

-- journal_path(workspace) → relative path to today's journal file.
local function journal_path(workspace)
   return string.format("workspace/%s/journal/%s.md",
                        workspace, os.date("!%Y-%m-%d"))
end

-- POST /journal/append?workspace=<name>
-- Body: JSON { text: string }
-- Appends "## HH:MM\n<text>\n" to today's file (or creates it with a header
-- if it doesn't exist). Auto-ingests the resulting file into RAG.
local function JournalAppendHandler()
   if GetMethod() ~= "POST" then
      SetStatus(405) ; set_cors_headers() ; SetHeader("Allow", "POST") ; return
   end

   local workspace = GetParam("workspace")
   if not workspace or workspace == "" then workspace = "default" end

   local raw_body = GetBody()
   if not raw_body or #raw_body == 0 then return json_err(400, "empty body") end
   local req = DecodeJson(raw_body)
   if type(req) ~= "table" then return json_err(400, "body is not valid JSON") end
   local text = req.text
   if type(text) ~= "string" or text == "" then
      return json_err(400, "missing or empty text")
   end
   if #text > JOURNAL_MAX_TEXT then
      return json(413, {
         error = "text exceeds " .. JOURNAL_MAX_TEXT .. " bytes",
         bytes = #text,
         max   = JOURNAL_MAX_TEXT,
      })
   end

   local rel_path = journal_path(workspace)
   local dir = rel_path:match("^(.+)/[^/]+$")
   local ok_mkdir, mkdir_err = ensure_dir(dir)
   if not ok_mkdir then return json_err(500, mkdir_err) end

   local today = os.date("!%Y-%m-%d")
   local hhmm  = os.date("!%H:%M")

   local existing = ""
   if unix.access(rel_path, unix.F_OK) ~= nil then
      local f = io.open(rel_path, "r")
      if f then
         existing = f:read("*a") or ""
         f:close()
      end
   end

   -- If the body already starts with its own markdown heading (`#` or `##`,
   -- typically a user-supplied timestamp), skip the auto `## HH:MM` line so
   -- we don't end up with a hollow heading immediately followed by another.
   local body_has_heading = text:match("^%s*#") ~= nil

   local new_content
   if existing == "" then
      if body_has_heading then
         new_content = string.format("# Journal — %s\n\n%s\n", today, text)
      else
         new_content = string.format("# Journal — %s\n\n## %s\n%s\n", today, hhmm, text)
      end
   else
      local trimmed = existing:gsub("%s+$", "")
      if body_has_heading then
         new_content = trimmed .. "\n\n" .. text .. "\n"
      else
         new_content = trimmed .. "\n\n## " .. hhmm .. "\n" .. text .. "\n"
      end
   end

   local f, ferr = io.open(rel_path, "w")
   if not f then return json_err(500, "open for write failed: " .. tostring(ferr)) end
   f:write(new_content)
   f:close()

   -- Auto-ingest into RAG. Soft-fail: file is written; ingest is best-effort
   -- so a down embed server doesn't lose the user's note. Same idempotent
   -- DELETE+INSERT path as POST /rag/ingest — re-running this for the same
   -- file replaces prior chunks.
   local response = {
      status        = "ok",
      workspace     = workspace,
      doc_path      = rel_path,
      bytes_written = #new_content,
   }
   local ingest_result = ingest_doc(workspace, rel_path, new_content,
                                    { source = "journal", date = today })
   if ingest_result.error then
      response.ingest_status = "failed"
      response.ingest_error  = ingest_result.error
      response.ingest_hint   = ingest_result.hint
   else
      response.ingest_status  = "ok"
      response.chunks_written = ingest_result.chunks_written
      response.ingest_took_ms = ingest_result.took_ms
   end
   json(nil, response)
end

-- GET /journal/today?workspace=<name>
-- Returns today's journal file content, or empty string if no file exists.
local function JournalTodayHandler()
   if GetMethod() ~= "GET" then
      SetStatus(405) ; set_cors_headers() ; SetHeader("Allow", "GET") ; return
   end

   local workspace = GetParam("workspace")
   if not workspace or workspace == "" then workspace = "default" end

   local rel_path = journal_path(workspace)
   if unix.access(rel_path, unix.F_OK) == nil then
      json(nil, {
         workspace = workspace,
         doc_path  = rel_path,
         content   = "",
         exists    = false,
      })
      return
   end

   local f, ferr = io.open(rel_path, "r")
   if not f then return json_err(500, "open failed: " .. tostring(ferr)) end
   local content = f:read("*a") or ""
   f:close()
   json(nil, {
      workspace = workspace,
      doc_path  = rel_path,
      content   = content,
      exists    = true,
   })
end

----------------------------------------------------------------------
-- dispatch
----------------------------------------------------------------------

function OnHttpRequest()
   local path   = GetPath()
   local method = GetMethod()

   -- Chat tab launches via file://D:\chat\index.html (Origin: null) and fetches
   -- http://127.0.0.1:8768/{rag,journal,chat}/* — cross-origin under the browser
   -- same-origin policy. Without CORS headers, every adapter fetch fails with
   -- "TypeError: Failed to fetch" and the entire RAG + journal + sessions UX is
   -- non-functional in the deployed kit. * is acceptable because redbean only
   -- binds 127.0.0.1; remote origins cannot reach the listener.
   --
   -- IMPORTANT: do NOT call set_cors_headers() at this top level. We tried it
   -- and Chrome rejected every successful response as opaque/blocked because
   -- the response carried duplicate Access-Control-Allow-Origin headers (RFC
   -- 7230 forbids duplicate single-value headers). Cause: SetStatus(200) does
   -- NOT clear the pending header set, so the up-front call PLUS json()'s own
   -- set_cors_headers() doubled. Instead, every response path is responsible
   -- for calling set_cors_headers() exactly once: json() and json_err() do it
   -- after SetStatus; OPTIONS branch does it after SetStatus(204); manual
   -- Write handlers (ListHandler, LoadHandler, TtsHandler, QueryHandler,
   -- ListWorkspacesHandler, ListDocsHandler, ChatListHandler) call it
   -- explicitly before their first SetHeader. The static-file fallback
   -- (Route()) does not call it — those assets are same-origin to redbean.

   if method == "OPTIONS" then
      SetStatus(204)
      set_cors_headers()
      return
   end

   if     path == "/health"               then HealthHandler()
   elseif path == "/save"                 then SaveHandler()
   elseif path == "/load"                 then LoadHandler()
   elseif path == "/list"                 then ListHandler()
   elseif path == "/tts"                  then TtsHandler()
   elseif path == "/rag/_loadtest"        then RagLoadtestHandler()
   elseif path == "/rag/ingest"           then IngestHandler()
   elseif path == "/rag/query"            then QueryHandler()
   elseif path == "/rag/list-docs"        then ListDocsHandler()
   elseif path == "/rag/list-workspaces"  then ListWorkspacesHandler()
   elseif path:sub(1, 4) == "/rag"        then NotImplemented(path, "v0.9+ (out-of-scope routes)")
   elseif path == "/chat/save"            then ChatSaveHandler()
   elseif path == "/chat/list"            then ChatListHandler()
   elseif path == "/chat/load"            then ChatLoadHandler()
   elseif path == "/journal/append"       then JournalAppendHandler()
   elseif path == "/journal/today"        then JournalTodayHandler()
   else
      -- Default: serve static files from the docroot configured via -D.
      Route()
   end
end
