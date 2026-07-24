// ============================================================
// app.js
// منطق الواجهة الكامل — نفس الشاشات والتصميم، لكن بيتكلم مع
// Supabase عن طريق api.js بدل google.script.run
// ============================================================

const state = {
  user: null,
  settings: null,
  currentPage: 'dashboard',
  treasuryRevealed: { total: false, cash: false, bank: false }
};

const NAV_GROUPS = [
  { label: 'نظرة عامة', items: [
    { key: 'dashboard', label: 'الداشبورد', icon: '📊', module: 'Dashboard' },
    { key: 'pos', label: 'شاشة الكاشير', icon: '🧾', module: 'POS' }
  ]},
  { label: 'العمليات', items: [
    { key: 'sales', label: 'المبيعات', icon: '💰', module: 'Sales' },
    { key: 'inventory', label: 'المخزون', icon: '📦', module: 'Inventory' },
    { key: 'warehouses', label: 'المخازن', icon: '🏬', module: 'Inventory' },
    { key: 'expenses', label: 'المصروفات', icon: '💸', module: 'Expenses' },
    { key: 'suppliers', label: 'الموردون والمشتريات', icon: '🚚', module: 'Suppliers' },
    { key: 'orders', label: 'الأوردرات والعملاء', icon: '🧍', module: 'Orders' },
    { key: 'invoices', label: 'الفواتير', icon: '📄', module: 'Invoices' }
  ]},
  { label: 'المالية', items: [
    { key: 'capital', label: 'رأس المال والشركاء', icon: '🤝', module: 'Capital' },
    { key: 'pettycash', label: 'العهدة', icon: '👛', module: 'PettyCash' },
    { key: 'treasury', label: 'الخزنة والبنوك', icon: '🏦', module: 'Reports' },
    { key: 'accounts', label: 'شجرة الحسابات', icon: '🗂️', module: 'Reports' },
    { key: 'costcenters', label: 'مراكز التكلفة', icon: '🎯', module: 'Expenses' },
    { key: 'reports', label: 'التقارير', icon: '📈', module: 'Reports' }
  ]},
  { label: 'الإدارة', items: [
    { key: 'hr', label: 'الموارد البشرية', icon: '👥', module: 'HR' },
    { key: 'users', label: 'المستخدمون والصلاحيات', icon: '🔐', module: 'Users' },
    { key: 'recyclebin', label: 'سلة المحذوفات', icon: '🗑️', module: 'Inventory' },
    { key: 'settings', label: 'الإعدادات', icon: '⚙️', module: 'Settings' }
  ]}
];

const PAGE_META = {
  dashboard: ['الداشبورد', 'نظرة سريعة وشاملة على أداء البيزنس'],
  pos: ['شاشة الكاشير', 'بيع سريع في المحل'],
  sales: ['المبيعات', 'تسجيل ومتابعة عمليات البيع'],
  inventory: ['المخزون', 'الفئات، المنتجات، المتغيرات، والكميات'],
  warehouses: ['المخازن', 'إدارة الفروع/المخازن المتعددة'],
  expenses: ['المصروفات', 'تسجيل وتصنيف كل المصروفات'],
  suppliers: ['الموردون والمشتريات', 'تسجيل مشتريات جديدة ومتابعة الموردين'],
  orders: ['الأوردرات والعملاء', 'طلبات الأونلاين وسجل العملاء'],
  invoices: ['الفواتير', 'متابعة حالة التحصيل'],
  capital: ['رأس المال والشركاء', 'نسب الملكية والأرباح'],
  pettycash: ['العهدة', 'حركة الكاش اليومي بالمحل'],
  reports: ['التقارير', 'قائمة الدخل، الضريبة، المواسم'],
  hr: ['الموارد البشرية', 'الموظفون، المرتبات، الحضور، السلف'],
  users: ['المستخدمون والصلاحيات', 'إدارة اليوزرات وصلاحيات كل قسم'],
  settings: ['الإعدادات', 'إعدادات البراند والنظام'],
  treasury: ['الخزنة والبنوك', 'حسابات كاش وبنوك متعددة والتحويل بينها'],
  accounts: ['شجرة الحسابات', 'الهيكل المحاسبي الكامل للبراند'],
  costcenters: ['مراكز التكلفة', 'ربط المصروفات والمبيعات بمركز تكلفة'],
  recyclebin: ['سلة المحذوفات', 'استرجاع أي عنصر اتحذف بالغلط']
};

// ------------------------------------------------------------
// نظام المودال العام
// ------------------------------------------------------------
function openModal(title, desc, bodyHtml, actionsHtml, wide) {
  const box = document.getElementById('modalBox');
  box.classList.toggle('wide', !!wide);
  box.innerHTML =
    '<div class="modal-close-x" onclick="closeModal()">✕</div>' +
    '<div class="modal-title">' + title + '</div>' +
    (desc ? '<div class="modal-desc">' + desc + '</div>' : '') +
    '<div id="modalBody">' + (bodyHtml || '') + '</div>' +
    '<div class="modal-actions">' + (actionsHtml || '') + '</div>';
  document.getElementById('modalOverlay').style.display = 'flex';
  enhanceSelects_(box);
}
function closeModal() { document.getElementById('modalOverlay').style.display = 'none'; }

function openConfirmModal(title, desc, onConfirm) {
  openModal(title, desc, '', '<button class="btn secondary" onclick="closeModal()">إلغاء</button><button class="btn" onclick="window.__modalConfirmCb()">تأكيد</button>');
  window.__modalConfirmCb = function () { closeModal(); onConfirm(); };
}

// ------------------------------------------------------------
// تسجيل الدخول
// ------------------------------------------------------------
async function handleLogin() {
  const username = document.getElementById('loginUsername').value.trim();
  const password = document.getElementById('loginPassword').value;
  const errorEl = document.getElementById('loginError');
  const btn = document.getElementById('loginBtn');

  if (!username || !password) { errorEl.textContent = 'اكتب اليوزرنيم وكلمة المرور'; return; }

  btn.innerHTML = '<span class="spinner"></span> جاري الدخول...';
  btn.disabled = true;
  errorEl.textContent = '';

  try {
    const res = await api.login(username, password);
    btn.textContent = 'دخول'; btn.disabled = false;
    if (!res.success) { errorEl.textContent = '⚠️ ' + res.error; return; }
    await bootApp();
  } catch (err) {
    btn.textContent = 'دخول'; btn.disabled = false;
    errorEl.textContent = '⚠️ حصل خطأ: ' + err.message;
  }
}

async function handleLogout() { await api.logout(); location.reload(); }

// ------------------------------------------------------------
// بداية تشغيل التطبيق
// ------------------------------------------------------------
async function bootApp() {
  try {
    const shell = await api.getAppShellData();
    state.user = shell.user;
    state.settings = shell.settings;
    applySettingsToUI();
    renderSidebar();
    populateUserChip_();

    document.getElementById('loginScreen').style.display = 'none';
    document.getElementById('app').style.display = 'flex';

    navigate(state.user.isCashier ? 'pos' : 'dashboard');
    refreshNotifications();
  } catch (err) {
    document.getElementById('loginScreen').style.display = 'flex';
    document.getElementById('app').style.display = 'none';
  }
}

function applySettingsToUI() {
  const s = state.settings;
  document.body.setAttribute('data-theme', s.darkMode ? 'dark' : 'light');
  document.getElementById('themeToggleBtn').textContent = s.darkMode ? '🌙' : '☀️';
  document.documentElement.style.setProperty('--accent', s.accentColor || '#e94560');
  document.getElementById('sidebarBrandName').textContent = s.brandName || 'براندي';
  if (s.logoUrl) {
    const logo = document.getElementById('sidebarLogo');
    logo.src = s.logoUrl; logo.style.display = 'block';
    document.getElementById('sidebarLogoFallback').style.display = 'none';
  }
}

function populateUserChip_() {
  document.getElementById('userNameChip').textContent = state.user.fullName || state.user.username;
  document.getElementById('userRoleChip').textContent = state.user.role;
  document.getElementById('userAvatar').textContent = (state.user.fullName || state.user.username).charAt(0);
}

// ------------------------------------------------------------
// القائمة الجانبية
// ------------------------------------------------------------
function renderSidebar() {
  const nav = document.getElementById('navList');
  if (state.user.isCashier) {
    nav.innerHTML = '<div class="nav-item active" data-key="pos" onclick="navigate(\'pos\')"><span class="nav-icon">🧾</span><span>شاشة الكاشير</span></div>' +
      '<div class="nav-item" onclick="handleLogout()"><span class="nav-icon">🚪</span><span>تسجيل الخروج</span></div>';
    return;
  }

  let html = '';
  NAV_GROUPS.forEach(function (group) {
    const visibleItems = group.items.filter(function (item) {
      const perm = state.user.role === 'أدمن' ? 'تعديل' : (state.user.permissions[item.module] || (state.user.role === 'شريك' ? 'عرض' : 'مخفي'));
      return perm !== 'مخفي';
    });
    if (visibleItems.length === 0) return;
    html += '<div class="nav-section-label">' + group.label + '</div>';
    visibleItems.forEach(function (item) {
      html += '<div class="nav-item' + (state.currentPage === item.key ? ' active' : '') + '" data-key="' + item.key + '" onclick="navigate(\'' + item.key + '\')">' +
        '<span class="nav-icon">' + item.icon + '</span><span>' + item.label + '</span></div>';
    });
  });
  html += '<div class="nav-section-label">الحساب</div><div class="nav-item" onclick="handleLogout()"><span class="nav-icon">🚪</span><span>تسجيل الخروج</span></div>';
  nav.innerHTML = html;
}

function toggleSidebar() { document.getElementById('sidebar').classList.toggle('collapsed'); }

async function toggleTheme() {
  const isDark = document.body.getAttribute('data-theme') === 'dark';
  document.body.setAttribute('data-theme', isDark ? 'light' : 'dark');
  document.getElementById('themeToggleBtn').textContent = isDark ? '☀️' : '🌙';
  await api.updateSetting(null, 'darkMode', String(!isDark));
}

// ------------------------------------------------------------
// التنقل بين الصفحات
// ------------------------------------------------------------
function navigate(pageKey) {
  state.currentPage = pageKey;
  document.querySelectorAll('.nav-item').forEach(function (el) { el.classList.toggle('active', el.dataset.key === pageKey); });

  const meta = PAGE_META[pageKey] || ['', ''];
  document.getElementById('pageTitle').textContent = meta[0];
  document.getElementById('pageSubtitle').textContent = meta[1];

  document.getElementById('content').innerHTML = renderSkeleton_();

  const renderers = {
    dashboard: renderDashboardPage, pos: renderPosPage, sales: renderSalesPage,
    inventory: renderInventoryPage, warehouses: renderWarehousesPage, expenses: renderExpensesPage, suppliers: renderSuppliersPage,
    orders: renderOrdersPage, invoices: renderInvoicesPage, capital: renderCapitalPage,
    pettycash: renderPettyCashPage, reports: renderReportsPage, hr: renderHrPage,
    users: renderUsersPage, settings: renderSettingsPage,
    treasury: renderTreasuryPage, accounts: renderAccountsPage,
    costcenters: renderCostCentersPage, recyclebin: renderRecycleBinPage
  };
  (renderers[pageKey] || renderComingSoon_)();
}

function renderSkeleton_() { return '<div class="grid grid-4">' + '<div class="loading-skeleton" style="height:110px; border-radius:16px;"></div>'.repeat(4) + '</div>'; }
function renderComingSoon_() { document.getElementById('content').innerHTML = '<div class="card"><div class="empty-state"><span class="emoji">🚧</span><div class="msg">الشاشة دي هتُبنى قريبًا</div></div></div>'; }
function setContent_(html) { document.getElementById('content').innerHTML = '<div class="page-fade">' + html + '</div>'; enhanceSelects_(document.getElementById('content')); }

// ============================================================
// محرّك القوائم المنسدلة المخصصة (Custom Select) — بيحوّل أي
// <select> عادي لقائمة بشكل البرنامج، مع الحفاظ الكامل على
// قيمته وأحداث onchange بتاعته (شفاف تمامًا لباقي الكود)
// ============================================================
function enhanceSelects_(container) {
  if (!container) return;
  container.querySelectorAll('select').forEach(function (select) {
    const existingWrap = select.previousElementSibling;
    if (existingWrap && existingWrap.classList && existingWrap.classList.contains('cs-wrap')) existingWrap.remove();

    const wrap = document.createElement('div');
    wrap.className = 'cs-wrap';
    const trigger = document.createElement('div');
    trigger.className = 'cs-trigger';
    trigger.tabIndex = 0;
    const labelSpan = document.createElement('span');
    labelSpan.className = 'cs-label';
    const arrowSpan = document.createElement('span');
    arrowSpan.className = 'cs-arrow';
    arrowSpan.textContent = '▾';
    trigger.appendChild(labelSpan);
    trigger.appendChild(arrowSpan);

    const panel = document.createElement('div');
    panel.className = 'cs-panel';

    function syncLabel() {
      const opt = select.options[select.selectedIndex];
      labelSpan.textContent = opt ? opt.textContent : '';
    }
    function buildOptions() {
      panel.innerHTML = '';
      Array.from(select.options).forEach(function (opt, idx) {
        const optEl = document.createElement('div');
        optEl.className = 'cs-option' + (idx === select.selectedIndex ? ' selected' : '') + (opt.disabled ? ' disabled' : '');
        optEl.textContent = opt.textContent;
        optEl.onclick = function (e) {
          e.stopPropagation();
          if (opt.disabled) return;
          select.selectedIndex = idx;
          syncLabel();
          closePanel();
          select.dispatchEvent(new Event('change', { bubbles: true }));
        };
        panel.appendChild(optEl);
      });
    }
    function openPanel() {
      document.querySelectorAll('.cs-panel.open').forEach(function (p) { p.classList.remove('open'); });
      document.querySelectorAll('.cs-trigger.open').forEach(function (t) { t.classList.remove('open'); });
      buildOptions();
      panel.classList.add('open');
      trigger.classList.add('open');
    }
    function closePanel() { panel.classList.remove('open'); trigger.classList.remove('open'); }

    trigger.onclick = function (e) { e.stopPropagation(); panel.classList.contains('open') ? closePanel() : openPanel(); };

    wrap.appendChild(trigger);
    wrap.appendChild(panel);
    select.insertAdjacentElement('beforebegin', wrap);
    syncLabel();

    select.__csRefresh = function () { syncLabel(); };
  });
}

document.addEventListener('click', function (e) {
  if (!e.target.closest('.cs-wrap')) {
    document.querySelectorAll('.cs-panel.open').forEach(function (p) { p.classList.remove('open'); });
    document.querySelectorAll('.cs-trigger.open').forEach(function (t) { t.classList.remove('open'); });
  }
});

// تُستدعى بعد أي تحديث ديناميكي لمحتوى select (زي الفئة الفرعية بعد تغيير الرئيسية)
function refreshSelect_(selectId) {
  const select = document.getElementById(selectId);
  if (select) enhanceSelects_(select.parentElement);
}

// ============================================================
// الداشبورد
// ============================================================
async function renderDashboardPage() {
  try {
    const data = await api.getDashboardData();
    window.__dashboardData = data;
    setContent_(buildDashboardHtml_(data));
  } catch (err) { showErrorToast_(err); }
}

function buildDashboardHtml_(d) {
  const cur = state.settings.currency || 'جنيه';
  let html = '';

  html += '<div class="grid grid-4">';
  html += statCard_('💰', 'إجمالي المبيعات (الشهر)', formatMoney_(d.sales.total, cur), 'أونلاين ' + formatMoney_(d.sales.online, cur) + ' · محل ' + formatMoney_(d.sales.store, cur), true);
  html += statCard_('💸', 'المصروفات (الشهر)', formatMoney_(d.expenses.total, cur), '', false);
  html += statCard_('⚠️', 'منتجات منخفضة', d.lowStockCount, '', false);
  html += statCard_('⚖️', 'مستحقات (عملاء/موردين)', formatMoney_(d.receivables, cur) + ' / ' + formatMoney_(d.payables, cur), 'لينا / علينا', false);
  html += '</div>';

  html += '<div class="section-title">الخزنة <span class="count-chip">خصوصية 👁</span></div>';
  html += '<div class="grid grid-4">';
  html += unifiedTreasuryCardHtml_(d.treasury, cur);
  html += statCard_('👛', 'العهدة', formatMoney_(d.pettyCash, cur), '', false);
  html += '</div>';

  if (d.partnersShares && d.partnersShares.length > 0) {
    html += '<div class="section-title">حصص الشركاء</div><div class="card">';
    d.partnersShares.forEach(function (p) {
      html += '<div class="list-item"><span>' + p.name + ' <span class="pill info">' + (p.ownershipPercent || 0) + '% ملكية</span></span><b>' + formatMoney_(p.share, cur) + '</b></div>';
    });
    html += '</div>';
  }

  html += '<div class="section-title">مؤشرات الربحية</div><div class="grid grid-4">';
  html += statCard_('📈', 'صافي الربح', '<span class="' + (d.profit.netProfit >= 0 ? 'money-positive' : 'money-negative') + '">' + formatMoney_(d.profit.netProfit, cur) + '</span>', 'هامش ' + d.profit.npMargin + '%', true);
  html += statCard_('🧾', 'عدد عمليات البيع', d.sales.count, '', false);
  html += statCard_('📐', 'GP / Sales', d.profit.gpMargin + '%', '', false);
  html += statCard_('📐', 'NP / Sales', d.profit.npMargin + '%', '', false);
  html += '</div>';

  html += '<div class="section-title">تنبيهات مخزون منخفض <span class="count-chip">' + d.lowStockCount + '</span></div><div class="card">';
  if (!d.lowStockAlerts || d.lowStockAlerts.length === 0) html += emptyRow_('✅', 'لا يوجد تنبيهات حاليًا');
  else d.lowStockAlerts.forEach(function (a) {
    html += '<div class="list-item"><span>' + a.productName + ' — ' + a.color + ' ' + a.size + '</span><span class="pill warning">الكمية: ' + a.quantity + '</span></div>';
  });
  html += '</div>';

  html += '<div class="section-title">أحدث العمليات</div><div class="card">';
  if (!d.recentOperations || d.recentOperations.length === 0) html += emptyRow_('🕊️', 'لا يوجد عمليات بعد');
  else d.recentOperations.slice(0, 8).forEach(function (op) {
    html += '<div class="list-item"><span>' + op.username + ' — ' + op.operation + '</span><span style="color:var(--text-dim); font-size:11.5px;">' + formatDate_(op.time) + '</span></div>';
  });
  html += '</div>';

  return html;
}

function statCard_(icon, label, value, sub, accent) {
  return '<div class="card stat-card' + (accent ? ' accent' : '') + '">' +
    '<div class="stat-icon">' + icon + '</div><div class="card-label">' + label + '</div><div class="card-value">' + value + '</div>' +
    (sub ? '<div class="card-sub">' + sub + '</div>' : '') + '</div>';
}
function emptyRow_(icon, msg) { return '<div class="empty-state" style="padding:26px;"><span class="emoji" style="font-size:24px;">' + icon + '</span><div class="msg" style="font-size:12.5px;">' + msg + '</div></div>'; }

function unifiedTreasuryCardHtml_(treasury, currency) {
  const totalRevealed = state.treasuryRevealed.total;
  const cashRevealed = state.treasuryRevealed.cash;
  const bankRevealed = state.treasuryRevealed.bank;

  return '<div class="card stat-card" style="grid-column: span 2;">' +
    '<div class="card-row">' +
      '<div class="stat-icon">🔒</div>' +
      '<button class="eye-btn" onclick="toggleTreasuryEye_(\'total\')">' + (totalRevealed ? '🙈' : '👁') + '</button>' +
    '</div>' +
    '<div class="card-label" style="margin-top:10px;">إجمالي الخزنة</div>' +
    '<div class="card-value big ' + (totalRevealed ? '' : 'hidden-value') + '">' + (totalRevealed ? formatMoney_(treasury.total, currency) : '••••••') + '</div>' +
    '<div style="display:flex; gap:22px; margin-top:14px; padding-top:14px; border-top:1px solid var(--border);">' +
      '<div style="flex:1;"><div class="card-row"><span class="card-label" style="margin:0;">💵 كاش</span>' +
        '<button class="eye-btn" style="padding:3px 7px; font-size:11px;" onclick="toggleTreasuryEye_(\'cash\')">' + (cashRevealed ? '🙈' : '👁') + '</button></div>' +
        '<div style="font-size:15px; font-weight:800; margin-top:4px;" class="' + (cashRevealed ? '' : 'hidden-value') + '">' + (cashRevealed ? formatMoney_(treasury.cash, currency) : '••••') + '</div></div>' +
      '<div style="flex:1;"><div class="card-row"><span class="card-label" style="margin:0;">🏦 بنك</span>' +
        '<button class="eye-btn" style="padding:3px 7px; font-size:11px;" onclick="toggleTreasuryEye_(\'bank\')">' + (bankRevealed ? '🙈' : '👁') + '</button></div>' +
        '<div style="font-size:15px; font-weight:800; margin-top:4px;" class="' + (bankRevealed ? '' : 'hidden-value') + '">' + (bankRevealed ? formatMoney_(treasury.bank, currency) : '••••') + '</div></div>' +
    '</div></div>';
}
function toggleTreasuryEye_(key) { state.treasuryRevealed[key] = !state.treasuryRevealed[key]; setContent_(buildDashboardHtml_(window.__dashboardData)); }

// ============================================================
// شاشة الكاشير (POS)
// ============================================================
let posCart = [];

function renderPosPage() {
  setContent_(
    '<div class="grid grid-2">' +
      '<div class="card">' +
        '<div class="card-heading">🔍 بحث عن منتج</div>' +
        '<div class="card-desc">اكتب اسم أو كود المنتج عشان تضيفه للسلة</div>' +
        '<div class="field"><input type="text" id="posSearchInput" oninput="posSearch_(this.value)" placeholder="مثال: تيشرت أساسي..."></div>' +
        '<div id="posSearchResults" style="margin-top:14px;"></div>' +
      '</div>' +
      '<div class="card">' +
        '<div class="card-heading">🛒 السلة الحالية</div>' +
        '<div id="posCartList" style="margin:14px 0;"></div>' +
        '<div class="form-grid">' +
          '<div class="field"><label>الخصم</label><input type="number" id="posDiscount" value="0"></div>' +
          '<div class="field"><label>طريقة الدفع</label><select id="posPaymentMethod"><option>كاش</option><option>فودافون كاش</option><option>بطاقة</option><option>انستاباي</option></select></div>' +
        '</div>' +
        '<button class="btn success block" style="margin-top:16px;" onclick="submitPosSale_()">✅ إتمام البيع</button>' +
        '<button class="btn danger block" style="margin-top:10px;" onclick="openPosReturnModal_()">↩️ مرتجع بيعة سابقة</button>' +
      '</div>' +
    '</div>' +
    '<div class="section-title">ملخص اليوم</div><div id="posTodaySummary" class="grid grid-3"></div>'
  );
  posCart = [];
  loadPosSummary_();
}

function openPosReturnModal_() {
  openModal('مرتجع بيعة سابقة', 'ابحث برقم الفاتورة أو اسم العميل',
    '<div class="field"><input type="text" id="posReturnSearchInput" oninput="posReturnSearch_(this.value)" placeholder="ابحث..."></div>' +
    '<div id="posReturnResults" style="margin-top:12px; max-height:280px; overflow-y:auto;"></div>',
    '<button class="btn secondary" onclick="closeModal()">إغلاق</button>');
}

async function posReturnSearch_(query) {
  if (!query || query.length < 2) { document.getElementById('posReturnResults').innerHTML = ''; return; }
  try {
    const results = await api.posSearchSaleForReturn(query);
    const cur = state.settings.currency || 'جنيه';
    document.getElementById('posReturnResults').innerHTML = results.length === 0 ? emptyRow_('🔎', 'لا يوجد نتائج') :
      results.map(function (r) {
        return '<div class="list-item"><span>' + r.saleId + ' — ' + (r.customerName || 'بدون اسم') + '</span>' +
          '<span>' + formatMoney_(r.total, cur) + ' <button class="btn sm" onclick="confirmPosReturn_(\'' + r.saleId + '\')">↩️ مرتجع</button></span></div>';
      }).join('');
  } catch (err) { showErrorToast_(err); }
}

function confirmPosReturn_(saleId) {
  openConfirmModal('تأكيد المرتجع', 'متأكد إنك عايز ترجّع البيعة "' + saleId + '"؟', async function () {
    try {
      const results = await api.posSearchSaleForReturn(saleId);
      const sale = results.find(function (r) { return r.saleId === saleId; });
      if (!sale) { showToast_('البيعة مش موجودة', 'error'); return; }
      await api.posReturn({ username: state.user.username }, saleId, sale.items);
      showToast_('تم المرتجع ✅', 'success'); loadPosSummary_();
    } catch (err) { showErrorToast_(err); }
  });
}

async function posSearch_(query) {
  if (!query || query.length < 2) { document.getElementById('posSearchResults').innerHTML = ''; return; }
  try {
    const results = await api.searchProducts(query);
    document.getElementById('posSearchResults').innerHTML = buildProductResultsHtml_(results, 'addToPosCart_');
  } catch (err) { showErrorToast_(err); }
}

function buildProductResultsHtml_(results, addFnName) {
  if (results.length === 0) return emptyRow_('🔎', 'لا يوجد نتائج');
  return results.map(function (p) {
    return p.variants.map(function (v) {
      const label = (p.name + ' — ' + v.color + ' ' + v.size).replace(/'/g, '');
      const price = v.specialPrice || p.basePrice;
      return '<div class="product-tile" onclick="' + addFnName + '(\'' + v.code + '\', \'' + label + '\', ' + price + ')">' +
        '<div class="product-thumb">👕</div>' +
        '<div class="product-tile-info"><div class="product-tile-name">' + p.name + '</div>' +
        '<div class="product-tile-meta">' + v.color + ' · ' + v.size + ' · متاح: ' + v.quantity + '</div></div>' +
        '<b>' + price + '</b></div>';
    }).join('');
  }).join('');
}

function addToPosCart_(variantCode, label, price) {
  const existing = posCart.find(function (i) { return i.variantCode === variantCode; });
  if (existing) existing.qty += 1; else posCart.push({ variantCode: variantCode, label: label, price: price, qty: 1 });
  renderPosCart_();
  showToast_('تمت الإضافة للسلة', 'success');
}

function renderPosCart_() {
  const el = document.getElementById('posCartList');
  if (posCart.length === 0) { el.innerHTML = emptyRow_('🛒', 'السلة فاضية'); return; }
  let total = 0;
  el.innerHTML = posCart.map(function (i, idx) {
    total += i.price * i.qty;
    return '<div class="variant-chip">' + i.label + ' <span class="qty-tag">×' + i.qty + '</span> = ' + (i.price * i.qty) +
      ' <span class="del-x" onclick="removeFromCart_(' + idx + ')">✕</span></div>';
  }).join('') + '<div class="list-item" style="margin-top:10px;"><b>الإجمالي</b><b style="font-size:17px;">' + total + '</b></div>';
}
function removeFromCart_(idx) { posCart.splice(idx, 1); renderPosCart_(); }

async function submitPosSale_() {
  if (posCart.length === 0) { showToast_('السلة فاضية', 'error'); return; }
  const discount = Number(document.getElementById('posDiscount').value) || 0;
  const paymentMethod = document.getElementById('posPaymentMethod').value;
  try {
    const res = await api.posSale({ username: state.user.username }, posCart.map(function (i) { return { variantCode: i.variantCode, qty: i.qty, price: i.price }; }), discount, paymentMethod);
    showToast_('تمت البيعة بنجاح ✅ الإجمالي: ' + res.total, 'success');
    posCart = []; renderPosCart_();
    document.getElementById('posSearchResults').innerHTML = '';
    document.getElementById('posSearchInput').value = '';
    loadPosSummary_();
  } catch (err) { showErrorToast_(err); }
}

async function loadPosSummary_() {
  try {
    const s = await api.getPosTodaySummary();
    const cur = state.settings.currency || 'جنيه';
    document.getElementById('posTodaySummary').innerHTML =
      statCard_('🧾', 'عدد البيعات', s.count, '', false) +
      statCard_('💰', 'إجمالي المبيعات', formatMoney_(s.totalSales, cur), '', true) +
      statCard_('💵', 'إجمالي الكاش', formatMoney_(s.totalCash, cur), '', false);
  } catch (err) { showErrorToast_(err); }
}

// ============================================================
// شاشة المخزون — جدول المنتجات هو الأساس + كل الإضافة عن طريق مودالز
// ============================================================
let invTreeCache = null;
let invProductsCache = null;
let invWarehousesCache = null;

async function renderInventoryPage() {
  setContent_(renderSkeleton_());
  await loadInventoryBaseData_();
  setContent_(buildInventoryMainHtml_());
}

async function loadInventoryBaseData_() {
  try {
    invTreeCache = await api.getProductTree();
    const idx = await api.getInventoryIndex();
    invProductsCache = idx.products;
    invWarehousesCache = await api.getWarehouses();
  } catch (err) { showErrorToast_(err); }
}

function buildInventoryMainHtml_() {
  const products = Object.values(invProductsCache || {});
  const totalVariants = products.reduce(function (s, p) { return s + p.variants.length; }, 0);

  let html = '<div class="card-row" style="margin-bottom:18px; flex-wrap:wrap; gap:10px;">' +
    '<div class="field" style="flex:1; min-width:220px; margin-bottom:0;"><input type="text" id="invSearchInput" oninput="invSearch_(this.value)" placeholder="🔍 ابحث بالاسم أو الكود..."></div>' +
    '<div style="display:flex; gap:8px; flex-wrap:wrap;">' +
      '<button class="btn secondary" onclick="openCategoriesModal_()">🗂️ الفئات (' + invTreeCache.mainCategories.length + ')</button>' +
      '<button class="btn success" onclick="openAddProductModal_()">➕ منتج جديد</button>' +
      '<button class="btn info-btn" onclick="openAddVariantModal_()">🎨 إضافة متغير</button>' +
    '</div></div>';

  html += '<div class="card" style="padding:0; overflow:hidden;">';
  html += '<div class="table-wrap" style="border:none; border-radius:0;"><table id="invTable"><thead><tr>' +
    '<th>الكود</th><th>المنتج</th><th>الفئة</th><th>السعر</th><th>المتغيرات</th><th>الحالة</th>' +
    '</tr></thead><tbody id="invTableBody">';
  html += buildInventoryRows_(products);
  html += '</tbody></table></div></div>';

  html += '<div class="hint" style="margin-top:10px;">📦 ' + products.length + ' منتج · 🎨 ' + totalVariants + ' متغير</div>';
  return html;
}

function buildInventoryRows_(products) {
  if (products.length === 0) {
    return '<tr><td colspan="6"><div class="empty-state"><span class="emoji">📦</span><div class="msg">لسه مفيش منتجات — دوسي "منتج جديد" فوق</div></div></td></tr>';
  }
  return products.map(function (p) {
    const mainRow = '<tr style="cursor:pointer;" onclick="toggleProductRow_(\'' + p.code + '\')">' +
      '<td><span class="pill info">' + p.code + '</span></td>' +
      '<td><b>' + p.name + '</b></td>' +
      '<td>' + (p.subCategoryName || '—') + '</td>' +
      '<td><b>' + p.basePrice + '</b></td>' +
      '<td>' + p.variants.length + ' متغير</td>' +
      '<td><span class="pill ' + (p.status === 'نشط' ? 'success' : 'danger') + '">' + p.status + '</span></td>' +
      '</tr>';
    const variantsRow = '<tr id="variants-row-' + p.code + '" style="display:none;"><td colspan="6" style="background:var(--surface-2);">' +
      (p.variants.length === 0 ? '<span class="hint">منتج بدون متغيرات (يُباع مباشرة)</span>' :
        p.variants.map(function (v) {
          const low = v.quantity <= v.lowStockThreshold;
          return '<span class="variant-chip">' + v.code + ' — ' + (v.color || '—') + '/' + (v.size || '—') +
            ' <span class="qty-tag" style="' + (low ? 'color:var(--danger);' : '') + '">' + v.quantity + '</span></span>';
        }).join('')) +
      '</td></tr>';
    return mainRow + variantsRow;
  }).join('');
}

function toggleProductRow_(code) {
  const row = document.getElementById('variants-row-' + code);
  if (row) row.style.display = row.style.display === 'none' ? 'table-row' : 'none';
}

function invSearch_(query) {
  const products = Object.values(invProductsCache || {});
  const filtered = !query ? products : products.filter(function (p) {
    return p.name.toLowerCase().includes(query.toLowerCase()) || p.code.includes(query);
  });
  document.getElementById('invTableBody').innerHTML = buildInventoryRows_(filtered);
}

// ------------------------------------------------------------
// مودال: الفئات (عرض الشجرة + إضافة رئيسية/فرعية)
// ------------------------------------------------------------
function openCategoriesModal_() {
  openModal('🗂️ الفئات', 'إدارة الفئات الرئيسية والفرعية', buildCategoriesModalBody_(), '<button class="btn secondary" onclick="closeModal()">إغلاق</button>');
}

function buildCategoriesModalBody_() {
  let html = '<div class="form-grid">' +
    '<div class="field"><label>فئة رئيسية جديدة</label><input type="text" id="mainCatName" placeholder="مثال: ملابس رجالي"></div>' +
    '<div class="field"><label>&nbsp;</label><button class="btn success block" onclick="submitMainCategory_()">➕ إضافة</button></div>' +
  '</div>' +
  '<div class="form-grid" style="margin-top:14px;">' +
    '<div class="field"><label>الفئة الرئيسية الأب</label><select id="subCatParent">' + mainCategoryOptions_() + '</select></div>' +
    '<div class="field"><label>فئة فرعية جديدة</label><input type="text" id="subCatName" placeholder="اسم الفئة الفرعية"></div>' +
  '</div>' +
  '<button class="btn success block" style="margin-top:10px;" onclick="submitSubCategory_()">➕ إضافة فرعية</button>' +
  '<div class="section-title" style="margin-top:22px;">الشجرة الحالية</div><div id="categoriesTreeView">' + buildCategoriesTreeView_() + '</div>';
  return html;
}

function buildCategoriesTreeView_() {
  if (invTreeCache.mainCategories.length === 0) return emptyRow_('🌳', 'لسه مفيش فئات');
  return invTreeCache.mainCategories.map(function (m) {
    const subs = invTreeCache.subCategories.filter(function (s) { return s.parent === m.code; });
    return '<div style="padding:10px 0; border-bottom:1px solid var(--border);">' +
      '<div style="font-weight:800; font-size:13.5px;">📁 ' + m.name + ' <span class="pill info">' + m.code + '</span></div>' +
      (subs.length > 0 ? '<div style="padding-right:22px; margin-top:8px;">' + subs.map(function (s) { return '<span class="variant-chip">' + s.name + ' <span class="qty-tag">' + s.code + '</span></span>'; }).join('') + '</div>' :
        '<div style="padding-right:22px; margin-top:6px; font-size:11.5px; color:var(--text-faint);">لا يوجد فئات فرعية بعد</div>') + '</div>';
  }).join('');
}

function mainCategoryOptions_(selected) {
  if (!invTreeCache.mainCategories.length) return '<option value="">أضف فئة رئيسية الأول</option>';
  return invTreeCache.mainCategories.map(function (m) { return '<option value="' + m.code + '"' + (m.code === selected ? ' selected' : '') + '>' + m.name + '</option>'; }).join('');
}
function subCategoryOptionsForParent_(parentCode) {
  const subs = invTreeCache.subCategories.filter(function (s) { return s.parent === parentCode; });
  if (subs.length === 0) return '<option value="">لا يوجد فئات فرعية — أضف واحدة فوق</option>';
  return subs.map(function (s) { return '<option value="' + s.code + '">' + s.name + '</option>'; }).join('');
}

async function submitMainCategory_() {
  const name = document.getElementById('mainCatName').value.trim();
  if (!name) { showToast_('اكتب اسم الفئة', 'error'); return; }
  try {
    const res = await api.createCategory({ username: state.user.username }, { name: name, type: 'رئيسية' });
    showToast_('تمت إضافة "' + res.name + '" ✅', 'success');
    await loadInventoryBaseData_();
    document.getElementById('modalBody').innerHTML = buildCategoriesModalBody_();
    enhanceSelects_(document.getElementById('modalBody'));
  } catch (err) { showErrorToast_(err); }
}

async function submitSubCategory_() {
  const parentCode = document.getElementById('subCatParent').value;
  const name = document.getElementById('subCatName').value.trim();
  if (!parentCode) { showToast_('لازم فئة رئيسية أول', 'error'); return; }
  if (!name) { showToast_('اكتب اسم الفئة الفرعية', 'error'); return; }
  try {
    const res = await api.createCategory({ username: state.user.username }, { name: name, type: 'فرعية', parentCode: parentCode });
    showToast_('تمت إضافة "' + res.name + '" ✅', 'success');
    await loadInventoryBaseData_();
    document.getElementById('modalBody').innerHTML = buildCategoriesModalBody_();
    enhanceSelects_(document.getElementById('modalBody'));
  } catch (err) { showErrorToast_(err); }
}

// ------------------------------------------------------------
// مودال: منتج جديد
// ------------------------------------------------------------
function openAddProductModal_() {
  if (!invTreeCache.mainCategories.length) { showToast_('لازم تضيفي فئة رئيسية وفرعية الأول', 'error'); openCategoriesModal_(); return; }
  const body = '<div class="inline-add-row"><div class="field"><label>الفئة الرئيسية <span class="req">*</span></label>' +
    '<select id="prodMainCat" onchange="onProductMainCatChange_()">' + mainCategoryOptions_() + '</select></div>' +
    '<button class="inline-add-btn" onclick="closeModal(); openCategoriesModal_();">+ فئة</button></div>' +
    '<div class="field" style="margin-top:14px;"><label>الفئة الفرعية <span class="req">*</span></label>' +
    '<select id="prodSubCat">' + subCategoryOptionsForParent_(invTreeCache.mainCategories[0].code) + '</select></div>' +
    '<div class="form-grid" style="margin-top:14px;">' +
      '<div class="field"><label>اسم المنتج <span class="req">*</span></label><input type="text" id="prodName" placeholder="مثال: تيشرت أساسي"></div>' +
      '<div class="field"><label>سعر البيع <span class="req">*</span></label><input type="number" id="prodPrice" placeholder="0"></div>' +
    '</div>' +
    '<div class="hint" style="margin-top:8px;">💡 بعد الحفظ افتحي "إضافة متغير" لو المنتج له ألوان/مقاسات</div>';

  openModal('🆕 منتج جديد', '', body, '<button class="btn secondary" onclick="closeModal()">إلغاء</button><button class="btn success" onclick="submitProduct_()">✅ حفظ المنتج</button>');
}

function onProductMainCatChange_() {
  document.getElementById('prodSubCat').innerHTML = subCategoryOptionsForParent_(document.getElementById('prodMainCat').value);
  refreshSelect_('prodSubCat');
}

async function submitProduct_() {
  const payload = {
    mainCategory: document.getElementById('prodMainCat').value, subCategory: document.getElementById('prodSubCat').value,
    name: document.getElementById('prodName').value.trim(), basePrice: Number(document.getElementById('prodPrice').value)
  };
  if (!payload.subCategory) { showToast_('اختاري فئة فرعية', 'error'); return; }
  if (!payload.name || !payload.basePrice) { showToast_('اسم المنتج والسعر مطلوبين', 'error'); return; }
  try {
    const res = await api.addProduct({ username: state.user.username }, payload);
    showToast_('تم حفظ المنتج ✅ الكود: ' + res.code, 'success');
    closeModal();
    await loadInventoryBaseData_();
    setContent_(buildInventoryMainHtml_());
  } catch (err) { showErrorToast_(err); }
}

// ------------------------------------------------------------
// مودال: إضافة متغير (لون/مقاس)
// ------------------------------------------------------------
function openAddVariantModal_(presetProductCode) {
  const products = Object.values(invProductsCache || {});
  if (products.length === 0) { showToast_('لازم تضيفي منتج الأول', 'error'); return; }
  const showWarehouse = invWarehousesCache && invWarehousesCache.length > 1;

  const body = '<div class="field"><label>المنتج <span class="req">*</span></label><select id="varProductSelect">' +
    products.map(function (p) { return '<option value="' + p.code + '"' + (p.code === presetProductCode ? ' selected' : '') + '>' + p.name + ' (' + p.code + ')</option>'; }).join('') + '</select></div>' +
    '<div class="form-grid" style="margin-top:14px;">' +
      '<div class="field"><label>اللون</label><input type="text" id="varColor" placeholder="مثال: أسود"></div>' +
      '<div class="field"><label>المقاس</label><input type="text" id="varSize" placeholder="مثال: M"></div>' +
      '<div class="field"><label>الكمية <span class="req">*</span></label><input type="number" id="varQty" placeholder="0"></div>' +
      '<div class="field"><label>سعر التكلفة <span class="req">*</span></label><input type="number" id="varCost" placeholder="0"></div>' +
    '</div>' +
    (showWarehouse ? '<div class="field" style="margin-top:14px;"><label>المخزن</label><select id="varWarehouse">' + invWarehousesCache.map(function (w) { return '<option value="' + w.id + '">' + w.name + '</option>'; }).join('') + '</select></div>' : '');

  openModal('🎨 إضافة متغير', 'لون/مقاس جديد لمنتج موجود', body, '<button class="btn secondary" onclick="closeModal()">إلغاء</button><button class="btn success" onclick="submitVariant_()">✅ إضافة</button>');
}

async function submitVariant_() {
  const payload = {
    productCode: document.getElementById('varProductSelect').value, color: document.getElementById('varColor').value,
    size: document.getElementById('varSize').value, quantity: Number(document.getElementById('varQty').value),
    cost: Number(document.getElementById('varCost').value)
  };
  const warehouseEl = document.getElementById('varWarehouse');
  if (warehouseEl) payload.warehouseId = warehouseEl.value;
  if (!payload.productCode || payload.quantity === '' || payload.cost === '') { showToast_('الكمية والتكلفة مطلوبين', 'error'); return; }

  try {
    await api.addVariant({ username: state.user.username }, payload);
    showToast_('تمت إضافة المتغير ✅', 'success');
    closeModal();
    await loadInventoryBaseData_();
    setContent_(buildInventoryMainHtml_());
  } catch (err) { showErrorToast_(err); }
}

// ============================================================
// ============================================================
// شاشة المصروفات
// ============================================================
let expCategoriesCache = null;

let expEmployeesCache = [];

async function renderExpensesPage() {
  try {
    expCategoriesCache = await api.listExpenseCategories();
    expEmployeesCache = await api.listEmployees(true);
    setContent_(buildExpensesPageHtml_());
    onExpSubCatChange_();
  } catch (err) { showErrorToast_(err); }
}

function buildExpensesPageHtml_() {
  return '<div class="grid grid-2">' +
    '<div class="card"><div class="card-heading">💸 مصروف جديد</div><div class="card-desc">اختار الفئة الرئيسية والفرعية، أو ضيف فئة جديدة لو مش موجودة</div>' +
      '<div class="inline-add-row"><div class="field"><label>الفئة الرئيسية <span class="req">*</span></label>' +
      '<select id="expMainCat" onchange="onExpMainCatChange_()">' + expMainCatOptions_() + '</select></div>' +
      '<button class="inline-add-btn" onclick="openAddExpenseCategoryModal_(false)">+ فئة جديدة</button></div>' +
      '<div class="inline-add-row" style="margin-top:14px;"><div class="field"><label>الفئة الفرعية</label>' +
      '<select id="expSubCat" onchange="onExpSubCatChange_()">' + expSubCatOptions_(expCategoriesCache.mainCategories[0] || '') + '</select></div>' +
      '<button class="inline-add-btn" onclick="openAddExpenseCategoryModal_(true)">+ فئة فرعية</button></div>' +

      '<div id="expDynamicFields" style="margin-top:14px;"></div>' +

      '<div class="form-grid" style="margin-top:16px;">' +
        '<div class="field"><label>الوصف</label><input type="text" id="expDesc" placeholder="اختياري"></div>' +
        '<div class="field"><label>المبلغ <span class="req">*</span></label><input type="number" id="expAmount" placeholder="0"></div>' +
        '<div class="field"><label>طريقة الدفع</label><select id="expPaymentMethod"><option>كاش</option><option>فودافون كاش</option><option>بطاقة</option><option>انستاباي</option><option>آجل</option></select></div>' +
        '<div class="field"><label>التاريخ</label><input type="date" id="expDate" value="' + new Date().toISOString().slice(0, 10) + '"></div>' +
      '</div>' +
      '<div style="display:flex; gap:18px; margin-top:14px;">' +
        '<label style="display:flex; align-items:center; gap:7px; font-size:12.5px; font-weight:700; color:var(--text-dim); cursor:pointer;"><input type="checkbox" id="expIsFixedAsset" style="width:auto;"> أصل ثابت؟</label>' +
        '<label style="display:flex; align-items:center; gap:7px; font-size:12.5px; font-weight:700; color:var(--text-dim); cursor:pointer;"><input type="checkbox" id="expIsRecurring" style="width:auto;"> مصروف متكرر؟</label>' +
      '</div>' +
      '<div id="expRecurrenceDaysWrap" style="display:none; margin-top:12px;"><div class="field"><label>يتكرر كل (يوم)</label><input type="number" id="expRecurrenceDays" value="30"></div></div>' +
      '<button class="btn success block" style="margin-top:18px;" onclick="submitExpense_()">✅ تسجيل المصروف</button></div>' +
    '<div class="card"><div class="card-heading">📋 آخر المصروفات</div><div id="expensesHistoryList" style="margin-top:14px;">' + emptyRow_('📊', 'راجع التقارير لتفاصيل المصروفات الكاملة') + '</div></div></div>';
}

// ------------------------------------------------------------
// الفئات الديناميكية: كل فئة فرعية ليها حقول إضافية خاصة بيها
// عايزة تزودي قاعدة جديدة؟ ضيفي مفتاح جديد هنا بس
// ------------------------------------------------------------
const EXPENSE_DYNAMIC_RULES = {
  'مرتبات': function () {
    return '<div class="form-grid">' +
      '<div class="field"><label>الموظف <span class="req">*</span></label><select id="expEmployeeSelect">' +
      expEmployeesCache.map(function (e) { return '<option value="' + e.name + '">' + e.name + '</option>'; }).join('') + '</select></div>' +
      '<div class="field"><label>بونص/مكافأة (اختياري)</label><input type="number" id="expBonus" placeholder="0"></div>' +
      '</div>';
  }
};

function onExpSubCatChange_() {
  const subCat = document.getElementById('expSubCat') ? document.getElementById('expSubCat').value : '';
  const wrap = document.getElementById('expDynamicFields');
  if (!wrap) return;
  const rule = EXPENSE_DYNAMIC_RULES[subCat];
  wrap.innerHTML = rule ? rule() : '';
  enhanceSelects_(wrap);
}

function expMainCatOptions_() {
  if (!expCategoriesCache.mainCategories.length) return '<option value="">لا يوجد فئات بعد</option>';
  return expCategoriesCache.mainCategories.map(function (c) { return '<option value="' + c + '">' + c + '</option>'; }).join('');
}
function expSubCatOptions_(mainCat) {
  const subs = (expCategoriesCache.subCategoriesByMain && expCategoriesCache.subCategoriesByMain[mainCat]) || [];
  return '<option value="">بدون فئة فرعية</option>' + subs.map(function (s) { return '<option value="' + s + '">' + s + '</option>'; }).join('');
}
function onExpMainCatChange_() { document.getElementById('expSubCat').innerHTML = expSubCatOptions_(document.getElementById('expMainCat').value); refreshSelect_('expSubCat'); onExpSubCatChange_(); }

function openAddExpenseCategoryModal_(isSub) {
  openModal(isSub ? 'فئة فرعية جديدة' : 'فئة رئيسية جديدة', isSub ? 'هتُضاف تحت "' + document.getElementById('expMainCat').value + '"' : 'فئة مصروفات جديدة من المستوى الأول',
    '<div class="field"><label>الاسم</label><input type="text" id="modalExpCatName" placeholder="مثال: إيجار، كهرباء..."></div>',
    '<button class="btn secondary" onclick="closeModal()">إلغاء</button><button class="btn" onclick="confirmAddExpenseCategory_(' + isSub + ')">إضافة</button>');
}

function confirmAddExpenseCategory_(isSub) {
  const name = document.getElementById('modalExpCatName').value.trim();
  if (!name) { showToast_('اكتب الاسم', 'error'); return; }
  if (isSub) {
    const mainCat = document.getElementById('expMainCat').value;
    expCategoriesCache.subCategoriesByMain[mainCat] = expCategoriesCache.subCategoriesByMain[mainCat] || [];
    if (expCategoriesCache.subCategoriesByMain[mainCat].indexOf(name) === -1) expCategoriesCache.subCategoriesByMain[mainCat].push(name);
    document.getElementById('expSubCat').innerHTML = expSubCatOptions_(mainCat);
    document.getElementById('expSubCat').value = name;
  } else {
    if (expCategoriesCache.mainCategories.indexOf(name) === -1) expCategoriesCache.mainCategories.push(name);
    document.getElementById('expMainCat').innerHTML = expMainCatOptions_();
    document.getElementById('expMainCat').value = name;
    onExpMainCatChange_();
  }
  closeModal();
  showToast_('تمت الإضافة، هتتسجل نهائيًا مع أول مصروف تحفظه ✅', 'success');
}

document.addEventListener('change', function (e) {
  if (e.target && e.target.id === 'expIsRecurring') document.getElementById('expRecurrenceDaysWrap').style.display = e.target.checked ? 'block' : 'none';
});

async function submitExpense_() {
  const payload = {
    mainCategory: document.getElementById('expMainCat').value, subCategory: document.getElementById('expSubCat').value,
    description: document.getElementById('expDesc').value, amount: Number(document.getElementById('expAmount').value),
    paymentMethod: document.getElementById('expPaymentMethod').value, date: document.getElementById('expDate').value,
    isFixedAsset: document.getElementById('expIsFixedAsset').checked, isRecurring: document.getElementById('expIsRecurring').checked,
    recurrenceDays: document.getElementById('expIsRecurring').checked ? Number(document.getElementById('expRecurrenceDays').value) : ''
  };
  const empSelect = document.getElementById('expEmployeeSelect');
  if (empSelect) {
    const emp = expEmployeesCache.find(function (e) { return e.name === empSelect.value; });
    payload.employeeId = emp ? emp.id : null;
    payload.bonus = Number(document.getElementById('expBonus').value) || null;
  }
  if (!payload.mainCategory || !payload.amount) { showToast_('الفئة الرئيسية والمبلغ مطلوبين', 'error'); return; }
  try {
    await api.addExpense({ username: state.user.username }, payload);
    showToast_('تم تسجيل المصروف ✅', 'success'); renderExpensesPage();
  } catch (err) { showErrorToast_(err); }
}

// ============================================================
// شاشة المبيعات (محل)
// ============================================================
let salesCart = [];

function renderSalesPage() {
  setContent_(
    '<div class="grid grid-2">' +
      '<div class="card"><div class="card-heading">🧾 بيعة جديدة (محل)</div>' +
        '<div class="field"><input type="text" id="salesSearchInput" oninput="salesSearch_(this.value)" placeholder="ابحث بالاسم أو الكود..."></div>' +
        '<div id="salesSearchResults" style="margin:10px 0;"></div><div id="salesCartList"></div>' +
        '<div class="form-grid" style="margin-top:14px;">' +
          '<div class="field"><label>الخصم</label><input type="number" id="salesDiscount" value="0"></div>' +
          '<div class="field"><label>طريقة الدفع</label><select id="salesPaymentMethod"><option>كاش</option><option>فودافون كاش</option><option>بطاقة</option><option>انستاباي</option></select></div>' +
          '<div class="field"><label>اسم العميل (اختياري)</label><input type="text" id="salesCustomerName"></div>' +
          '<div class="field"><label>تليفون العميل (اختياري)</label><input type="text" id="salesCustomerPhone"></div>' +
          '<div class="field"><label>التاريخ</label><input type="datetime-local" id="salesDate"></div>' +
        '</div>' +
        '<button class="btn success block" style="margin-top:16px;" onclick="submitSale_()">✅ تسجيل البيعة</button></div>' +
      '<div class="card"><div class="card-heading">📋 آخر المبيعات</div><div id="salesHistoryList" style="margin-top:14px;"></div></div></div>'
  );
  salesCart = [];
  document.getElementById('salesDate').value = new Date().toISOString().slice(0, 16);
  loadSalesHistory_();
}

async function salesSearch_(query) {
  if (!query || query.length < 2) { document.getElementById('salesSearchResults').innerHTML = ''; return; }
  try { document.getElementById('salesSearchResults').innerHTML = buildProductResultsHtml_(await api.searchProducts(query), 'addToSalesCart_'); }
  catch (err) { showErrorToast_(err); }
}

function addToSalesCart_(variantCode, label, price) {
  const existing = salesCart.find(function (i) { return i.variantCode === variantCode; });
  if (existing) existing.qty += 1; else salesCart.push({ variantCode: variantCode, label: label, price: price, qty: 1 });
  renderSalesCart_();
}

function renderSalesCart_() {
  const el = document.getElementById('salesCartList');
  if (salesCart.length === 0) { el.innerHTML = emptyRow_('🛒', 'السلة فاضية'); return; }
  let total = 0;
  el.innerHTML = salesCart.map(function (i, idx) {
    total += i.price * i.qty;
    return '<div class="variant-chip">' + i.label + ' <span class="qty-tag">×' + i.qty + '</span> = ' + (i.price * i.qty) + ' <span class="del-x" onclick="removeFromSalesCart_(' + idx + ')">✕</span></div>';
  }).join('') + '<div class="list-item" style="margin-top:10px;"><b>الإجمالي</b><b style="font-size:17px;">' + total + '</b></div>';
}
function removeFromSalesCart_(idx) { salesCart.splice(idx, 1); renderSalesCart_(); }

async function submitSale_() {
  if (salesCart.length === 0) { showToast_('السلة فاضية', 'error'); return; }
  const payload = {
    source: 'محل', items: salesCart.map(function (i) { return { variantCode: i.variantCode, qty: i.qty, price: i.price }; }),
    discount: Number(document.getElementById('salesDiscount').value) || 0, paymentMethod: document.getElementById('salesPaymentMethod').value,
    customerName: document.getElementById('salesCustomerName').value, customerPhone: document.getElementById('salesCustomerPhone').value,
    date: document.getElementById('salesDate').value
  };
  try {
    const res = await api.recordSale({ username: state.user.username }, payload);
    showToast_('تمت البيعة ✅ الإجمالي: ' + res.total, 'success'); renderSalesPage();
  } catch (err) { showErrorToast_(err); }
}

async function loadSalesHistory_() {
  try {
    const sales = await api.listSales({ limit: 30 });
    const el = document.getElementById('salesHistoryList');
    const cur = state.settings.currency || 'جنيه';
    if (sales.length === 0) { el.innerHTML = emptyRow_('🧾', 'لا يوجد مبيعات بعد'); return; }
    let html = '<div class="table-wrap"><table><thead><tr><th>رقم البيعة</th><th>المصدر</th><th>التاريخ</th><th>الإجمالي</th><th>الحالة</th><th></th></tr></thead><tbody>';
    html += sales.map(function (s) {
      const statusPill = s.status === 'مكتملة' ? 'success' : 'warning';
      return '<tr><td>' + s.saleId + '</td><td>' + s.source + '</td><td>' + formatDate_(s.date) + '</td>' +
        '<td class="money-positive">' + formatMoney_(s.total, cur) + '</td><td><span class="pill ' + statusPill + '">' + s.status + '</span></td>' +
        '<td>' + (s.status === 'مكتملة' ? '<button class="eye-btn" onclick="quickReturnSale_(\'' + s.saleId + '\')">↩️</button>' : '') + '</td></tr>';
    }).join('');
    html += '</tbody></table></div>';
    el.innerHTML = html;
  } catch (err) { showErrorToast_(err); }
}

function quickReturnSale_(saleId) {
  openConfirmModal('تأكيد المرتجع', 'متأكد إنك عايز ترجّع البيعة "' + saleId + '" بالكامل؟', async function () {
    try {
      const sales = await api.listSales({ limit: 200 });
      const sale = sales.find(function (s) { return s.saleId === saleId; });
      if (!sale) { showToast_('البيعة مش موجودة', 'error'); return; }
      await api.posReturn({ username: state.user.username }, saleId, sale.items);
      showToast_('تم المرتجع ✅', 'success'); loadSalesHistory_();
    } catch (err) { showErrorToast_(err); }
  });
}

// ============================================================
// شاشة الموردين والمشتريات
// ============================================================
let poCart = [];

async function renderSuppliersPage() {
  setContent_(
    '<div class="grid grid-2">' +
      '<div class="card"><div class="card-heading">🏭 مورد جديد</div>' +
        '<div class="form-grid" style="margin-top:6px;">' +
          '<div class="field"><label>اسم المورد <span class="req">*</span></label><input type="text" id="supName"></div>' +
          '<div class="field"><label>رقم التواصل</label><input type="text" id="supContact"></div>' +
        '</div><button class="btn success block" style="margin-top:14px;" onclick="submitSupplier_(event)">➕ إضافة مورد</button>' +
        '<div class="card-heading" style="margin-top:26px;">📦 أوردر شراء جديد</div>' +
        '<div class="field" style="margin-top:8px;"><label>المورد <span class="req">*</span></label><select id="poSupplierSelect"></select></div>' +
        '<div class="field" style="margin-top:12px;"><input type="text" id="poSearchInput" oninput="poSearch_(this.value)" placeholder="ابحث عن منتج لإضافته..."></div>' +
        '<div id="poSearchResults"></div><div id="poCartList" style="margin:10px 0;"></div>' +
        '<div class="form-grid">' +
          '<div class="field"><label>حالة الدفع</label><select id="poPaymentStatus"><option>مدفوع بالكامل</option><option>مدفوع جزئيًا</option><option>متأخر/غير مدفوع</option></select></div>' +
          '<div class="field"><label>المبلغ المدفوع (لو جزئي)</label><input type="number" id="poAmountPaid" value="0"></div>' +
        '</div><button class="btn success block" style="margin-top:14px;" onclick="submitPurchaseOrder_()">✅ تسجيل أوردر الشراء</button></div>' +
      '<div class="card"><div class="card-heading">📇 الموردون</div><div id="suppliersList" style="margin-top:10px;"></div>' +
        '<div class="card-heading" style="margin-top:26px;">🧾 أوردرات الشراء الأخيرة</div><div id="poList" style="margin-top:10px;"></div></div></div>'
  );
  poCart = [];
  loadSuppliers_(); loadPurchaseOrders_();
}

async function submitSupplier_(evt) {
  const name = document.getElementById('supName').value;
  if (!name) { showToast_('اسم المورد مطلوب', 'error'); return; }
  const btn = evt.target; btn.disabled = true;
  try {
    await api.addSupplier({ username: state.user.username }, { name: name, contact: document.getElementById('supContact').value });
    showToast_('تم إضافة المورد ✅', 'success'); renderSuppliersPage();
  } catch (err) { btn.disabled = false; showErrorToast_(err); }
}

async function loadSuppliers_() {
  try {
    const suppliers = await api.getSuppliers();
    document.getElementById('poSupplierSelect').innerHTML = suppliers.map(function (s) { return '<option>' + s.name + '</option>'; }).join('') || '<option value="">أضف مورد الأول</option>';
    document.getElementById('suppliersList').innerHTML = suppliers.length === 0 ? emptyRow_('🏭', 'لا يوجد موردين بعد') :
      suppliers.map(function (s) {
        return '<div class="list-item" style="cursor:pointer;" onclick="openSupplierDetailModal_(\'' + s.name.replace(/'/g, "\\'") + '\')"><span><b>' + s.name + '</b></span><span style="color:var(--text-dim);">' + (s.contact || '—') + ' ›</span></div>';
      }).join('');
  } catch (err) { showErrorToast_(err); }
}

// ------------------------------------------------------------
// صفحة تفاصيل المورد — Modal بـ3 تابات (بيانات / المشتريات / كشف حساب)
// ------------------------------------------------------------
let supplierDetailTab = 'data';
let supplierDetailCache = null;

async function openSupplierDetailModal_(supplierName) {
  try {
    supplierDetailCache = await api.getSupplierStatement(supplierName);
    supplierDetailTab = 'data';
    openModal('📇 ' + supplierName, '', buildSupplierDetailHtml_(), '<button class="btn secondary" onclick="closeModal()">إغلاق</button>', true);
  } catch (err) { showErrorToast_(err); }
}

function buildSupplierDetailHtml_() {
  const cur = state.settings.currency || 'جنيه';
  const s = supplierDetailCache;
  let html = '<div class="subtabs">' +
    '<div class="subtab' + (supplierDetailTab === 'data' ? ' active' : '') + '" onclick="switchSupplierTab_(\'data\')">📇 البيانات</div>' +
    '<div class="subtab' + (supplierDetailTab === 'purchases' ? ' active' : '') + '" onclick="switchSupplierTab_(\'purchases\')">📦 المشتريات</div>' +
    '<div class="subtab' + (supplierDetailTab === 'statement' ? ' active' : '') + '" onclick="switchSupplierTab_(\'statement\')">🧾 كشف الحساب</div>' +
  '</div>';

  if (supplierDetailTab === 'data') {
    html += '<div class="form-grid">' +
      '<div class="field"><label>الاسم</label><input type="text" value="' + s.supplier.name + '" disabled></div>' +
      '<div class="field"><label>رقم التواصل</label><input type="text" value="' + (s.supplier.contact || '—') + '" disabled></div>' +
    '</div><div class="hint" style="margin-top:10px;">' + (s.supplier.notes || 'لا يوجد ملاحظات') + '</div>';
  } else if (supplierDetailTab === 'purchases') {
    html += '<div class="table-wrap"><table><thead><tr><th>رقم الأوردر</th><th>التاريخ</th><th>الإجمالي</th><th>الحالة</th></tr></thead><tbody>';
    html += s.purchases.length === 0 ? '<tr><td colspan="4">' + emptyRow_('📦', 'لا يوجد مشتريات بعد') + '</td></tr>' :
      s.purchases.map(function (p) {
        const pill = p.paymentStatus === 'مدفوع بالكامل' ? 'success' : (p.paymentStatus === 'مدفوع جزئيًا' ? 'warning' : 'danger');
        return '<tr><td>' + p.orderNumber + '</td><td>' + formatDate_(p.date) + '</td><td><b>' + formatMoney_(p.total, cur) + '</b></td><td><span class="pill ' + pill + '">' + p.paymentStatus + '</span></td></tr>';
      }).join('');
    html += '</tbody></table></div>';
  } else {
    const balance = s.totalRemaining;
    html += '<div class="grid grid-3">' +
      statCard_('💰', 'إجمالي المشتريات', formatMoney_(s.totalPurchases, cur), '', false) +
      statCard_('✅', 'إجمالي المدفوع', formatMoney_(s.totalPaid, cur), '', false) +
      '<div class="card stat-card"><div class="stat-icon">⚖️</div><div class="card-label">الرصيد (متبقي له)</div>' +
        '<div class="card-value ' + (balance > 0 ? 'money-negative' : 'money-positive') + '">' + formatMoney_(balance, cur) + '</div>' +
        '<div class="card-sub">' + (balance > 0 ? 'مستحق للمورد (دائن)' : 'لا يوجد مستحقات') + '</div></div>' +
    '</div>';
  }
  return html;
}

function switchSupplierTab_(tab) {
  supplierDetailTab = tab;
  document.getElementById('modalBody').innerHTML = buildSupplierDetailHtml_();
}

async function poSearch_(query) {
  if (!query || query.length < 2) { document.getElementById('poSearchResults').innerHTML = ''; return; }
  try {
    const results = await api.searchProducts(query);
    let html = results.map(function (p) {
      return p.variants.map(function (v) {
        const label = (p.name + ' — ' + v.color + ' ' + v.size).replace(/'/g, '');
        return '<div class="product-tile" onclick="addToPoCart_(\'' + v.code + '\', \'' + label + '\', ' + v.cost + ')">' +
          '<div class="product-thumb">👕</div><div class="product-tile-info"><div class="product-tile-name">' + p.name + '</div>' +
          '<div class="product-tile-meta">' + v.color + ' · ' + v.size + '</div></div><b>آخر تكلفة: ' + v.cost + '</b></div>';
      }).join('');
    }).join('');

    if (results.length === 0) {
      const safeQuery = query.replace(/'/g, "\\'");
      html = '<div class="callout-notfound" id="poNotFoundPrompt">' +
        '⚠️ المنتج "' + query + '" غير موجود في المخزون — ' +
        '<span style="color:var(--accent); font-weight:800; cursor:pointer; text-decoration:underline;" onclick="openPoQuickAddForm_(\'' + safeQuery + '\')">تريدين إضافته؟</span>' +
        '</div><div id="poQuickAddInline"></div>';
    }
    document.getElementById('poSearchResults').innerHTML = html;
  } catch (err) { showErrorToast_(err); }
}

// ------------------------------------------------------------
// إضافة منتج جديد Inline من داخل شاشة أمر الشراء (بدون مغادرتها)
// 3 خانات بس: الاسم / السعر (التكلفة) / الكود (اختياري)
// ------------------------------------------------------------
async function openPoQuickAddForm_(prefillName) {
  document.getElementById('poQuickAddInline').innerHTML =
    '<div class="card" style="background:var(--surface-2); margin-top:10px; padding:14px;">' +
      '<div class="form-grid" style="grid-template-columns: 2fr 1fr 1fr;">' +
        '<div class="field"><label>اسم المنتج</label><input type="text" id="poQuickName" value="' + prefillName + '"></div>' +
        '<div class="field"><label>سعر التكلفة</label><input type="number" id="poQuickPrice" placeholder="0"></div>' +
        '<div class="field"><label>الكود (اختياري)</label><input type="text" id="poQuickCode" placeholder="تلقائي"></div>' +
      '</div>' +
      '<button class="btn success block" style="margin-top:10px;" onclick="submitPoQuickAdd_()">✅ إضافة المنتج للمخزون وللأوردر</button>' +
    '</div>';
}

async function submitPoQuickAdd_() {
  const name = document.getElementById('poQuickName').value.trim();
  const price = Number(document.getElementById('poQuickPrice').value);
  const manualCode = document.getElementById('poQuickCode').value.trim();
  if (!name || !price) { showToast_('الاسم والسعر مطلوبين', 'error'); return; }

  try {
    const result = await api.quickAddProduct({ username: state.user.username }, name, price, manualCode);
    showToast_('تمت إضافة "' + name + '" للمخزون ✅', 'success');
    addToPoCart_(result.variantCode, name, price);
    document.getElementById('poSearchResults').innerHTML = '';
    document.getElementById('poSearchInput').value = '';
  } catch (err) { showErrorToast_(err); }
}

function addToPoCart_(variantCode, label, cost) {
  const existing = poCart.find(function (i) { return i.variantCode === variantCode; });
  if (existing) existing.qty += 1; else poCart.push({ variantCode: variantCode, label: label, price: cost, qty: 1 });
  renderPoCart_();
}

function renderPoCart_() {
  const el = document.getElementById('poCartList');
  if (poCart.length === 0) { el.innerHTML = emptyRow_('📦', 'لسه محددتش أصناف'); return; }
  let total = 0;
  el.innerHTML = poCart.map(function (i, idx) {
    total += i.price * i.qty;
    return '<div class="list-item"><span>' + i.label + '</span><span>سعر <input type="number" value="' + i.price + '" style="width:65px; padding:5px;" onchange="updatePoItemPrice_(' + idx + ', this.value)"> ' +
      'كمية <input type="number" value="' + i.qty + '" style="width:50px; padding:5px;" onchange="updatePoItemQty_(' + idx + ', this.value)"> ' +
      '<span class="del-x" onclick="removeFromPoCart_(' + idx + ')" style="cursor:pointer;">✕</span></span></div>';
  }).join('') + '<div class="list-item"><b>الإجمالي</b><b>' + total + '</b></div>';
}
function updatePoItemPrice_(idx, val) { poCart[idx].price = Number(val); renderPoCart_(); }
function updatePoItemQty_(idx, val) { poCart[idx].qty = Number(val); renderPoCart_(); }
function removeFromPoCart_(idx) { poCart.splice(idx, 1); renderPoCart_(); }

async function submitPurchaseOrder_() {
  if (poCart.length === 0) { showToast_('لازم تضيف صنف واحد على الأقل', 'error'); return; }
  const payload = {
    supplierName: document.getElementById('poSupplierSelect').value,
    items: poCart.map(function (i) { return { variantCode: i.variantCode, qty: i.qty, price: i.price }; }),
    paymentStatus: document.getElementById('poPaymentStatus').value, amountPaid: Number(document.getElementById('poAmountPaid').value) || 0
  };
  try {
    const res = await api.createPurchaseOrder({ username: state.user.username }, payload);
    showToast_('تم تسجيل أوردر الشراء ✅ الإجمالي: ' + res.total, 'success'); renderSuppliersPage();
  } catch (err) { showErrorToast_(err); }
}

async function loadPurchaseOrders_() {
  try {
    const orders = await api.listPurchaseOrders();
    const cur = state.settings.currency || 'جنيه';
    document.getElementById('poList').innerHTML = orders.length === 0 ? emptyRow_('📭', 'لا يوجد أوردرات شراء بعد') :
      orders.map(function (o) {
        const pill = o.paymentStatus === 'مدفوع بالكامل' ? 'success' : (o.paymentStatus === 'مدفوع جزئيًا' ? 'warning' : 'danger');
        return '<div class="list-item"><span>' + o.supplierName + '</span><span>' + formatMoney_(o.total, cur) + ' <span class="pill ' + pill + '">' + o.paymentStatus + '</span>' +
          (o.remaining > 0 ? ' <button class="eye-btn" onclick="openPaySupplierModal_(\'' + o.orderId + '\', ' + o.remaining + ')">💳</button>' : '') + '</span></div>';
      }).join('');
  } catch (err) { showErrorToast_(err); }
}

function openPaySupplierModal_(orderId, remaining) {
  openModal('دفع دفعة للمورد', 'المتبقي: ' + remaining, '<div class="field"><label>المبلغ المدفوع</label><input type="number" id="modalSupplierPayAmount" value="' + remaining + '"></div>',
    '<button class="btn secondary" onclick="closeModal()">إلغاء</button><button class="btn" onclick="confirmPaySupplier_(\'' + orderId + '\')">تأكيد الدفع</button>');
}

async function confirmPaySupplier_(orderId) {
  const amount = Number(document.getElementById('modalSupplierPayAmount').value);
  if (!amount) { showToast_('اكتب مبلغ صحيح', 'error'); return; }
  try {
    await api.paySupplierInstallment({ username: state.user.username }, orderId, amount);
    closeModal(); showToast_('تم تسجيل الدفعة ✅', 'success'); loadPurchaseOrders_();
  } catch (err) { showErrorToast_(err); }
}

// ============================================================
// الأوردرات والعملاء + الفواتير
// ============================================================
async function renderOrdersPage() {
  setContent_(
    '<div class="grid grid-2">' +
      '<div class="card"><div class="card-heading">📮 سجل الطلبات (أونلاين)</div>' +
        '<div class="field"><select id="ordersStatusFilter" onchange="loadOrders_()"><option value="">كل الحالات</option>' +
        '<option value="pending">pending</option><option value="confirmed">confirmed</option><option value="shipped">shipped</option>' +
        '<option value="delivered">delivered</option><option value="cancelled">cancelled</option></select></div>' +
        '<div id="ordersList" style="margin-top:12px;"></div></div>' +
      '<div class="card"><div class="card-heading">🔍 بحث عميل برقم التليفون</div>' +
        '<div class="inline-add-row"><div class="field"><input type="text" id="customerPhoneSearch" placeholder="01xxxxxxxxx"></div>' +
        '<button class="btn secondary" onclick="searchCustomerHistory_()">بحث</button></div>' +
        '<div id="customerHistoryResult" style="margin-top:14px;"></div>' +
        '<div class="card-heading" style="margin-top:26px;">👥 كل العملاء</div><div id="customersList" style="margin-top:10px;"></div></div></div>'
  );
  loadOrders_(); loadCustomers_();
}

async function loadOrders_() {
  const status = document.getElementById('ordersStatusFilter').value;
  try {
    const orders = await api.listOrders(status ? { status: status } : {});
    const cur = state.settings.currency || 'جنيه';
    document.getElementById('ordersList').innerHTML = orders.length === 0 ? emptyRow_('📭', 'لا يوجد أوردرات') :
      orders.map(function (o) {
        return '<div class="list-item"><span>' + o.orderId + ' — ' + (o.customerName || 'بدون اسم') + '</span>' +
          '<span>' + formatMoney_(o.total, cur) + ' <span class="pill info">' + o.status + '</span>' +
          (!o.confirmed && o.status === 'pending' ? ' <button class="eye-btn" onclick="confirmOrderUI_(\'' + o.orderId + '\')">✅</button>' : '') + '</span></div>';
      }).join('');
  } catch (err) { showErrorToast_(err); }
}

async function confirmOrderUI_(orderId) {
  try { await api.confirmOrder({ username: state.user.username }, orderId); showToast_('تم تأكيد الأوردر ✅', 'success'); loadOrders_(); }
  catch (err) { showErrorToast_(err); }
}

async function loadCustomers_() {
  try {
    const customers = await api.listCustomers();
    const cur = state.settings.currency || 'جنيه';
    document.getElementById('customersList').innerHTML = customers.length === 0 ? emptyRow_('👤', 'لا يوجد عملاء بعد') :
      customers.map(function (c) {
        return '<div class="list-item"><span>' + (c.name || c.phone) + '<br><span style="color:var(--text-faint); font-size:11px;">' + c.phone + '</span></span>' +
          '<span>' + c.orderCount + ' طلب — ' + formatMoney_(c.totalPurchases, cur) + '</span></div>';
      }).join('');
  } catch (err) { showErrorToast_(err); }
}

async function searchCustomerHistory_() {
  const phone = document.getElementById('customerPhoneSearch').value.trim();
  if (!phone) return;
  try {
    const history = await api.getCustomerOrderHistory(phone);
    const cur = state.settings.currency || 'جنيه';
    const el = document.getElementById('customerHistoryResult');
    if (!history.customer) { el.innerHTML = emptyRow_('🚫', 'مفيش عميل بالرقم ده'); return; }
    let html = '<div class="pill info" style="margin-bottom:10px;">' + history.customer.name + ' — ' + history.customer.orderCount + ' طلب سابق</div>';
    history.storeSales.forEach(function (o) { html += '<div class="list-item"><span>' + o.saleId + '</span><span>' + formatMoney_(o.total, cur) + '</span></div>'; });
    el.innerHTML = html;
  } catch (err) { showErrorToast_(err); }
}

async function renderInvoicesPage() {
  setContent_(
    '<div class="grid grid-2">' +
      '<div class="card"><div class="card-heading">📄 فاتورة جديدة</div>' +
        '<div class="form-grid" style="margin-top:6px;">' +
          '<div class="field"><label>اسم العميل <span class="req">*</span></label><input type="text" id="invCustomerName"></div>' +
          '<div class="field"><label>الإجمالي <span class="req">*</span></label><input type="number" id="invTotal"></div>' +
          '<div class="field"><label>المدفوع</label><input type="number" id="invPaid" value="0"></div>' +
          '<div class="field"><label>تم التحصيل COD؟</label><select id="invIsCOD"><option value="false">لا</option><option value="true">نعم</option></select></div>' +
        '</div><button class="btn success block" style="margin-top:14px;" onclick="submitInvoice_()">➕ إنشاء فاتورة</button></div>' +
      '<div class="card"><div class="card-heading">📋 الفواتير</div>' +
        '<div class="field"><select id="invStatusFilter" onchange="loadInvoices_()"><option value="">كل الحالات</option>' +
        '<option>مدفوعة بالكامل</option><option>مدفوعة جزئيًا</option><option>متأخرة</option><option>تم التحصيل COD</option></select></div>' +
        '<div id="invoicesList" style="margin-top:12px;"></div></div></div>'
  );
  loadInvoices_();
}

async function submitInvoice_() {
  const payload = {
    customerName: document.getElementById('invCustomerName').value, total: Number(document.getElementById('invTotal').value),
    paid: Number(document.getElementById('invPaid').value) || 0, isCOD: document.getElementById('invIsCOD').value === 'true'
  };
  if (!payload.customerName || !payload.total) { showToast_('اسم العميل والإجمالي مطلوبين', 'error'); return; }
  try { await api.createInvoice({ username: state.user.username }, payload); showToast_('تم إنشاء الفاتورة ✅', 'success'); renderInvoicesPage(); }
  catch (err) { showErrorToast_(err); }
}

async function loadInvoices_() {
  const status = document.getElementById('invStatusFilter').value;
  try {
    const invoices = await api.listInvoices(status ? { status: status } : {});
    const cur = state.settings.currency || 'جنيه';
    const el = document.getElementById('invoicesList');
    if (invoices.length === 0) { el.innerHTML = emptyRow_('📄', 'لا يوجد فواتير'); return; }
    let html = '<div class="table-wrap"><table><thead><tr><th>العميل</th><th>الإجمالي</th><th>المتبقي</th><th>الحالة</th><th></th></tr></thead><tbody>';
    html += invoices.map(function (inv) {
      const pill = inv.status === 'مدفوعة بالكامل' ? 'success' : (inv.status === 'متأخرة' ? 'danger' : 'warning');
      return '<tr><td>' + inv.customerName + '</td><td class="money-positive">' + formatMoney_(inv.total, cur) + '</td>' +
        '<td class="' + (inv.remaining > 0 ? 'money-negative' : '') + '">' + formatMoney_(inv.remaining, cur) + '</td>' +
        '<td><span class="pill ' + pill + '">' + inv.status + '</span></td>' +
        '<td>' + (inv.remaining > 0 ? '<button class="btn sm info-btn" onclick="openPayInvoiceModal_(\'' + inv.invoiceId + '\', ' + inv.remaining + ')">💳 تحصيل</button>' : '') + '</td></tr>';
    }).join('');
    html += '</tbody></table></div>';
    el.innerHTML = html;
  } catch (err) { showErrorToast_(err); }
}

function openPayInvoiceModal_(invoiceId, remaining) {
  openModal('تحصيل فاتورة', 'المتبقي حاليًا: ' + remaining, '<div class="field"><label>المبلغ المحصّل</label><input type="number" id="modalPayAmount" value="' + remaining + '"></div>',
    '<button class="btn secondary" onclick="closeModal()">إلغاء</button><button class="btn success" onclick="confirmPayInvoice_(\'' + invoiceId + '\')">تأكيد التحصيل</button>');
}

async function confirmPayInvoice_(invoiceId) {
  const amount = Number(document.getElementById('modalPayAmount').value);
  if (!amount) { showToast_('اكتب مبلغ صحيح', 'error'); return; }
  try { await api.payInvoiceInstallment({ username: state.user.username }, invoiceId, amount); closeModal(); showToast_('تم تسجيل التحصيل ✅', 'success'); loadInvoices_(); }
  catch (err) { showErrorToast_(err); }
}

// ============================================================
// رأس المال والشركاء + العهدة
// ============================================================
async function renderCapitalPage() {
  try {
    const summary = await api.getCapitalSummary();
    const cur = state.settings.currency || 'جنيه';
    let html = '<div class="grid grid-2">';
    html += '<div class="card"><div class="card-heading">🤝 إضافة / سحب رأس مال</div><div class="card-desc">لو الشريك جديد، اكتب اسمه هنا وهيتسجل تلقائيًا</div>' +
      '<div class="field"><label>اسم الشريك <span class="req">*</span></label><input type="text" id="capPartnerName" list="existingPartnersList" placeholder="اكتب اسم الشريك"></div>' +
      '<datalist id="existingPartnersList">' + summary.partners.map(function (p) { return '<option value="' + p.name + '">'; }).join('') + '</datalist>' +
      '<div class="form-grid" style="margin-top:14px;">' +
        '<div class="field"><label>نوع الحركة</label><select id="capType"><option>إضافة رأس مال</option><option>سحب رأس مال</option></select></div>' +
        '<div class="field"><label>المبلغ <span class="req">*</span></label><input type="number" id="capAmount"></div>' +
      '</div><button class="btn success block" style="margin-top:16px;" onclick="submitCapitalMovement_()">✅ تسجيل الحركة</button>' +
      '<div class="card-heading" style="margin-top:26px;">⚙️ نسب الشريك</div><div class="card-desc">نسبة توزيع الأرباح ونسبة الإدارة</div>' +
      '<div class="field"><label>الشريك</label><select id="ratePartnerSelect">' + summary.partners.map(function (p) { return '<option>' + p.name + '</option>'; }).join('') + '</select></div>' +
      '<div class="form-grid" style="margin-top:12px;">' +
        '<div class="field"><label>نسبة توزيع الأرباح %</label><input type="number" id="rateProfitShare"></div>' +
        '<div class="field"><label>نسبة/مبلغ الإدارة</label><input type="number" id="rateAdminValue"></div>' +
      '</div><div class="field" style="margin-top:12px;"><label>نوع نسبة الإدارة</label><select id="rateAdminType"><option value="نسبة %">نسبة %</option><option value="مبلغ ثابت">مبلغ ثابت</option></select></div>' +
      '<button class="btn success block" style="margin-top:14px;" onclick="submitPartnerRates_()">💾 حفظ النسب</button></div>';

    html += '<div class="card"><div class="card-heading">📊 الشركاء الحاليين</div><div style="margin-top:10px;">';
    html += summary.partners.length === 0 ? emptyRow_('🤝', 'لا يوجد شركاء مسجلين بعد') :
      summary.partners.map(function (p) {
        return '<div class="list-item" style="display:block; padding:14px 4px;"><div class="card-row"><b>' + p.name + '</b><span class="pill info">' + p.ownershipPercent + '% ملكية</span></div>' +
          '<div style="margin-top:6px; font-size:12px; color:var(--text-dim);">الرصيد: ' + formatMoney_(p.balance, cur) +
          ' · توزيع أرباح: ' + (p.profitSharePercent !== null ? p.profitSharePercent + '%' : '—') +
          ' · إدارة: ' + (p.adminRate !== null ? p.adminRate + (p.adminRateType === 'نسبة %' ? '%' : ' ' + cur) : '—') + '</div></div>';
      }).join('');
    html += '</div></div></div>';
    setContent_(html);
  } catch (err) { showErrorToast_(err); }
}

async function submitCapitalMovement_() {
  const payload = { partnerName: document.getElementById('capPartnerName').value.trim(), type: document.getElementById('capType').value, amount: Number(document.getElementById('capAmount').value) };
  if (!payload.partnerName || !payload.amount) { showToast_('اسم الشريك والمبلغ مطلوبين', 'error'); return; }
  try { await api.addCapitalMovement({ username: state.user.username }, payload); showToast_('تم تسجيل الحركة ✅', 'success'); renderCapitalPage(); }
  catch (err) { showErrorToast_(err); }
}

async function submitPartnerRates_() {
  const partnerName = document.getElementById('ratePartnerSelect').value;
  const profitShare = Number(document.getElementById('rateProfitShare').value);
  const adminValue = Number(document.getElementById('rateAdminValue').value);
  const adminType = document.getElementById('rateAdminType').value;
  try {
    await api.setPartnerProfitShare({ username: state.user.username }, partnerName, profitShare);
    await api.setPartnerAdminRate({ username: state.user.username }, partnerName, adminValue, adminType);
    showToast_('تم حفظ النسب ✅', 'success'); renderCapitalPage();
  } catch (err) { showErrorToast_(err); }
}

async function renderPettyCashPage() {
  try {
    const balance = await api.getPettyCashBalance();
    const history = await api.getPettyCashHistory(20);
    const cur = state.settings.currency || 'جنيه';
    let html = '<div class="grid grid-4">' + statCard_('👛', 'رصيد العهدة الحالي', formatMoney_(balance, cur), '', true) + '</div>';
    html += '<div class="grid grid-2" style="margin-top:22px;">';
    html += '<div class="card"><div class="card-heading">➕ حركة عهدة جديدة</div>' +
      '<div class="field"><label>نوع الحركة</label><select id="pcType"><option>إيداع</option><option>سحب</option><option>مصروف</option></select></div>' +
      '<div class="form-grid" style="margin-top:14px;"><div class="field"><label>المبلغ <span class="req">*</span></label><input type="number" id="pcAmount"></div>' +
      '<div class="field"><label>الوصف</label><input type="text" id="pcDesc"></div></div>' +
      '<button class="btn success block" style="margin-top:16px;" onclick="submitPettyCash_()">✅ تسجيل الحركة</button></div>';
    html += '<div class="card"><div class="card-heading">📋 آخر الحركات</div><div style="margin-top:12px;">';
    html += history.length === 0 ? emptyRow_('👛', 'لا يوجد حركات بعد') :
      history.map(function (h) {
        const pill = h.type === 'إيداع' ? 'success' : (h.type === 'سحب' ? 'warning' : 'danger');
        return '<div class="list-item"><span>' + (h.description || h.type) + '<br><span style="color:var(--text-faint); font-size:11px;">' + formatDate_(h.date) + '</span></span>' +
          '<span><span class="pill ' + pill + '">' + h.type + '</span> ' + formatMoney_(h.amount, cur) + '</span></div>';
      }).join('');
    html += '</div></div></div>';
    setContent_(html);
  } catch (err) { showErrorToast_(err); }
}

async function submitPettyCash_() {
  const type = document.getElementById('pcType').value, amount = Number(document.getElementById('pcAmount').value), desc = document.getElementById('pcDesc').value;
  if (!amount) { showToast_('المبلغ مطلوب', 'error'); return; }
  try { await api.addPettyCashMovement({ username: state.user.username }, type, amount, desc); showToast_('تم تسجيل الحركة ✅', 'success'); renderPettyCashPage(); }
  catch (err) { showErrorToast_(err); }
}

// ============================================================
// التقارير
// ============================================================
function renderReportsPage() {
  const firstOfMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().slice(0, 10);
  const today = new Date().toISOString().slice(0, 10);
  setContent_(
    '<div class="card"><div class="card-heading">📈 قائمة الدخل</div>' +
      '<div class="form-grid"><div class="field"><label>من تاريخ</label><input type="date" id="repStart" value="' + firstOfMonth + '"></div>' +
      '<div class="field"><label>إلى تاريخ</label><input type="date" id="repEnd" value="' + today + '"></div></div>' +
      '<button class="btn info-btn" style="margin-top:16px;" onclick="loadIncomeStatement_()">📊 عرض</button></div>' +
    '<div id="incomeStatementResult" style="margin-top:18px;"></div>' +
    '<div class="section-title">المواسم</div>' +
    '<div class="card"><div class="form-grid">' +
      '<div class="field"><label>اسم الموسم</label><input type="text" id="seasonName"></div>' +
      '<div class="field"><label>من</label><input type="date" id="seasonStart"></div>' +
      '<div class="field"><label>إلى</label><input type="date" id="seasonEnd"></div></div>' +
      '<button class="btn" style="margin-top:14px;" onclick="submitSeason_()">➕ إضافة موسم</button><div id="seasonsList" style="margin-top:14px;"></div></div>'
  );
  loadSeasons_();
}

async function loadIncomeStatement_() {
  const start = document.getElementById('repStart').value, end = document.getElementById('repEnd').value;
  try {
    const income = await api.getIncomeStatement(start, end);
    const cur = state.settings.currency || 'جنيه';
    let html = '<div class="card">';
    html += rowLine_('إجمالي المبيعات', formatMoney_(income.totalSales, cur));
    html += rowLine_('تكلفة البضاعة المباعة (COGS)', formatMoney_(income.cogs, cur));
    html += rowLine_('مجمل الربح (GP)', formatMoney_(income.grossProfit, cur), true);
    html += rowLine_('المصروفات التشغيلية', formatMoney_(income.operatingExpenses, cur));
    html += rowLine_('الإيرادات الأخرى', formatMoney_(income.otherRevenue, cur));
    html += rowLine_('صافي الربح قبل الضريبة', formatMoney_(income.netProfitBeforeTax, cur), true);
    if (income.taxEnabled) { html += rowLine_('الضريبة', formatMoney_(income.tax, cur)); html += rowLine_('صافي الربح بعد الضريبة', formatMoney_(income.netProfitAfterTax, cur), true); }
    html += '</div>';
    document.getElementById('incomeStatementResult').innerHTML = html;
  } catch (err) { showErrorToast_(err); }
}
function rowLine_(label, value, bold) { return '<div class="list-item"><span' + (bold ? ' style="font-weight:900;"' : '') + '>' + label + '</span><b>' + value + '</b></div>'; }

async function submitSeason_() {
  const payload = { name: document.getElementById('seasonName').value, startDate: document.getElementById('seasonStart').value, endDate: document.getElementById('seasonEnd').value };
  if (!payload.name || !payload.startDate || !payload.endDate) { showToast_('كل الحقول مطلوبة', 'error'); return; }
  try { await api.addSeason({ username: state.user.username }, payload); showToast_('تم إضافة الموسم ✅', 'success'); loadSeasons_(); }
  catch (err) { showErrorToast_(err); }
}

async function loadSeasons_() {
  try {
    const seasons = await api.listSeasons();
    document.getElementById('seasonsList').innerHTML = seasons.length === 0 ? emptyRow_('📅', 'لا يوجد مواسم بعد') :
      seasons.map(function (s) { return '<div class="list-item"><span>' + s.name + '</span><span>' + formatDate_(s.startDate) + ' → ' + formatDate_(s.endDate) + '</span></div>'; }).join('');
  } catch (err) { showErrorToast_(err); }
}

// ============================================================
// الموارد البشرية
// ============================================================
async function renderHrPage() {
  setContent_(
    '<div class="grid grid-2">' +
      '<div class="card"><div class="card-heading">👤 موظف جديد</div>' +
        '<div class="form-grid"><div class="field"><label>الاسم</label><input type="text" id="empName"></div>' +
        '<div class="field"><label>الوظيفة</label><input type="text" id="empJob"></div>' +
        '<div class="field"><label>الراتب الأساسي</label><input type="number" id="empSalary"></div>' +
        '<div class="field"><label>التليفون</label><input type="text" id="empPhone"></div></div>' +
        '<button class="btn success block" style="margin-top:14px;" onclick="submitEmployee_()">➕ إضافة موظف</button>' +
        '<div class="card-heading" style="margin-top:26px;">🕒 تسجيل حضور</div>' +
        '<div class="form-grid"><div class="field"><label>الموظف</label><select id="attEmployeeSelect"></select></div>' +
        '<div class="field"><label>الحالة</label><select id="attStatus"><option>حضور</option><option>غياب</option><option>إجازة</option></select></div></div>' +
        '<button class="btn success block" style="margin-top:14px;" onclick="submitAttendance_()">تسجيل</button>' +
        '<div class="card-heading" style="margin-top:26px;">💵 سلفة جديدة</div>' +
        '<div class="form-grid"><div class="field"><label>الموظف</label><select id="advEmployeeSelect"></select></div>' +
        '<div class="field"><label>المبلغ</label><input type="number" id="advAmount"></div></div>' +
        '<button class="btn success block" style="margin-top:14px;" onclick="submitAdvance_()">تسجيل السلفة</button></div>' +
      '<div class="card"><div class="card-heading">👥 الموظفون</div><div id="employeesList" style="margin-top:10px;"></div>' +
        '<div class="card-heading" style="margin-top:26px;">💰 مرتبات الشهر الحالي</div>' +
        '<button class="btn secondary" style="margin-top:8px;" onclick="runSalaries_()">تشغيل المرتبات</button><div id="salariesList" style="margin-top:14px;"></div></div></div>'
  );
  loadEmployees_();
}

async function submitEmployee_() {
  const payload = { name: document.getElementById('empName').value, jobTitle: document.getElementById('empJob').value, baseSalary: Number(document.getElementById('empSalary').value), phone: document.getElementById('empPhone').value };
  if (!payload.name || !payload.baseSalary) { showToast_('الاسم والراتب مطلوبين', 'error'); return; }
  try { await api.addEmployee({ username: state.user.username }, payload); showToast_('تم إضافة الموظف ✅', 'success'); renderHrPage(); }
  catch (err) { showErrorToast_(err); }
}

async function loadEmployees_() {
  try {
    const employees = await api.listEmployees(true);
    const cur = state.settings.currency || 'جنيه';
    document.getElementById('employeesList').innerHTML = employees.length === 0 ? emptyRow_('👥', 'لا يوجد موظفين بعد') :
      employees.map(function (e) { return '<div class="list-item"><span>' + e.name + ' — ' + e.jobTitle + '</span><span>' + formatMoney_(e.baseSalary, cur) + '</span></div>'; }).join('');
    const options = employees.map(function (e) { return '<option>' + e.name + '</option>'; }).join('');
    document.getElementById('attEmployeeSelect').innerHTML = options;
    document.getElementById('advEmployeeSelect').innerHTML = options;
  } catch (err) { showErrorToast_(err); }
}

async function submitAttendance_() {
  try { await api.recordAttendance({ username: state.user.username }, document.getElementById('attEmployeeSelect').value, document.getElementById('attStatus').value); showToast_('تم تسجيل الحضور ✅', 'success'); }
  catch (err) { showErrorToast_(err); }
}

async function submitAdvance_() {
  const amount = Number(document.getElementById('advAmount').value);
  if (!amount) { showToast_('المبلغ مطلوب', 'error'); return; }
  try { await api.addEmployeeAdvance({ username: state.user.username }, document.getElementById('advEmployeeSelect').value, amount); showToast_('تم تسجيل السلفة ✅', 'success'); }
  catch (err) { showErrorToast_(err); }
}

async function runSalaries_() {
  const monthLabel = new Date().toISOString().slice(0, 7);
  try { const res = await api.runMonthlySalaries({ username: state.user.username }, monthLabel); showToast_('تم تجهيز مرتبات ' + res.count + ' موظف ✅', 'success'); loadSalaries_(monthLabel); }
  catch (err) { showErrorToast_(err); }
}

async function loadSalaries_(monthLabel) {
  try {
    const salaries = await api.listSalaries(monthLabel);
    const cur = state.settings.currency || 'جنيه';
    document.getElementById('salariesList').innerHTML = salaries.map(function (s) {
      return '<div class="list-item"><span>' + s.employeeName + '</span><span>' + formatMoney_(s.net, cur) +
        (s.paid === 'لا' ? ' <button class="eye-btn" onclick="paySalaryUI_(\'' + monthLabel + '\', \'' + s.employeeName + '\')">💳</button>' : ' <span class="pill success">مدفوع</span>') + '</span></div>';
    }).join('');
  } catch (err) { showErrorToast_(err); }
}

async function paySalaryUI_(monthLabel, employeeName) {
  try { await api.paySalary({ username: state.user.username }, monthLabel, employeeName); showToast_('تم صرف الراتب ✅', 'success'); loadSalaries_(monthLabel); }
  catch (err) { showErrorToast_(err); }
}

// ============================================================
// المخازن + المستخدمون والصلاحيات + الإعدادات
// ============================================================
async function renderWarehousesPage() {
  try {
    const warehouses = await api.getWarehouses();
    let html = '<div class="grid grid-2">' +
      '<div class="card"><div class="card-heading">🏬 مخزن جديد</div>' +
      '<div class="card-desc">لو عندك مخزن واحد بس، مش لازم تضيف تاني.</div>' +
      '<div class="form-grid"><div class="field"><label>اسم المخزن <span class="req">*</span></label><input type="text" id="whName"></div>' +
      '<div class="field"><label>الموقع</label><input type="text" id="whLocation"></div></div>' +
      '<div class="field" style="margin-top:14px;"><label>الوصف</label><input type="text" id="whDesc"></div>' +
      '<label style="display:flex; align-items:center; gap:7px; font-size:12.5px; font-weight:700; color:var(--text-dim); margin-top:14px; cursor:pointer;">' +
      '<input type="checkbox" id="whIsDefaultOnline" style="width:auto;"> المخزن الافتراضي لأوردرات الأونلاين</label>' +
      '<button class="btn success block" style="margin-top:16px;" onclick="submitWarehouse_()">➕ إضافة مخزن</button></div>' +
      '<div class="card"><div class="card-heading">📋 المخازن الحالية <span class="pill info">' + warehouses.length + '</span></div><div style="margin-top:12px;">';
    html += warehouses.length === 0 ? emptyRow_('🏬', 'لسه مفيش مخازن مسجلة') :
      warehouses.map(function (w) { return '<div class="list-item"><span><b>' + w.name + '</b><br><span style="color:var(--text-dim); font-size:11.5px;">' + (w.location || '—') + '</span></span>' + (w.isDefaultOnline ? '<span class="pill success">افتراضي أونلاين</span>' : '') + '</div>'; }).join('');
    html += '</div></div></div>';
    setContent_(html);
  } catch (err) { showErrorToast_(err); }
}

async function submitWarehouse_() {
  const payload = { name: document.getElementById('whName').value.trim(), location: document.getElementById('whLocation').value, description: document.getElementById('whDesc').value, isDefaultOnline: document.getElementById('whIsDefaultOnline').checked };
  if (!payload.name) { showToast_('اسم المخزن مطلوب', 'error'); return; }
  try { await api.addWarehouse({ username: state.user.username }, payload); showToast_('تم إضافة المخزن ✅', 'success'); renderWarehousesPage(); }
  catch (err) { showErrorToast_(err); }
}

const PERMISSION_MODULES = ['Dashboard', 'POS', 'Sales', 'Inventory', 'Expenses', 'Suppliers', 'Orders', 'Invoices', 'Capital', 'PettyCash', 'Reports', 'HR', 'Users', 'Settings'];
const PERMISSION_MODULE_LABELS = { Dashboard: 'الداشبورد', POS: 'الكاشير', Sales: 'المبيعات', Inventory: 'المخزون', Expenses: 'المصروفات', Suppliers: 'الموردون', Orders: 'الأوردرات', Invoices: 'الفواتير', Capital: 'رأس المال', PettyCash: 'العهدة', Reports: 'التقارير', HR: 'الموارد البشرية', Users: 'المستخدمون', Settings: 'الإعدادات' };

async function renderUsersPage() {
  try {
    const users = await api.listUsers();
    let html = '<div class="card"><div class="card-row"><div class="card-heading">🔐 المستخدمون</div><button class="btn" onclick="openAddUserModal_()">➕ إضافة مستخدم جديد</button></div>' +
      '<div class="table-wrap" style="margin-top:16px;"><table><thead><tr><th>اليوزرنيم</th><th>الاسم</th><th>الدور</th><th>الحالة</th><th></th></tr></thead><tbody>';
    users.forEach(function (u) {
      html += '<tr><td>' + u.username + '</td><td>' + u.fullName + '</td><td><span class="pill info">' + u.role + '</span></td>' +
        '<td><span class="pill ' + (u.active === 'نعم' ? 'success' : 'danger') + '">' + u.active + '</span></td>' +
        '<td>' + (u.role !== 'أدمن' ? '<button class="btn sm secondary" onclick=\'openEditPermissionsModal_(' + JSON.stringify(u.username) + ', ' + JSON.stringify(u.permissions) + ')\'>الصلاحيات</button>' : '—') + '</td></tr>';
    });
    html += '</tbody></table></div></div>';
    setContent_(html);
  } catch (err) { showErrorToast_(err); }
}

function openAddUserModal_() {
  openModal('إضافة مستخدم جديد', 'اختار دور المستخدم — هتقدر تظبط صلاحياته بالتفصيل بعدين',
    '<div class="field"><label>اليوزرنيم <span class="req">*</span></label><input type="text" id="newUserUsername"></div>' +
    '<div class="field" style="margin-top:12px;"><label>الاسم الكامل</label><input type="text" id="newUserFullName"></div>' +
    '<div class="field" style="margin-top:12px;"><label>كلمة المرور <span class="req">*</span></label><input type="password" id="newUserPassword"></div>' +
    '<div class="field" style="margin-top:12px;"><label>الدور</label><select id="newUserRole"><option value="بائع">بائع</option><option value="كاشير">كاشير</option><option value="شريك">شريك</option><option value="أدمن">أدمن</option></select></div>',
    '<button class="btn secondary" onclick="closeModal()">إلغاء</button><button class="btn" onclick="submitNewUser_()">إضافة</button>');
}

async function submitNewUser_() {
  const payload = { username: document.getElementById('newUserUsername').value.trim(), fullName: document.getElementById('newUserFullName').value, password: document.getElementById('newUserPassword').value, role: document.getElementById('newUserRole').value, permissions: {} };
  if (!payload.username || !payload.password) { showToast_('اليوزرنيم وكلمة المرور مطلوبين', 'error'); return; }
  try { await api.createUser(state.user.username, payload); closeModal(); showToast_('تم إضافة المستخدم ✅', 'success'); renderUsersPage(); }
  catch (err) { showErrorToast_(err); }
}

function openEditPermissionsModal_(username, currentPermissions) {
  const rows = PERMISSION_MODULES.map(function (m) {
    const current = currentPermissions[m] || 'مخفي';
    return '<div class="list-item"><span>' + PERMISSION_MODULE_LABELS[m] + '</span><select id="perm_' + m + '" style="width:130px;">' +
      '<option value="مخفي"' + (current === 'مخفي' ? ' selected' : '') + '>مخفي</option>' +
      '<option value="عرض"' + (current === 'عرض' ? ' selected' : '') + '>عرض فقط</option>' +
      '<option value="تعديل"' + (current === 'تعديل' ? ' selected' : '') + '>تعديل كامل</option></select></div>';
  }).join('');
  openModal('صلاحيات ' + username, 'حدد مستوى الوصول لكل قسم', '<div style="max-height:340px; overflow-y:auto;">' + rows + '</div>',
    '<button class="btn secondary" onclick="closeModal()">إلغاء</button><button class="btn" onclick="submitPermissions_(\'' + username + '\')">حفظ الصلاحيات</button>');
}

async function submitPermissions_(username) {
  const newPermissions = {};
  PERMISSION_MODULES.forEach(function (m) { newPermissions[m] = document.getElementById('perm_' + m).value; });
  try { await api.updateUserPermissions(state.user.username, username, newPermissions); closeModal(); showToast_('تم تحديث الصلاحيات ✅', 'success'); renderUsersPage(); }
  catch (err) { showErrorToast_(err); }
}

async function renderSettingsPage() {
  try {
    const s = await api.getSettings();
    setContent_('<div class="card" style="max-width:760px;"><div class="card-heading">⚙️ إعدادات النظام</div><div class="form-grid" style="margin-top:10px;">' +
      field_('اسم البراند', 'setBrandName', s.brandName) + field_('رابط اللوجو', 'setLogoUrl', s.logoUrl) +
      field_('اللون الأساسي', 'setPrimaryColor', s.primaryColor, 'color') + field_('لون التمييز', 'setAccentColor', s.accentColor, 'color') +
      field_('العملة', 'setCurrency', s.currency) +
      selectField_('وضع تشغيل النظام', 'setOperatingMode', s.operatingMode, [['STORE_ONLY', 'محل فقط'], ['ONLINE_ONLY', 'أونلاين فقط'], ['BOTH', 'محل + أونلاين']]) +
      selectField_('نسبة الإدارة مفعّلة؟', 'setAdminFeeEnabled', s.adminFeeEnabled, [['true', 'نعم'], ['false', 'لا']]) +
      selectField_('الضريبة مفعّلة؟', 'setTaxEnabled', s.taxEnabled, [['true', 'نعم'], ['false', 'لا']]) +
      field_('نسبة الضريبة %', 'setTaxRate', s.taxRate) +
      selectField_('موافقة الشركاء مفعّلة؟', 'setPartnerApprovalEnabled', s.partnerApprovalEnabled, [['true', 'نعم'], ['false', 'لا']]) +
      field_('EasyOrders API Key', 'setEasyOrdersApiKey', s.easyOrdersApiKey) + field_('EasyOrders Secret', 'setEasyOrdersSecret', s.easyOrdersSecret) +
      field_('حد التنبيه الافتراضي للمخزون', 'setLowStockThresholdDefault', s.lowStockThresholdDefault) +
      '</div><button class="btn success block" style="margin-top:20px;" onclick="saveSettings_()">💾 حفظ الإعدادات</button></div>');
  } catch (err) { showErrorToast_(err); }
}

function field_(label, id, value, type) { return '<div class="field"><label>' + label + '</label><input type="' + (type || 'text') + '" id="' + id + '" value="' + (value || '') + '"></div>'; }
function selectField_(label, id, value, options) {
  const opts = options.map(function (o) { return '<option value="' + o[0] + '"' + (o[0] === value ? ' selected' : '') + '>' + o[1] + '</option>'; }).join('');
  return '<div class="field"><label>' + label + '</label><select id="' + id + '">' + opts + '</select></div>';
}

async function saveSettings_() {
  const payload = {
    brandName: document.getElementById('setBrandName').value, logoUrl: document.getElementById('setLogoUrl').value,
    primaryColor: document.getElementById('setPrimaryColor').value, accentColor: document.getElementById('setAccentColor').value,
    currency: document.getElementById('setCurrency').value, operatingMode: document.getElementById('setOperatingMode').value,
    adminFeeEnabled: document.getElementById('setAdminFeeEnabled').value, taxEnabled: document.getElementById('setTaxEnabled').value,
    taxRate: document.getElementById('setTaxRate').value, partnerApprovalEnabled: document.getElementById('setPartnerApprovalEnabled').value,
    easyOrdersApiKey: document.getElementById('setEasyOrdersApiKey').value, easyOrdersSecret: document.getElementById('setEasyOrdersSecret').value,
    lowStockThresholdDefault: document.getElementById('setLowStockThresholdDefault').value
  };
  try {
    await api.updateSettingsBulk({ username: state.user.username }, payload);
    showToast_('تم حفظ الإعدادات ✅', 'success');
    state.settings = Object.assign(state.settings, payload); applySettingsToUI();
  } catch (err) { showErrorToast_(err); }
}

// ============================================================
// التنبيهات + Helpers عامة + بداية التشغيل
// ============================================================
async function refreshNotifications() {
  try {
    const notifs = await api.getNotifications();
    const badge = document.getElementById('notifBadge');
    if (notifs.length > 0) { badge.style.display = 'flex'; badge.textContent = notifs.length > 9 ? '9+' : notifs.length; }
    else badge.style.display = 'none';
    window.__notifications = notifs;
  } catch (err) { /* صامت — التنبيهات مش حرجة */ }
}

function toggleNotifications() {
  const dropdown = document.getElementById('notifDropdown');
  if (dropdown.style.display === 'block') { dropdown.style.display = 'none'; return; }
  const notifs = window.__notifications || [];
  dropdown.style.display = 'block';
  dropdown.innerHTML = '<div class="notif-header">🔔 التنبيهات</div>' + (
    notifs.length === 0 ? '<div class="empty-state" style="padding:24px;"><span class="emoji" style="font-size:22px;">✅</span><div class="msg" style="font-size:12px;">مفيش تنبيهات جديدة</div></div>' :
    notifs.map(function (n) { return '<div class="notif-item"><div class="notif-dot ' + n.severity + '"></div><div><div class="notif-text">' + n.message + '</div>' + (n.time ? '<div class="notif-time">' + formatDate_(n.time) + '</div>' : '') + '</div></div>'; }).join('')
  );
}

document.addEventListener('click', function (e) {
  const dropdown = document.getElementById('notifDropdown');
  if (!dropdown) return;
  if (dropdown.style.display === 'block' && !dropdown.contains(e.target) && !e.target.closest('.icon-btn')) dropdown.style.display = 'none';
});

function formatMoney_(amount, currency) { const n = Number(amount) || 0; return n.toLocaleString('ar-EG', { maximumFractionDigits: 2 }) + ' ' + (currency || ''); }
function formatDate_(d) { try { return new Date(d).toLocaleString('ar-EG'); } catch (e) { return ''; } }

function showToast_(message, type) {
  const container = document.getElementById('toastContainer');
  const toast = document.createElement('div');
  toast.className = 'toast ' + (type || '');
  const icon = type === 'success' ? '✅' : (type === 'error' ? '⚠️' : 'ℹ️');
  toast.innerHTML = '<span>' + icon + '</span><span>' + message + '</span>';
  container.appendChild(toast);
  setTimeout(function () { toast.classList.add('fadeout'); setTimeout(function () { toast.remove(); }, 300); }, 3200);
}
function showErrorToast_(err) { showToast_('حصل خطأ: ' + (err.message || err), 'error'); console.error(err); }

// ------------------------------------------------------------
// بداية التشغيل
// ------------------------------------------------------------
window.addEventListener('DOMContentLoaded', async function () {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (session) await bootApp();
  else document.getElementById('loginScreen').style.display = 'flex';

  document.getElementById('loginPassword').addEventListener('keydown', function (e) { if (e.key === 'Enter') handleLogin(); });
  setInterval(function () { if (state.user) refreshNotifications(); }, 90000);
});

// ============================================================
// شجرة الحسابات
// ============================================================
async function renderAccountsPage() {
  try {
    const accounts = await api.getAccounts();
    const cur = state.settings.currency || 'جنيه';
    let html = '<div class="card"><div class="card-heading">🗂️ حساب جديد</div>' +
      '<div class="form-grid"><div class="field"><label>اسم الحساب <span class="req">*</span></label><input type="text" id="accName"></div>' +
      '<div class="field"><label>النوع <span class="req">*</span></label><select id="accType"><option>أصول</option><option>خصوم</option><option>حقوق ملكية</option><option>إيرادات</option><option>مصروفات</option></select></div></div>' +
      '<div class="form-grid" style="margin-top:10px;"><div class="field"><label>كود الحساب الأب (اختياري)</label><input type="text" id="accParentCode" placeholder="مثال: 1"></div>' +
      '<div class="field"><label>حساب تجميعي (Group)؟</label><select id="accIsGroup"><option value="false">لا</option><option value="true">نعم</option></select></div></div>' +
      '<button class="btn success block" style="margin-top:16px;" onclick="submitAccount_()">✅ إضافة الحساب</button></div>';

    html += '<div class="section-title">شجرة الحسابات الحالية</div><div class="card">';
    html += accounts.length === 0 ? emptyRow_('🗂️', 'لسه مفيش حسابات مضافة') :
      accounts.map(function (a) {
        return '<div class="list-item"><span><b>' + a.code + '</b> — ' + a.name + (a.isGroup ? ' <span class="pill">تجميعي</span>' : '') + '</span><span class="pill">' + a.type + '</span></div>';
      }).join('');
    html += '</div>';
    setContent_(html);
  } catch (err) { showErrorToast_(err); }
}

async function submitAccount_() {
  const name = document.getElementById('accName').value.trim();
  const type = document.getElementById('accType').value;
  const parentCode = document.getElementById('accParentCode').value.trim();
  const isGroup = document.getElementById('accIsGroup').value === 'true';
  if (!name) { showToast_('اسم الحساب مطلوب', 'error'); return; }
  try {
    await api.addAccount({ username: state.user.username }, { name: name, type: type, parentCode: parentCode || null, isGroup: isGroup });
    showToast_('تم إضافة الحساب ✅', 'success');
    renderAccountsPage();
  } catch (err) { showErrorToast_(err); }
}

// ============================================================
// الخزنة والبنوك المتعددة
// ============================================================
async function renderTreasuryPage() {
  try {
    const accounts = await api.listTreasuryAccounts();
    const cur = state.settings.currency || 'جنيه';
    const totalBalance = accounts.reduce(function (s, a) { return s + Number(a.currentBalance); }, 0);

    let html = '<div class="grid grid-4">' + statCard_('🏦', 'إجمالي الأرصدة', formatMoney_(totalBalance, cur), '', true) + '</div>';

    html += '<div class="grid grid-2" style="margin-top:22px;">';
    html += '<div class="card"><div class="card-heading">➕ حساب خزنة/بنك جديد</div>' +
      '<div class="field"><label>الاسم <span class="req">*</span></label><input type="text" id="trName"></div>' +
      '<div class="form-grid" style="margin-top:10px;"><div class="field"><label>النوع</label><select id="trType"><option>كاش</option><option>بنك</option></select></div>' +
      '<div class="field"><label>الرصيد الافتتاحي</label><input type="number" id="trOpening" value="0"></div></div>' +
      '<div class="form-grid" style="margin-top:10px;"><div class="field"><label>اسم البنك (لو بنك)</label><input type="text" id="trBankName"></div>' +
      '<div class="field"><label>رقم الحساب</label><input type="text" id="trAccNumber"></div></div>' +
      '<button class="btn success block" style="margin-top:16px;" onclick="submitTreasuryAccount_()">✅ إضافة</button></div>';

    html += '<div class="card"><div class="card-heading">🔁 تحويل بين حسابات</div>' +
      '<div class="field"><label>من حساب</label><select id="trFrom">' + accounts.map(function (a) { return '<option value="' + a.id + '">' + a.name + ' (' + formatMoney_(a.currentBalance, cur) + ')</option>'; }).join('') + '</select></div>' +
      '<div class="field" style="margin-top:10px;"><label>إلى حساب</label><select id="trTo">' + accounts.map(function (a) { return '<option value="' + a.id + '">' + a.name + '</option>'; }).join('') + '</select></div>' +
      '<div class="form-grid" style="margin-top:10px;"><div class="field"><label>المبلغ</label><input type="number" id="trAmount"></div>' +
      '<div class="field"><label>ملاحظة</label><input type="text" id="trNotes"></div></div>' +
      '<button class="btn block" style="margin-top:16px;" onclick="submitTreasuryTransfer_()">🔁 تحويل</button></div>';
    html += '</div>';

    html += '<div class="section-title">الحسابات الحالية</div><div class="card">';
    html += accounts.length === 0 ? emptyRow_('🏦', 'لسه مفيش حسابات خزنة/بنوك مضافة') :
      accounts.map(function (a) {
        return '<div class="list-item"><span>' + (a.type === 'بنك' ? '🏦' : '💵') + ' ' + a.name + (a.bankName ? ' — ' + a.bankName : '') + '</span><span><b>' + formatMoney_(a.currentBalance, cur) + '</b></span></div>';
      }).join('');
    html += '</div>';
    setContent_(html);
  } catch (err) { showErrorToast_(err); }
}

async function submitTreasuryAccount_() {
  const name = document.getElementById('trName').value.trim();
  if (!name) { showToast_('الاسم مطلوب', 'error'); return; }
  try {
    await api.addTreasuryAccount({ username: state.user.username }, {
      name: name, type: document.getElementById('trType').value,
      bankName: document.getElementById('trBankName').value, accountNumber: document.getElementById('trAccNumber').value,
      openingBalance: Number(document.getElementById('trOpening').value) || 0
    });
    showToast_('تم إضافة الحساب ✅', 'success');
    renderTreasuryPage();
  } catch (err) { showErrorToast_(err); }
}

async function submitTreasuryTransfer_() {
  const fromId = document.getElementById('trFrom').value, toId = document.getElementById('trTo').value;
  const amount = Number(document.getElementById('trAmount').value);
  if (!amount) { showToast_('المبلغ مطلوب', 'error'); return; }
  if (fromId === toId) { showToast_('اختاري حسابين مختلفين', 'error'); return; }
  try {
    await api.transferBetweenTreasuries({ username: state.user.username }, fromId, toId, amount, document.getElementById('trNotes').value);
    showToast_('تم التحويل ✅', 'success');
    renderTreasuryPage();
  } catch (err) { showErrorToast_(err); }
}

// ============================================================
// مراكز التكلفة
// ============================================================
async function renderCostCentersPage() {
  try {
    const centers = await api.listCostCenters();
    let html = '<div class="card"><div class="card-heading">🎯 مركز تكلفة جديد</div>' +
      '<div class="form-grid"><div class="field"><label>الاسم <span class="req">*</span></label><input type="text" id="ccName"></div>' +
      '<div class="field"><label>الوصف</label><input type="text" id="ccDesc"></div></div>' +
      '<button class="btn success block" style="margin-top:16px;" onclick="submitCostCenter_()">✅ إضافة</button></div>';

    html += '<div class="section-title">مراكز التكلفة الحالية</div><div class="card">';
    html += centers.length === 0 ? emptyRow_('🎯', 'لسه مفيش مراكز تكلفة مضافة') :
      centers.map(function (c) { return '<div class="list-item"><span>' + c.name + (c.description ? '<br><span style="color:var(--text-faint); font-size:11px;">' + c.description + '</span>' : '') + '</span></div>'; }).join('');
    html += '</div>';
    setContent_(html);
  } catch (err) { showErrorToast_(err); }
}

async function submitCostCenter_() {
  const name = document.getElementById('ccName').value.trim();
  if (!name) { showToast_('الاسم مطلوب', 'error'); return; }
  try {
    await api.addCostCenter({ username: state.user.username }, { name: name, description: document.getElementById('ccDesc').value });
    showToast_('تم إضافة مركز التكلفة ✅', 'success');
    renderCostCentersPage();
  } catch (err) { showErrorToast_(err); }
}

// ============================================================
// سلة المحذوفات
// ============================================================
async function renderRecycleBinPage() {
  try {
    const items = await api.listDeletedRecords();
    let html = '<div class="card">';
    html += items.length === 0 ? emptyRow_('🗑️', 'سلة المحذوفات فاضية دلوقتي') :
      items.map(function (it) {
        return '<div class="list-item"><span><span class="pill">' + it.tableLabel + '</span> ' + it.label +
          '<br><span style="color:var(--text-faint); font-size:11px;">اتحذف: ' + formatDate_(it.deletedAt) + '</span></span>' +
          '<button class="btn secondary" onclick="restoreDeletedItem_(\'' + it.table + '\', \'' + it.id + '\')">↩️ استرجاع</button></div>';
      }).join('');
    html += '</div>';
    setContent_(html);
  } catch (err) { showErrorToast_(err); }
}

async function restoreDeletedItem_(table, id) {
  try {
    await api.restoreDeletedRecord({ username: state.user.username }, table, id);
    showToast_('تم الاسترجاع ✅', 'success');
    renderRecycleBinPage();
  } catch (err) { showErrorToast_(err); }
}
