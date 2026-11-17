// CamStream live view: plays a MediaMTX path over WebRTC (WHEP, non-trickle) behind /cam/.
(function () {
  const id = new URLSearchParams(location.search).get('id') || 'camera1';
  const $ = (s) => document.getElementById(s);
  const video = $('video');
  const overlay = $('overlay');
  const text = $('overlay-text');
  const mark = $('overlay-mark');
  const retry = $('retry');
  const liveTag = $('live-tag');

  let pc = null;
  let session = null;
  let retryTimer = null;
  let liveSince = null;
  let cam = { name: 'Camera' };

  function showLoading(msg) {
    overlay.classList.remove('gone');
    mark.hidden = false;
    retry.hidden = true;
    text.textContent = msg;
    liveTag.hidden = true;
    $('f-status').textContent = 'Connecting';
  }

  function showProblem(msg) {
    overlay.classList.remove('gone');
    mark.hidden = true;
    retry.hidden = false;
    text.textContent = msg;
    liveTag.hidden = true;
    $('f-status').textContent = 'Offline';
  }

  function waitForIce(peer, ms) {
    return new Promise((resolve) => {
      if (peer.iceGatheringState === 'complete') return resolve();
      const t = setTimeout(resolve, ms);
      peer.addEventListener('icegatheringstatechange', () => {
        if (peer.iceGatheringState === 'complete') { clearTimeout(t); resolve(); }
      });
    });
  }

  function stop() {
    if (session) { fetch(session, { method: 'DELETE', keepalive: true }).catch(() => {}); session = null; }
    if (pc) { pc.close(); pc = null; }
  }

  async function start() {
    clearTimeout(retryTimer);
    stop();
    showLoading(`Connecting to ${cam.name}`);
    try {
      pc = new RTCPeerConnection();
      pc.addTransceiver('video', { direction: 'recvonly' });
      pc.ontrack = (e) => { video.srcObject = e.streams[0] || new MediaStream([e.track]); };
      pc.onconnectionstatechange = () => {
        if (pc && (pc.connectionState === 'failed' || pc.connectionState === 'disconnected')) scheduleRetry();
      };

      await pc.setLocalDescription(await pc.createOffer());
      await waitForIce(pc, 2000);

      const r = await fetch(`/cam/${encodeURIComponent(id)}/whep`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/sdp' },
        body: pc.localDescription.sdp,
      });
      if (r.status === 401) { location.href = '/login.html'; return; }
      if (r.status === 404) {
        showProblem(`${cam.name} is offline. Check that the camera and its site connection are powered on, then try again.`);
        scheduleRetry(10000);
        return;
      }
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      session = r.headers.get('Location');
      await pc.setRemoteDescription({ type: 'answer', sdp: await r.text() });
    } catch (e) {
      showProblem(`Could not connect to ${cam.name}. Retrying shortly.`);
      scheduleRetry();
    }
  }

  function scheduleRetry(ms = 4000) {
    clearTimeout(retryTimer);
    retryTimer = setTimeout(start, ms);
  }

  video.addEventListener('playing', () => {
    overlay.classList.add('gone');
    liveTag.hidden = false;
    liveSince = liveSince || Date.now();
    $('f-status').textContent = 'Live';
  });
  video.addEventListener('resize', () => {
    if (video.videoWidth) $('f-res').textContent = `${video.videoWidth} × ${video.videoHeight}`;
  });

  setInterval(() => {
    if (!liveSince) return;
    const s = Math.floor((Date.now() - liveSince) / 1000);
    $('f-time').textContent = s < 60 ? `${s} s` : `${Math.floor(s / 60)} min ${s % 60} s`;
  }, 1000);

  retry.addEventListener('click', start);

  $('fullscreen').addEventListener('click', () => {
    const stage = $('stage');
    if (document.fullscreenElement) document.exitFullscreen();
    else (stage.requestFullscreen || stage.webkitRequestFullscreen).call(stage);
  });

  $('snapshot').addEventListener('click', () => {
    if (!video.videoWidth) { toast('The live picture is not ready yet.'); return; }
    const c = document.createElement('canvas');
    c.width = video.videoWidth;
    c.height = video.videoHeight;
    c.getContext('2d').drawImage(video, 0, 0);
    const a = document.createElement('a');
    const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-');
    a.download = `${id}-${stamp}.png`;
    a.href = c.toDataURL('image/png');
    a.click();
    toast('Snapshot saved.');
  });

  window.addEventListener('pagehide', stop);

  (async () => {
    loadUser();
    try {
      const list = (await api('/api/cameras')).cameras;
      cam = list.find((c) => c.id === id) || cam;
    } catch { /* keep defaults */ }
    document.title = `${cam.name} | CamStream`;
    $('crumb-name').textContent = cam.name;
    $('cam-name').textContent = cam.name;
    $('cam-loc').textContent = cam.location || '';
    $('f-model').textContent = cam.model || '–';
    start();
  })();
})();
