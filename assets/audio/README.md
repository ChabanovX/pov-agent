# Hands-free acceptance audio

`hands_free_question_en_us.pcm` is a deterministic, one-shot input for the
native streaming-ASR acceptance lane. It contains US English speech:

> Assistant. What can you see in front of the camera?

The raw format is mono, signed little-endian PCM16 at 16 kHz. The 188,954-byte
fixture lasts 5.904813 seconds and has SHA-256:

```text
022256446f20bcd100316d1b892d7cb4bd9ce785ab6eac6ee74836ea60c69c52
```

It was generated with the macOS Samantha voice at 145 words per minute. The
layout is 0.5 seconds of lead-in silence, the wake phrase, 0.6 seconds of
silence, the question, and 2 seconds of trailing silence. The short middle gap
gives the application time to reset the sherpa stream after detecting the wake
phrase without reaching the configured 1.2-second speech endpoint.

Regenerate the two source clips with:

```sh
say -v Samantha -r 145 -o /tmp/pov-m7-wake.aiff Assistant
say -v Samantha -r 145 -o /tmp/pov-m7-question.aiff \
  'What can you see in front of the camera?'
```

Then concatenate and convert them without retaining the source clips:

```sh
ffmpeg -y \
  -i /tmp/pov-m7-wake.aiff \
  -i /tmp/pov-m7-question.aiff \
  -filter_complex \
  'anullsrc=r=16000:cl=mono:d=0.5[lead];\
[0:a]aresample=16000,aformat=sample_fmts=s16:channel_layouts=mono[wake];\
anullsrc=r=16000:cl=mono:d=0.6[gap];\
[1:a]aresample=16000,aformat=sample_fmts=s16:channel_layouts=mono[question];\
anullsrc=r=16000:cl=mono:d=2.0[tail];\
[lead][wake][gap][question][tail]concat=n=5:v=0:a=1[out]' \
  -map '[out]' \
  -f s16le \
  -acodec pcm_s16le \
  assets/audio/hands_free_question_en_us.pcm
```

This asset is synthetic test input. Production composition uses live
microphone capture and never persists user audio.
