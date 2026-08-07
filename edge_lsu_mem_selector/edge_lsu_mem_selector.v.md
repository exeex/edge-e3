# edge_lsu_mem_selector.v

## Purpose

`edge_lsu_mem_selector` owns the scalar LSU backend choice between the core
DTCM window and the scalar D-cache path.

It is a structural extraction from the first `edge_core_top` scalar memory
slice. The behavior is intentionally conservative: one outstanding DTCM scalar
load is tracked locally, D-cache requests are suppressed while a DTCM load is
pending or returning, and DTCM loads wait while the D-cache backend reports an
outstanding load.

## Interface

Inputs from the core:

```text
edge_dtcm_enable
edge_dtcm_base
edge_dtcm_mask
```

The selector treats a scalar LSU address as a DTCM hit when:

```text
(addr & edge_dtcm_mask) == edge_dtcm_base
```

Scalar LSU request/response side:

```text
lsu_load_req_valid
lsu_load_req_ready
lsu_load_req_seq_id
lsu_load_req_epoch
lsu_load_req_addr
lsu_load_req_size
lsu_load_req_signed
lsu_load_req1_valid
lsu_load_req1_ready
lsu_load_req1_seq_id
lsu_load_req1_epoch
lsu_load_req1_addr
lsu_load_req1_size
lsu_load_req1_signed
lsu_store_req_valid
lsu_store_req_ready
lsu_store_req_addr
lsu_store_req_data
lsu_store_req_wstrb
lsu_store_req1_valid
lsu_store_req1_ready
lsu_store_req1_seq_id
lsu_store_req1_epoch
lsu_store_req1_addr
lsu_store_req1_size
lsu_store_req1_data
lsu_store_req1_wstrb
lsu_load_resp_valid
lsu_load_resp_seq_id
lsu_load_resp_epoch
lsu_load_resp_error
lsu_load_resp_value
```

D-cache side:

```text
dcache_load_req_valid
dcache_load_req_ready
dcache_load_resp_valid
dcache_load_resp_seq_id
dcache_load_resp_epoch
dcache_load_resp_error
dcache_load_resp_value
dcache_load_req1_valid
dcache_load_req1_ready
dcache_store_req_valid
dcache_store_req_ready
dcache_store_req1_valid
dcache_store_req1_ready
dcache_store_predict_phase
dcache_store_predict_mem_active
dcache_store_predict_backend_blocked
dcache_debug_load_pending
```

DTCM scalar LSU side:

```text
dtcm_scalar_lsu_req
dtcm_scalar_lsu_we
dtcm_scalar_lsu_addr
dtcm_scalar_lsu_wdata
dtcm_scalar_lsu_wstrb
dtcm_scalar_lsu_rdata
dtcm_scalar_lsu_ready
dtcm_scalar_lsu_rvalid
```

## Behavior

- DTCM-hit scalar stores issue to DTCM when there is no pending/returning DTCM
  scalar load.
- Non-DTCM scalar stores issue to D-cache.
- Non-DTCM scalar store ready is gated with the same store-side
  `edge_dcache_pair_predictor` policy used by D-cache. The selector consumes the
  D-cache phase, MEM-active, and backend-blocked summary, compares the two STB
  head addresses for same-line/different-bank eligibility, and only lets lane1
  drain when the pair can be accepted together. An idle MEM side permits either
  half; same-bank, different-line, active-MEM wrong-phase, or blocked pairs
  replay from the STB instead of being optimistically drained.
- DTCM-hit scalar loads issue to DTCM when no DTCM load is pending, no DTCM
  response is returning, no DTCM store is taking priority, the D-cache backend
  is not reporting an outstanding load, and DTCM is ready.
- Non-DTCM scalar loads issue to D-cache when no DTCM load is pending or
  returning and D-cache is ready.
- Lane1 D-cache requests are forwarded only when lane0 is also selecting
  D-cache. DTCM-hit lane1 operations are held in the LSU queues for replay,
  because the scalar DTCM boundary remains single-lane in this slice.
- DTCM scalar load response metadata is captured at issue and replayed with
  the returning DTCM data.
- D-cache response errors pass through with their sequence/epoch metadata;
  DTCM responses always report no backend error.
- redirect marks a matching-epoch pending DTCM load younger than the boundary
  stale using modulo sequence age. Its physical response still drains and
  releases the selector but is not forwarded to LSU, allowing safe reuse of
  the exact same `(seq_id, epoch)` tag later.
- DTCM load data is formatted by byte offset, size, and signedness before
  returning to the scalar LSU.
- DTCM response wins the scalar load response mux over D-cache response. The
  gating above prevents an intentional same-cycle conflict in the current
  single-outstanding slice.

## Deliberate Limits

- No rotating-channel lease for scalar LSU yet. Keep the current immediate
  DTCM scalar request contract until the LSU boundary grows explicit request
  state.
- No dual-lane scalar DTCM access yet. Paired requests can reach D-cache only.
- No overlap/fairness policy beyond the first conservative single-load
  selector.
- No vector/tensor DTCM clients are selected here yet.
- Redirect/wrong-path suppression still belongs upstream in `edge_lsu_top` and
  the scalar pipe; this selector assumes incoming requests are allowed to reach
  a backend.

## Tests

Module-local test:

```text
src/test-e3/edge_lsu_mem_selector/edge_lsu_mem_selector_tb.v
```

The test covers DTCM store routing, D-cache store fallback, DTCM load issue and
formatted response, D-cache load fallback and response muxing, mixed stream
ordering, pending/backpressure cases, and upstream store-pair predictor gating
for D-cache phase, backend-blocked, same-bank replay, different-line replay,
same-line different-bank paired drain, and DTCM-hit lane1 load/store replay.
