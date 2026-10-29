// Script da landing page. Fica num arquivo (e não dentro do HTML) para a
// Content-Security-Policy não precisar liberar scripts inline (deploy/security-headers.caddy).

// Versão e tamanho do APK publicado (deploy/publish-apk.sh grava esse arquivo).
fetch('/download/version.json', { cache: 'no-store' })
  .then(r => r.ok ? r.json() : null)
  .then(v => {
    if (!v) return;
    const mb = bytes => Math.round(bytes / 1048576);
    document.querySelectorAll('.js-meta').forEach(el => {
      el.textContent = `Versão ${v.version} · ${mb(v.size)} MB · Android ${v.minAndroid}+`;
    });
    if (v.universalSize) {
      document.querySelectorAll('.js-universal').forEach(el => {
        el.textContent += ` (${mb(v.universalSize)} MB)`;
      });
    }
  })
  .catch(() => {});

// Seções entram com um fade curto quando aparecem (uma vez). Sem suporte, tudo já aparece.
if ('IntersectionObserver' in window) {
  const io = new IntersectionObserver(entries => entries.forEach(e => {
    if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
  }), { rootMargin: '0px 0px -40px 0px' });
  document.querySelectorAll('.reveal').forEach(el => io.observe(el));
} else {
  document.querySelectorAll('.reveal').forEach(el => el.classList.add('in'));
}
