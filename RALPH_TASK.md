---
task: Implement live voice chat with PTT for urfd-nng-dashboard
test_command: "tilt ci"
---

# Task: Live Voice Chat Implementation

Implement live listen and PTT (Push-to-Talk) functionality between the urfd-nng-dashboard web client and the URFD reflector module. Users will be able to listen to live audio from transcoded reflector modules and transmit back using a push-to-talk interface in half-duplex mode.

## Architecture Summary

- **Audio Format:** Opus codec (12kbps, 8kHz mono, 20ms frames)
- **Transport:** WebSocket binary frames (existing connection)
- **Reflector:** CNNGVoiceStream component taps live audio, uses NNG PAIR protocol (port 5556)
- **Dashboard:** Go voice handler bridges NNG ↔ WebSocket
- **Frontend:** Vue.js VoiceChat component with opus-recorder.js (TX) and libopus.js (RX)
- **Auth:** Global password for transmit, callsign required, listen-only without auth
- **Half-duplex:** Single active transmitter per module (first wins, others rejected)

For detailed architecture, see: `.opencode/plans/webvoiceclient.md`

## Success Criteria

### Phase 1: Reflector Audio Streaming (Receive Only)
- [x] Create `src/NNGVoiceStream.h` with CNNGVoiceStream class definition
- [x] Create `src/NNGVoiceStream.cpp` implementing audio tap and Opus encoding
- [x] Add voice configuration section to `src/configure.h`
- [x] Modify `src/PacketStream.cpp` to add audio tap observer pattern
- [x] Modify `src/Reflector.cpp` to initialize CNNGVoiceStream when enabled
- [x] Test NNG voice endpoint streams Opus audio (verify with simple client)

### Phase 2: Dashboard Voice Bridge (Receive Path)
- [x] Create `internal/voice/nng.go` implementing NNG client for voice endpoint
- [x] Create `internal/voice/session.go` with voice session state machine
- [x] Modify `internal/server/server.go` to add WebSocket voice handler
- [x] Modify `internal/server/hub.go` to add voice session management
- [x] Add voice configuration to `config.yaml`
- [x] Test WebSocket endpoint streams Opus frames to browser clients

### Phase 3: Frontend Voice Receiver
- [x] Add `opus-recorder` and `libopus.js` dependencies to `web/package.json`
- [x] Create `web/src/components/VoiceChat/VoiceEngine.vue` with Web Audio API
- [x] Create `web/src/components/VoiceChat/VoiceChat.vue` main UI component
- [x] Create `web/src/components/VoiceChat/PTTButton.vue` for PTT control
- [x] Create `web/src/stores/voice.ts` Pinia store for voice state
- [x] Modify `web/src/layouts/AppShell.vue` to integrate voice chat button
- [x] Implement callsign input with validation and localStorage persistence
- [x] Implement module selector (transcoded modules only)
- [x] Test users can hear live audio from selected module

### Phase 4: Frontend PTT Transmit
- [x] Implement microphone permission handling in VoiceEngine
- [x] Integrate opus-recorder.js for microphone capture and encoding
- [x] Implement PTT button state management (press/release)
- [x] Add half-duplex logic (lock PTT when receiving audio)
- [x] Wire up WebSocket audio upload for transmit path
- [x] Create password prompt dialog component
- [x] Implement password authentication flow in voice store
- [x] Test PTT button locks during RX and allows TX when clear

### Phase 5: Reflector Audio Injection (Transmit Path)
- [x] Implement Opus decode in CNNGVoiceStream
- [x] Create virtual USRP client/user for web transmissions in Reflector
- [x] Implement stream injection via OpenStream() for web audio
- [x] Add callsign and user metadata handling for web streams
- [x] Tag web streams with `source=web` metadata
- [x] Implement single active stream enforcement per module
- [x] Add password validation in dashboard voice handler
- [ ] Test end-to-end: browser PTT → dashboard → reflector → other clients

### Phase 6: Polish & Core Features
- [x] Add audio level meters (RX and TX) to VoiceChat UI
- [x] Implement AGC/noise gate on transmit audio
- [x] Add echo cancellation hints to getUserMedia config
- [x] Implement voice activity detection (optional)
- [x] Add connection recovery handling (WebSocket reconnect)
- [x] Add session timeout enforcement (120s max TX per config)
- [x] Improve error messages and user feedback
- [x] Add logging and diagnostics for troubleshooting
- [ ] Test connection interruption and recovery scenarios

### Phase 6.5: Mobile Support & Advanced Features
- [x] Implement Media Session API for background audio playback
- [ ] Add Wake Lock API to prevent screen sleep during sessions
- [ ] Handle iOS audio context resume requirements
- [ ] Add persistent notification with active talker info (mobile)
- [ ] Implement auto-reconnect on app resume from background
- [ ] Add data usage indicator for mobile users
- [ ] Test background audio on iOS Safari 15+ and Android Chrome
- [ ] Test lock screen controls functionality

### Testing & Validation
- [ ] Run `tilt ci` successfully with all changes
- [ ] Verify no regressions in existing dashboard functionality
- [ ] Test with multiple concurrent listeners on same module
- [ ] Test with multiple modules active simultaneously (no crosstalk)
- [ ] Verify PTT denial when module busy (second user rejected)
- [ ] Test password authentication (valid and invalid passwords)
- [ ] Test callsign validation and persistence
- [ ] Verify audio quality is intelligible with no artifacts
- [ ] Measure end-to-end latency (target: <300ms on local network)
- [ ] Test rapid PTT press/release handling
- [ ] Test max transmission timeout enforcement (120s)
- [ ] Test microphone permission denied handling
- [ ] Test disconnect during transmission (cleanup verification)
- [ ] Test network interruption recovery

## Context

### Key Design Decisions
1. **Callsign:** Users enter in voice UI, validated and stored in localStorage
2. **Auth:** Global password in config for transmit (listen-only without auth)
3. **Modules:** All transcoded modules support voice chat (auto-detected)
4. **Concurrency:** Single active transmitter per module (first wins, FIFO)
5. **Mobile:** Background audio via Media Session API + Wake Lock

### Virtual Client Representation
- Web transmissions appear as USRP protocol clients
- Callsign: as entered by user (no suffix)
- Logs: `[WEB] KC1XXX started stream on module A`
- NNG events tagged with `source: "web"`

### Configuration Files
**Reflector (`config.inc`):**
```ini
[voice]
enable = true
nng_addr = tcp://127.0.0.1:5556
```

**Dashboard (`config.yaml`):**
```yaml
voice:
  enable: true
  reflector_addr: tcp://127.0.0.1:5556
  transmit_password: ""  # Empty = no password
  max_clients: 100
  opus_bitrate: 12000
  max_tx_duration: 120
```

### WebSocket Protocol
```json
// Client → Server
{"type": "voice_start", "module": "A", "callsign": "KC1XXX"}
{"type": "voice_stop"}
{"type": "ptt_press", "password": "xxx"}
{"type": "ptt_release"}
{"type": "audio_data", "opus": "<base64>"}

// Server → Client
{"type": "voice_state", "state": "listening|transmitting|rx_busy"}
{"type": "audio_data", "opus": "<base64>", "from": "KC1XXX"}
{"type": "ptt_denied", "reason": "active_talker", "active_talker": "KC1XXX"}
```

### State Machine
```
IDLE → [module select] → LISTENING
LISTENING → [PTT press + no active talker] → TRANSMITTING
TRANSMITTING → [PTT release] → LISTENING
LISTENING → [active talker detected] → RX_BUSY (PTT locked)
RX_BUSY → [talker finishes] → LISTENING
```

### Technical Targets
- **Latency:** <300ms end-to-end (local network)
- **Bandwidth:** ~1.5 KB/s per direction (Opus @ 12kbps)
- **Audio Quality:** Intelligible speech, no artifacts
- **Mobile:** iOS 15+ Safari, Android 10+ Chrome
- **Scalability:** 50 concurrent listeners per module

### Files to Create
**Reflector (C++):**
- `src/NNGVoiceStream.h`
- `src/NNGVoiceStream.cpp`

**Dashboard Backend (Go):**
- `internal/voice/nng.go`
- `internal/voice/session.go`

**Dashboard Frontend (Vue.js):**
- `web/src/components/VoiceChat/VoiceChat.vue`
- `web/src/components/VoiceChat/VoiceEngine.vue`
- `web/src/components/VoiceChat/PTTButton.vue`
- `web/src/stores/voice.ts`

### Files to Modify
**Reflector:**
- `src/configure.h` (add voice config)
- `src/Reflector.cpp` (initialize voice stream)
- `src/PacketStream.cpp` (audio tap)

**Dashboard:**
- `internal/server/server.go` (add voice handler)
- `internal/server/hub.go` (voice sessions)
- `config.yaml` (voice config)
- `web/package.json` (add deps)
- `web/src/layouts/AppShell.vue` (integrate UI)

### References
- Existing audio code: `src/AudioRecorder.h/cpp`
- Existing NNG code: `src/NNGPublisher.h/cpp`
- Existing player: `web/src/components/AudioPlayer/`
- Full plan: `.opencode/plans/webvoiceclient.md`

### Dependencies to Add
```json
{
  "opus-recorder": "^8.0.5",
  "libopus.js": "^1.0.0"
}
```

### Known Risks
1. **iOS Safari quirks:** Background audio may require special handling
2. **Echo/feedback:** Mitigate with echoCancellation flag and half-duplex
3. **Network interruption:** Implement timeouts and cleanup
4. **Concurrent PTT:** Server-side locking with first-wins policy
5. **Password security:** Plain text in config (acceptable for v1)

---

## Ralph Instructions

1. Work on the next incomplete criterion (marked [ ])
2. Check off completed criteria (change [ ] to [x])
3. Run tests after significant changes (`tilt ci`)
4. Commit your changes frequently with clear messages
5. When ALL criteria are [x], say: `RALPH_COMPLETE`
6. If stuck on the same issue 3+ times, say: `RALPH_GUTTER`
7. Read `.opencode/plans/webvoiceclient.md` for detailed implementation guidance

### Phase Progression Notes
- Complete Phase 1 before starting Phase 2 (dependency: NNG endpoint must exist)
- Complete Phase 2 before starting Phase 3 (dependency: WebSocket bridge needed)
- Complete Phase 3 before starting Phase 4 (dependency: RX must work for half-duplex)
- Complete Phase 4 before starting Phase 5 (dependency: frontend must send audio)
- Phases 6 and 6.5 can be done in parallel or incrementally

### Testing Strategy
- After each phase, verify the phase deliverable works
- Run `tilt ci` after significant code changes
- Manual testing required for audio quality and UX
- Mobile testing should be done on real devices (iOS Safari, Android Chrome)

### Success Indicators
- Users can select module and hear live audio (Phase 3)
- Users can press PTT and transmit audio (Phase 4)
- Other users hear web transmissions (Phase 5)
- All features polished and mobile-friendly (Phases 6+)
- No regressions in existing dashboard functionality
- CI passes consistently
