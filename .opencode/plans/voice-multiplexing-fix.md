---
task: Fix Voice Chat Multi-Client Bugs and Add Real-Time Audio Multiplexing
test_command: "cd src/urfd-nng-dashboard && go test ./internal/voice/... -v"
---

# Voice Chat Multiplexing Fix - Implementation Plan

## ⚠️ CRITICAL: Test-Driven Development Required

**YOU MUST WRITE TESTS FIRST BEFORE ANY IMPLEMENTATION CODE!**

This is a complex, multi-component fix involving Go backend, C++ reflector, and real-time audio. Writing tests first ensures:
- Correct behavior is defined before implementation
- Regressions are caught immediately
- Edge cases are considered upfront
- Code is testable by design

### TDD Workflow for This Project:
1. ✅ Write failing test(s) for the feature/fix
2. ✅ Run tests to verify they fail (red)
3. ✅ Write minimal code to make tests pass (green)
4. ✅ Refactor if needed while keeping tests green
5. ✅ Commit changes with tests + implementation together

### Test Categories:
- **Unit Tests**: Individual functions/methods (Go: `*_test.go`, C++: Google Test)
- **Integration Tests**: Component interaction (e.g., pool + session)
- **End-to-End Tests**: Full flow (browser → dashboard → urfd → back)

---

## 🧭 Context Window Management

### Progress Tracking File
**Location**: `.opencode/plans/voice-multiplexing-progress.md`

**When to Update**:
- After completing each checkbox task
- Before switching contexts or taking a break
- When hitting a blocker or error

**What to Include**:
- Current phase and task number
- Completed checkboxes (copy from this file)
- Current work-in-progress details
- Any blockers or decisions needed
- Next immediate step
- Recent commit SHAs for reference

### Checkpoint Strategy
After completing each phase:
1. Create git commit with all phase changes
2. Update progress file with checkpoint marker
3. Run verification tests
4. Document any deviations from plan

**If context window is filling up**:
1. Save current progress to progress file
2. Commit work-in-progress with clear message
3. Create new session and load progress file
4. Continue from checkpoint

---

## Executive Summary

### Problem Statement
The URFD dashboard's web-based voice chat has critical bugs when multiple clients connect:
1. **Multi-client connection bug**: When 2+ web clients connect to same module, only one can transmit at a time, recordings fail after first transmission
2. **No real-time audio**: Clients cannot hear each other's transmissions
3. **Connection conflicts**: After second client connects, first client must reload

### Root Cause
1. **NNG PAIR 1:1 Limitation**: Each WebSocket session created its own NNG PAIR socket to urfd. Since PAIR only supports 1:1 connections, multiple sessions conflicted.
2. **Virtual Client Lifecycle**: urfd created and destroyed virtual clients on **every PTT press/release** instead of maintaining them for the entire voice session.

### Solution Architecture

**Before (Broken)**:
```
Browser (KF8S)  --WebSocket--> Session #1 --[NNG PAIR]--> urfd (conflict!)
Browser (W8EAP) --WebSocket--> Session #2 --[NNG PAIR]--> urfd (conflict!)
```

**After (Fixed)**:
```
Browser (KF8S)  --WebSocket--> Session #1 ──┐
Browser (W8EAP) --WebSocket--> Session #2 ──┼──> SharedVoiceClient --[NNG PAIR]--> urfd
Browser (...)   --WebSocket--> Session #3 ──┘
         ↓                                              ↓
    Real-time audio forwarding              Recording only
    (Works without urfd)                    (Persistent virtual clients)
```

### Key Features
✅ **Half-duplex enforcement**: Dashboard enforces (primary), urfd defends (secondary)
✅ **Real-time audio**: Sessions forward audio to each other directly
✅ **Recording**: urfd records (no dashboard buffering/fallback)
✅ **Persistent virtual clients**: Created once per voice session (not per PTT)
✅ **Graceful degradation**: Audio works between browsers even if urfd disconnected

---

## Phase 1: Dashboard Real-Time Audio Multiplexing

**Goal**: Enable browsers to hear each other WITHOUT urfd round-trip
**Estimated Time**: 6-8 hours
**Test File**: `src/urfd-nng-dashboard/internal/voice/pool_test.go`

### Tasks

#### 1.1: Test Setup and Half-Duplex Tests (1 hour)
- [ ] Create `src/urfd-nng-dashboard/internal/voice/pool_test.go`
- [ ] Write test: `TestRequestPTT_FirstCaller_Granted`
  - Setup: No active talker
  - Action: Call RequestPTT("session1", "KF8S")
  - Assert: Returns nil, activeTalker = "KF8S"
- [ ] Write test: `TestRequestPTT_SecondCaller_Denied`
  - Setup: activeTalker = "KF8S"
  - Action: Call RequestPTT("session2", "W8EAP")
  - Assert: Returns error "PTT denied - KF8S is transmitting"
- [ ] Write test: `TestReleasePTT_ClearsActiveTalker`
  - Setup: activeTalker = "KF8S"
  - Action: Call ReleasePTT("session1", "KF8S")
  - Assert: activeTalker = ""
- [ ] Write test: `TestReleasePTT_WrongCallsign_NoEffect`
  - Setup: activeTalker = "KF8S"
  - Action: Call ReleasePTT("session2", "W8EAP")
  - Assert: activeTalker still = "KF8S"
- [ ] Run tests: `cd src/urfd-nng-dashboard && go test ./internal/voice/... -v -run TestRequestPTT`
- [ ] Verify all tests FAIL (red) - no implementation yet

#### 1.2: Implement Half-Duplex Logic in pool.go (1.5 hours)
- [ ] Open `src/urfd-nng-dashboard/internal/voice/pool.go`
- [ ] Add fields to `SharedVoiceClient` struct:
  ```go
  activeTalker    string              // callsign of current transmitter (empty = none)
  activeTalkerMu  sync.RWMutex        // protects activeTalker
  sessions        map[string]*VoiceSession  // key: sessionID
  sessionsMu      sync.RWMutex        // protects sessions map
  ```
- [ ] Implement `RequestPTT(sessionID, callsign string) error` method:
  ```go
  // Lock for write, check activeTalker
  // If empty: set to callsign, log "PTT granted to %s", return nil
  // If occupied: log "PTT denied for %s (active: %s)", return error
  ```
- [ ] Implement `ReleasePTT(sessionID, callsign string)` method:
  ```go
  // Lock for write, clear activeTalker if matches callsign
  // Log "PTT released by %s"
  ```
- [ ] Add always-on debug logging to both methods
- [ ] Run tests: `go test ./internal/voice/... -v -run TestRequestPTT`
- [ ] Verify all tests PASS (green)

#### 1.3: Session Management Tests (1 hour)
- [ ] Write test: `TestRegisterSession_AddsToMap`
- [ ] Write test: `TestUnregisterSession_RemovesFromMap`
- [ ] Write test: `TestUnregisterSession_ClearsActiveTalkerIfMatch`
- [ ] Write test: `TestRegisterSession_Concurrent_ThreadSafe`
  - Use goroutines to register 100 sessions concurrently
  - Assert: all sessions registered, no race conditions
- [ ] Run tests: `go test ./internal/voice/... -v -run TestRegisterSession -race`
- [ ] Verify all tests FAIL (red)

#### 1.4: Implement Session Management in pool.go (1 hour)
- [ ] Implement `RegisterSession(sessionID string, session *VoiceSession)`:
  ```go
  // Lock sessionsMu for write
  // Add to sessions map
  // Log "Session registered: %s (%s on module %s)"
  ```
- [ ] Implement `UnregisterSession(sessionID string)`:
  ```go
  // Lock sessionsMu for write
  // Get session from map, check if was activeTalker
  // If yes: call ReleasePTT
  // Remove from map
  // Log "Session unregistered: %s"
  ```
- [ ] Initialize sessions map in NewSharedVoiceClient constructor
- [ ] Run tests: `go test ./internal/voice/... -v -run TestRegisterSession -race`
- [ ] Verify all tests PASS (green)

#### 1.5: Audio Broadcasting Tests (1 hour)
- [ ] Write test: `TestBroadcastAudioToSessions_SameModule_ReceivesAudio`
  - Setup: 3 sessions on module "A", 1 session on module "D"
  - Action: BroadcastAudioToSessions(data, "session1", "KF8S", "A")
  - Assert: sessions 2 & 3 (module A) receive audio, session 4 (module D) does NOT
- [ ] Write test: `TestBroadcastAudioToSessions_ExcludesSender`
  - Assert: session1 does NOT receive its own audio back
- [ ] Write test: `TestBroadcastAudioToSessions_EmptySessions_NoError`
- [ ] Run tests: `go test ./internal/voice/... -v -run TestBroadcast`
- [ ] Verify all tests FAIL (red)

#### 1.6: Implement Audio Broadcasting in pool.go (1.5 hours)
- [ ] Implement `BroadcastAudioToSessions(opusData []byte, fromSessionID, fromCallsign, module string)`:
  ```go
  // Lock sessionsMu for read
  // Iterate sessions map
  // For each session:
  //   - Skip if sessionID == fromSessionID (don't echo to sender)
  //   - Skip if session.module != module (module isolation)
  //   - Call session.SendAudioFromPeer(opusData, fromCallsign)
  //   - Handle errors gracefully (session might be closing)
  // Log "Broadcasting audio from %s to %d peers on module %s"
  ```
- [ ] Add error handling for closed/closing sessions
- [ ] Run tests: `go test ./internal/voice/... -v -run TestBroadcast`
- [ ] Verify all tests PASS (green)

#### 1.7: Session Handler Tests (1 hour)
- [ ] Create `src/urfd-nng-dashboard/internal/voice/session_test.go`
- [ ] Write test: `TestHandleVoiceStart_RegistersSession`
- [ ] Write test: `TestHandlePTTPress_Granted_SendsToUrfd`
- [ ] Write test: `TestHandlePTTPress_Denied_SendsPttDeniedMessage`
- [ ] Write test: `TestHandleAudioData_BroadcastsAndSendsToUrfd`
- [ ] Run tests: `go test ./internal/voice/... -v -run TestHandle`
- [ ] Verify all tests FAIL (red)

#### 1.8: Update session.go with Multiplexing Logic (2 hours)
- [ ] Open `src/urfd-nng-dashboard/internal/voice/session.go`
- [ ] Add `sessionID string` field to `VoiceSession` struct
- [ ] Update `handleVoiceStart()`:
  ```go
  // Generate sessionID: uuid.New().String()
  // Call sharedClient.RegisterSession(sessionID, s)
  // Send voice_session_start to urfd (if connected, don't fail if down)
  // Log "Voice session started: %s (%s on module %s)"
  ```
- [ ] Update `handleVoiceStop()`:
  ```go
  // Call sharedClient.UnregisterSession(sessionID)
  // Send voice_session_stop to urfd (if connected)
  // Log "Voice session stopped: %s"
  ```
- [ ] Update `handlePTTPress()`:
  ```go
  // err := sharedClient.RequestPTT(sessionID, callsign)
  // If err != nil:
  //   - Send {"type":"ptt_denied","reason":"..."}
  //   - Log "PTT denied for %s: %v"
  //   - Return early
  // If granted:
  //   - Send ptt_start to urfd (if connected, log warning if down)
  //   - Log "PTT pressed by %s"
  ```
- [ ] Update `handlePTTRelease()`:
  ```go
  // Call sharedClient.ReleasePTT(sessionID, callsign)
  // Send ptt_stop to urfd (if connected)
  // Log "PTT released by %s"
  ```
- [ ] Update `handleAudioData()`:
  ```go
  // NEW: sharedClient.BroadcastAudioToSessions(opusData, sessionID, callsign, module)
  // EXISTING: Send audio_data to urfd (if connected, log warning if down)
  // Log "Audio data from %s: %d bytes"
  ```
- [ ] Add NEW method `SendAudioFromPeer(opusData []byte, fromCallsign string)`:
  ```go
  // Construct WebSocket message: {"type":"peer_audio","callsign":"...","opus":[...]}
  // Send to browser via WebSocket
  // Handle send errors gracefully (session might be closing)
  ```
- [ ] Update `Stop()` to call handleVoiceStop() if not already called
- [ ] Check if UUID library is imported, add if needed: `import "github.com/google/uuid"`
- [ ] Run tests: `go test ./internal/voice/... -v`
- [ ] Verify all tests PASS (green)

#### 1.9: Integration Tests (1 hour)
- [ ] Create `src/urfd-nng-dashboard/internal/voice/integration_test.go`
- [ ] Write test: `TestMultipleSessionsSameModule_AudioFlows`
  - Create 2 sessions on module "A"
  - Session 1 presses PTT
  - Session 1 sends audio data
  - Assert: Session 2 receives peer_audio message
  - Assert: Session 1 does NOT receive echo
- [ ] Write test: `TestModuleIsolation_NoAudioCrosstalk`
  - Create session on module "A" and module "D"
  - Module A sends audio
  - Assert: Module D does NOT receive audio
- [ ] Write test: `TestUrfdDisconnected_AudioStillFlows`
  - Mock urfd as disconnected
  - 2 sessions transmit audio
  - Assert: Audio still flows between sessions
  - Assert: Logs show "urfd disconnected" warnings
- [ ] Run tests: `go test ./internal/voice/... -v -run Integration`
- [ ] Verify all tests PASS (green)

#### 1.10: Manual Testing with Real Browsers (1 hour)
- [ ] Start dashboard: `tilt up`
- [ ] Open browser 1 (Chrome): Connect to module A as "KF8S"
- [ ] Open browser 2 (Firefox): Connect to module A as "W8EAP"
- [ ] Browser 1 presses PTT and speaks
- [ ] Verify: Browser 2 hears audio in real-time
- [ ] Verify: Browser 1 does NOT hear echo
- [ ] Browser 2 tries to press PTT while Browser 1 transmitting
- [ ] Verify: Browser 2 receives "ptt_denied" message (check browser console)
- [ ] Browser 1 releases PTT
- [ ] Browser 2 presses PTT and speaks
- [ ] Verify: Browser 1 hears audio
- [ ] Check dashboard logs for expected debug messages
- [ ] Test module isolation: Browser 3 on module D should NOT hear module A audio

#### 1.11: Phase 1 Checkpoint
- [ ] Run full test suite: `cd src/urfd-nng-dashboard && go test ./... -v`
- [ ] Verify all tests pass
- [ ] Update `.opencode/plans/voice-multiplexing-progress.md` with Phase 1 complete
- [ ] Commit changes: `git add . && git commit -m "Phase 1: Dashboard real-time audio multiplexing"`
- [ ] Document any deviations from plan in progress file

---

## Phase 2: urfd Persistent Virtual Client Lifecycle

**Goal**: Keep virtual clients alive across multiple PTT cycles
**Estimated Time**: 8-10 hours
**Test Framework**: Google Test (C++)

### Tasks

#### 2.1: Setup C++ Test Infrastructure (1 hour)
- [ ] Check if Google Test is available in project
- [ ] Create `src/urfd/reflector/NNGVoiceStream_test.cpp` (if testing framework exists)
- [ ] If no test framework: Document test plan in comments for manual verification
- [ ] Define test cases in comments:
  - Session lifecycle (create, multiple PTT, destroy)
  - PTT without session (should reject)
  - Concurrent sessions on different modules
  - Session cleanup on dashboard disconnect

#### 2.2: Update NNGVoiceStream.h with Session Structures (1.5 hours)
- [ ] Open `src/urfd/reflector/NNGVoiceStream.h`
- [ ] Add session structure:
  ```cpp
  struct VoiceSession {
      std::shared_ptr<CUSRPClient> virtualClient;
      std::string callsign;
      std::string source;  // "web"
      std::string module;
      time_t createdAt;
      bool hasActiveStream;  // true during PTT, false when idle
  };
  ```
- [ ] Add to CNNGVoiceStream class:
  ```cpp
  private:
      std::map<std::string, VoiceSession> m_Sessions;  // key: callsign
      std::mutex m_SessionMutex;
      
      // New handler methods
      void HandleVoiceSessionStart(const std::string& module, const std::string& callsign, const std::string& source);
      void HandleVoiceSessionStop(const std::string& callsign);
      void HandlePTTStart(const std::string& callsign);  // Updated signature
      void HandlePTTStop(const std::string& callsign);   // Updated signature
  ```
- [ ] Add logging includes if needed: `#include "Tracer.h"`
- [ ] Commit header changes: `git add src/urfd/reflector/NNGVoiceStream.h && git commit -m "Add voice session structures to NNGVoiceStream.h"`

#### 2.3: Implement Message Parsing in NNGVoiceStream.cpp (2 hours)
- [ ] Open `src/urfd/reflector/NNGVoiceStream.cpp`
- [ ] Locate existing message parsing code (likely in a receive loop)
- [ ] Add parsing for new message types:
  ```cpp
  // Parse JSON message from dashboard
  if (msgType == "voice_session_start") {
      std::string module = json["module"];
      std::string callsign = json["callsign"];
      std::string source = json["source"];  // "web"
      HandleVoiceSessionStart(module, callsign, source);
  }
  else if (msgType == "voice_session_stop") {
      std::string callsign = json["callsign"];
      HandleVoiceSessionStop(callsign);
  }
  ```
- [ ] Add debug logging for received messages
- [ ] Test message parsing with simple debug output

#### 2.4: Implement HandleVoiceSessionStart (2 hours)
- [ ] Implement `HandleVoiceSessionStart()` method:
  ```cpp
  void CNNGVoiceStream::HandleVoiceSessionStart(const std::string& module, 
                                                  const std::string& callsign, 
                                                  const std::string& source) {
      std::lock_guard<std::mutex> lock(m_SessionMutex);
      
      // Check if session already exists
      if (m_Sessions.find(callsign) != m_Sessions.end()) {
          LogWarning("Voice session already exists for %s", callsign.c_str());
          return;
      }
      
      // Create virtual USRP client
      auto virtualClient = std::make_shared<CUSRPClient>(/* params */);
      virtualClient->SetCallsign(callsign);
      virtualClient->SetModule(module);
      // Set source metadata: virtualClient->SetSource(source);
      
      // Add to reflector's client list
      g_Reflector.AddClient(virtualClient);
      
      // Store in sessions map
      VoiceSession session;
      session.virtualClient = virtualClient;
      session.callsign = callsign;
      session.source = source;
      session.module = module;
      session.createdAt = time(nullptr);
      session.hasActiveStream = false;
      m_Sessions[callsign] = session;
      
      LogInfo("[WEB] Voice session started: %s on module %s", callsign.c_str(), module.c_str());
  }
  ```
- [ ] Verify CUSRPClient constructor signature (may need to check existing code)
- [ ] Add error handling for client creation failure
- [ ] Add debug logging

#### 2.5: Implement HandleVoiceSessionStop (1 hour)
- [ ] Implement `HandleVoiceSessionStop()` method:
  ```cpp
  void CNNGVoiceStream::HandleVoiceSessionStop(const std::string& callsign) {
      std::lock_guard<std::mutex> lock(m_SessionMutex);
      
      auto it = m_Sessions.find(callsign);
      if (it == m_Sessions.end()) {
          LogWarning("Voice session not found for %s", callsign.c_str());
          return;
      }
      
      VoiceSession& session = it->second;
      
      // Close active stream if any
      if (session.hasActiveStream) {
          g_Reflector.CloseStream(session.virtualClient);
      }
      
      // Remove virtual client from reflector
      g_Reflector.RemoveClient(session.virtualClient);
      
      // Remove from sessions map
      m_Sessions.erase(it);
      
      LogInfo("[WEB] Voice session stopped: %s", callsign.c_str());
  }
  ```
- [ ] Add error handling for reflector operations
- [ ] Add debug logging

#### 2.6: Update HandlePTTStart (2 hours)
- [ ] Modify existing `HandlePTTStart()` to use session map:
  ```cpp
  void CNNGVoiceStream::HandlePTTStart(const std::string& callsign) {
      std::lock_guard<std::mutex> lock(m_SessionMutex);
      
      // Get virtual client from sessions (DON'T create new one!)
      auto it = m_Sessions.find(callsign);
      if (it == m_Sessions.end()) {
          LogError("PTT start rejected: No voice session for %s", callsign.c_str());
          // TODO: Send error back to dashboard
          return;
      }
      
      VoiceSession& session = it->second;
      
      // Half-duplex defense: Check if module already has active stream
      if (ModuleHasActiveStream(session.module, callsign)) {
          LogWarning("PTT start rejected: Module %s busy", session.module.c_str());
          // TODO: Send error back to dashboard
          return;
      }
      
      // Open reflector stream for this virtual client
      g_Reflector.OpenStream(session.virtualClient);
      session.hasActiveStream = true;
      
      LogInfo("[WEB] PTT started: %s on module %s", callsign.c_str(), session.module.c_str());
  }
  ```
- [ ] Implement helper: `ModuleHasActiveStream(module, excludeCallsign)`:
  ```cpp
  // Iterate m_Sessions, check if any other session on same module has hasActiveStream=true
  ```
- [ ] Remove OLD code that created virtual clients on PTT press
- [ ] Add debug logging

#### 2.7: Update HandlePTTStop (1 hour)
- [ ] Modify existing `HandlePTTStop()`:
  ```cpp
  void CNNGVoiceStream::HandlePTTStop(const std::string& callsign) {
      std::lock_guard<std::mutex> lock(m_SessionMutex);
      
      auto it = m_Sessions.find(callsign);
      if (it == m_Sessions.end()) {
          LogWarning("PTT stop ignored: No voice session for %s", callsign.c_str());
          return;
      }
      
      VoiceSession& session = it->second;
      
      // Close reflector stream
      if (session.hasActiveStream) {
          g_Reflector.CloseStream(session.virtualClient);
          session.hasActiveStream = false;
      }
      
      // DON'T destroy virtual client - keep it for next PTT cycle!
      
      LogInfo("[WEB] PTT stopped: %s", callsign.c_str());
  }
  ```
- [ ] Remove OLD code that destroyed virtual clients on PTT release
- [ ] Add debug logging

#### 2.8: Compile and Test urfd Changes (1.5 hours)
- [ ] Build urfd: `cd src/urfd && make clean && make`
- [ ] Fix any compilation errors
- [ ] Start urfd with updated code
- [ ] Check logs for new debug messages
- [ ] Verify no crashes or memory leaks (run under valgrind if available)

#### 2.9: Integration Testing with Dashboard (1 hour)
- [ ] Ensure dashboard Phase 1 code is running
- [ ] Connect browser to module A as "KF8S"
- [ ] Check urfd logs: Should see "Voice session started: KF8S on module A"
- [ ] Press PTT multiple times (press, release, press, release)
- [ ] Check urfd logs: Should see "PTT started" and "PTT stopped" but NO "Voice session stopped"
- [ ] Disconnect browser
- [ ] Check urfd logs: Should see "Voice session stopped: KF8S"
- [ ] Verify virtual client was removed from reflector
- [ ] Check for memory leaks or orphaned clients

#### 2.10: Multi-Client Testing (1 hour)
- [ ] Browser 1: Connect to module A as "KF8S", press PTT
- [ ] Check urfd logs: "PTT started: KF8S"
- [ ] Browser 2: Connect to module A as "W8EAP", press PTT while Browser 1 transmitting
- [ ] Check urfd logs: "PTT start rejected: Module A busy"
- [ ] Browser 1: Release PTT
- [ ] Browser 2: Press PTT again (should succeed now)
- [ ] Check urfd logs: "PTT started: W8EAP"
- [ ] Verify both browsers maintain sessions across multiple PTT cycles

#### 2.11: Phase 2 Checkpoint
- [ ] Build urfd successfully with all changes
- [ ] Manual tests pass (session lifecycle, multiple PTT, half-duplex)
- [ ] No memory leaks detected
- [ ] Update `.opencode/plans/voice-multiplexing-progress.md` with Phase 2 complete
- [ ] Commit changes: `git add src/urfd && git commit -m "Phase 2: Persistent virtual client lifecycle in urfd"`
- [ ] Document any deviations from plan in progress file

---

## Phase 3: Dashboard Session Lifecycle Messages

**Goal**: Dashboard sends session start/stop messages and handles reconnection
**Estimated Time**: 2-3 hours
**Test File**: `src/urfd-nng-dashboard/internal/voice/lifecycle_test.go`

### Tasks

#### 3.1: Write Tests for Session Lifecycle Messages (1 hour)
- [ ] Create `src/urfd-nng-dashboard/internal/voice/lifecycle_test.go`
- [ ] Write test: `TestHandleVoiceStart_SendsSessionStartMessage`
  - Mock NNG connection
  - Call handleVoiceStart()
  - Assert: Message sent to urfd with type="voice_session_start"
- [ ] Write test: `TestHandleVoiceStop_SendsSessionStopMessage`
  - Mock NNG connection
  - Call handleVoiceStop()
  - Assert: Message sent to urfd with type="voice_session_stop"
- [ ] Write test: `TestSessionStop_OnDisconnect_SendsMessage`
  - Simulate WebSocket disconnect
  - Assert: voice_session_stop sent before cleanup
- [ ] Write test: `TestReconnectToUrfd_ResendsActiveSessions`
  - Setup: 2 active sessions
  - Simulate urfd reconnect
  - Assert: voice_session_start sent for both sessions
- [ ] Run tests: `go test ./internal/voice/... -v -run Lifecycle`
- [ ] Verify all tests FAIL (red)

#### 3.2: Implement Session Start/Stop Message Sending (1 hour)
- [ ] Update `handleVoiceStart()` in `session.go`:
  - Already has sessionID generation and RegisterSession from Phase 1
  - Add message construction and send to urfd:
  ```go
  msg := map[string]interface{}{
      "type": "voice_session_start",
      "module": s.module,
      "callsign": callsign,
      "source": "web",
  }
  if err := s.sharedClient.SendToUrfd(msg); err != nil {
      log.Printf("Warning: Failed to send voice_session_start to urfd: %v", err)
      // Don't fail - audio can still work between browsers
  }
  ```
- [ ] Update `handleVoiceStop()` in `session.go`:
  ```go
  msg := map[string]interface{}{
      "type": "voice_session_stop",
      "callsign": s.callsign,
  }
  if err := s.sharedClient.SendToUrfd(msg); err != nil {
      log.Printf("Warning: Failed to send voice_session_stop to urfd: %v", err)
  }
  ```
- [ ] Update `Stop()` method to ensure handleVoiceStop() is called

#### 3.3: Implement Reconnection Logic (1 hour)
- [ ] Open `src/urfd-nng-dashboard/internal/voice/pool.go`
- [ ] Add method to SharedVoiceClient:
  ```go
  func (c *SharedVoiceClient) OnUrfdReconnect() {
      c.sessionsMu.RLock()
      defer c.sessionsMu.RUnlock()
      
      log.Printf("urfd reconnected, resyncing %d active sessions", len(c.sessions))
      
      for _, session := range c.sessions {
          msg := map[string]interface{}{
              "type": "voice_session_start",
              "module": session.module,
              "callsign": session.callsign,
              "source": "web",
          }
          if err := c.SendToUrfd(msg); err != nil {
              log.Printf("Warning: Failed to resync session %s: %v", session.callsign, err)
          }
      }
  }
  ```
- [ ] Hook OnUrfdReconnect() into NNG reconnection handler (in nng.go or pool.go)
- [ ] Add debug logging

#### 3.4: Test Session Lifecycle (30 min)
- [ ] Run tests: `go test ./internal/voice/... -v -run Lifecycle`
- [ ] Verify all tests PASS (green)
- [ ] Fix any test failures

#### 3.5: Integration Testing (1 hour)
- [ ] Start dashboard and urfd
- [ ] Browser connects to module A as "KF8S"
- [ ] Check urfd logs: "Voice session started: KF8S on module A"
- [ ] Stop urfd container: `docker stop urfd` (or Tilt equivalent)
- [ ] Browser stays connected to dashboard (audio should still work between browsers)
- [ ] Start urfd container again
- [ ] Check urfd logs: Should see "Voice session started: KF8S" (resync message)
- [ ] Browser presses PTT
- [ ] Verify recording works in urfd (check recording files)

#### 3.6: End-to-End Testing (1 hour)
- [ ] Full scenario test:
  - Browser 1 (KF8S) connects to module A
  - Browser 2 (W8EAP) connects to module A
  - Browser 3 (N0CALL) connects to module D
- [ ] Verify urfd shows 3 voice sessions active
- [ ] KF8S presses PTT and speaks
- [ ] Verify: W8EAP hears audio in real-time (from dashboard multiplexing)
- [ ] Verify: N0CALL does NOT hear audio (module isolation)
- [ ] Verify: urfd records KF8S transmission
- [ ] W8EAP presses PTT while KF8S transmitting
- [ ] Verify: W8EAP receives "ptt_denied" (from dashboard half-duplex)
- [ ] KF8S releases PTT
- [ ] W8EAP presses PTT and speaks
- [ ] Verify: KF8S hears audio in real-time
- [ ] Verify: urfd records W8EAP transmission
- [ ] Verify: Recording files contain both transmissions (check filesystem)

#### 3.7: Edge Case Testing (30 min)
- [ ] Test rapid connect/disconnect (10 browsers in 10 seconds)
- [ ] Test rapid PTT press/release (press-release 20 times quickly)
- [ ] Test browser crash (kill browser tab) - verify session cleanup
- [ ] Test urfd crash during transmission - verify graceful handling
- [ ] Test network interruption - verify reconnection

#### 3.8: Phase 3 Checkpoint
- [ ] Run full test suite: `cd src/urfd-nng-dashboard && go test ./... -v`
- [ ] Verify all tests pass
- [ ] All integration tests pass
- [ ] Update `.opencode/plans/voice-multiplexing-progress.md` with Phase 3 complete
- [ ] Commit changes: `git add . && git commit -m "Phase 3: Dashboard session lifecycle messages"`
- [ ] Document any deviations from plan in progress file

---

## Final Verification & Acceptance Testing

### Complete Test Matrix

#### Functional Tests
- [ ] **Multi-client real-time audio**: 2-3 browsers hear each other on same module
- [ ] **Half-duplex enforcement**: Only one talker at a time (dashboard blocks PTT)
- [ ] **Module isolation**: Module A traffic doesn't reach module D
- [ ] **Recording works**: urfd creates recording files for web transmissions
- [ ] **Graceful degradation**: Audio works between browsers when urfd disconnected
- [ ] **Session persistence**: Virtual clients survive multiple PTT cycles
- [ ] **Reconnection**: Dashboard resyncs sessions when urfd reconnects

#### Performance Tests
- [ ] **Latency**: <200ms browser-to-browser audio (measure with timestamp logs)
- [ ] **Audio quality**: Clear, intelligible speech with no distortion
- [ ] **Concurrent sessions**: 5+ browsers connected simultaneously without issues
- [ ] **Memory usage**: No leaks after 100 PTT cycles (check with `top` or profiler)

#### Edge Case Tests
- [ ] **Browser disconnect during TX**: PTT released, session cleaned up
- [ ] **Rapid PTT press/release**: No crashes or stuck states
- [ ] **urfd restart**: Sessions resync, recordings resume
- [ ] **Dashboard restart**: All sessions cleaned up in urfd
- [ ] **Network interruption**: Reconnection works, no orphaned clients

### Success Criteria
✅ All checkbox tasks completed (100%)
✅ All automated tests passing
✅ Manual testing scenarios validated
✅ No memory leaks detected
✅ Logs show expected debug messages at all stages
✅ Real-time audio latency <200ms
✅ Module isolation verified
✅ Recordings work correctly

---

## Protocol Reference

### Dashboard → urfd Messages (NEW in Phase 3)
```json
{
  "type": "voice_session_start",
  "module": "A",
  "callsign": "KF8S",
  "source": "web"
}

{
  "type": "voice_session_stop",
  "callsign": "KF8S"
}
```

### Dashboard → urfd Messages (EXISTING)
```json
{
  "type": "ptt_start",
  "module": "A",
  "callsign": "KF8S",
  "source": "web"
}

{
  "type": "ptt_stop",
  "module": "A",
  "callsign": "KF8S"
}

{
  "type": "audio_data",
  "module": "A",
  "callsign": "KF8S",
  "opus": [1, 2, 3, ...]
}
```

### Dashboard → Browser Messages (NEW in Phase 1)
```json
{
  "type": "ptt_denied",
  "reason": "KF8S is currently transmitting"
}

{
  "type": "peer_audio",
  "callsign": "KF8S",
  "opus": [1, 2, 3, ...]
}
```

---

## Files Modified/Created

### Phase 1 (Dashboard Go)
**Modified:**
- `src/urfd-nng-dashboard/internal/voice/pool.go`
- `src/urfd-nng-dashboard/internal/voice/session.go`

**Created:**
- `src/urfd-nng-dashboard/internal/voice/pool_test.go`
- `src/urfd-nng-dashboard/internal/voice/session_test.go`
- `src/urfd-nng-dashboard/internal/voice/integration_test.go`

### Phase 2 (urfd C++)
**Modified:**
- `src/urfd/reflector/NNGVoiceStream.h`
- `src/urfd/reflector/NNGVoiceStream.cpp`

**Created (optional):**
- `src/urfd/reflector/NNGVoiceStream_test.cpp`

### Phase 3 (Dashboard Go)
**Modified:**
- `src/urfd-nng-dashboard/internal/voice/session.go` (further updates)
- `src/urfd-nng-dashboard/internal/voice/pool.go` (reconnection logic)

**Created:**
- `src/urfd-nng-dashboard/internal/voice/lifecycle_test.go`

### Progress Tracking
**Created:**
- `.opencode/plans/voice-multiplexing-progress.md` (created during implementation)

---

## Dependencies & Prerequisites

### Go Dependencies (already in project)
- `github.com/google/uuid` - Session ID generation
- `github.com/gorilla/websocket` - WebSocket handling
- NNG Go bindings - Already in use

### C++ Dependencies (already in project)
- libopus - Opus codec
- NNG C library - Messaging
- Existing reflector infrastructure

### Build Tools
- Go 1.19+ (check: `go version`)
- GCC/Clang for C++ compilation
- Make for urfd builds

---

## Risk Mitigation

### Risk: Breaking Existing Voice Chat
**Mitigation**: Extensive testing at each phase, all changes are additive/replacement, not removal

### Risk: Memory Leaks in urfd
**Mitigation**: Manual testing with valgrind, session cleanup on disconnect, timeout-based cleanup (future)

### Risk: Race Conditions in Go
**Mitigation**: All tests run with `-race` flag, proper mutex usage in pool.go

### Risk: Module Audio Crosstalk
**Mitigation**: Explicit module isolation tests, defensive checks in broadcast logic

### Risk: urfd/Dashboard Version Mismatch
**Mitigation**: urfd gracefully ignores unknown message types, dashboard checks connection status

---

## Rollback Plan

If critical issues are found:
1. Revert to last known good commit (before Phase 1)
2. Dashboard and urfd can be rolled back independently
3. Browser code unchanged - no rollback needed
4. VoiceClientPool architecture is backward compatible (single client = same as before)

---

## Future Enhancements (Post-Fix)

After all 3 phases are complete and stable:
- [ ] Add session timeout (auto-cleanup after 30 min inactivity)
- [ ] Add PTT queue (instead of deny, queue second caller)
- [ ] Add audio recording in dashboard (fallback when urfd down)
- [ ] Add metrics/telemetry for audio quality monitoring
- [ ] Browser UI updates to show peer audio indicators
- [ ] Add voice activity detection (VAD) for auto-PTT

---

## Support & References

**Original Implementation Plan**: `.opencode/plans/webvoiceclient.md`
**Existing Code References**:
- Dashboard NNG: `src/urfd-nng-dashboard/internal/nng/`
- Dashboard Voice: `src/urfd-nng-dashboard/internal/voice/`
- urfd Voice Stream: `src/urfd/reflector/NNGVoiceStream.*`
- urfd Reflector: `src/urfd/reflector/Reflector.*`

**Debugging Tips**:
- Dashboard logs: `tilt logs dashboard`
- urfd logs: `tilt logs urfd` or check urfd console output
- Browser console: F12 → Console tab
- Network tab: F12 → Network → WS (WebSocket messages)

---

**Last Updated**: Session start
**Total Estimated Time**: 16-21 hours
**Current Status**: Ready to begin Phase 1, Task 1.1
