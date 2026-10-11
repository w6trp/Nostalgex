// Browser playback policy. Pure helpers are also exercised by Node regression tests.
(function (global) {
  'use strict';
  function identity(item) {
    if (item.itemKey) return item.itemKey;
    const server = item.serverId || item.serverUrl;
    return server ? JSON.stringify([server, String(item.ratingKey)]) : String(item.ratingKey);
  }
  function canDirectPlay(item, video) {
    if (item._forceTranscode || !item.partKey) return false;
    const container = String(item.container || '').toLowerCase();
    const v = String(item.videoCodec || '').toLowerCase();
    const a = String(item.audioCodec || '').toLowerCase();
    const videoCodec = { h264: 'avc1.42E01E', avc: 'avc1.42E01E', hevc: 'hvc1', h265: 'hvc1', vp8: 'vp8', vp9: 'vp9', av1: 'av01.0.08M.08' }[v];
    const audioCodec = { aac: 'mp4a.40.2', mp3: 'mp3', opus: 'opus', vorbis: 'vorbis', flac: 'flac' }[a];
    if (!videoCodec || !audioCodec || Number(item.audioChannels || 2) > 2) return false;
    // H.264 High 10 is not the ubiquitous 8-bit AVC decode path. Unknown metadata
    // still has a one-shot transcode fallback, but known incompatible profiles do not.
    if (['h264', 'avc'].includes(v) && (Number(item.bitDepth || 8) > 8 || /10|422|444/i.test(item.videoProfile || ''))) return false;
    const mime = { mp4: 'video/mp4', m4v: 'video/mp4', mov: 'video/mp4', webm: 'video/webm' }[container];
    return Boolean(mime && video.canPlayType(`${mime}; codecs="${videoCodec},${audioCodec}"`));
  }
  function transport(fetcher, timeoutMs = 5000) {
    let tail = Promise.resolve(), epoch = 0;
    const active = new Set();
    return {
      request(url, options = {}) {
        const ticket = epoch;
        const run = async () => {
          if (ticket !== epoch) return false;
          const controller = new AbortController();
          active.add(controller);
          const timeout = setTimeout(() => controller.abort(), timeoutMs);
          try {
            const response = await fetcher(url, { ...options, signal: controller.signal });
            return response.ok;
          } catch { return false; }
          finally { clearTimeout(timeout); active.delete(controller); }
        };
        const result = tail.then(run, run);
        tail = result.then(() => undefined, () => undefined);
        return result;
      },
      cancel() { epoch++; for (const controller of active) controller.abort(); },
    };
  }
  function tracker({ video, item, hidden, send, scrobble, cancelReports = () => {}, now = Date.now, every = setInterval, cancel = clearInterval }) {
    let started = false, stopped = false, timer = null, state = 'paused', watched = 0, marked = false, marking = false, abandoned = false;
    let lastTime = now(), lastPosition = Number(video.currentTime) || 0;
    function durationSeconds() {
      const source = Number(item.sourceDurationSeconds);
      if (Number.isFinite(source) && source > 0) return source;
      // A transcoded HLS asset may advertise only the remaining segment duration.
      // Use video.duration only when this is the original direct-play source.
      const decoded = Number(video.duration);
      if (item._isDirectPlay && Number.isFinite(decoded) && decoded > 0) return decoded;
      return Number(item.duration || 0) * 60;
    }
    function sample(count = true) {
      const clock = now(), position = Number(video.currentTime) || 0;
      if (count && state === 'playing' && !video.seeking && !hidden()) {
        const delta = position - lastPosition;
        const elapsed = Math.max(0, (clock - lastTime) / 1000) * (Number(video.playbackRate) || 1);
        // A seek is a discontinuity, not watched time. Events reset the baseline too.
        if (delta > 0 && delta <= elapsed + 1) watched += Math.min(delta, elapsed);
      }
      lastTime = clock; lastPosition = position;
    }
    function report(next, keepalive = false) {
      if (!started || stopped) return;
      send(next, Math.max(0, Math.round((Number(video.currentTime) || 0) * 1000)), Math.round(durationSeconds() * 1000), keepalive);
    }
    function mark() {
      const duration = durationSeconds();
      const eligible = duration > 0 && Number(item.offsetSeconds || 0) / duration <= .15;
      if (marked || marking || stopped || !eligible || watched < duration * .75) return;
      marking = true;
      Promise.resolve().then(() => abandoned ? false : scrobble()).then(ok => { if (ok === true) marked = true; })
        .catch(() => {}).finally(() => { marking = false; });
    }
    const api = {
      onReady() { if (started || stopped) return; started = true; state = 'playing'; sample(false); report(state); timer = every(() => { if (stopped) return; sample(); report(state); mark(); }, 10000); },
      onPause() { if (stopped) return; sample(); state = 'paused'; report(state); },
      onWaiting() { if (stopped) return; sample(); state = 'buffering'; report(state); },
      onResume() { if (stopped) return; state = 'playing'; sample(false); report(state); },
      onSeek() { sample(false); report(state); },
      onVisibility() { sample(false); },
      stop(keepalive = false) { if (stopped) return; sample(); report('stopped', keepalive); mark(); stopped = true; if (timer) cancel(timer); },
      abandon() { abandoned = true; stopped = true; cancelReports(); if (timer) cancel(timer); },
    };
    return api;
  }
  global.NostalgexPlaybackCore = { identity, canDirectPlay, tracker, transport };
})(typeof globalThis !== 'undefined' ? globalThis : window);
