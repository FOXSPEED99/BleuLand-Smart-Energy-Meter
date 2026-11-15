// Local HTTP API on port 80 (home network only).
//
//   GET  /              bench / calibration page
//   GET  /api/live      live values (JSON), open to read
//   GET  /api/info      diagnostics (JSON), open to read
//   POST /api/cal       calibration, needs key=<pop from the label QR>
//        params: v=230.1 | i=4.35 | p=1000 | reset=1 | energy=int|pf
#pragma once

namespace localApi {
void begin();
void loop();
}  // namespace localApi
