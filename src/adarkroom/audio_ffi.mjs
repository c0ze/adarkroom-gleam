// The AudioEngine (script/audio.js), translated nearly verbatim: a Web Audio
// context with a master gain, a lazy fetch-and-decode buffer cache, looping
// background music with a one-second crossfade, looping event music that
// ducks the background to 0.2, and one-shot sounds that skip while the same
// buffer is still sounding. A missing file plays the original's beep.

const FADE_TIME = 1;

const cache = {};
let context = null;
let master = null;
let currentBackground = null;
let currentEvent = null;
let currentSound = null;

function ensureContext() {
  if (context === null) {
    context = new (window.AudioContext || window.webkitAudioContext)();
    master = context.createGain();
    master.gain.setValueAtTime(1.0, context.currentTime);
    master.connect(context.destination);
  }
  // Browsers suspend audio until a user gesture; try resuming on every use.
  if (context.state === "suspended") {
    context.resume();
  }
}

function missingAudioBuffer() {
  // The original's beep, marking a missing file.
  const buffer = context.createBuffer(1, context.sampleRate, context.sampleRate);
  const data = buffer.getChannelData(0);
  for (let i = 0; i < buffer.length / 2; i++) {
    data[i] = Math.sin(i * 0.05) / 4;
  }
  return buffer;
}

function load(src) {
  if (!src.startsWith("http") && !src.startsWith("/")) {
    src = "/" + src;
  }
  if (cache[src]) {
    return Promise.resolve(cache[src]);
  }
  return fetch(new Request(src))
    .then((response) => response.arrayBuffer())
    .then((buffer) => {
      if (buffer.byteLength === 0) {
        console.error("cannot load audio from " + src);
        return missingAudioBuffer();
      }
      return context.decodeAudioData(buffer).then((decoded) => {
        cache[src] = decoded;
        return decoded;
      });
    })
    .catch(() => missingAudioBuffer());
}

export function playBackgroundMusic(src) {
  ensureContext();
  load(src).then((buffer) => {
    const source = context.createBufferSource();
    source.buffer = buffer;
    source.loop = true;

    const envelope = context.createGain();
    envelope.gain.setValueAtTime(0.0, context.currentTime);
    const fadeTime = context.currentTime + FADE_TIME;

    if (currentBackground && currentBackground.source) {
      const gain = currentBackground.envelope.gain;
      const value = gain.value;
      gain.cancelScheduledValues(context.currentTime);
      gain.setValueAtTime(value, context.currentTime);
      gain.linearRampToValueAtTime(0.0, fadeTime);
      currentBackground.source.stop(fadeTime + 0.3);
    }

    source.connect(envelope);
    envelope.connect(master);
    source.start();
    envelope.gain.linearRampToValueAtTime(1.0, fadeTime);

    currentBackground = { source, envelope };
  });
}

export function playEventMusic(src) {
  ensureContext();
  load(src).then((buffer) => {
    const source = context.createBufferSource();
    source.buffer = buffer;
    source.loop = true;

    const envelope = context.createGain();
    envelope.gain.setValueAtTime(0.0, context.currentTime);
    const fadeTime = context.currentTime + FADE_TIME * 2;

    // Duck the background under the event.
    if (currentBackground !== null) {
      const gain = currentBackground.envelope.gain;
      const value = gain.value;
      gain.cancelScheduledValues(context.currentTime);
      gain.setValueAtTime(value, context.currentTime);
      gain.linearRampToValueAtTime(0.2, fadeTime);
    }

    source.connect(envelope);
    envelope.connect(master);
    source.start();
    envelope.gain.linearRampToValueAtTime(1.0, fadeTime);

    currentEvent = { source, envelope };
  });
}

export function stopEventMusic() {
  if (context === null) return;
  const fadeTime = context.currentTime + FADE_TIME * 2;

  if (currentEvent && currentEvent.source && currentEvent.source.buffer) {
    const gain = currentEvent.envelope.gain;
    const value = gain.value;
    gain.cancelScheduledValues(context.currentTime);
    gain.setValueAtTime(value, context.currentTime);
    gain.linearRampToValueAtTime(0.0, fadeTime);
    currentEvent.source.stop(fadeTime + 1);
    currentEvent = null;
  }

  if (currentBackground) {
    const gain = currentBackground.envelope.gain;
    const value = gain.value;
    gain.cancelScheduledValues(context.currentTime);
    gain.setValueAtTime(value, context.currentTime);
    gain.linearRampToValueAtTime(1.0, fadeTime);
  }
}

export function playSound(src) {
  ensureContext();
  load(src).then((buffer) => {
    // The same effect never overlaps itself.
    if (currentSound && currentSound.source.buffer === buffer) {
      return;
    }
    const source = context.createBufferSource();
    source.buffer = buffer;
    source.onended = () => {
      if (currentSound && currentSound.source.buffer === buffer) {
        currentSound = null;
      }
    };
    source.connect(master);
    source.start();
    currentSound = { source };
  });
}

export function setBackgroundMusicVolume(volume, seconds) {
  if (master === null || currentBackground === null) return;
  const gain = currentBackground.envelope.gain;
  const value = gain.value;
  gain.cancelScheduledValues(context.currentTime);
  gain.setValueAtTime(value, context.currentTime);
  gain.linearRampToValueAtTime(volume, context.currentTime + seconds);
}

export function setMasterVolume(volume, seconds) {
  if (master === null) return;
  const value = master.gain.value;
  master.gain.cancelScheduledValues(context.currentTime);
  master.gain.setValueAtTime(value, context.currentTime);
  master.gain.linearRampToValueAtTime(volume, context.currentTime + seconds);
}
