// Approval request di halaman Details (T2-3).
// Revise / Reject wajib catatan (BR-08): dicek SEBELUM dialog konfirmasi notify.js muncul.
// Listener dipasang langsung di tombol (fase target), jadi berjalan lebih dulu daripada handler data-confirm di document.
// Validasi akhir tetap di stored procedure.
(function () {
    'use strict';

    var form = document.getElementById('approvalForm');
    if (!form) return;

    var remarks = document.getElementById('approvalRemarks');

    form.querySelectorAll('button[data-requires-remarks="true"]').forEach(function (btn) {
        btn.addEventListener('click', function (e) {
            if (remarks.value.trim() !== '') return;
            e.preventDefault();
            e.stopPropagation();
            remarks.classList.add('is-invalid');
            remarks.focus();
        });
    });

    remarks.addEventListener('input', function () {
        if (remarks.value.trim() !== '') remarks.classList.remove('is-invalid');
    });
})();
