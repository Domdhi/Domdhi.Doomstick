-- redbean/lua/rag-cosine.lua — pure-Lua cosine similarity helpers for RAG.
--
-- Ships as part of the Doomstick offline AI kit (v0.8 RAG layer).
-- Baked into redbean.com's appended zip alongside .init.lua so that
-- require("rag-cosine") resolves from the zip at runtime.
--
-- Architecture context (see docs/research/rag-architecture-2026-05-09.md §D4):
-- redbean's bundled lsqlite3 has NO load_extension and NO FTS5, so vec0 /
-- sqlite_vss / sqlite-vec cannot be used. This module provides the full
-- vector-similarity path over plain SQLite BLOB columns:
--   1. embed_blob_pack   — float[] → packed bytes + L2 norm (ingest time)
--   2. embed_blob_unpack — packed bytes → float[] (query time, also for tests)
--   3. cosine_topk       — score pre-fetched rows, return top-k by distance
--
-- Lua 5.4 required (string.pack / string.unpack with format "<f").
-- Redbean 3.0.0 ships Lua 5.4 — this is safe.
--
-- Performance envelope (full-scan, estimated on 8 GB host):
--   100 chunks  ~50 ms
--   500 chunks  ~250 ms
--   1000 chunks ~500 ms    ← design target per §D4

local M = {}

-- embed_blob_pack(vec)
--
-- Takes a Lua array of floats (the embedding vector), packs it into a
-- little-endian float32 byte string, and computes the L2 norm of the vector.
--
-- Returns: blob_string (string), l2_norm (number)
--   blob_string  — #vec * 4 bytes, each float serialized as little-endian f32
--   l2_norm      — math.sqrt(sum(v_i^2)), precomputed so query-time cosine
--                  only needs one dot product + one cheap divide (no sqrt per chunk)
--
-- The caller (S2.2 ingest handler) stores blob_string in the `embedding` BLOB
-- column and l2_norm in `embedding_norm`. Storing the norm avoids recomputing
-- it on every query for every chunk — the biggest bottleneck in a full-scan loop.
function M.embed_blob_pack(vec)
   local parts = {}
   local sq_sum = 0.0
   for i = 1, #vec do
      local v = vec[i]
      parts[i] = string.pack("<f", v)
      sq_sum = sq_sum + v * v
   end
   return table.concat(parts), math.sqrt(sq_sum)
end

-- embed_blob_unpack(blob, dim)
--
-- Reverse of embed_blob_pack. Takes a BLOB string and the expected dimension,
-- returns a Lua array of floats.
--
-- Errors if #blob ~= dim * 4, which would indicate a mismatched EMBED_DIM
-- constant (version drift between ingest time and query time).
function M.embed_blob_unpack(blob, dim)
   local expected_len = dim * 4
   if #blob ~= expected_len then
      error(string.format(
         "embed_blob_unpack: blob length %d does not match dim %d (expected %d bytes)",
         #blob, dim, expected_len
      ))
   end
   local vec = {}
   local offset = 1
   for i = 1, dim do
      local v, next_offset = string.unpack("<f", blob, offset)
      vec[i] = v
      offset = next_offset
   end
   return vec
end

-- cosine_topk(query_vec, query_norm, rows, k)
--
-- Scores a pre-fetched result set against a query vector and returns the
-- top-k rows sorted ascending by cosine distance (1 - cosine_similarity),
-- so distance=0.0 means identical direction and distance=1.0 means orthogonal.
--
-- Parameters:
--   query_vec   (table) — Lua float array, the embedded query
--   query_norm  (number) — precomputed L2 norm of query_vec (from embed_blob_pack
--                          or computed separately; pass math.huge to disable
--                          normalization — useful only in unit tests where you
--                          know the input is already unit-length)
--   rows        (table) — array of row tables, each with keys:
--                           chunk_id        (integer)
--                           embedding_blob  (string) — packed float32 bytes
--                           embedding_norm  (number) — precomputed L2 norm
--                           doc_path        (string)
--                           chunk_idx       (integer)
--                           text            (string)
--                           metadata        (string or nil) — JSON blob
--   k           (integer) — max results to return
--
-- Returns: array of up to k tables, each with the same keys as the input rows
--          plus an added `distance` (number, 0.0..1.0) and `score` (number,
--          cosine similarity in [−1, 1]).
--
-- Design: sort-after-scan is clearer than a min-heap for k ≤ 20 and avoids
-- the ~30-line heap implementation. The bottleneck is the BLOB unpack + dot
-- product inner loop, not the O(n log n) sort over a small result table.
-- If k grows beyond ~50 or corpus exceeds 5000 chunks revisit with a min-heap.
function M.cosine_topk(query_vec, query_norm, rows, k)
   local dim = #query_vec
   local scored = {}

   for _, row in ipairs(rows) do
      -- Unpack the stored float32 BLOB into a Lua array.
      local chunk_dim = #row.embedding_blob / 4
      if chunk_dim ~= dim then
         -- Dim mismatch means ingest-time and query-time EMBED_DIM diverged.
         -- Skip rather than error so a single bad row doesn't kill the query.
         -- The caller (S2.3 handler) should surface this as a warning.
         goto continue
      end

      -- Dot product: sum(query_i * chunk_i)
      local dot = 0.0
      local offset = 1
      for i = 1, dim do
         local cv, next_offset = string.unpack("<f", row.embedding_blob, offset)
         dot = dot + query_vec[i] * cv
         offset = next_offset
      end

      -- Cosine similarity = dot / (query_norm * chunk_norm).
      -- Guard against zero-norm vectors (e.g., all-zero embeddings, which
      -- should never appear in practice but would produce NaN otherwise).
      local denom = query_norm * row.embedding_norm
      local sim
      if denom == 0.0 then
         sim = 0.0
      else
         sim = dot / denom
      end

      -- Distance in [0, 1] for ascending sort (lower = more similar).
      -- Clamp sim to [-1, 1] to guard against float32 precision overflow.
      if sim > 1.0 then sim = 1.0 end
      if sim < -1.0 then sim = -1.0 end
      local dist = 1.0 - sim

      scored[#scored+1] = {
         chunk_id       = row.chunk_id,
         embedding_blob = row.embedding_blob,
         embedding_norm = row.embedding_norm,
         doc_path       = row.doc_path,
         chunk_idx      = row.chunk_idx,
         text           = row.text,
         metadata       = row.metadata,
         score          = sim,
         distance       = dist,
      }

      ::continue::
   end

   -- Sort ascending by distance (closest first).
   table.sort(scored, function(a, b) return a.distance < b.distance end)

   -- Trim to k results.
   local result = {}
   for i = 1, math.min(k, #scored) do
      result[i] = scored[i]
   end
   return result
end

return M
