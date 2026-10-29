// Standar notifikasi aplikasi (lihat CLAUDE.md > "Notifikasi dan Dialog").
//   notify.success(message)                    -> Bootstrap Toast
//   notify.error(message, title?)              -> SweetAlert2 (icon error)
//   notify.confirm({ title, text, confirmText, cancelText, danger }) -> Promise<boolean>
//   notify.fetchError(responseOrError)         -> SweetAlert2 untuk error fetch
// Konfirmasi deklaratif: form/button/a dengan data-confirm="pesan"
//   (opsional: data-confirm-title, data-confirm-ok, data-confirm-danger="true").
// Penjaga perubahan belum tersimpan: form[data-dirty-guard] + a[data-confirm-if-dirty="#idForm"][data-confirm].
(function () {
    'use strict';

    var TOAST_DELAY = 4000;

    function toastContainer() {
        return document.getElementById('toast-container');
    }

    function success(message) {
        var container = toastContainer();
        if (!container || !message) return;

        var el = document.createElement('div');
        el.className = 'toast align-items-center text-bg-success border-0';
        el.setAttribute('role', 'status');
        el.setAttribute('aria-live', 'polite');
        el.setAttribute('aria-atomic', 'true');

        var flex = document.createElement('div');
        flex.className = 'd-flex';

        var body = document.createElement('div');
        body.className = 'toast-body';
        body.textContent = message;

        var close = document.createElement('button');
        close.type = 'button';
        close.className = 'btn-close btn-close-white me-2 m-auto';
        close.setAttribute('data-bs-dismiss', 'toast');
        close.setAttribute('aria-label', 'Tutup');

        flex.appendChild(body);
        flex.appendChild(close);
        el.appendChild(flex);
        container.appendChild(el);

        el.addEventListener('hidden.bs.toast', function () { el.remove(); });
        new bootstrap.Toast(el, { autohide: true, delay: TOAST_DELAY }).show();
    }

    function error(message, title) {
        return Swal.fire({
            icon: 'error',
            title: title || 'Terjadi kesalahan',
            text: message || 'Terjadi kesalahan yang tidak diketahui.',
            confirmButtonText: 'Tutup',
            buttonsStyling: false,
            customClass: { confirmButton: 'btn btn-primary btn-lg' }
        });
    }

    function confirmDialog(options) {
        var o = options || {};
        return Swal.fire({
            icon: 'question',
            title: o.title || 'Konfirmasi',
            text: o.text || '',
            showCancelButton: true,
            confirmButtonText: o.confirmText || 'Ya',
            cancelButtonText: o.cancelText || 'Batal',
            reverseButtons: true,
            focusCancel: !!o.danger,
            buttonsStyling: false,
            customClass: {
                confirmButton: 'btn btn-lg ' + (o.danger ? 'btn-danger' : 'btn-primary'),
                cancelButton: 'btn btn-lg btn-secondary'
            }
        }).then(function (result) { return result.isConfirmed === true; });
    }

    function statusMessage(status) {
        if (status === 400) return 'Permintaan tidak valid.';
        if (status === 401 || status === 403) return 'Anda tidak memiliki akses untuk aksi ini.';
        if (status === 404) return 'Data atau halaman tidak ditemukan.';
        if (status >= 500) return 'Terjadi kesalahan pada server. Silakan coba lagi.';
        return 'Permintaan gagal (HTTP ' + status + ').';
    }

    // Terima Response (non-2xx) atau Error (kegagalan jaringan).
    async function fetchError(responseOrError) {
        if (typeof Response !== 'undefined' && responseOrError instanceof Response) {
            var message = statusMessage(responseOrError.status);
            try {
                var type = responseOrError.headers.get('content-type') || '';
                if (type.indexOf('json') !== -1) {
                    var data = await responseOrError.clone().json();
                    message = data.message || data.detail || data.title || message;
                }
            } catch (e) { /* pakai pesan standar */ }
            return error(message);
        }
        return error('Tidak dapat terhubung ke server. Periksa koneksi Anda lalu coba lagi.', 'Koneksi gagal');
    }

    window.notify = { success: success, error: error, confirm: confirmDialog, fetchError: fetchError };

    // ---- Konfirmasi deklaratif ----
    function optionsFrom(el) {
        return {
            title: el.getAttribute('data-confirm-title') || 'Konfirmasi',
            text: el.getAttribute('data-confirm'),
            confirmText: el.getAttribute('data-confirm-ok') || 'Ya',
            danger: el.getAttribute('data-confirm-danger') === 'true'
        };
    }

    function isDirtyTarget(link) {
        var selector = link.getAttribute('data-confirm-if-dirty');
        if (selector === null) return true; // tanpa guard: selalu konfirmasi
        var form = selector ? document.querySelector(selector) : null;
        return !!form && form.getAttribute('data-dirty') === '1';
    }

    // Form: konfirmasi lalu kirim ulang lewat requestSubmit (semua field + token anti-forgery ikut terkirim).
    document.addEventListener('submit', function (e) {
        var form = e.target;
        if (!(form instanceof HTMLFormElement)) return;

        if (!form.hasAttribute('data-confirm')) return;
        if (form.getAttribute('data-confirmed') === '1') {
            form.removeAttribute('data-confirmed');
            return;
        }

        e.preventDefault();
        var submitter = e.submitter;
        confirmDialog(optionsFrom(form)).then(function (ok) {
            if (!ok) return;
            form.setAttribute('data-confirmed', '1');
            if (submitter) form.requestSubmit(submitter); else form.requestSubmit();
        });
    });

    // Button / link dengan data-confirm.
    document.addEventListener('click', function (e) {
        var el = e.target.closest('button[data-confirm], a[data-confirm]');
        if (!el) return;

        if (el.tagName === 'A') {
            if (!isDirtyTarget(el)) return;
            e.preventDefault();
            confirmDialog(optionsFrom(el)).then(function (ok) {
                if (ok) window.location.href = el.href;
            });
            return;
        }

        // Button: bila form-nya sendiri sudah punya data-confirm, biarkan handler submit yang menangani.
        if (el.form && el.form.hasAttribute('data-confirm')) return;
        if (el.getAttribute('data-confirmed') === '1') {
            el.removeAttribute('data-confirmed');
            return;
        }
        e.preventDefault();
        confirmDialog(optionsFrom(el)).then(function (ok) {
            if (!ok) return;
            el.setAttribute('data-confirmed', '1');
            el.click();
        });
    });

    // Penjaga perubahan belum tersimpan.
    function markDirty(e) {
        var form = e.target.closest ? e.target.closest('form[data-dirty-guard]') : null;
        if (form) form.setAttribute('data-dirty', '1');
    }
    document.addEventListener('input', markDirty);
    document.addEventListener('change', markDirty);

    // ---- Notifikasi dari server (TempData / error umum ModelState) ----
    document.addEventListener('DOMContentLoaded', function () {
        var holder = document.getElementById('server-notifications');
        if (!holder) return;

        var successMessage = holder.getAttribute('data-success');
        var errorMessage = holder.getAttribute('data-error');
        if (successMessage) success(successMessage);
        if (errorMessage) error(errorMessage);
    });
})();
