// Filter Request List: pilihan departemen mengikuti Company terpilih (cascade).
// "All companies" = semua departemen dalam lingkup user. Server tetap menyaring ulang (lingkup + Company).
(function () {
    'use strict';

    var company = document.querySelector('[data-filter-company]');
    var department = document.querySelector('[data-filter-department]');
    if (!company || !department) return;

    var apply = function () {
        var co = company.value;
        Array.from(department.options).forEach(function (opt) {
            if (!opt.value) return;
            var match = !co || opt.getAttribute('data-cocode') === co;
            opt.hidden = !match;
            opt.disabled = !match;
        });
        var selected = department.selectedOptions[0];
        if (selected && selected.value && selected.disabled) department.value = '';
    };

    company.addEventListener('change', apply);
    apply();
})();
