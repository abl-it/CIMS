// Halaman Actual Cost Upload (T5-3): tampilkan spinner dan cegah klik ganda saat file dikirim.
(function () {
    'use strict';

    var form = document.querySelector('form[data-upload-form]');
    if (!form) return;

    form.addEventListener('submit', function () {
        var button = form.querySelector('[data-upload-submit]');
        var spinner = form.querySelector('[data-upload-spinner]');
        if (spinner) spinner.classList.remove('d-none');
        // Dinonaktifkan setelah event submit selesai agar data form tetap terkirim
        setTimeout(function () { if (button) button.disabled = true; }, 0);
    });
})();
