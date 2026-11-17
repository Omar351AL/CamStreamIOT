// CamStream shared UI: toast, user menu, sign out, prototype-only buttons.
(function () {
  const toastEl = document.getElementById('toast');
  let toastTimer;

  window.toast = function (msg) {
    if (!toastEl) return;
    toastEl.textContent = msg;
    toastEl.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toastEl.classList.remove('show'), 2600);
  };

  // Buttons and links that are part of the prototype design but not wired yet.
  document.addEventListener('click', (e) => {
    const el = e.target.closest('[data-soon]');
    if (!el) return;
    e.preventDefault();
    toast(`${el.dataset.soon} will be available in the full version.`);
  });

  const userBtn = document.getElementById('user-btn');
  const menu = document.getElementById('user-menu');
  if (userBtn && menu) {
    userBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      menu.hidden = !menu.hidden;
      userBtn.setAttribute('aria-expanded', String(!menu.hidden));
    });
    document.addEventListener('click', () => { menu.hidden = true; userBtn.setAttribute('aria-expanded', 'false'); });
  }

  const signOut = document.getElementById('sign-out');
  if (signOut) {
    signOut.addEventListener('click', async () => {
      await fetch('/auth/logout', { method: 'POST' }).catch(() => {});
      location.href = '/login.html';
    });
  }

  // Shared fetch that sends the user back to sign in when the session has expired.
  window.api = async function (path) {
    const r = await fetch(path, { credentials: 'same-origin', cache: 'no-store' });
    if (r.status === 401) { location.href = '/login.html'; throw new Error('signed out'); }
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    return r.json();
  };

  window.loadUser = async function () {
    try {
      const me = await api('/api/me');
      document.querySelectorAll('[data-user]').forEach((n) => { n.textContent = me.user; });
      document.querySelectorAll('[data-initial]').forEach((n) => { n.textContent = me.user.slice(0, 1).toUpperCase(); });
    } catch { /* handled by api() */ }
  };

  window.hideSplash = function (splash, startedAt, minMs = 650) {
    const wait = Math.max(0, minMs - (performance.now() - startedAt));
    setTimeout(() => splash.classList.add('done'), wait);
  };
})();
