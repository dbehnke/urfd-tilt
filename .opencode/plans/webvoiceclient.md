# Live Voice Chat Implementation Plan

## Overview

This document outlines the plan for implementing live listen and PTT (Push-to-Talk) functionality between the urfd-nng-dashboard web client and the URFD reflector module. Users will be able to listen to live audio from transcoded reflector modules and transmit back using a push-to-talk interface in half-duplex mode.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Mobile/Desktop Browser                    │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  VoiceChat.vue                                       │  │
│  │  • Callsign input + validation                       │  │
│  │  • Password prompt (first PTT)                       │  │
│  │  • Module selector (transcoded only)                 │  │
│  │  • PTT button (locked if stream active)              │  │
│  │  • Active talker display                             │  │
│  │  • Wake Lock + Media Session (mobile)                │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  VoiceEngine.vue                                     │  │
│  │  • opus-recorder.js (TX) + codec2.js (RX)            │  │
│  │  • Background audio support                          │  │
│  │  • iOS audio context management                      │  │
│  └──────────────────────────────────────────────────────┘  │
│         ↕ WebSocket: {"type": "ptt_press",                 │
│            "password": "xxx", "callsign": "KC1XXX"}         │
└─────────────────────────────────────────────────────────────┘
                            ↕
┌─────────────────────────────────────────────────────────────┐
│          Dashboard Backend (Go)                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Voice Session Manager                               │  │
│  │  • Password validation (global config)               │  │
│  │  • Per-module active transmitter tracking            │  │
│  │  • PTT request queuing/rejection                     │  │
│  │  • Session timeout enforcement                       │  │
│  │  • Opus frame routing                                │  │
│  └──────────────────────────────────────────────────────┘  │
│                    ↕ NNG PAIR/REQ-REP                       │
└─────────────────────────────────────────────────────────────┘
                            ↕
┌─────────────────────────────────────────────────────────────┐
│              URFD Reflector (C++)                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  CNNGVoiceStream                                     │  │
│  │  • Per-module audio tap (transcoded modules only)    │  │
│  │  • PCM → Opus encode (RX path)                       │  │
│  │  • Opus → PCM decode (TX path)                       │  │
│  │  • Stream injection via virtual USRP client          │  │
│  │  • Single active stream enforcement                  │  │
│  │  • Tag streams with source=web metadata             │  │
│  └──────────────────────────────────────────────────────┘  │
│                    ↕ CPacketStream                          │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Module A/B/C/D (transcoded)                         │  │
│  │  • Normal reflector operation                        │  │
│  │  • Web streams appear as USRP clients                │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Key Design Decisions

### 1. Callsign Handling
- **Decision:** Users enter callsign directly in voice UI
- **Implementation:** Add callsign input field to VoiceChat component
- **Validation:** Basic format check (alphanumeric + dash, 3-10 chars)
- **Storage:** Save in localStorage for convenience (pre-fill on return)

### 2. Transmission Access Control
- **Decision:** Simple global password for transmit permission
- **Configuration:**
  ```yaml
  voice:
    transmit_password: "your-secret-here"  # Empty = no password required
  ```
- **Flow:** 
  - Listen mode: No authentication required
  - Transmit mode: Prompt for password on first PTT press
  - Password stored in memory for session duration

### 3. Module Access
- **Decision:** All transcoded modules support voice chat
- **Implementation:** Dashboard queries reflector for active modules with transcoding enabled
- **UI:** Module selector shows only eligible modules (those with CodecStream active)

### 4. Concurrent Transmission Handling
- **Decision:** Single active stream per module (first wins, others rejected)
- **Server logic:**
  - Dashboard tracks active transmitter per module
  - New PTT requests denied if stream active
  - Return `ptt_denied` with reason and active talker info
- **Client feedback:**
  - Toast notification: "KC1XXX is currently transmitting"
  - Visual indicator showing active talker
  - Auto-retry option when stream closes

### 5. Mobile Background Audio
- **Solution:** Media Session API + Wake Lock API
- **Implementation:**
  ```javascript
  // Keep audio playing in background
  navigator.mediaSession.setActionHandler('pause', () => {
    // Allow pause but maintain connection
  });
  
  // Prevent screen sleep during active session
  const wakeLock = await navigator.wakeLock.request('screen');
  ```
- **Features:**
  - Lock screen controls (play/pause, session info)
  - Show active talker in notification
  - Maintain WebSocket during background
  - Release wake lock when voice session ends

### 6. Audio Format & Transport
- **Codec:** Opus (12kbps, 8kHz mono, 20ms frames)
- **Transport:** WebSocket binary frames over existing connection
- **Receive:** Opus frames decoded via codec2.js WebAssembly
- **Transmit:** Browser mic → opus-recorder.js → WebSocket

## Component Breakdown

### 1. Reflector Module Changes (C++)

**New Component: CNNGVoiceStream**
- **Location:** `src/NNGVoiceStream.h/cpp`
- **Responsibilities:**
  - Subscribe to live audio from selected module's `CPacketStream`
  - Encode PCM audio (8kHz mono) to Opus frames
  - Send Opus frames via NNG to dashboard
  - Receive Opus frames from dashboard, decode to PCM
  - Inject received PCM as new stream into reflector
  - Track active talker state for half-duplex enforcement

**Key Implementation Details:**
- **NNG Pattern:** PAIR protocol (separate from existing PUB/SUB on port 5555)
- **Audio Tap:** Hook into `PacketStream::Push()` or `RouterThread` to capture live PCM
- **Opus Encoding:** Reuse libopus integration from `CAudioRecorder`
  - Sample rate: 8kHz mono
  - Bitrate: 12kbps
  - Frame size: 20ms (160 samples)
- **Stream Injection:** Use existing `Reflector::OpenStream()` API
  - Assign virtual client/user for web PTT transmissions
  - Generate stream ID and route to selected module
  - Tag with `source=web` metadata
- **Configuration:**
  ```ini
  [voice]
  enable = true
  nng_addr = tcp://127.0.0.1:5556
  # Modules auto-detected from transcoding config
  ```

**Modified Components:**
- `PacketStream.cpp` - Add audio tap observer pattern
- `Reflector.cpp` - Initialize CNNGVoiceStream if enabled
- `configure.h` - Add voice chat config section

**Virtual Client Representation:**
- **Protocol:** Reuse USRP protocol (already supports software clients)
- **Callsign format:** As entered by user (no suffix needed)
- **Source identification:** 
  - Add metadata field: `source=web` in NNG messages
  - Logs show: `[WEB] KC1XXX started stream on module A`
  - Dashboard hearing events tagged with `source: "web"`

---

### 2. Dashboard Backend Changes (Go)

**New Component: Voice Handler**
- **Location:** `internal/voice/voice.go`
- **Responsibilities:**
  - Manage NNG connection to reflector's voice endpoint
  - Handle WebSocket voice control messages
  - Route Opus frames bidirectionally
  - Enforce half-duplex state machine
  - Track which clients are listening to which modules

**Voice Session State Machine:**
```
IDLE → [module select] → LISTENING
LISTENING → [PTT press + no active talker] → TRANSMITTING
TRANSMITTING → [PTT release] → LISTENING
LISTENING → [active talker detected] → RX_BUSY (PTT locked)
RX_BUSY → [talker finishes] → LISTENING
```

**WebSocket Message Protocol:**
```json
// Client → Server
{"type": "voice_start", "module": "A", "callsign": "KC1XXX"}
{"type": "voice_stop"}
{"type": "ptt_press", "password": "xxx"}  // password only on first press
{"type": "ptt_release"}
{"type": "audio_data", "opus": "<base64>"}

// Server → Client
{"type": "voice_state", "state": "listening|transmitting|rx_busy"}
{"type": "audio_data", "opus": "<base64>", "from": "KC1XXX"}
{"type": "ptt_denied", "reason": "active_talker", "active_talker": "KC1XXX"}
{"type": "auth_required"}
{"type": "auth_failed", "reason": "invalid_password"}
```

**Password Authentication Flow:**

Server-side (`voice/session.go`):
```go
func (s *Session) HandlePTTPress(password, callsign string) error {
    if !s.authenticated && s.config.RequirePassword {
        if password != s.config.TransmitPassword {
            return errors.New("invalid password")
        }
        s.authenticated = true
    }
    
    // Check for active stream on module
    if s.hub.HasActiveTransmitter(s.module) {
        return errors.New("module busy")
    }
    
    s.hub.SetActiveTransmitter(s.module, callsign)
    // ... continue with PTT logic
}
```

**Key Files to Create/Modify:**
- `internal/server/server.go` - Add `/ws/voice` endpoint
- `internal/server/hub.go` - Add voice session management
- New: `internal/voice/nng.go` - NNG voice client
- New: `internal/voice/session.go` - Session state machine
- `config.yaml` - Add voice configuration section

**Configuration Example:**
```yaml
voice:
  enable: true
  reflector_addr: tcp://127.0.0.1:5556
  transmit_password: ""  # Empty = no password required
  max_clients: 100
  opus_bitrate: 12000
  max_tx_duration: 120  # seconds, prevent stuck transmissions
```

---

### 3. Dashboard Frontend Changes (Vue.js)

**New Components:**

**A. VoiceChat.vue** (Main component)
- **Location:** `web/src/components/VoiceChat/VoiceChat.vue`
- **Features:**
  - Callsign input with validation and localStorage
  - Module selector dropdown (transcoded modules only)
  - PTT button (press & hold or click to toggle)
  - Password prompt dialog (first PTT press)
  - Voice state indicator (idle/listening/transmitting/busy)
  - Active talker display (callsign + visual indicator)
  - Audio level meter (RX and TX)
  - Connection status
- **Layout:** Floating panel or bottom sheet (mobile-friendly)

**B. VoiceEngine.vue** (Audio processing)
- **Location:** `web/src/components/VoiceChat/VoiceEngine.vue`
- **Responsibilities:**
  - Microphone access via `getUserMedia()`
  - Opus encoding via `opus-recorder.js`
  - Opus decoding via `codec2.js` WebAssembly
  - Web Audio API playback with gain control
  - Real-time audio visualization
  - Echo cancellation configuration
  - iOS audio context resume handling
  - Background audio support (Media Session API)

**C. PTTButton.vue** (Input control)
- **Location:** `web/src/components/VoiceChat/PTTButton.vue`
- **Features:**
  - Touch/click/spacebar support
  - Visual feedback (color changes on state)
  - Disabled state during RX
  - Haptic feedback (mobile)

**New Pinia Store:**
- **Location:** `web/src/stores/voice.ts`
- **State:**
  ```typescript
  {
    connected: boolean
    module: string | null
    state: 'idle' | 'listening' | 'transmitting' | 'rx_busy'
    activeTalker: { callsign: string, module: string } | null
    micPermission: boolean
    audioLevel: { rx: number, tx: number }
    authenticated: boolean
    callsign: string
  }
  ```
- **Actions:**
  - `startVoice(module: string, callsign: string)`
  - `stopVoice()`
  - `pressPTT(password?: string)`
  - `releasePTT()`
  - `sendAudioData(opus: Uint8Array)`
  - `receiveAudioData(opus: Uint8Array, from: string)`

**Dependencies to Add:**
```json
{
  "opus-recorder": "^8.0.5",
  "libopus.js": "^1.0.0"
}
```

**Integration Points:**
- Add voice chat button to `AppShell.vue` (always accessible)
- Optional: Add voice indicator overlay to `LastHeard.vue`

**localStorage Schema:**
```json
{
  "voice_callsign": "KC1XXX",
  "voice_last_module": "A"
  // Note: auth token NOT persisted (session only)
}
```

---

## Mobile Optimization

### Background Audio Support
- **Media Session API:** Lock screen controls and background playback
- **Wake Lock API:** Prevent screen sleep during active session
- **iOS-specific handling:**
  ```javascript
  // iOS requires user gesture to unlock audio context
  const audioContext = new AudioContext();
  document.addEventListener('touchstart', () => {
    if (audioContext.state === 'suspended') {
      audioContext.resume();
    }
  }, { once: true });
  ```

### Features
- Lock screen controls (play/pause, session info)
- Show active talker in notification
- Maintain WebSocket during background
- Release wake lock when voice session ends
- Handle audio interruptions (calls, alarms)
- Auto-reconnect WebSocket on app resume

---

## Implementation Phases

### Phase 1: Reflector Audio Streaming (Receive Only)
**Goal:** Web client can listen to live audio from selected module

**Tasks:**
1. Create `CNNGVoiceStream` class with audio tap capability
2. Implement Opus encoding for live audio
3. Add NNG voice endpoint to reflector (port 5556)
4. Add voice configuration to `configure.h`
5. Test with `nc` or simple Python client

**Deliverable:** Reflector streams live Opus audio via NNG

**Files Created/Modified:**
- `src/NNGVoiceStream.h` (new)
- `src/NNGVoiceStream.cpp` (new)
- `src/Reflector.cpp` (modified)
- `src/PacketStream.cpp` (modified)
- `src/configure.h` (modified)

---

### Phase 2: Dashboard Voice Bridge (Receive Path)
**Goal:** Dashboard receives audio and forwards to web clients

**Tasks:**
1. Create `internal/voice` package with NNG client
2. Add WebSocket voice handler to `server.go`
3. Implement voice session management (module selection)
4. Add configuration options to `config.yaml`
5. Implement module filtering logic

**Deliverable:** WebSocket endpoint streams Opus to browser

**Files Created/Modified:**
- `internal/voice/nng.go` (new)
- `internal/voice/session.go` (new)
- `internal/server/server.go` (modified)
- `internal/server/hub.go` (modified)
- `config.yaml` (modified)

---

### Phase 3: Frontend Voice Receiver
**Goal:** Web client plays live audio

**Tasks:**
1. Add Opus decoder (libopus.js) to project
2. Create `VoiceEngine.vue` with Web Audio API
3. Create `VoiceChat.vue` UI component
4. Create `PTTButton.vue` component
5. Create `voice.ts` Pinia store
6. Integrate into `AppShell.vue`
7. Implement callsign input and validation

**Deliverable:** Users can hear live audio from selected module

**Files Created/Modified:**
- `web/src/components/VoiceChat/VoiceEngine.vue` (new)
- `web/src/components/VoiceChat/VoiceChat.vue` (new)
- `web/src/components/VoiceChat/PTTButton.vue` (new)
- `web/src/stores/voice.ts` (new)
- `web/src/layouts/AppShell.vue` (modified)
- `web/package.json` (modified)

---

### Phase 4: Frontend PTT Transmit
**Goal:** Web client can transmit audio back

**Tasks:**
1. Add microphone permission handling
2. Integrate `opus-recorder.js` for encoding
3. Implement PTT button with state management
4. Add half-duplex logic (lock PTT during RX)
5. Wire up WebSocket audio upload
6. Implement password prompt dialog
7. Add password authentication flow

**Deliverable:** Users can transmit via PTT (half-duplex)

**Files Modified:**
- `web/src/components/VoiceChat/VoiceEngine.vue`
- `web/src/components/VoiceChat/VoiceChat.vue`
- `web/src/components/VoiceChat/PTTButton.vue`
- `web/src/stores/voice.ts`

---

### Phase 5: Reflector Audio Injection (Transmit Path)
**Goal:** Dashboard audio appears as virtual client on reflector

**Tasks:**
1. Implement Opus decode in `CNNGVoiceStream`
2. Create virtual client/user for web transmissions
3. Implement stream injection via `OpenStream()`
4. Add callsign/user metadata handling
5. Add `source=web` tagging
6. Implement single active stream enforcement
7. Test end-to-end voice communication

**Deliverable:** Full duplex communication working

**Files Modified:**
- `src/NNGVoiceStream.cpp`
- `src/Reflector.cpp`

---

### Phase 6: Polish & Features
**Goal:** Production-ready experience

**Tasks:**
1. Add audio level meters and visualization
2. Implement AGC/noise gate on TX
3. Add echo cancellation hints
4. Improve mobile UX (prevent screen sleep)
5. Add voice activity detection (optional)
6. Connection recovery handling
7. Logging and diagnostics
8. Add session timeout enforcement
9. Improve error messages and user feedback

**Deliverable:** Professional, reliable voice chat

---

### Phase 6.5: Authentication & Mobile Support
**Goal:** Secure transmit access and excellent mobile UX

**Tasks:**
1. Add password authentication to voice handler
2. Implement Media Session API for background audio
3. Add Wake Lock API for screen management
4. Handle iOS audio context quirks
5. Add persistent notification with talker info
6. Implement auto-reconnect on app resume
7. Add data usage indicator for mobile users

**Deliverable:** Secure, mobile-friendly voice chat

**Files Modified:**
- `internal/voice/session.go`
- `web/src/components/VoiceChat/VoiceEngine.vue`
- `web/src/stores/voice.ts`

---

## Technical Considerations

### Half-Duplex Enforcement
- **Server-side:** Dashboard tracks active talkers per module from NNG events
- **Client-side:** UI disables PTT button when receiving audio
- **Grace period:** 200ms after RX ends before allowing TX

### Audio Latency Targets
- **Opus encoding:** ~20ms (frame size)
- **Network transit:** <50ms (local) to ~200ms (internet)
- **WebSocket overhead:** ~10-20ms
- **Opus decoding:** ~5-10ms
- **Total target:** <300ms end-to-end

### Bandwidth Estimation
- **Opus @ 12kbps:** ~1.5 KB/s per direction
- **WebSocket overhead:** ~10%
- **Per active session:** ~3.3 KB/s bidirectional
- **100 concurrent listeners:** ~150 KB/s downstream

### Security & Authentication
- **Callsign verification:** Require callsign entry, validate format
- **PTT permissions:** Global password in config (phase 1)
- **Future enhancement:** Per-user credentials
- **Rate limiting:** Prevent audio spam/abuse
- **TLS:** Secure WebSocket (wss://) in production

---

## Testing Strategy

### Functional Testing
- [ ] Listen to live audio from each transcoded module
- [ ] Enter callsign and password, press PTT, transmit audio
- [ ] Verify other users hear transmitted audio
- [ ] Second user PTT denied while first transmits
- [ ] Stream cleanup after transmission ends
- [ ] Password authentication (valid/invalid)
- [ ] Module selector shows only transcoded modules
- [ ] Callsign validation and localStorage persistence

### Mobile Testing
- [ ] Background audio playback (iOS Safari 15+)
- [ ] Background audio playback (Android Chrome)
- [ ] Lock screen controls appear and function
- [ ] Wake lock prevents screen sleep
- [ ] WebSocket reconnect after app resume
- [ ] Handle phone call interruption
- [ ] Audio context resume after user gesture (iOS)
- [ ] Data usage reasonable (<2MB/min)

### Edge Cases
- [ ] Disconnect during transmission (cleanup)
- [ ] Network interruption recovery
- [ ] Multiple modules active simultaneously (no crosstalk)
- [ ] Rapid PTT press/release
- [ ] Max transmission timeout enforced (120s)
- [ ] Empty/invalid callsign rejected
- [ ] Microphone permission denied handling
- [ ] Browser without Opus/WebAssembly support

### Integration Tests
- [ ] NNG communication (reflector ↔ dashboard)
- [ ] WebSocket binary frame handling
- [ ] Audio buffer management
- [ ] Opus encoding/decoding round-trip
- [ ] Voice session state machine
- [ ] Half-duplex logic

### Performance Testing
- [ ] Measure end-to-end latency
- [ ] CPU usage with 10/50/100 concurrent clients
- [ ] Memory leak detection (long-running sessions)
- [ ] Network bandwidth usage verification

---

## Risk Assessment & Mitigation

### Risk 1: Multiple Users Press PTT Simultaneously
- **Mitigation:** Server-side locking with first-wins policy
- **User feedback:** Immediate rejection message with active talker shown
- **Retry:** Auto-enable PTT when stream closes

### Risk 2: iOS Safari Background Audio Quirks
- **Mitigation:** Extensive iOS-specific testing
- **Fallback:** Warn users to keep app in foreground if background fails
- **Documentation:** Clear mobile browser compatibility matrix

### Risk 3: Network Interruption During Transmission
- **Mitigation:** 
  - Client-side timeout (5s no ack → release PTT)
  - Server-side timeout (max 120s per config)
  - Auto-cleanup of stale sessions
- **User feedback:** Connection status indicator

### Risk 4: Audio Feedback Loop (Echo)
- **Mitigation:**
  - Browser echo cancellation (`echoCancellation: true` in getUserMedia)
  - Server enforces half-duplex (can't RX while TX)
  - Optional: Add simple VOX delay

### Risk 5: Password Security
- **Current:** Plain text in config (acceptable for community use)
- **Future Enhancement:** 
  - Per-user credentials
  - Integration with existing auth systems
  - Rate limiting on failed attempts

---

## Success Metrics

1. **Latency:** <300ms end-to-end (local network)
2. **Audio Quality:** Intelligible speech, no artifacts
3. **Reliability:** >99% uptime for 24-hour test
4. **Mobile:** Background audio works on iOS 15+ and Android 10+
5. **Scalability:** Support 50 concurrent listeners per module
6. **Security:** No unauthorized transmissions

---

## Future Enhancements

1. **Multi-user Authentication:**
   - Per-user accounts with callsign validation
   - Integration with QRZ.com for verification
   - Role-based permissions (listen-only vs transmit)

2. **Advanced Audio Features:**
   - Voice activity detection (VAD)
   - Automatic gain control (AGC)
   - Noise suppression
   - Audio compressor/limiter

3. **Enhanced UX:**
   - Visual waveform display
   - Recent talkers list
   - Favorites/quick module switching
   - Keyboard shortcuts

4. **Analytics:**
   - Usage statistics
   - Audio quality metrics
   - Connection reliability tracking

5. **Advanced Mobile:**
   - Native iOS/Android apps
   - CarPlay/Android Auto integration
   - Bluetooth headset PTT support

---

## References

- **Existing Code:**
  - Audio recording: `src/AudioRecorder.h/cpp`
  - NNG publisher: `src/NNGPublisher.h/cpp`
  - Packet streams: `src/PacketStream.h/cpp`
  - Dashboard audio player: `web/src/components/AudioPlayer/`

- **Technologies:**
  - Opus codec: https://opus-codec.org/
  - NNG: https://nng.nanomsg.org/
  - Web Audio API: https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API
  - Media Session API: https://developer.mozilla.org/en-US/docs/Web/API/Media_Session_API
  - Wake Lock API: https://developer.mozilla.org/en-US/docs/Web/API/Screen_Wake_Lock_API

- **Libraries:**
  - opus-recorder: https://github.com/chris-rudmin/opus-recorder
  - libopus.js: https://github.com/kazuki/libopus.js
  - codec2.js: https://github.com/GoogleChromeLabs/web-audio-samples/tree/main/audio-worklet
