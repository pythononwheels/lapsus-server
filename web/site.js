// Shared header + footer for every static page, so navigation is identical
// everywhere and lives in one place. Each page includes:
//   <div id="site-header"></div> ... <div id="site-footer"></div>
//   <script src="/site.js"></script>
(function () {
  var path = location.pathname.replace(/\/index\.html$/, "/").replace(/\.html$/, "");
  if (path === "" || path === "/index") path = "/";

  var NAV = [
    { href: "/how", label: "How it works" },
    { href: "/mission", label: "The mission" },
    { href: "/why", label: "Why LAPSUS" }
  ];

  function navItems() {
    return NAV.map(function (i) {
      return path === i.href
        ? '<span class="muted" style="font-size:.95rem">' + i.label + "</span>"
        : '<a href="' + i.href + '" class="lnk">' + i.label + "</a>";
    }).join("");
  }

  var getCta =
    path === "/get"
      ? '<span class="muted" style="font-size:.95rem">Get the app</span>'
      : '<a href="/get" class="btn btn-primary">Get the app</a>';

  var header =
    '<nav class="nav">' +
    '<a href="/" class="brand"><img src="/assets/lapsus.png" alt="LAPSUS" /> LAPSUS</a>' +
    navItems() +
    '<span class="spacer"></span>' +
    getCta +
    "</nav>";

  var footer =
    '<footer class="footer">' +
    "<span>LAPSUS — early prototype</span>" +
    '<span class="spacer"></span>' +
    '<a href="/how">How it works</a>' +
    '<a href="/mission">The mission</a>' +
    '<a href="/why">Why LAPSUS</a>' +
    '<a href="/stack">Under the hood</a>' +
    '<a href="/guardrail">Guardrail</a>' +
    '<a href="https://github.com/pythononwheels/lapsus-app/blob/main/LICENSE" target="_blank" rel="noopener">AGPL-3.0</a>' +
    "</footer>";

  var h = document.getElementById("site-header");
  var f = document.getElementById("site-footer");
  if (h) h.outerHTML = header;
  if (f) f.outerHTML = footer;
})();
