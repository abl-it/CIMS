// Aksi di halaman Details request: approval (T2-3) dan Feasibility Civil (T3-1).
// - form[data-remarks-form]: tombol data-requires-remarks (Revise / Reject) wajib catatan (BR-08), dicek SEBELUM
//   dialog konfirmasi notify.js muncul. Listener dipasang langsung di tombol (fase target), jadi berjalan lebih dulu
//   daripada handler data-confirm di document.
// - Form ubah kategori: sub-kategori hanya milik kategori terpilih (BR-02).
// Validasi akhir tetap di stored procedure.
(function () {
    'use strict';

    document.querySelectorAll('form[data-remarks-form]').forEach(function (form) {
        var remarks = form.querySelector('textarea[name="remarks"]');
        if (!remarks) return;

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
    });

    var category = document.querySelector('[data-cascade-category]');
    var subCategory = document.querySelector('[data-cascade-subcategory]');
    if (category && subCategory) {
        var applyCategory = function () {
            Array.from(subCategory.options).forEach(function (opt) {
                if (!opt.value) return;
                var match = opt.dataset.category === category.value;
                opt.hidden = !match;
                opt.disabled = !match;
            });
            var selected = subCategory.selectedOptions[0];
            if (selected && selected.value && selected.disabled) subCategory.value = '';
        };
        category.addEventListener('change', applyCategory);
        applyCategory();
    }
})();
