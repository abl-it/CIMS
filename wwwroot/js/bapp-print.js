// Cetak Berita Acara (T6-1, BR-94): tombol Print / Save as PDF memakai dialog print browser.
(function () {
    'use strict';
    var btn = document.querySelector('[data-print]');
    if (btn) btn.addEventListener('click', function () { window.print(); });
})();
