# Ralph Signs (Lessons Learned)

> This file contains lessons learned from failures during development.
> Follow these signs to avoid repeating mistakes.

## Signs

### Stream Injection Complexity
**Problem:** Stream injection into URFD reflector is more complex than initially estimated  
**Root Cause:** Requires understanding of:
- DVHeaderPacket and DVFramePacket structures
- Virtual client lifecycle management
- Stream ID generation and management  
- Codec chain (PCM → Codec2/AMBE for non-USRP modes)
- USRP protocol flow and packet creation

**Solution for Next Iteration:**
1. Use USRP frame format since it accepts PCM directly (160 samples/frame)
2. Create virtual CUSRPClient when PTT starts
3. Generate unique stream ID
4. Create DVHeaderPacket with web callsign
5. Call Reflector::OpenStream() to get PacketStream
6. For each audio frame, create CDvFramePacket(pcm, streamid, islast) 
7. Push packets to stream
8. Close stream when PTT stops

**Reference Code:**
- USRPProtocol.cpp line 224: Example of OpenStream() usage
- DVFramePacket.cpp: USRP constructor takes int16_t[160]
- PacketStream has CodecStream that handles transcoding
