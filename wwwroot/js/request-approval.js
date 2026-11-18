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

    // Addendum (T4-4): form addendum baru muncul setelah "New Addendum" diklik -> gulir ke form dan fokus field pertama;
    // tombol header ditandai aktif selama form terbuka.
    var addendumPanel = document.getElementById('addendumCreatePanel');
    if (addendumPanel) {
        var newButton = document.querySelector('[data-addendum-new]');
        addendumPanel.addEventListener('shown.bs.collapse', function () {
            addendumPanel.scrollIntoView({ behavior: 'smooth', block: 'start' });
            var first = addendumPanel.querySelector('input:not([type="hidden"])');
            if (first) first.focus({ preventScroll: true });
            if (newButton) newButton.setAttribute('aria-expanded', 'true');
        });
        addendumPanel.addEventListener('hidden.bs.collapse', function () {
            if (newButton) newButton.setAttribute('aria-expanded', 'false');
        });
    }
})();
