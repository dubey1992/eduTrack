// The 404 page's two live details (web/404.html). The path is read here
// rather than written by a server, so the page stays a plain static asset
// any host can serve.
document.getElementById('asked-for').textContent = window.location.pathname;
document.getElementById('year').textContent = new Date().getFullYear();
