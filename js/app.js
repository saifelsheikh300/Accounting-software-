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
    { key: 'purchaserequests', label: 'طلبات الشراء والاعتماد', icon: '📝', module: 'Suppliers' },
    { key: 'orders', label: 'الأوردرات والعملاء', icon: '🧍', module: 'Orders' },
    { key: 'invoices', label: 'الفواتير', icon: '📄', module: 'Invoices' }
  ]},
  { label: 'المالية', items: [
    { key: 'capital', label: 'رأس المال والشركاء', icon: '🤝', module: 'Capital' },
    { key: 'pettycash', label: 'العهدة', icon: '👛', module: 'PettyCash' },
    { key: 'treasury', label: 'الخزنة والبنوك', icon: '🏦', module: 'Reports' },
    { key: 'accounts', label: 'شجرة الحسابات', icon: '🗂️', module: 'Reports' },
    { key: 'costcenters', label: 'مراكز التكلفة', icon: '🎯', module: 'Expenses' },
    { key: 'checks', label: 'الشيكات', icon: '📑', module: 'Reports' },
    { key: 'currencies', label: 'العملات وأسعار الصرف', icon: '💱', module: 'Settings' },
    { key: 'reports', label: 'التقارير', icon: '📈', module: 'Reports' },
    { key: 'trialbalance', label: 'ميزان المراجعة', icon: '⚖️', module: 'Reports' },
    { key: 'balancesheet', label: 'الميزانية العمومية', icon: '🏛️', module: 'Reports' },
    { key: 'periods', label: 'قفل الفترات المحاسبية', icon: '🔒', module: 'Reports' },
    { key: 'fixedassets', label: 'الأصول الثابتة', icon: '🏗️', module: 'Reports' },
    { key: 'openingbalances', label: 'أرصدة أول مدة', icon: '📂', module: 'Reports' }
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
  purchaserequests: ['طلبات الشراء والاعتماد', 'مرحلة الطلب قبل تحويله لأمر شراء فعلي'],
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
  checks: ['الشيكات', 'متابعة الشيكات الواردة والصادرة وحالتها'],
  currencies: ['العملات وأسعار الصرف', 'إدارة العملات الإضافية وسعر الصرف اليومي'],
  recyclebin: ['سلة المحذوفات', 'استرجاع أي عنصر اتحذف بالغلط'],
  trialbalance: ['ميزان المراجعة', 'كل الحسابات ومجاميعها المدينة والدائنة من دفتر اليومية'],
  balancesheet: ['الميزانية العمومية', 'الأصول والخصوم وحقوق الملكية حتى تاريخ معيّن'],
  periods: ['قفل الفترات المحاسبية', 'منع التعديل على شهر اتقفل خلاص بعد مراجعته'],
  fixedassets: ['الأصول الثابتة', 'متابعة الأصول والإهلاك الشهري المتراكم'],
  openingbalances: ['أرصدة أول مدة', 'رصيد بداية التشغيل لكل حساب، وترحيله لدفتر اليومية']
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

  btn.innerHTML = '<span class="dots-loader"><span></span><span></span><span></span><span></span></span>';
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
// براند شاشة تسجيل الدخول + التاب (اسم/لوجو/لون) — بيتطبق من غير
// تسجيل دخول عشان يبان صح من أول ما الصفحة تفتح
// ------------------------------------------------------------
async function applyPublicBranding() {
  const s = await api.getPublicBranding();
  if (s.accentColor) document.documentElement.style.setProperty('--accent', s.accentColor);
  if (s.brandName) {
    const el = document.getElementById('loginBrandName');
    if (el) el.textContent = s.brandName;
  }
  if (s.logoUrl) {
    const loginLogo = document.getElementById('loginLogo');
    if (loginLogo) { loginLogo.classList.add('has-img'); loginLogo.innerHTML = '<img src="' + s.logoUrl + '" alt="logo">'; }
    setCircularFavicon_(s.logoUrl);
  }
}

function setCircularFavicon_(url) {
  const img = new Image();
  img.crossOrigin = 'anonymous';
  img.onload = function () {
    try {
      const size = 64;
      const canvas = document.createElement('canvas');
      canvas.width = size; canvas.height = size;
      const ctx = canvas.getContext('2d');
      ctx.save();
      ctx.beginPath();
      ctx.arc(size / 2, size / 2, size / 2, 0, Math.PI * 2);
      ctx.closePath();
      ctx.clip();
      ctx.drawImage(img, 0, 0, size, size);
      ctx.restore();
      const link = document.getElementById('faviconLink');
      if (link) link.href = canvas.toDataURL('image/png');
    } catch (e) {
      const link = document.getElementById('faviconLink');
      if (link) link.href = url; // لو المصدر مانع CORS، نستخدم الرابط زي ما هو من غير قص دائري
    }
  };
  img.onerror = function () {};
  img.src = url;
}

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
    purchaserequests: renderPurchaseRequestsPage,
    orders: renderOrdersPage, invoices: renderInvoicesPage, capital: renderCapitalPage,
    pettycash: renderPettyCashPage, reports: renderReportsPage, hr: renderHrPage,
    users: renderUsersPage, settings: renderSettingsPage,
    treasury: renderTreasuryPage, accounts: renderAccountsPage,
    costcenters: renderCostCentersPage, recyclebin: renderRecycleBinPage,
    checks: renderChecksPage, currencies: renderCurrenciesPage,
    trialbalance: renderTrialBalancePage, balancesheet: renderBalanceSheetPage,
    periods: renderPeriodsPage, fixedassets: renderFixedAssetsPage,
    openingbalances: renderOpeningBalancesPage
  };
  (renderers[pageKey] || renderComingSoon_)();
}

function renderSkeleton_() { return '<div class="grid grid-4">' + '<div class="loading-skeleton" style="height:110px; border-radius:16px;"></div>'.repeat(4) + '</div>'; }
function renderComingSoon_() { document.getElementById('content').innerHTML = '<div class="card"><div class="empty-state"><span class="emoji">🚧</span><div class="msg">الشاشة دي هتُبنى قريبًا</div></div></div>'; }
function setContent_(html) { document.getElementById('content').innerHTML = '<div class="page-fade">' + html + '</div>'; enhanceSelects_(document.getElementById('content')); }

// ============================================================
// هيلبر مشترك: حسابات الخزنة/البنوك — تُستخدم في أي شاشة بتحرك
// فلوس (بيع/مصروف/شراء/تحصيل/عهدة/شيكات) عشان تحدد منين بالظبط
// ============================================================
let treasuryAccountsCache_ = null;

async function getTreasuryAccountsCached_(forceRefresh) {
  if (!treasuryAccountsCache_ || forceRefresh) treasuryAccountsCache_ = await api.listTreasuryAccounts();
  return treasuryAccountsCache_;
}

function treasuryAccountOptionsHtml_(accounts) {
  if (!accounts || accounts.length === 0) return '<option value="">لا يوجد حسابات — ضيفي من صفحة "الخزنة والبنوك"</option>';
  return accounts.map(function (t) { return '<option value="' + t.id + '">' + t.name + ' (' + t.type + ')</option>'; }).join('');
}

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

let posAllProducts = [];

function renderPosPage() {
  setContent_(
    '<div class="grid grid-2">' +
      '<div class="card">' +
        '<div class="card-heading">🛍️ المنتجات</div>' +
        '<div class="card-desc">دوسي على أي منتج عشان تضيفيه للسلة، أو دوري لو عايزة تفلتري</div>' +
        '<div class="field"><input type="text" id="posSearchInput" oninput="posSearch_(this.value)" placeholder="فلترة (اختياري)..."></div>' +
        '<div id="posSearchResults" style="margin-top:14px;"></div>' +
      '</div>' +
      '<div class="card">' +
        '<div class="card-heading">🛒 السلة الحالية</div>' +
        '<div id="posCartList" style="margin:14px 0;"></div>' +
        '<div class="form-grid">' +
          '<div class="field"><label>الخصم</label><input type="number" id="posDiscount" value="0"></div>' +
          '<div class="field"><label>طريقة الدفع</label><select id="posPaymentMethod" onchange="onPosPaymentMethodChange_()"><option>كاش</option><option>فودافون كاش</option><option>بطاقة</option><option>انستاباي</option><option value="آجل">آجل - فاتورة عميل</option></select></div>' +
        '</div>' +
        '<div class="field" id="posTreasuryFieldWrap"><label>هتضاف لحساب</label><select id="posTreasuryAccount"><option value="">جاري التحميل...</option></select></div>' +
        '<div id="posInvoiceSection" style="display:none;"></div>' +
        '<button class="btn success block" style="margin-top:16px;" onclick="submitPosSale_()">✅ إتمام البيع</button>' +
        '<button class="btn danger block" style="margin-top:10px;" onclick="openStandaloneReturnModal_()">↩️ مرتجع منتج</button>' +
      '</div>' +
    '</div>' +
    '<div class="section-title">ملخص اليوم</div><div id="posTodaySummary" class="grid grid-3"></div>'
  );
  posCart = [];
  loadPosSummary_();
  loadPosProductGrid_();
  loadPosTreasuryOptions_();
}

async function loadPosTreasuryOptions_() {
  try {
    const accounts = await getTreasuryAccountsCached_();
    document.getElementById('posTreasuryAccount').innerHTML = treasuryAccountOptionsHtml_(accounts);
    refreshSelect_('posTreasuryAccount');
  } catch (err) { /* صامت — مش بيمنع إتمام البيع لو فشل التحميل */ }
}

async function loadPosProductGrid_() {
  document.getElementById('posSearchResults').innerHTML = emptyRow_('⏳', 'جاري التحميل...');
  try {
    const idx = await api.getInventoryIndex();
    posAllProducts = Object.values(idx.products)
      .filter(function (p) { return p.status === 'نشط'; })
      .map(function (p) { return { code: p.code, name: p.name, basePrice: p.basePrice, variants: p.variants.filter(function (v) { return v.status === 'نشط'; }) }; })
      .sort(function (a, b) { return a.code.localeCompare(b.code); });
    renderPosProductGrid_(posAllProducts);
  } catch (err) { showErrorToast_(err); }
}

function renderPosProductGrid_(list) {
  document.getElementById('posSearchResults').innerHTML = list.length === 0 ? emptyRow_('📦', 'لا يوجد منتجات') : buildProductResultsHtml_(list, 'addToPosCart_');
}

function posSearch_(query) {
  const q = (query || '').trim().toLowerCase();
  if (!q) { renderPosProductGrid_(posAllProducts); return; }
  const filtered = posAllProducts.filter(function (p) {
    if (p.name.toLowerCase().includes(q) || p.code.toLowerCase().includes(q)) return true;
    return p.variants.some(function (v) { return v.code.toLowerCase().includes(q) || (v.color || '').toLowerCase().includes(q) || (v.size || '').toLowerCase().includes(q); });
  });
  renderPosProductGrid_(filtered);
}

// ------------------------------------------------------------
// مرتجع منتج مباشر — بحث عن المنتج زي البيع بالظبط، من غير أي
// حاجة برقم فاتورة قديمة. بيزوّد المخزون ويقلل الإيراد فورًا
// ------------------------------------------------------------
let returnCart = [];
let returnLinkedSale = null;

async function openStandaloneReturnModal_() {
  returnCart = [];
  returnLinkedSale = null;
  const body = '<div class="field"><label>ربط المرتجع بفاتورة؟ (اختياري)</label><input type="text" id="returnInvoiceSearch" oninput="returnInvoiceSearch_(this.value)" placeholder="دوري برقم الفاتورة أو اسم العميل..."></div>' +
    '<div id="returnInvoiceResults"></div>' +
    '<div id="returnLinkedSaleBadge" style="display:none; margin-bottom:14px;"></div>' +
    '<div class="field"><input type="text" id="returnSearchInput" oninput="returnProductSearch_(this.value)" placeholder="🔍 دوري عن المنتج..."></div>' +
    '<div id="returnSearchResults" style="margin-top:12px; max-height:220px; overflow-y:auto;"></div>' +
    '<div class="section-title" style="margin-top:14px;">الأصناف المرتجعة</div>' +
    '<div id="returnCartList"></div>' +
    '<div class="field" style="margin-top:12px;"><label>طريقة الدفع الأصلية</label><select id="returnPaymentMethod" onchange="onReturnPaymentMethodChange_()"><option>كاش</option><option>فودافون كاش</option><option>بطاقة</option><option>انستاباي</option><option value="آجل">آجل</option></select></div>' +
    '<div class="field" id="returnTreasuryFieldWrap"><label>هيتخصم من حساب</label><select id="returnTreasuryAccount"><option value="">جاري التحميل...</option></select></div>';

  openModal('↩️ مرتجع منتج', 'دوري عن المنتج، حددي الكمية، وسجّلي المرتجع', body,
    '<button class="btn secondary" onclick="closeModal()">إلغاء</button><button class="btn danger" onclick="submitStandaloneReturn_()">✅ تسجيل المرتجع</button>');

  renderReturnCart_();
  if (!posAllProducts || posAllProducts.length === 0) { await loadPosProductGrid_(); }
  renderReturnProductGrid_(posAllProducts || []);
  getTreasuryAccountsCached_().then(function (accounts) {
    document.getElementById('returnTreasuryAccount').innerHTML = treasuryAccountOptionsHtml_(accounts);
    refreshSelect_('returnTreasuryAccount');
  }).catch(function () { /* صامت */ });
}

async function returnInvoiceSearch_(query) {
  const el = document.getElementById('returnInvoiceResults');
  if (!query || query.length < 2) { el.innerHTML = ''; return; }
  try {
    const results = await api.posSearchSaleForReturn(query);
    const cur = state.settings.currency || 'جنيه';
    el.innerHTML = results.length === 0 ? emptyRow_('🔎', 'لا يوجد نتائج') :
      results.map(function (r) {
        return '<div class="list-item" style="cursor:pointer;" onclick="linkReturnToSale_(\'' + r.saleId.replace(/'/g, "\\'") + '\', \'' + (r.customerName || '').replace(/'/g, "\\'") + '\')">' +
          '<span>' + r.saleId + ' — ' + (r.customerName || 'بدون اسم') + '</span><span>' + formatMoney_(r.total, cur) + '</span></div>';
      }).join('');
  } catch (err) { showErrorToast_(err); }
}

function linkReturnToSale_(saleId, customerName) {
  returnLinkedSale = saleId;
  document.getElementById('returnInvoiceSearch').value = '';
  document.getElementById('returnInvoiceResults').innerHTML = '';
  const badge = document.getElementById('returnLinkedSaleBadge');
  badge.style.display = 'block';
  badge.innerHTML = '<div class="list-item"><span class="pill success">🔗 مرتبط بفاتورة ' + saleId + (customerName ? ' — ' + customerName : '') + '</span>' +
    '<span style="cursor:pointer; color:var(--danger);" onclick="unlinkReturnSale_()">✕ إلغاء الربط</span></div>';
}

function unlinkReturnSale_() {
  returnLinkedSale = null;
  document.getElementById('returnLinkedSaleBadge').style.display = 'none';
  document.getElementById('returnLinkedSaleBadge').innerHTML = '';
}

function renderReturnProductGrid_(list) {
  const el = document.getElementById('returnSearchResults');
  if (!el) return;
  el.innerHTML = list.length === 0 ? emptyRow_('📦', 'لا يوجد منتجات') : buildProductResultsHtml_(list, 'addToReturnCart_');
}

function returnProductSearch_(query) {
  const q = (query || '').trim().toLowerCase();
  const source = posAllProducts || [];
  if (!q) { renderReturnProductGrid_(source); return; }
  const filtered = source.filter(function (p) {
    if (p.name.toLowerCase().includes(q) || p.code.toLowerCase().includes(q)) return true;
    return p.variants.some(function (v) { return v.code.toLowerCase().includes(q) || (v.color || '').toLowerCase().includes(q) || (v.size || '').toLowerCase().includes(q); });
  });
  renderReturnProductGrid_(filtered);
}

function addToReturnCart_(variantCode, label, price) {
  const existing = returnCart.find(function (i) { return i.variantCode === variantCode; });
  if (existing) existing.qty += 1; else returnCart.push({ variantCode: variantCode, label: label, price: price, qty: 1 });
  renderReturnCart_();
}

function renderReturnCart_() {
  const el = document.getElementById('returnCartList');
  if (!el) return;
  if (returnCart.length === 0) { el.innerHTML = emptyRow_('↩️', 'لسه محددتش أي صنف'); return; }
  let total = 0;
  el.innerHTML = returnCart.map(function (i, idx) {
    total += i.price * i.qty;
    return '<div class="list-item"><span>' + i.label + '</span><span>سعر <input type="number" value="' + i.price + '" style="width:65px; padding:5px;" onchange="updateReturnItemPrice_(' + idx + ', this.value)"> ' +
      'كمية <input type="number" value="' + i.qty + '" style="width:50px; padding:5px;" onchange="updateReturnItemQty_(' + idx + ', this.value)"> ' +
      '<span class="del-x" onclick="removeFromReturnCart_(' + idx + ')" style="cursor:pointer;">✕</span></span></div>';
  }).join('') + '<div class="list-item"><b>الإجمالي</b><b>' + total + '</b></div>';
}
function updateReturnItemPrice_(idx, val) { returnCart[idx].price = Number(val); renderReturnCart_(); }
function updateReturnItemQty_(idx, val) { returnCart[idx].qty = Number(val); renderReturnCart_(); }
function removeFromReturnCart_(idx) { returnCart.splice(idx, 1); renderReturnCart_(); }

function onReturnPaymentMethodChange_() {
  const val = document.getElementById('returnPaymentMethod').value;
  document.getElementById('returnTreasuryFieldWrap').style.display = val === 'آجل' ? 'none' : 'block';
}

async function submitStandaloneReturn_() {
  if (returnCart.length === 0) { showToast_('حددي صنف واحد على الأقل', 'error'); return; }
  const paymentMethod = document.getElementById('returnPaymentMethod').value;
  const treasuryAccountId = document.getElementById('returnTreasuryAccount').value || null;
  const items = returnCart.map(function (i) { return { variantCode: i.variantCode, qty: i.qty, price: i.price }; });
  const saleReference = returnLinkedSale;
  closeModal();
  try {
    await api.recordStandaloneReturn({ username: state.user.username }, items, paymentMethod, treasuryAccountId, '', saleReference);
    showToast_('تم تسجيل المرتجع ✅ اتزود في المخزون واتقل من الإيراد', 'success');
    loadPosSummary_(); loadPosProductGrid_();
  } catch (err) { showErrorToast_(err); }
}

// ------------------------------------------------------------
// مودال مرتجع جزئي مشترك — تحديد الكمية المرتجعة من كل صنف
// (يُستخدم من شاشة المبيعات عند الإرجاع مقابل فاتورة محددة)
// ------------------------------------------------------------
let pendingReturnItems = [];
let pendingReturnSaleId = '';
let pendingReturnRefreshFn = null;

async function openReturnModal_(saleId, items, refreshFn) {
  pendingReturnItems = items;
  pendingReturnSaleId = saleId;
  pendingReturnRefreshFn = refreshFn;
  const accounts = await getTreasuryAccountsCached_().catch(function () { return []; });

  const body = '<div class="hint" style="margin-bottom:10px;">حددي الكمية اللي فعلاً رجعتلك من كل صنف — سيبي 0 لأي صنف مترجعش</div>' +
    '<div>' + items.map(function (it, idx) {
      return '<div class="card" style="background:var(--surface-2); padding:10px; margin-bottom:8px;">' +
        '<div class="card-row"><b>' + it.variantCode + '</b><span class="hint">الكمية الأصلية بالبيعة: ' + it.qty + '</span></div>' +
        '<div class="field" style="margin-top:8px; margin-bottom:0;"><label>الكمية المرتجعة</label>' +
        '<input type="number" id="retQty_' + idx + '" value="0" min="0" max="' + it.qty + '"></div></div>';
    }).join('') + '</div>' +
    '<div class="field"><label>هتتخصم من حساب (لو كانت البيعة كاش)</label><select id="returnTreasuryAccount">' + treasuryAccountOptionsHtml_(accounts) + '</select></div>';

  openModal('↩️ مرتجع بيعة ' + saleId, '', body,
    '<button class="btn secondary" onclick="closeModal()">إلغاء</button><button class="btn danger" onclick="submitPartialReturn_()">✅ تسجيل المرتجع</button>');
}

async function submitPartialReturn_() {
  const treasuryAccountId = document.getElementById('returnTreasuryAccount').value || null;
  const returnItems = [];
  let isFull = true;
  pendingReturnItems.forEach(function (it, idx) {
    const input = document.getElementById('retQty_' + idx);
    const qty = Math.min(Math.max(Number(input.value) || 0, 0), it.qty);
    if (qty < it.qty) isFull = false;
    if (qty > 0) returnItems.push({ variantCode: it.variantCode, qty: qty, price: it.price });
  });
  if (returnItems.length === 0) { showToast_('حددي كمية مرتجعة لصنف واحد على الأقل', 'error'); return; }
  closeModal();
  try {
    await api.recordPartialReturn({ username: state.user.username }, pendingReturnSaleId, returnItems, isFull, treasuryAccountId);
    showToast_('تم تسجيل المرتجع ✅', 'success');
    if (pendingReturnRefreshFn) pendingReturnRefreshFn();
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

  if (paymentMethod === 'آجل') { await submitPosSaleOnInvoice_(discount); return; }

  const treasuryAccountId = document.getElementById('posTreasuryAccount').value || null;
  try {
    const res = await api.posSale({ username: state.user.username }, posCart.map(function (i) { return { variantCode: i.variantCode, qty: i.qty, price: i.price }; }), discount, paymentMethod, treasuryAccountId);
    showToast_('تمت البيعة بنجاح ✅ الإجمالي: ' + res.total, 'success');
    posCart = []; renderPosCart_();
    document.getElementById('posSearchInput').value = '';
    loadPosSummary_();
    loadPosProductGrid_();
  } catch (err) { showErrorToast_(err); }
}

// ------------------------------------------------------------
// البيع "آجل" من الكاشير مباشرة — إما فتح فاتورة عميل جديدة أو
// الإضافة على فاتورة مفتوحة موجودة، بدل الدفع الفوري
// ------------------------------------------------------------
function onPosPaymentMethodChange_() {
  const val = document.getElementById('posPaymentMethod').value;
  const section = document.getElementById('posInvoiceSection');
  document.getElementById('posTreasuryFieldWrap').style.display = val === 'آجل' ? 'none' : 'block';
  if (val === 'آجل') {
    section.style.display = 'block';
    section.innerHTML =
      '<div class="section-title" style="margin-top:6px;">فاتورة العميل</div>' +
      '<div class="field"><select id="posInvoiceMode" onchange="onPosInvoiceModeChange_()"><option value="new">فتح فاتورة جديدة</option><option value="existing">إضافة على فاتورة مفتوحة</option></select></div>' +
      '<div id="posInvoiceModeFields"></div>';
    onPosInvoiceModeChange_();
    enhanceSelects_(section);
  } else { section.style.display = 'none'; section.innerHTML = ''; }
}

function onPosInvoiceModeChange_() {
  const mode = document.getElementById('posInvoiceMode').value;
  const el = document.getElementById('posInvoiceModeFields');
  if (mode === 'new') {
    el.innerHTML = '<div class="form-grid"><div class="field"><label>اسم العميل <span class="req">*</span></label><input type="text" id="posInvCustomerName"></div>' +
      '<div class="field"><label>تليفون (اختياري)</label><input type="text" id="posInvCustomerPhone"></div></div>';
  } else {
    el.innerHTML = '<div class="field"><label>ابحثي عن الفاتورة (اسم العميل)</label><input type="text" id="posInvSearchInput" oninput="posInvoiceSearch_(this.value)"></div>' +
      '<div id="posInvSearchResults"></div><input type="hidden" id="posSelectedInvoiceId">';
  }
}

async function posInvoiceSearch_(query) {
  if (!query || query.length < 2) { document.getElementById('posInvSearchResults').innerHTML = ''; return; }
  try {
    const invoices = await api.listInvoices({});
    const matched = invoices.filter(function (i) { return i.status !== 'مدفوعة بالكامل' && i.customerName.toLowerCase().includes(query.toLowerCase()); });
    document.getElementById('posInvSearchResults').innerHTML = matched.length === 0 ? emptyRow_('🔎', 'لا يوجد فواتير مفتوحة بهذا الاسم') :
      matched.map(function (i) {
        return '<div class="list-item" style="cursor:pointer;" onclick="selectPosInvoice_(\'' + i.invoiceId + '\', \'' + i.customerName.replace(/'/g, '') + '\')"><span>' + i.customerName + ' — ' + i.invoiceNumber + '</span><span class="pill warning">متبقي ' + i.remaining + '</span></div>';
      }).join('');
  } catch (err) { showErrorToast_(err); }
}

function selectPosInvoice_(id, name) {
  document.getElementById('posSelectedInvoiceId').value = id;
  document.getElementById('posInvSearchResults').innerHTML = '<div class="hint">✅ هيتضاف على فاتورة: ' + name + '</div>';
}

async function submitPosSaleOnInvoice_(discount) {
  const mode = document.getElementById('posInvoiceMode').value;
  const subtotal = posCart.reduce(function (s, i) { return s + i.price * i.qty; }, 0);
  const ratio = discount > 0 && subtotal > 0 ? Math.max(0, (subtotal - discount) / subtotal) : 1;
  const items = posCart.map(function (i) { return { variantCode: i.variantCode, qty: i.qty, price: Math.round(i.price * ratio * 100) / 100 }; });

  try {
    let invoiceId;
    if (mode === 'new') {
      const name = document.getElementById('posInvCustomerName').value.trim();
      const phone = document.getElementById('posInvCustomerPhone').value.trim();
      if (!name) { showToast_('اسم العميل مطلوب', 'error'); return; }
      const opened = await api.openInvoice({ username: state.user.username }, { customerName: name, customerPhone: phone });
      invoiceId = opened.invoiceId;
    } else {
      invoiceId = document.getElementById('posSelectedInvoiceId').value;
      if (!invoiceId) { showToast_('اختاري فاتورة الأول', 'error'); return; }
    }

    await api.addItemsToInvoice({ username: state.user.username }, invoiceId, items);
    showToast_('تم تسجيل الأصناف على الفاتورة ✅', 'success');
    posCart = []; renderPosCart_();
    document.getElementById('posSearchInput').value = '';
    document.getElementById('posPaymentMethod').value = 'كاش';
    onPosPaymentMethodChange_();
    loadPosSummary_();
    loadPosProductGrid_();
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

  let html = '<div class="field"><input type="text" id="invSearchInput" oninput="invSearch_(this.value)" placeholder="🔍 دوري باسم المنتج أو الكود..."></div>' +
    '<button class="btn success block" style="margin-top:10px; padding:15px; font-size:15px;" onclick="openAddProductModal_()">➕ منتج جديد</button>' +
    '<div class="hint" style="cursor:pointer; margin-top:8px; text-align:center;" onclick="openCategoriesModal_()">🗂️ إدارة الفئات (' + invTreeCache.mainCategories.length + ')</div>';

  html += '<div id="invCardsWrap" style="margin-top:16px;">' + buildInventoryCards_(products) + '</div>';
  html += '<div class="hint" style="margin-top:14px; text-align:center;">📦 ' + products.length + ' منتج · 🎨 ' + totalVariants + ' متغير</div>';
  return html;
}

function buildInventoryCards_(products) {
  if (products.length === 0) {
    return emptyRow_('📦', 'لسه مفيش منتجات — دوسي "منتج جديد" فوق عشان تبدئي');
  }
  return products.map(function (p) {
    const totalQty = p.variants.reduce(function (s, v) { return s + Number(v.quantity); }, 0);
    const anyLow = p.variants.some(function (v) { return v.quantity <= v.lowStockThreshold; });
    const catLine = (p.mainCategoryName ? p.mainCategoryName + ' ← ' : '') + (p.subCategoryName || 'بدون فئة');
    return '<div class="card" style="margin-bottom:10px; padding:14px;">' +
      '<div class="card-row"><b style="font-size:15.5px;">' + p.name + '</b>' +
      '<span style="font-size:12px; color:var(--accent); cursor:pointer; white-space:nowrap;" onclick="openEditProductModal_(\'' + p.code + '\')">✏️ تعديل</span></div>' +
      '<div style="font-size:11px; color:var(--text-faint); margin-top:3px;">' + catLine + '</div>' +
      '<div class="card-row" style="margin-top:10px; flex-wrap:wrap; gap:8px;">' +
        '<span class="pill">' + p.code + '</span>' +
        (p.variants.length > 1 ? '<span class="pill">🎨 ' + p.variants.length + ' متغير</span>' : '') +
        '<span class="pill info">سعر البيع: ' + p.basePrice + '</span>' +
        '<span class="pill ' + (anyLow ? 'danger' : 'success') + '">الكمية: ' + totalQty + '</span>' +
        '<span class="pill ' + (p.status === 'نشط' ? 'success' : 'danger') + '">' + p.status + '</span>' +
      '</div></div>';
  }).join('');
}

function invSearch_(query) {
  const products = Object.values(invProductsCache || {});
  const q = (query || '').trim().toLowerCase();
  const filtered = !q ? products : products.filter(function (p) {
    if (p.name.toLowerCase().includes(q) || p.code.toLowerCase().includes(q)) return true;
    if ((p.subCategoryName || '').toLowerCase().includes(q)) return true;
    return p.variants.some(function (v) {
      return v.code.toLowerCase().includes(q) || (v.color || '').toLowerCase().includes(q) || (v.size || '').toLowerCase().includes(q);
    });
  });
  document.getElementById('invCardsWrap').innerHTML = buildInventoryCards_(filtered);
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
      '<div style="font-weight:800; font-size:13.5px; display:flex; align-items:center; gap:8px;">📁 ' + m.name + ' <span class="pill info">' + m.code + '</span>' +
      '<span style="cursor:pointer; font-size:11.5px; color:var(--accent); font-weight:700;" onclick="promptRenameCategory_(\'' + m.code + '\', \'' + escapeJsStr_(m.name) + '\')">✏️ تعديل</span></div>' +
      (subs.length > 0 ? '<div style="padding-right:22px; margin-top:8px; display:flex; flex-wrap:wrap; gap:6px;">' + subs.map(function (s) {
        return '<span class="variant-chip">' + s.name + ' <span class="qty-tag">' + s.code + '</span> <span style="cursor:pointer; color:var(--accent);" onclick="promptRenameCategory_(\'' + s.code + '\', \'' + escapeJsStr_(s.name) + '\')">✏️</span></span>';
      }).join('') + '</div>' :
        '<div style="padding-right:22px; margin-top:6px; font-size:11.5px; color:var(--text-faint);">لا يوجد فئات فرعية بعد</div>') + '</div>';
  }).join('');
}

function escapeJsStr_(s) { return String(s || '').replace(/'/g, "\\'"); }

function promptRenameCategory_(code, currentName) {
  openModal('✏️ تعديل اسم الفئة', 'الكود: ' + code,
    '<div class="field"><label>الاسم الجديد</label><input type="text" id="renameCatInput" value="' + currentName + '"></div>',
    '<button class="btn secondary" onclick="openCategoriesModal_()">إلغاء</button><button class="btn success" onclick="submitRenameCategory_(\'' + code + '\')">✅ حفظ</button>');
}

async function submitRenameCategory_(code) {
  const newName = document.getElementById('renameCatInput').value.trim();
  if (!newName) { showToast_('اكتب اسم صحيح', 'error'); return; }
  try {
    await api.updateCategory({ username: state.user.username }, code, newName);
    showToast_('تم التعديل ✅', 'success');
    await loadInventoryBaseData_();
    openCategoriesModal_();
  } catch (err) { showErrorToast_(err); }
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
let prodVariantRowCount = 0;

async function ensureDefaultCategory_() {
  if (invTreeCache.mainCategories.length > 0) return;
  try {
    const main = await api.createCategory({ username: state.user.username }, { name: 'عام', type: 'رئيسية' });
    await api.createCategory({ username: state.user.username }, { name: 'عام', type: 'فرعية', parentCode: main.code });
    invTreeCache = await api.getProductTree();
  } catch (err) { showErrorToast_(err); }
}

async function openAddProductModal_() {
  await ensureDefaultCategory_();
  prodVariantRowCount = 0;
  const body =
    '<div class="field"><label>اسم المنتج <span class="req">*</span></label><input type="text" id="prodName" placeholder="مثال: تيشرت أساسي"></div>' +
    '<div class="form-grid" style="margin-bottom:14px;">' +
      '<div class="field"><label>سعر البيع <span class="req">*</span></label><input type="number" id="prodPrice" placeholder="0"></div>' +
      '<div class="field"><label>سعر الشراء (التكلفة)</label><input type="number" id="prodCost" placeholder="0"></div>' +
    '</div>' +
    '<div class="field"><label>الكمية الحالية بالمخزون</label><input type="number" id="prodQty" value="0"></div>' +
    '<div class="inline-add-row" style="margin-bottom:10px;"><div class="field"><label>الفئة</label>' +
    '<select id="prodMainCat" onchange="onProductMainCatChange_()">' + mainCategoryOptions_() + '</select></div>' +
    '<button class="inline-add-btn" onclick="closeModal(); openCategoriesModal_();">+ فئة</button></div>' +
    '<div class="field"><select id="prodSubCat">' + subCategoryOptionsForParent_(invTreeCache.mainCategories[0].code) + '</select></div>' +
    '<div class="hint" style="cursor:pointer; color:var(--accent); margin-top:6px;" onclick="toggleMultiVariant_()">🎨 المنتج ده بيه أكتر من لون أو مقاس؟ دوسي هنا</div>' +
    '<div id="multiVariantSection" style="display:none; margin-top:12px;">' +
      '<div class="hint">ضيفي كل لون/مقاس بكميته وتكلفته — هيتحفظوا بدل الكمية والتكلفة العامة اللي فوق</div>' +
      '<div id="prodVariantsRows" style="margin-top:10px;"></div>' +
      '<button class="btn secondary block" style="margin-top:8px;" onclick="addProductVariantRow_()">+ إضافة لون/مقاس</button>' +
    '</div>';

  openModal('🆕 منتج جديد', '', body, '<button class="btn secondary" onclick="closeModal()">إلغاء</button><button class="btn success" onclick="submitProduct_()">✅ حفظ المنتج</button>');
}

function toggleMultiVariant_() {
  const section = document.getElementById('multiVariantSection');
  const opening = section.style.display === 'none';
  section.style.display = opening ? 'block' : 'none';
  if (opening && prodVariantRowCount === 0) addProductVariantRow_();
}

function addProductVariantRow_() {
  const wrap = document.getElementById('prodVariantsRows');
  const idx = prodVariantRowCount++;
  const row = document.createElement('div');
  row.id = 'prodVarRow_' + idx;
  row.className = 'card';
  row.style.cssText = 'background:var(--surface-2); padding:12px; margin-bottom:8px;';
  row.innerHTML =
    '<div class="card-row"><b style="font-size:12px;">متغير جديد</b><span class="del-x" style="cursor:pointer;" onclick="removeProductVariantRow_(' + idx + ')">✕</span></div>' +
    '<div class="form-grid" style="margin-top:8px;">' +
      '<div class="field" style="margin-bottom:0;"><label>اللون</label><input type="text" id="varColor_' + idx + '" placeholder="أسود"></div>' +
      '<div class="field" style="margin-bottom:0;"><label>المقاس</label><input type="text" id="varSize_' + idx + '" placeholder="M"></div>' +
    '</div>' +
    '<div class="form-grid" style="margin-top:8px;">' +
      '<div class="field" style="margin-bottom:0;"><label>الكمية</label><input type="number" id="varQty_' + idx + '" placeholder="0"></div>' +
      '<div class="field" style="margin-bottom:0;"><label>سعر الشراء</label><input type="number" id="varCost_' + idx + '" placeholder="0"></div>' +
    '</div>';
  wrap.appendChild(row);
}

function removeProductVariantRow_(idx) {
  const row = document.getElementById('prodVarRow_' + idx);
  if (row) row.remove();
}

function collectProductVariantRows_() {
  const wrap = document.getElementById('prodVariantsRows');
  if (!wrap) return [];
  const rows = [];
  Array.from(wrap.children).forEach(function (rowEl) {
    const idx = rowEl.id.replace('prodVarRow_', '');
    const color = document.getElementById('varColor_' + idx).value.trim();
    const size = document.getElementById('varSize_' + idx).value.trim();
    const qty = document.getElementById('varQty_' + idx).value;
    const cost = document.getElementById('varCost_' + idx).value;
    if (color || size || qty || cost) {
      rows.push({ color: color, size: size, quantity: Number(qty || 0), cost: Number(cost || 0) });
    }
  });
  return rows;
}

function onProductMainCatChange_() {
  document.getElementById('prodSubCat').innerHTML = subCategoryOptionsForParent_(document.getElementById('prodMainCat').value);
  refreshSelect_('prodSubCat');
}

async function submitProduct_() {
  const multiVariantOpen = document.getElementById('multiVariantSection').style.display !== 'none';
  const multiVariants = multiVariantOpen ? collectProductVariantRows_() : [];
  const simpleCost = Number(document.getElementById('prodCost').value) || 0;
  const simpleQty = Number(document.getElementById('prodQty').value) || 0;

  const payload = {
    subCategory: document.getElementById('prodSubCat').value,
    name: document.getElementById('prodName').value.trim(), basePrice: Number(document.getElementById('prodPrice').value),
    variants: multiVariants.length > 0 ? multiVariants : [{ color: '', size: '', quantity: simpleQty, cost: simpleCost }]
  };
  if (!payload.subCategory) { showToast_('اختاري فئة', 'error'); return; }
  if (!payload.name || !payload.basePrice) { showToast_('اسم المنتج وسعر البيع مطلوبين', 'error'); return; }
  try {
    const res = await api.addProductWithVariants({ username: state.user.username }, payload);
    showToast_('تم حفظ المنتج ✅ الكود: ' + res.productCode, 'success');
    closeModal();
    await loadInventoryBaseData_();
    setContent_(buildInventoryMainHtml_());
  } catch (err) { showErrorToast_(err); }
}

// ------------------------------------------------------------
// مودال: تعديل منتج موجود — كل حاجة مع بعض (الاسم، الفئة الرئيسية
// والفرعية، سعر البيع، سعر الشراء، الكمية، وكل الألوان/المقاسات)
// ------------------------------------------------------------
function mainNameForSub_(parentCode) {
  const m = invTreeCache.mainCategories.find(function (c) { return c.code === parentCode; });
  return m ? m.name : '';
}

function subCategoryOptionsForParentWithSelected_(parentCode, selectedCode) {
  const subs = invTreeCache.subCategories.filter(function (s) { return s.parent === parentCode; });
  if (subs.length === 0) return '<option value="">لا يوجد فئات فرعية — أضف واحدة فوق</option>';
  return subs.map(function (s) { return '<option value="' + s.code + '"' + (s.code === selectedCode ? ' selected' : '') + '>' + s.name + '</option>'; }).join('');
}

let editProductNewRowCount = 0;

function openEditProductModal_(code) {
  const p = invProductsCache[code];
  if (!p) return;
  editProductNewRowCount = 0;
  const subCatObj = invTreeCache.subCategories.find(function (s) { return s.code === p.subCategoryCode; });
  const mainCode = subCatObj ? subCatObj.parent : (invTreeCache.mainCategories[0] ? invTreeCache.mainCategories[0].code : '');

  let body = '<div class="field"><label>اسم المنتج</label><input type="text" id="editProdName" value="' + p.name + '"></div>' +
    '<div class="inline-add-row"><div class="field"><label>الفئة الرئيسية</label>' +
    '<select id="editProdMainCat" onchange="onEditProdMainCatChange_()">' + mainCategoryOptions_(mainCode) + '</select></div>' +
    '<button class="inline-add-btn" onclick="closeModal(); openCategoriesModal_();">+ فئة</button></div>' +
    '<div class="field" style="margin-top:10px;"><label>الفئة الفرعية</label><select id="editProdSubCat">' +
    subCategoryOptionsForParentWithSelected_(mainCode, p.subCategoryCode) + '</select></div>' +
    '<div class="field" style="margin-top:10px;"><label>سعر البيع</label><input type="number" id="editProdPrice" value="' + p.basePrice + '"></div>';

  const isSimple = p.variants.length <= 1;
  if (isSimple) {
    const v = p.variants[0];
    body += '<div class="form-grid" style="margin-top:10px;">' +
      '<div class="field"><label>سعر الشراء (التكلفة)</label><input type="number" id="editSimpleCost" value="' + (v ? v.cost : 0) + '"></div>' +
      '<div class="field"><label>الكمية بالمخزون</label><input type="number" id="editSimpleQty" value="' + (v ? v.quantity : 0) + '"></div>' +
    '</div>';
  } else {
    body += '<div class="section-title" style="margin-top:16px;">الألوان/المقاسات</div>' +
      '<div id="editVariantsRows">' + p.variants.map(editVariantRowHtml_).join('') + '</div>' +
      '<button class="btn secondary block" style="margin-top:8px;" onclick="addEditVariantRow_()">+ إضافة لون/مقاس جديد</button>';
  }

  openModal('✏️ تعديل المنتج', 'الكود: ' + code, body,
    '<button class="btn secondary" onclick="closeModal()">إلغاء</button><button class="btn success" onclick="submitEditProductFull_(\'' + code + '\')">✅ حفظ كل التعديلات</button>');
}

function onEditProdMainCatChange_() {
  document.getElementById('editProdSubCat').innerHTML = subCategoryOptionsForParent_(document.getElementById('editProdMainCat').value);
  refreshSelect_('editProdSubCat');
}

function editVariantRowHtml_(v) {
  return '<div class="card" data-existing-code="' + v.code + '" style="background:var(--surface-2); padding:10px; margin-bottom:8px;">' +
    '<div class="hint" style="margin-bottom:6px;">' + (v.color || '—') + ' / ' + (v.size || '—') + ' — كود: ' + v.code + '</div>' +
    '<div class="form-grid">' +
      '<div class="field" style="margin-bottom:0;"><label>سعر الشراء</label><input type="number" class="ev-cost" value="' + v.cost + '"></div>' +
      '<div class="field" style="margin-bottom:0;"><label>الكمية</label><input type="number" class="ev-qty" value="' + v.quantity + '"></div>' +
    '</div>' +
    '<div class="field" style="margin-top:8px; margin-bottom:0;"><label>سعر بيع خاص لهذا اللون/المقاس (اختياري)</label><input type="number" class="ev-price" value="' + (v.specialPrice || '') + '"></div>' +
  '</div>';
}

function addEditVariantRow_() {
  const wrap = document.getElementById('editVariantsRows');
  const idx = editProductNewRowCount++;
  const div = document.createElement('div');
  div.id = 'editNewVarRow_' + idx;
  div.setAttribute('data-new-row', 'true');
  div.className = 'card';
  div.style.cssText = 'background:var(--surface-2); padding:10px; margin-bottom:8px;';
  div.innerHTML = '<div class="card-row"><b style="font-size:12px;">لون/مقاس جديد</b><span class="del-x" style="cursor:pointer;" onclick="removeEditVariantRow_(' + idx + ')">✕</span></div>' +
    '<div class="form-grid" style="margin-top:8px;">' +
      '<div class="field" style="margin-bottom:0;"><label>اللون</label><input type="text" class="ev-new-color" placeholder="أسود"></div>' +
      '<div class="field" style="margin-bottom:0;"><label>المقاس</label><input type="text" class="ev-new-size" placeholder="M"></div>' +
    '</div>' +
    '<div class="form-grid" style="margin-top:8px;">' +
      '<div class="field" style="margin-bottom:0;"><label>الكمية</label><input type="number" class="ev-new-qty" value="0"></div>' +
      '<div class="field" style="margin-bottom:0;"><label>سعر الشراء</label><input type="number" class="ev-new-cost" value="0"></div>' +
    '</div>';
  wrap.appendChild(div);
}

function removeEditVariantRow_(idx) {
  const row = document.getElementById('editNewVarRow_' + idx);
  if (row) row.remove();
}

async function submitEditProductFull_(code) {
  const p = invProductsCache[code];
  const name = document.getElementById('editProdName').value.trim();
  const basePrice = Number(document.getElementById('editProdPrice').value);
  const subCategory = document.getElementById('editProdSubCat').value;
  if (!name || !basePrice) { showToast_('اسم المنتج وسعر البيع مطلوبين', 'error'); return; }
  if (!subCategory) { showToast_('اختاري فئة فرعية', 'error'); return; }

  try {
    await api.updateProduct({ username: state.user.username }, { code: code, subCategory: subCategory, name: name, basePrice: basePrice });

    const simpleCostEl = document.getElementById('editSimpleCost');
    if (simpleCostEl) {
      const v = p.variants[0];
      const payload = { cost: Number(simpleCostEl.value) || 0, quantity: Number(document.getElementById('editSimpleQty').value) || 0, specialPrice: null, lowStockThreshold: v ? v.lowStockThreshold : 5 };
      if (v) await api.updateVariant({ username: state.user.username }, v.code, payload);
      else await api.addVariant({ username: state.user.username }, { productCode: code, color: '', size: '', quantity: payload.quantity, cost: payload.cost });
    } else {
      const existingRows = Array.from(document.querySelectorAll('#editVariantsRows > [data-existing-code]'));
      for (const row of existingRows) {
        const vCode = row.getAttribute('data-existing-code');
        const orig = p.variants.find(function (x) { return x.code === vCode; });
        const cost = Number(row.querySelector('.ev-cost').value) || 0;
        const qty = Number(row.querySelector('.ev-qty').value) || 0;
        const salePriceRaw = row.querySelector('.ev-price').value;
        await api.updateVariant({ username: state.user.username }, vCode, {
          cost: cost, quantity: qty, specialPrice: salePriceRaw ? Number(salePriceRaw) : null, lowStockThreshold: orig ? orig.lowStockThreshold : 5
        });
      }
      const newRows = Array.from(document.querySelectorAll('#editVariantsRows > [data-new-row]'));
      for (const row of newRows) {
        const color = row.querySelector('.ev-new-color').value.trim();
        const size = row.querySelector('.ev-new-size').value.trim();
        const qty = Number(row.querySelector('.ev-new-qty').value) || 0;
        const cost = Number(row.querySelector('.ev-new-cost').value) || 0;
        if (color || size || qty || cost) {
          await api.addVariant({ username: state.user.username }, { productCode: code, color: color, size: size, quantity: qty, cost: cost });
        }
      }
    }

    showToast_('تم حفظ كل التعديلات ✅', 'success');
    closeModal();
    await loadInventoryBaseData_();
    setContent_(buildInventoryMainHtml_());
  } catch (err) { showErrorToast_(err); }
}

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
    loadExpTreasuryOptions_();
  } catch (err) { showErrorToast_(err); }
}

async function loadExpTreasuryOptions_() {
  try {
    const accounts = await getTreasuryAccountsCached_();
    document.getElementById('expTreasuryAccount').innerHTML = treasuryAccountOptionsHtml_(accounts);
    refreshSelect_('expTreasuryAccount');
  } catch (err) { /* صامت */ }
}

function onExpPaymentMethodChange_() {
  document.getElementById('expTreasuryFieldWrap').style.display = document.getElementById('expPaymentMethod').value === 'آجل' ? 'none' : 'block';
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
        '<div class="field"><label>طريقة الدفع</label><select id="expPaymentMethod" onchange="onExpPaymentMethodChange_()"><option>كاش</option><option>فودافون كاش</option><option>بطاقة</option><option>انستاباي</option><option>آجل</option></select></div>' +
        '<div class="field"><label>التاريخ</label><input type="date" id="expDate" value="' + new Date().toISOString().slice(0, 10) + '"></div>' +
      '</div>' +
      '<div class="field" id="expTreasuryFieldWrap"><label>هتتخصم من حساب</label><select id="expTreasuryAccount"><option value="">جاري التحميل...</option></select></div>' +
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
    recurrenceDays: document.getElementById('expIsRecurring').checked ? Number(document.getElementById('expRecurrenceDays').value) : '',
    treasuryAccountId: document.getElementById('expTreasuryAccount').value || null
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
          '<div class="field"><label>طريقة الدفع</label><select id="salesPaymentMethod" onchange="onSalesPaymentMethodChange_()"><option>كاش</option><option>فودافون كاش</option><option>بطاقة</option><option>انستاباي</option><option value="آجل">آجل - فاتورة عميل</option></select></div>' +
          '<div class="field"><label>اسم العميل (اختياري)</label><input type="text" id="salesCustomerName"></div>' +
          '<div class="field"><label>تليفون العميل (اختياري)</label><input type="text" id="salesCustomerPhone"></div>' +
          '<div class="field"><label>التاريخ</label><input type="datetime-local" id="salesDate"></div>' +
        '</div>' +
        '<div class="field" id="salesTreasuryFieldWrap"><label>هتضاف لحساب</label><select id="salesTreasuryAccount"><option value="">جاري التحميل...</option></select></div>' +
        '<div id="salesInvoiceSection" style="display:none;"></div>' +
        '<button class="btn success block" style="margin-top:16px;" onclick="submitSale_()">✅ تسجيل البيعة</button></div>' +
      '<div class="card"><div class="card-heading">📋 آخر المبيعات</div><div id="salesHistoryList" style="margin-top:14px;"></div></div></div>'
  );
  salesCart = [];
  document.getElementById('salesDate').value = new Date().toISOString().slice(0, 16);
  loadSalesHistory_();
  loadSalesTreasuryOptions_();
}

async function loadSalesTreasuryOptions_() {
  try {
    const accounts = await getTreasuryAccountsCached_();
    document.getElementById('salesTreasuryAccount').innerHTML = treasuryAccountOptionsHtml_(accounts);
    refreshSelect_('salesTreasuryAccount');
  } catch (err) { /* صامت */ }
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
  const paymentMethod = document.getElementById('salesPaymentMethod').value;
  const discount = Number(document.getElementById('salesDiscount').value) || 0;

  if (paymentMethod === 'آجل') { await submitSaleOnInvoice_(discount); return; }

  const payload = {
    source: 'محل', items: salesCart.map(function (i) { return { variantCode: i.variantCode, qty: i.qty, price: i.price }; }),
    discount: discount, paymentMethod: paymentMethod,
    customerName: document.getElementById('salesCustomerName').value, customerPhone: document.getElementById('salesCustomerPhone').value,
    date: document.getElementById('salesDate').value, treasuryAccountId: document.getElementById('salesTreasuryAccount').value || null
  };
  try {
    const res = await api.recordSale({ username: state.user.username }, payload);
    showToast_('تمت البيعة ✅ الإجمالي: ' + res.total, 'success'); renderSalesPage();
  } catch (err) { showErrorToast_(err); }
}

// ------------------------------------------------------------
// البيع "آجل" من شاشة المبيعات اليدوي — فتح فاتورة جديدة بنفس
// بيانات العميل المكتوبة فوق، أو الإضافة على فاتورة مفتوحة
// ------------------------------------------------------------
function onSalesPaymentMethodChange_() {
  const val = document.getElementById('salesPaymentMethod').value;
  const section = document.getElementById('salesInvoiceSection');
  document.getElementById('salesTreasuryFieldWrap').style.display = val === 'آجل' ? 'none' : 'block';
  if (val === 'آجل') {
    section.style.display = 'block';
    section.innerHTML =
      '<div class="section-title" style="margin-top:6px;">فاتورة العميل</div>' +
      '<div class="field"><select id="salesInvoiceMode" onchange="onSalesInvoiceModeChange_()">' +
      '<option value="new">فتح فاتورة جديدة بنفس بيانات العميل فوق</option><option value="existing">إضافة على فاتورة مفتوحة</option></select></div>' +
      '<div id="salesInvoiceModeFields"></div>';
    onSalesInvoiceModeChange_();
    enhanceSelects_(section);
  } else { section.style.display = 'none'; section.innerHTML = ''; }
}

function onSalesInvoiceModeChange_() {
  const mode = document.getElementById('salesInvoiceMode').value;
  const el = document.getElementById('salesInvoiceModeFields');
  if (mode === 'existing') {
    el.innerHTML = '<div class="field"><label>ابحثي عن الفاتورة (اسم العميل)</label><input type="text" id="salesInvSearchInput" oninput="salesInvoiceSearch_(this.value)"></div>' +
      '<div id="salesInvSearchResults"></div><input type="hidden" id="salesSelectedInvoiceId">';
  } else { el.innerHTML = ''; }
}

async function salesInvoiceSearch_(query) {
  if (!query || query.length < 2) { document.getElementById('salesInvSearchResults').innerHTML = ''; return; }
  try {
    const invoices = await api.listInvoices({});
    const matched = invoices.filter(function (i) { return i.status !== 'مدفوعة بالكامل' && i.customerName.toLowerCase().includes(query.toLowerCase()); });
    document.getElementById('salesInvSearchResults').innerHTML = matched.length === 0 ? emptyRow_('🔎', 'لا يوجد فواتير مفتوحة بهذا الاسم') :
      matched.map(function (i) {
        return '<div class="list-item" style="cursor:pointer;" onclick="selectSalesInvoice_(\'' + i.invoiceId + '\', \'' + i.customerName.replace(/'/g, '') + '\')"><span>' + i.customerName + ' — ' + i.invoiceNumber + '</span><span class="pill warning">متبقي ' + i.remaining + '</span></div>';
      }).join('');
  } catch (err) { showErrorToast_(err); }
}

function selectSalesInvoice_(id, name) {
  document.getElementById('salesSelectedInvoiceId').value = id;
  document.getElementById('salesInvSearchResults').innerHTML = '<div class="hint">✅ هيتضاف على فاتورة: ' + name + '</div>';
}

async function submitSaleOnInvoice_(discount) {
  const mode = document.getElementById('salesInvoiceMode').value;
  const subtotal = salesCart.reduce(function (s, i) { return s + i.price * i.qty; }, 0);
  const ratio = discount > 0 && subtotal > 0 ? Math.max(0, (subtotal - discount) / subtotal) : 1;
  const items = salesCart.map(function (i) { return { variantCode: i.variantCode, qty: i.qty, price: Math.round(i.price * ratio * 100) / 100 }; });

  try {
    let invoiceId;
    if (mode === 'new') {
      const name = document.getElementById('salesCustomerName').value.trim();
      const phone = document.getElementById('salesCustomerPhone').value.trim();
      if (!name) { showToast_('اسم العميل مطلوب لفتح فاتورة جديدة', 'error'); return; }
      const opened = await api.openInvoice({ username: state.user.username }, { customerName: name, customerPhone: phone });
      invoiceId = opened.invoiceId;
    } else {
      invoiceId = document.getElementById('salesSelectedInvoiceId').value;
      if (!invoiceId) { showToast_('اختاري فاتورة الأول', 'error'); return; }
    }
    await api.addItemsToInvoice({ username: state.user.username }, invoiceId, items);
    showToast_('تم تسجيل الأصناف على الفاتورة ✅', 'success');
    renderSalesPage();
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

async function quickReturnSale_(saleId) {
  try {
    const sales = await api.listSales({ limit: 200 });
    const sale = sales.find(function (s) { return s.saleId === saleId; });
    if (!sale) { showToast_('البيعة مش موجودة', 'error'); return; }
    openReturnModal_(saleId, sale.items, loadSalesHistory_);
  } catch (err) { showErrorToast_(err); }
}

// ============================================================
// شاشة الموردين والمشتريات
// ============================================================
let poCart = [];
let supplierPageTab = 'neworder';
let suppliersCache_ = null;

async function renderSuppliersPage() {
  supplierPageTab = 'neworder';
  poCart = [];
  suppliersCache_ = null;
  renderSupplierPageShell_();
}

function renderSupplierPageShell_() {
  setContent_(
    '<div class="subtabs">' +
      '<div class="subtab' + (supplierPageTab === 'neworder' ? ' active' : '') + '" onclick="switchSupplierPageTab_(\'neworder\')">🛒 أوردر شراء جديد</div>' +
      '<div class="subtab' + (supplierPageTab === 'suppliers' ? ' active' : '') + '" onclick="switchSupplierPageTab_(\'suppliers\')">🏭 الموردين</div>' +
      '<div class="subtab' + (supplierPageTab === 'orders' ? ' active' : '') + '" onclick="switchSupplierPageTab_(\'orders\')">🧾 الأوردرات السابقة</div>' +
    '</div><div id="supplierTabContent"></div>'
  );
  renderSupplierTabContent_();
}

function switchSupplierPageTab_(tab) { supplierPageTab = tab; poCart = []; renderSupplierPageShell_(); }

async function getSuppliersCached_() {
  if (!suppliersCache_) suppliersCache_ = await api.getSuppliers();
  return suppliersCache_;
}

async function renderSupplierTabContent_() {
  const el = document.getElementById('supplierTabContent');

  if (supplierPageTab === 'neworder') {
    let suppliers = [];
    try { suppliers = await getSuppliersCached_(); }
    catch (err) { showErrorToast_(err); }

    const supplierStepHtml = suppliers.length === 0
      ? '<div class="hint" style="color:var(--danger);">لسه مفيش موردين مسجلين</div>' +
        '<button class="btn success block" style="margin-top:8px;" onclick="openQuickAddSupplierModal_()">➕ إضافة مورد الأول</button>'
      : '<div class="field" style="margin-top:8px;"><select id="poSupplierSelect">' + suppliers.map(function (s) { return '<option>' + s.name + '</option>'; }).join('') + '</select></div>';

    el.innerHTML =
      '<div class="card"><div class="card-heading">1️⃣ اختاري المورد</div>' + supplierStepHtml + '</div>' +
      '<div class="card" style="margin-top:14px;"><div class="card-heading">2️⃣ ضيفي الأصناف</div>' +
        '<div class="field" style="margin-top:8px;"><input type="text" id="poSearchInput" oninput="poSearch_(this.value)" placeholder="🔍 دوري باسم المنتج، أو اسيبيها فاضية تشوفي كل المنتجات..."></div>' +
        '<div id="poSearchResults"></div></div>' +
      '<div class="card" style="margin-top:14px;"><div class="card-heading">3️⃣ السلة</div><div id="poCartList" style="margin-top:8px;"></div></div>' +
      '<div class="card" style="margin-top:14px;"><div class="card-heading">4️⃣ الدفع</div>' +
        '<div class="form-grid" style="margin-top:8px;">' +
          '<div class="field"><label>حالة الدفع</label><select id="poPaymentStatus" onchange="onPoPaymentStatusChange_()"><option>مدفوع بالكامل</option><option>مدفوع جزئيًا</option><option>متأخر/غير مدفوع</option></select></div>' +
          '<div class="field" id="poAmountPaidWrap" style="display:none;"><label>المبلغ المدفوع دلوقتي</label><input type="number" id="poAmountPaid" value="0"></div>' +
        '</div>' +
        '<div class="field" id="poTreasuryWrap"><label>هيتخصم من حساب</label><select id="poTreasuryAccount"><option value="">جاري التحميل...</option></select></div>' +
      '</div>' +
      '<button class="btn success block" style="margin-top:16px; font-size:15px; padding:16px;" onclick="submitPurchaseOrder_()">✅ تسجيل أوردر الشراء</button>';

    renderPoCart_();
    poSearch_('');
    getTreasuryAccountsCached_().then(function (accounts) {
      document.getElementById('poTreasuryAccount').innerHTML = treasuryAccountOptionsHtml_(accounts);
      refreshSelect_('poTreasuryAccount');
    }).catch(function (err) { showErrorToast_(err); });

  } else if (supplierPageTab === 'suppliers') {
    el.innerHTML =
      '<div class="card"><div class="card-heading">🏭 مورد جديد</div>' +
        '<div class="form-grid" style="margin-top:6px;">' +
          '<div class="field"><label>اسم المورد <span class="req">*</span></label><input type="text" id="supName"></div>' +
          '<div class="field"><label>رقم التواصل</label><input type="text" id="supContact"></div>' +
        '</div><button class="btn success block" style="margin-top:14px;" onclick="submitSupplier_(event)">➕ إضافة مورد</button></div>' +
      '<div class="card" style="margin-top:14px;"><div class="card-heading">📇 الموردون</div><div id="suppliersList" style="margin-top:10px;"></div></div>';
    loadSuppliersListUI_();

  } else {
    el.innerHTML = '<div class="card"><div class="card-heading">🧾 أوردرات الشراء</div><div id="poList" style="margin-top:10px;"></div></div>';
    loadPurchaseOrders_();
  }

  enhanceSelects_(el);
}

function onPoPaymentStatusChange_() {
  const status = document.getElementById('poPaymentStatus').value;
  document.getElementById('poAmountPaidWrap').style.display = status === 'مدفوع جزئيًا' ? '' : 'none';
  document.getElementById('poTreasuryWrap').style.display = status === 'متأخر/غير مدفوع' ? 'none' : '';
}

function openQuickAddSupplierModal_() {
  openModal('➕ مورد جديد بسرعة', '',
    '<div class="field"><label>اسم المورد</label><input type="text" id="quickSupName"></div>' +
    '<div class="field" style="margin-top:10px;"><label>رقم التواصل</label><input type="text" id="quickSupContact"></div>',
    '<button class="btn secondary" onclick="closeModal()">إلغاء</button><button class="btn success" onclick="submitQuickAddSupplier_()">إضافة</button>');
}

async function submitQuickAddSupplier_() {
  const name = document.getElementById('quickSupName').value.trim();
  if (!name) { showToast_('اسم المورد مطلوب', 'error'); return; }
  try {
    await api.addSupplier({ username: state.user.username }, { name: name, contact: document.getElementById('quickSupContact').value });
    suppliersCache_ = null;
    closeModal();
    showToast_('تم إضافة المورد ✅', 'success');
    await renderSupplierTabContent_();
    const select = document.getElementById('poSupplierSelect');
    if (select) select.value = name;
  } catch (err) { showErrorToast_(err); }
}

async function submitSupplier_(evt) {
  const name = document.getElementById('supName').value;
  if (!name) { showToast_('اسم المورد مطلوب', 'error'); return; }
  const btn = evt.target; btn.disabled = true;
  try {
    await api.addSupplier({ username: state.user.username }, { name: name, contact: document.getElementById('supContact').value });
    suppliersCache_ = null;
    showToast_('تم إضافة المورد ✅', 'success');
    renderSupplierTabContent_();
  } catch (err) { btn.disabled = false; showErrorToast_(err); }
}

async function loadSuppliersListUI_() {
  try {
    const suppliers = await getSuppliersCached_();
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
  try {
    const results = await api.searchProducts(query, query ? 30 : 60);
    let html = results.map(function (p) {
      return p.variants.map(function (v) {
        const label = (p.name + ' — ' + v.color + ' ' + v.size).replace(/'/g, '');
        const salePrice = v.specialPrice != null ? v.specialPrice : p.basePrice;
        return '<div class="product-tile" onclick="addToPoCart_(\'' + v.code + '\', \'' + label + '\', ' + v.cost + ', ' + salePrice + ')">' +
          '<div class="product-thumb">👕</div><div class="product-tile-info"><div class="product-tile-name">' + p.name + '</div>' +
          '<div class="product-tile-meta">' + v.color + ' · ' + v.size + '</div></div>' +
          '<b style="text-align:left; line-height:1.6;">شراء: ' + v.cost + '<br>بيع: ' + salePrice + '</b></div>';
      }).join('');
    }).join('');

    if (results.length === 0) {
      if (query) {
        const safeQuery = query.replace(/'/g, "\\'");
        html = '<div class="callout-notfound" id="poNotFoundPrompt">' +
          '⚠️ المنتج "' + query + '" غير موجود في المخزون — ' +
          '<span style="color:var(--accent); font-weight:800; cursor:pointer; text-decoration:underline;" onclick="openPoQuickAddForm_(\'' + safeQuery + '\')">تريدين إضافته؟</span>' +
          '</div><div id="poQuickAddInline"></div>';
      } else {
        html = emptyRow_('📦', 'لا يوجد منتجات في المخزون بعد — دوري باسم منتج جديد وهقولك تضيفيه ازاي');
      }
    }
    document.getElementById('poSearchResults').innerHTML = html;
  } catch (err) { showErrorToast_(err); }
}

// ------------------------------------------------------------
// إضافة منتج جديد Inline من داخل شاشة أمر الشراء (بدون مغادرتها)
// بتسمح باختيار الفئة الرئيسية/الفرعية الحقيقية + الكمية المشتراة
// ------------------------------------------------------------
let poTreeCache = null;

async function openPoQuickAddForm_(prefillName) {
  try {
    poTreeCache = await api.getProductTree();
  } catch (err) { showErrorToast_(err); return; }
  if (!poTreeCache.mainCategories.length) {
    document.getElementById('poQuickAddInline').innerHTML = '<div class="hint" style="color:var(--danger);">لازم تضيفي فئة رئيسية وفرعية الأول من صفحة المخزون</div>';
    return;
  }
  renderPoQuickAddForm_(prefillName);
}

function renderPoQuickAddForm_(prefillName) {
  const mainOpts = poTreeCache.mainCategories.map(function (m) { return '<option value="' + m.code + '">' + m.name + '</option>'; }).join('');
  document.getElementById('poQuickAddInline').innerHTML =
    '<div class="card" style="background:var(--surface-2); margin-top:10px; padding:14px;">' +
      '<div class="inline-add-row"><div class="field"><label>الفئة الرئيسية</label>' +
      '<select id="poQuickMainCat" onchange="onPoQuickMainCatChange_()">' + mainOpts + '</select></div>' +
      '<button class="inline-add-btn" onclick="openPoQuickAddCategoryPrompt_(false)">+ فئة</button></div>' +
      '<div class="inline-add-row" style="margin-top:10px;"><div class="field"><label>الفئة الفرعية</label>' +
      '<select id="poQuickSubCat">' + poSubCategoryOptions_(poTreeCache.mainCategories[0].code) + '</select></div>' +
      '<button class="inline-add-btn" onclick="openPoQuickAddCategoryPrompt_(true)">+ فئة فرعية</button></div>' +
      '<div class="form-grid" style="margin-top:12px;">' +
        '<div class="field"><label>اسم المنتج</label><input type="text" id="poQuickName" value="' + (prefillName || '').replace(/"/g, '') + '"></div>' +
        '<div class="field"><label>سعر الشراء (التكلفة)</label><input type="number" id="poQuickPrice" placeholder="0"></div>' +
      '</div>' +
      '<div class="form-grid">' +
        '<div class="field"><label>سعر البيع</label><input type="number" id="poQuickSalePrice" placeholder="0"></div>' +
        '<div class="field"><label>الكمية المشتراة</label><input type="number" id="poQuickQty" value="1"></div>' +
      '</div>' +
      '<div class="field"><label>الكود (اختياري)</label><input type="text" id="poQuickCode" placeholder="تلقائي"></div>' +
      '<button class="btn success block" style="margin-top:10px;" onclick="submitPoQuickAdd_()">✅ إضافة المنتج للمخزون وللأوردر</button>' +
    '</div>';
  enhanceSelects_(document.getElementById('poQuickAddInline'));
}

function poSubCategoryOptions_(parentCode) {
  const subs = poTreeCache.subCategories.filter(function (s) { return s.parent === parentCode; });
  if (!subs.length) return '<option value="">لا يوجد فئات فرعية — أضيفي واحدة</option>';
  return subs.map(function (s) { return '<option value="' + s.code + '">' + s.name + '</option>'; }).join('');
}

function onPoQuickMainCatChange_() {
  document.getElementById('poQuickSubCat').innerHTML = poSubCategoryOptions_(document.getElementById('poQuickMainCat').value);
  refreshSelect_('poQuickSubCat');
}

function openPoQuickAddCategoryPrompt_(isSub) {
  const parentCode = isSub ? document.getElementById('poQuickMainCat').value : '';
  openModal(isSub ? 'فئة فرعية جديدة' : 'فئة رئيسية جديدة', '',
    '<div class="field"><label>الاسم</label><input type="text" id="poQuickNewCatName"></div>',
    '<button class="btn secondary" onclick="submitPoQuickAddCategoryCancel_()">إلغاء</button><button class="btn success" onclick="submitPoQuickAddCategory_(' + isSub + ', \'' + parentCode + '\')">إضافة</button>');
}

function submitPoQuickAddCategoryCancel_() {
  closeModal();
  renderPoQuickAddForm_(document.getElementById('poQuickName') ? document.getElementById('poQuickName').value : '');
}

async function submitPoQuickAddCategory_(isSub, parentCode) {
  const name = document.getElementById('poQuickNewCatName').value.trim();
  if (!name) { showToast_('اكتب اسم الفئة', 'error'); return; }
  try {
    await api.createCategory({ username: state.user.username }, { name: name, type: isSub ? 'فرعية' : 'رئيسية', parentCode: isSub ? parentCode : null });
    poTreeCache = await api.getProductTree();
    const prevName = document.getElementById('poQuickName') ? document.getElementById('poQuickName').value : '';
    closeModal();
    renderPoQuickAddForm_(prevName);
    showToast_('تمت إضافة الفئة ✅', 'success');
  } catch (err) { showErrorToast_(err); }
}

async function submitPoQuickAdd_() {
  const name = document.getElementById('poQuickName').value.trim();
  const price = Number(document.getElementById('poQuickPrice').value);
  const salePrice = Number(document.getElementById('poQuickSalePrice').value) || price;
  const qty = Number(document.getElementById('poQuickQty').value) || 1;
  const manualCode = document.getElementById('poQuickCode').value.trim();
  const subCategory = document.getElementById('poQuickSubCat').value;
  if (!subCategory) { showToast_('اختاري فئة فرعية', 'error'); return; }
  if (!name || !price) { showToast_('الاسم وسعر الشراء مطلوبين', 'error'); return; }

  try {
    const res = await api.addProductWithVariants({ username: state.user.username }, {
      name: name, subCategory: subCategory, basePrice: salePrice,
      variants: [{ color: '', size: '', quantity: 0, cost: price, specialPrice: salePrice }], manualCode: manualCode || null
    });
    showToast_('تمت إضافة "' + name + '" للمخزون ✅', 'success');
    addToPoCart_(res.variantCodes[0], name, price, salePrice, qty);
    document.getElementById('poSearchInput').value = '';
    poSearch_('');
  } catch (err) { showErrorToast_(err); }
}

function addToPoCart_(variantCode, label, cost, salePrice, qty) {
  const existing = poCart.find(function (i) { return i.variantCode === variantCode; });
  if (existing) existing.qty += (qty || 1);
  else poCart.push({ variantCode: variantCode, label: label, price: cost, salePrice: salePrice || 0, qty: qty || 1 });
  renderPoCart_();
}

function renderPoCart_() {
  const el = document.getElementById('poCartList');
  if (poCart.length === 0) { el.innerHTML = emptyRow_('📦', 'لسه محددتش أصناف'); return; }
  let total = 0;
  el.innerHTML = poCart.map(function (i, idx) {
    total += i.price * i.qty;
    return '<div class="list-item" style="display:block; padding:12px 4px;"><div class="card-row"><b>' + i.label + '</b>' +
      '<span class="del-x" onclick="removeFromPoCart_(' + idx + ')" style="cursor:pointer;">✕</span></div>' +
      '<div style="display:flex; gap:8px; flex-wrap:wrap; margin-top:8px; font-size:12.5px;">' +
      '<span>شراء <input type="number" value="' + i.price + '" style="width:65px; padding:5px;" onchange="updatePoItemPrice_(' + idx + ', this.value)"></span>' +
      '<span>بيع <input type="number" value="' + i.salePrice + '" style="width:65px; padding:5px;" onchange="updatePoItemSalePrice_(' + idx + ', this.value)"></span>' +
      '<span>كمية <input type="number" value="' + i.qty + '" style="width:50px; padding:5px;" onchange="updatePoItemQty_(' + idx + ', this.value)"></span>' +
      '</div></div>';
  }).join('') + '<div class="list-item" style="font-weight:900;"><b>الإجمالي (شراء)</b><b>' + total + '</b></div>';
}
function updatePoItemPrice_(idx, val) { poCart[idx].price = Number(val); renderPoCart_(); }
function updatePoItemSalePrice_(idx, val) { poCart[idx].salePrice = Number(val); renderPoCart_(); }
function updatePoItemQty_(idx, val) { poCart[idx].qty = Number(val); renderPoCart_(); }
function removeFromPoCart_(idx) { poCart.splice(idx, 1); renderPoCart_(); }

async function submitPurchaseOrder_() {
  if (poCart.length === 0) { showToast_('لازم تضيف صنف واحد على الأقل', 'error'); return; }
  const supplierEl = document.getElementById('poSupplierSelect');
  if (!supplierEl || !supplierEl.value) { showToast_('لازم تضيفي مورد وتختاريه الأول', 'error'); return; }
  const payload = {
    supplierName: supplierEl.value,
    items: poCart.map(function (i) { return { variantCode: i.variantCode, qty: i.qty, price: i.price }; }),
    paymentStatus: document.getElementById('poPaymentStatus').value, amountPaid: Number(document.getElementById('poAmountPaid').value) || 0,
    treasuryAccountId: document.getElementById('poTreasuryAccount').value || null
  };
  try {
    const res = await api.createPurchaseOrder({ username: state.user.username }, payload);
    await Promise.all(poCart.map(function (i) {
      return i.salePrice > 0 ? api.setVariantSalePrice({ username: state.user.username }, i.variantCode, i.salePrice).catch(function () { /* صامت */ }) : null;
    }));
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
          (o.remaining > 0 ? ' <button class="eye-btn" onclick="openPaySupplierModal_(\'' + o.orderId + '\', ' + o.remaining + ')">💳</button>' : '') +
          ' <button class="eye-btn" onclick="openAttachmentsModal_(\'purchase_order\', \'' + o.orderId + '\', \'' + o.supplierName + '\')">📎</button></span></div>';
      }).join('');
  } catch (err) { showErrorToast_(err); }
}

async function openPaySupplierModal_(orderId, remaining) {
  const accounts = await getTreasuryAccountsCached_().catch(function () { return []; });
  openModal('دفع دفعة للمورد', 'المتبقي: ' + remaining,
    '<div class="field"><label>المبلغ المدفوع</label><input type="number" id="modalSupplierPayAmount" value="' + remaining + '"></div>' +
    '<div class="field"><label>هيتخصم من حساب</label><select id="modalSupplierTreasuryAccount">' + treasuryAccountOptionsHtml_(accounts) + '</select></div>',
    '<button class="btn secondary" onclick="closeModal()">إلغاء</button><button class="btn" onclick="confirmPaySupplier_(\'' + orderId + '\')">تأكيد الدفع</button>');
}

async function confirmPaySupplier_(orderId) {
  const amount = Number(document.getElementById('modalSupplierPayAmount').value);
  const treasuryAccountId = document.getElementById('modalSupplierTreasuryAccount').value || null;
  if (!amount) { showToast_('اكتب مبلغ صحيح', 'error'); return; }
  try {
    await api.paySupplierInstallment({ username: state.user.username }, orderId, amount, treasuryAccountId);
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
      '<div class="card"><div class="card-heading">📂 فتح فاتورة جديدة لعميل</div>' +
        '<div class="hint">افتحي حساب مفتوح للعميل، وبعدين ضيفي عليه أي منتجات ياخدها — دلوقتي أو بعد كذا ساعة، من غير ما تفتحي فاتورة جديدة كل مرة</div>' +
        '<div class="form-grid" style="margin-top:10px;">' +
          '<div class="field"><label>اسم العميل <span class="req">*</span></label><input type="text" id="invOpenCustomerName"></div>' +
          '<div class="field"><label>رقم التليفون (اختياري)</label><input type="text" id="invOpenCustomerPhone"></div>' +
        '</div>' +
        '<button class="btn success block" style="margin-top:12px;" onclick="submitOpenInvoice_()">📂 فتح الفاتورة</button>' +
        '<div class="section-title" style="margin-top:20px;">فاتورة سريعة بإجمالي يدوي</div>' +
        '<div class="hint">من غير ربط بمنتجات معينة — لفاتورة تحصيل أونلاين مثلاً</div>' +
        '<div class="form-grid" style="margin-top:8px;">' +
          '<div class="field"><label>اسم العميل</label><input type="text" id="invCustomerName"></div>' +
          '<div class="field"><label>الإجمالي</label><input type="number" id="invTotal"></div>' +
          '<div class="field"><label>المدفوع</label><input type="number" id="invPaid" value="0"></div>' +
          '<div class="field"><label>تم التحصيل COD؟</label><select id="invIsCOD"><option value="false">لا</option><option value="true">نعم</option></select></div>' +
        '</div><button class="btn secondary block" style="margin-top:10px;" onclick="submitInvoice_()">➕ إنشاء فاتورة سريعة</button></div>' +
      '<div class="card"><div class="card-heading">📋 الفواتير</div>' +
        '<div class="field"><select id="invStatusFilter" onchange="loadInvoices_()"><option value="">كل الحالات</option>' +
        '<option>مفتوحة</option><option>مدفوعة بالكامل</option><option>مدفوعة جزئيًا</option><option>متأخرة</option><option>تم التحصيل COD</option></select></div>' +
        '<div id="invoicesList" style="margin-top:12px;"></div></div></div>'
  );
  loadInvoices_();
}

async function submitOpenInvoice_() {
  const name = document.getElementById('invOpenCustomerName').value.trim();
  const phone = document.getElementById('invOpenCustomerPhone').value.trim();
  if (!name) { showToast_('اسم العميل مطلوب', 'error'); return; }
  try {
    const res = await api.openInvoice({ username: state.user.username }, { customerName: name, customerPhone: phone });
    showToast_('تم فتح الفاتورة ✅ ' + res.invoiceNumber, 'success');
    document.getElementById('invOpenCustomerName').value = '';
    document.getElementById('invOpenCustomerPhone').value = '';
    loadInvoices_();
    openInvoiceDetailModal_(res.invoiceId);
  } catch (err) { showErrorToast_(err); }
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
      const pill = inv.status === 'مدفوعة بالكامل' ? 'success' : (inv.status === 'متأخرة' ? 'danger' : (inv.status === 'مفتوحة' ? 'info' : 'warning'));
      return '<tr style="cursor:pointer;" onclick="openInvoiceDetailModal_(\'' + inv.invoiceId + '\')">' +
        '<td>' + inv.customerName + '</td><td class="money-positive">' + formatMoney_(inv.total, cur) + '</td>' +
        '<td class="' + (inv.remaining > 0 ? 'money-negative' : '') + '">' + formatMoney_(inv.remaining, cur) + '</td>' +
        '<td><span class="pill ' + pill + '">' + inv.status + '</span></td>' +
        '<td onclick="event.stopPropagation();">' + (inv.remaining > 0 ? '<button class="btn sm info-btn" onclick="openPayInvoiceModal_(\'' + inv.invoiceId + '\', ' + inv.remaining + ')">💳 تحصيل</button>' : '') +
        ' <button class="btn sm secondary" onclick="openAttachmentsModal_(\'invoice\', \'' + inv.invoiceId + '\', \'' + inv.invoiceNumber + '\')">📎</button></td></tr>';
    }).join('');
    html += '</tbody></table></div>';
    el.innerHTML = html;
  } catch (err) { showErrorToast_(err); }
}

// ------------------------------------------------------------
// مودال: تفاصيل فاتورة (الأصناف اللي اتضافت + إضافة أصناف جديدة)
// ------------------------------------------------------------
let invDetailCache = null;
let invAddItemsCart = [];

async function openInvoiceDetailModal_(invoiceId) {
  try {
    invDetailCache = await api.getInvoiceDetails(invoiceId);
    invAddItemsCart = [];
    openModal('📄 فاتورة ' + invDetailCache.invoice.invoice_number, invDetailCache.invoice.customer_name, buildInvoiceDetailHtml_(), buildInvoiceDetailActions_(), true);
  } catch (err) { showErrorToast_(err); }
}

function buildInvoiceDetailActions_() {
  const inv = invDetailCache.invoice;
  return '<button class="btn secondary" onclick="closeModal(); loadInvoices_();">إغلاق</button>' +
    (inv.remaining > 0 ? '<button class="btn info-btn" onclick="openPayInvoiceModal_(\'' + inv.id + '\', ' + inv.remaining + ')">💳 تحصيل</button>' : '');
}

function buildInvoiceDetailHtml_() {
  const inv = invDetailCache.invoice;
  const items = invDetailCache.items;
  const cur = state.settings.currency || 'جنيه';
  let html = '<div class="grid grid-3">' +
    statCard_('💰', 'الإجمالي', formatMoney_(inv.total, cur), '', false) +
    statCard_('✅', 'المدفوع', formatMoney_(inv.paid, cur), '', false) +
    '<div class="card stat-card"><div class="stat-icon">⚖️</div><div class="card-label">المتبقي</div>' +
      '<div class="card-value ' + (inv.remaining > 0 ? 'money-negative' : 'money-positive') + '">' + formatMoney_(inv.remaining, cur) + '</div></div>' +
  '</div>';

  html += '<div class="section-title" style="margin-top:16px;">الأصناف المضافة على الفاتورة</div>';
  html += '<div class="table-wrap"><table><thead><tr><th>المنتج</th><th>الكمية</th><th>السعر</th><th>الإجمالي</th><th>وقت الإضافة</th></tr></thead><tbody>';
  html += items.length === 0 ? '<tr><td colspan="5">' + emptyRow_('📦', 'لسه مفيش أصناف مضافة') + '</td></tr>' :
    items.map(function (it) {
      return '<tr><td>' + it.productName + (it.color || it.size ? ' (' + (it.color || '—') + '/' + (it.size || '—') + ')' : '') + '</td>' +
        '<td>' + it.qty + '</td><td>' + it.unitPrice + '</td><td><b>' + it.lineTotal + '</b></td><td>' + formatDate_(it.addedAt) + '</td></tr>';
    }).join('');
  html += '</tbody></table></div>';

  html += '<div class="section-title" style="margin-top:18px;">➕ إضافة أصناف جديدة للفاتورة</div>';
  html += '<div class="field"><input type="text" id="invAddSearchInput" oninput="invAddSearch_(this.value)" placeholder="دوري على منتج تضيفيه..."></div>';
  html += '<div id="invAddSearchResults"></div><div id="invAddCartList" style="margin-top:10px;"></div>';
  html += '<button class="btn success block" style="margin-top:10px;" onclick="submitAddItemsToInvoice_(\'' + inv.id + '\')">✅ حفظ الأصناف على الفاتورة</button>';
  return html;
}

async function invAddSearch_(query) {
  if (!query || query.length < 2) { document.getElementById('invAddSearchResults').innerHTML = ''; return; }
  try {
    const results = await api.searchProducts(query);
    let html = results.map(function (p) {
      return p.variants.map(function (v) {
        const label = (p.name + ' — ' + v.color + ' ' + v.size).replace(/'/g, '');
        const price = v.specialPrice || p.basePrice;
        return '<div class="product-tile" onclick="addToInvoiceCart_(\'' + v.code + '\', \'' + label + '\', ' + price + ')">' +
          '<div class="product-thumb">👕</div><div class="product-tile-info"><div class="product-tile-name">' + p.name + '</div>' +
          '<div class="product-tile-meta">' + v.color + ' · ' + v.size + ' · متاح: ' + v.quantity + '</div></div><b>' + price + '</b></div>';
      }).join('');
    }).join('');
    document.getElementById('invAddSearchResults').innerHTML = html || '<div class="hint">مفيش نتايج</div>';
  } catch (err) { showErrorToast_(err); }
}

function addToInvoiceCart_(variantCode, label, price) {
  const existing = invAddItemsCart.find(function (i) { return i.variantCode === variantCode; });
  if (existing) existing.qty += 1; else invAddItemsCart.push({ variantCode: variantCode, label: label, price: price, qty: 1 });
  renderInvoiceAddCart_();
}

function renderInvoiceAddCart_() {
  const el = document.getElementById('invAddCartList');
  if (!el) return;
  if (invAddItemsCart.length === 0) { el.innerHTML = ''; return; }
  let total = 0;
  el.innerHTML = invAddItemsCart.map(function (i, idx) {
    total += i.price * i.qty;
    return '<div class="list-item"><span>' + i.label + '</span><span>سعر <input type="number" value="' + i.price + '" style="width:65px; padding:5px;" onchange="updateInvoiceCartPrice_(' + idx + ', this.value)"> ' +
      'كمية <input type="number" value="' + i.qty + '" style="width:50px; padding:5px;" onchange="updateInvoiceCartQty_(' + idx + ', this.value)"> ' +
      '<span class="del-x" onclick="removeFromInvoiceCart_(' + idx + ')" style="cursor:pointer;">✕</span></span></div>';
  }).join('') + '<div class="list-item"><b>إجمالي المضاف</b><b>' + total + '</b></div>';
}
function updateInvoiceCartPrice_(idx, val) { invAddItemsCart[idx].price = Number(val); renderInvoiceAddCart_(); }
function updateInvoiceCartQty_(idx, val) { invAddItemsCart[idx].qty = Number(val); renderInvoiceAddCart_(); }
function removeFromInvoiceCart_(idx) { invAddItemsCart.splice(idx, 1); renderInvoiceAddCart_(); }

async function submitAddItemsToInvoice_(invoiceId) {
  if (invAddItemsCart.length === 0) { showToast_('ضيفي صنف واحد على الأقل', 'error'); return; }
  try {
    await api.addItemsToInvoice({ username: state.user.username }, invoiceId, invAddItemsCart);
    showToast_('تم إضافة الأصناف للفاتورة ✅', 'success');
    invAddItemsCart = [];
    openInvoiceDetailModal_(invoiceId);
  } catch (err) { showErrorToast_(err); }
}

async function openPayInvoiceModal_(invoiceId, remaining) {
  const accounts = await getTreasuryAccountsCached_().catch(function () { return []; });
  openModal('تحصيل فاتورة', 'المتبقي حاليًا: ' + remaining,
    '<div class="field"><label>المبلغ المحصّل</label><input type="number" id="modalPayAmount" value="' + remaining + '"></div>' +
    '<div class="field"><label>هيضاف لحساب</label><select id="modalPayTreasuryAccount">' + treasuryAccountOptionsHtml_(accounts) + '</select></div>',
    '<button class="btn secondary" onclick="closeModal()">إلغاء</button><button class="btn success" onclick="confirmPayInvoice_(\'' + invoiceId + '\')">تأكيد التحصيل</button>');
}

async function confirmPayInvoice_(invoiceId) {
  const amount = Number(document.getElementById('modalPayAmount').value);
  const treasuryAccountId = document.getElementById('modalPayTreasuryAccount').value || null;
  if (!amount) { showToast_('اكتب مبلغ صحيح', 'error'); return; }
  try {
    await api.payInvoiceInstallment({ username: state.user.username }, invoiceId, amount, treasuryAccountId);
    showToast_('تم تسجيل التحصيل ✅', 'success');
    if (invDetailCache && invDetailCache.invoice.id === invoiceId) { openInvoiceDetailModal_(invoiceId); }
    else { closeModal(); loadInvoices_(); }
  } catch (err) { showErrorToast_(err); }
}

// ============================================================
// رأس المال والشركاء + العهدة
// ============================================================
async function renderCapitalPage() {
  try {
    const summary = await api.getCapitalSummary();
    const treasuryAccounts = await api.listTreasuryAccounts();
    const cur = state.settings.currency || 'جنيه';
    let html = '<div class="grid grid-2">';
    html += '<div class="card"><div class="card-heading">🤝 إضافة / سحب رأس مال</div><div class="card-desc">لو الشريك جديد، اكتب اسمه هنا وهيتسجل تلقائيًا</div>' +
      '<div class="field"><label>اسم الشريك <span class="req">*</span></label><input type="text" id="capPartnerName" list="existingPartnersList" placeholder="اكتب اسم الشريك"></div>' +
      '<datalist id="existingPartnersList">' + summary.partners.map(function (p) { return '<option value="' + p.name + '">'; }).join('') + '</datalist>' +
      '<div class="form-grid" style="margin-top:14px;">' +
        '<div class="field"><label>نوع الحركة</label><select id="capType"><option>إضافة رأس مال</option><option>سحب رأس مال</option></select></div>' +
        '<div class="field"><label>المبلغ <span class="req">*</span></label><input type="number" id="capAmount"></div>' +
      '</div>' +
      '<div class="field" style="margin-top:12px;"><label>هتضاف/تتسحب من حساب</label><select id="capTreasuryAccount">' +
        (treasuryAccounts.length === 0 ? '<option value="">لا يوجد حسابات خزنة/بنوك مضافة</option>' :
          treasuryAccounts.map(function (t) { return '<option value="' + t.id + '">' + t.name + ' (' + t.type + ')</option>'; }).join('')) +
      '</select></div>' +
      (treasuryAccounts.length === 0 ? '<div class="hint">لسه معملتيش حساب خزنة/بنك — أضيفي واحد من صفحة "الخزنة والبنوك" الأول عشان تختاري منين هتضاف الفلوس</div>' : '') +
      '<button class="btn success block" style="margin-top:16px;" onclick="submitCapitalMovement_()">✅ تسجيل الحركة</button>' +
      '<div class="card-heading" style="margin-top:26px;">⚙️ نسب الشريك</div><div class="card-desc">نسبة توزيع الأرباح ونسبة الإدارة</div>' +
      '<div class="field"><label>الشريك</label><select id="ratePartnerSelect">' + summary.partners.map(function (p) { return '<option>' + p.name + '</option>'; }).join('') + '</select></div>' +
      '<div class="form-grid" style="margin-top:12px;">' +
        '<div class="field"><label>نسبة توزيع الأرباح %</label><input type="number" id="rateProfitShare"></div>' +
        '<div class="field"><label>نسبة/مبلغ الإدارة</label><input type="number" id="rateAdminValue"></div>' +
      '</div><div class="field" style="margin-top:12px;"><label>نوع نسبة الإدارة</label><select id="rateAdminType"><option value="نسبة %">نسبة %</option><option value="مبلغ ثابت">مبلغ ثابت</option></select></div>' +
      '<button class="btn success block" style="margin-top:14px;" onclick="submitPartnerRates_()">💾 حفظ النسب</button></div>';

    const activePartners = summary.partners.filter(function (p) { return p.active; });
    const formerPartners = summary.partners.filter(function (p) { return !p.active; });
    function partnerRow_(p) {
      return '<div class="list-item" style="display:block; padding:14px 4px;"><div class="card-row"><b>' + p.name + '</b><span class="pill info">' + p.ownershipPercent + '% ملكية</span></div>' +
        '<div style="margin-top:6px; font-size:12px; color:var(--text-dim);">الرصيد: ' + formatMoney_(p.balance, cur) +
        ' · توزيع أرباح: ' + (p.profitSharePercent !== null ? p.profitSharePercent + '%' : '—') +
        ' · إدارة: ' + (p.adminRate !== null ? p.adminRate + (p.adminRateType === 'نسبة %' ? '%' : ' ' + cur) : '—') + '</div>' +
        '<button class="btn sm secondary" style="margin-top:8px;" onclick=\'togglePartnerActive_(' + JSON.stringify(p.name) + ', ' + (!p.active) + ')\'>' + (p.active ? '🔒 تعطيل (شريك مشى)' : '✅ إعادة تفعيل') + '</button></div>';
    }
    html += '<div class="card"><div class="card-heading">📊 الشركاء الحاليين</div><div style="margin-top:10px;">';
    html += activePartners.length === 0 ? emptyRow_('🤝', 'لا يوجد شركاء نشطين حاليًا') : activePartners.map(partnerRow_).join('');
    html += '</div></div></div>';
    if (formerPartners.length > 0) {
      html += '<div class="card" style="margin-top:16px; opacity:.7;"><div class="card-heading">📁 شركاء سابقون</div><div style="margin-top:10px;">' + formerPartners.map(partnerRow_).join('') + '</div></div>';
    }

    const adminRights = await api.getAdminRights().catch(function () { return []; });
    const availableByPartner = {};
    adminRights.forEach(function (r) { availableByPartner[r.partnerName] = (availableByPartner[r.partnerName] || 0) + Number(r.available); });

    html += '<div class="section-title">💼 مستحقات نسبة الإدارة</div>';
    html += '<div class="grid grid-2">';
    html += '<div class="card"><div class="card-heading">سحب مستحق</div>' +
      '<div class="field"><label>الشريك</label><select id="adminWithdrawPartner">' + summary.partners.map(function (p) { return '<option>' + p.name + '</option>'; }).join('') + '</select></div>' +
      '<div class="form-grid" style="margin-top:10px;"><div class="field"><label>المبلغ</label><input type="number" id="adminWithdrawAmount"></div>' +
      '<div class="field"><label>يتخصم من حساب</label><select id="adminWithdrawTreasury">' + treasuryAccountOptionsHtml_(treasuryAccounts) + '</select></div></div>' +
      '<button class="btn success block" style="margin-top:14px;" onclick="submitWithdrawAdminRight_()">✅ سحب المستحق</button>' +
      '<button class="btn secondary block" style="margin-top:10px;" onclick="submitRunAdminFee_()">▶️ تشغيل نسبة إدارة الشهر الحالي يدويًا</button></div>';
    html += '<div class="card"><div class="card-heading">المتاح لكل شريك</div><div style="margin-top:10px;">' +
      (Object.keys(availableByPartner).length === 0 ? emptyRow_('💼', 'لا يوجد مستحقات إدارة بعد') :
        Object.keys(availableByPartner).map(function (name) { return '<div class="list-item"><span>' + name + '</span><b>' + formatMoney_(availableByPartner[name], cur) + '</b></div>'; }).join('')) +
      '</div></div></div>';

    setContent_(html);
  } catch (err) { showErrorToast_(err); }
}

async function submitWithdrawAdminRight_() {
  const partnerName = document.getElementById('adminWithdrawPartner').value;
  const amount = Number(document.getElementById('adminWithdrawAmount').value);
  const treasuryAccountId = document.getElementById('adminWithdrawTreasury').value || null;
  if (!amount) { showToast_('المبلغ مطلوب', 'error'); return; }
  try { await api.withdrawAdminRight({ username: state.user.username }, partnerName, amount, treasuryAccountId); showToast_('تم السحب ✅', 'success'); renderCapitalPage(); }
  catch (err) { showErrorToast_(err); }
}

async function submitRunAdminFee_() {
  try { await api.runMonthlyAdminFee({ username: state.user.username }); showToast_('تم تشغيل نسبة الإدارة الشهرية ✅', 'success'); renderCapitalPage(); }
  catch (err) { showErrorToast_(err); }
}

async function togglePartnerActive_(partnerName, newActive) {
  try { await api.setPartnerActive({ username: state.user.username }, partnerName, newActive); showToast_(newActive ? 'تم تفعيل الشريك ✅' : 'تم تعطيل الشريك ✅', 'success'); renderCapitalPage(); }
  catch (err) { showErrorToast_(err); }
}

async function submitCapitalMovement_() {
  const payload = {
    partnerName: document.getElementById('capPartnerName').value.trim(), type: document.getElementById('capType').value,
    amount: Number(document.getElementById('capAmount').value), treasuryAccountId: document.getElementById('capTreasuryAccount').value || null
  };
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
      '<div class="field"><label>نوع الحركة</label><select id="pcType" onchange="onPcTypeChange_()"><option>إيداع</option><option>سحب</option><option>مصروف</option></select></div>' +
      '<div class="form-grid" style="margin-top:14px;"><div class="field"><label>المبلغ <span class="req">*</span></label><input type="number" id="pcAmount"></div>' +
      '<div class="field"><label>الوصف</label><input type="text" id="pcDesc"></div></div>' +
      '<div class="field" id="pcTreasuryFieldWrap"><label>من/لحساب</label><select id="pcTreasuryAccount">' + treasuryAccountOptionsHtml_(await getTreasuryAccountsCached_().catch(function () { return []; })) + '</select></div>' +
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

function onPcTypeChange_() {
  const type = document.getElementById('pcType').value;
  document.getElementById('pcTreasuryFieldWrap').style.display = type === 'مصروف' ? 'none' : 'block';
}

async function submitPettyCash_() {
  const type = document.getElementById('pcType').value, amount = Number(document.getElementById('pcAmount').value), desc = document.getElementById('pcDesc').value;
  const treasuryAccountId = document.getElementById('pcTreasuryAccount').value || null;
  if (!amount) { showToast_('المبلغ مطلوب', 'error'); return; }
  try { await api.addPettyCashMovement({ username: state.user.username }, type, amount, desc, treasuryAccountId); showToast_('تم تسجيل الحركة ✅', 'success'); renderPettyCashPage(); }
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
    '<div class="section-title">📊 الربحية الحقيقية</div>' +
    '<div class="card"><div class="card-row" style="gap:10px; flex-wrap:wrap;">' +
      '<button class="btn info-btn" onclick="loadProfitabilityByProduct_()">🏷️ حسب الصنف</button>' +
      '<button class="btn info-btn" onclick="loadProfitabilityByCustomer_()">👤 حسب العميل</button></div>' +
      '<div id="profitabilityResult" style="margin-top:14px;"></div></div>' +
    '<div class="section-title">🤖 الذكاء الاصطناعي</div>' +
    '<div class="card"><div class="card-row" style="gap:10px; flex-wrap:wrap;">' +
      '<button class="btn info-btn" onclick="loadStagnantStock_()">📦 أصناف راكدة</button>' +
      '<button class="btn info-btn" onclick="loadSalesForecast_()">📈 توقع المبيعات</button>' +
      '<button class="btn" onclick="loadAiInsights_()">✨ تحليل ذكي (Gemini)</button></div>' +
      '<div id="aiResult" style="margin-top:14px;"></div></div>' +
    '<div class="section-title">💵 الإيرادات الأخرى</div>' +
    '<div class="card"><div class="form-grid">' +
      '<div class="field"><label>المصدر</label><input type="text" id="orSource" placeholder="مثال: بيع كرتونة فاضية"></div>' +
      '<div class="field"><label>المبلغ</label><input type="number" id="orAmount"></div></div>' +
      '<div class="form-grid" style="margin-top:10px;"><div class="field"><label>الوصف</label><input type="text" id="orDesc"></div>' +
      '<div class="field"><label>هتضاف لحساب</label><select id="orTreasuryAccount"></select></div></div>' +
      '<button class="btn success block" style="margin-top:14px;" onclick="submitOtherRevenue_()">➕ تسجيل الإيراد</button>' +
      '<div id="otherRevenueList" style="margin-top:14px;"></div></div>' +
    '<div class="section-title">المواسم</div>' +
    '<div class="card"><div class="form-grid">' +
      '<div class="field"><label>اسم الموسم</label><input type="text" id="seasonName"></div>' +
      '<div class="field"><label>من</label><input type="date" id="seasonStart"></div>' +
      '<div class="field"><label>إلى</label><input type="date" id="seasonEnd"></div></div>' +
      '<button class="btn" style="margin-top:14px;" onclick="submitSeason_()">➕ إضافة موسم</button><div id="seasonsList" style="margin-top:14px;"></div></div>'
  );
  loadSeasons_();
  loadOtherRevenue_();
  getTreasuryAccountsCached_().then(function (accounts) {
    document.getElementById('orTreasuryAccount').innerHTML = treasuryAccountOptionsHtml_(accounts);
    refreshSelect_('orTreasuryAccount');
  }).catch(function () { /* صامت */ });
}

async function submitOtherRevenue_() {
  const payload = {
    source: document.getElementById('orSource').value.trim(), amount: Number(document.getElementById('orAmount').value),
    description: document.getElementById('orDesc').value, treasuryAccountId: document.getElementById('orTreasuryAccount').value || null
  };
  if (!payload.source || !payload.amount) { showToast_('المصدر والمبلغ مطلوبين', 'error'); return; }
  try { await api.addOtherRevenue({ username: state.user.username }, payload); showToast_('تم تسجيل الإيراد ✅', 'success'); renderReportsPage(); }
  catch (err) { showErrorToast_(err); }
}

async function loadOtherRevenue_() {
  try {
    const list = await api.listOtherRevenue(15);
    const cur = state.settings.currency || 'جنيه';
    document.getElementById('otherRevenueList').innerHTML = list.length === 0 ? emptyRow_('💵', 'لا يوجد إيرادات أخرى مسجلة بعد') :
      list.map(function (r) { return '<div class="list-item"><span>' + r.source + (r.description ? ' — ' + r.description : '') + '<br><span style="color:var(--text-faint); font-size:11px;">' + formatDate_(r.date) + '</span></span><b>' + formatMoney_(r.amount, cur) + '</b></div>'; }).join('');
  } catch (err) { /* صامت */ }
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
        '<div class="field"><label>هتتخصم من حساب</label><select id="advTreasuryAccount"></select></div>' +
        '<button class="btn success block" style="margin-top:14px;" onclick="submitAdvance_()">تسجيل السلفة</button></div>' +
      '<div class="card"><div class="card-heading">👥 الموظفون</div><div id="employeesList" style="margin-top:10px;"></div>' +
        '<div class="card-heading" style="margin-top:26px;">💰 مرتبات الشهر الحالي</div>' +
        '<button class="btn secondary" style="margin-top:8px;" onclick="runSalaries_()">تشغيل المرتبات</button><div id="salariesList" style="margin-top:14px;"></div></div></div>'
  );
  loadEmployees_();
  getTreasuryAccountsCached_().then(function (accounts) {
    document.getElementById('advTreasuryAccount').innerHTML = treasuryAccountOptionsHtml_(accounts);
    refreshSelect_('advTreasuryAccount');
  }).catch(function () { /* صامت */ });
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
  const treasuryAccountId = document.getElementById('advTreasuryAccount').value || null;
  if (!amount) { showToast_('المبلغ مطلوب', 'error'); return; }
  try { await api.addEmployeeAdvance({ username: state.user.username }, document.getElementById('advEmployeeSelect').value, amount, treasuryAccountId); showToast_('تم تسجيل السلفة ✅', 'success'); }
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
  const accounts = await getTreasuryAccountsCached_().catch(function () { return []; });
  openModal('صرف مرتب ' + employeeName, monthLabel, '<div class="field"><label>هيتخصم من حساب</label><select id="modalSalaryTreasuryAccount">' + treasuryAccountOptionsHtml_(accounts) + '</select></div>',
    '<button class="btn secondary" onclick="closeModal()">إلغاء</button><button class="btn success" onclick="confirmPaySalary_(\'' + monthLabel + '\', \'' + employeeName.replace(/'/g, '') + '\')">✅ تأكيد الصرف</button>');
}

async function confirmPaySalary_(monthLabel, employeeName) {
  const treasuryAccountId = document.getElementById('modalSalaryTreasuryAccount').value || null;
  try {
    await api.paySalary({ username: state.user.username }, monthLabel, employeeName, treasuryAccountId);
    closeModal(); showToast_('تم صرف الراتب ✅', 'success'); loadSalaries_(monthLabel);
  } catch (err) { showErrorToast_(err); }
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

    if (warehouses.length >= 2) {
      html += '<div class="section-title">🔁 نقل مخزون بين المخازن</div><div class="card">' +
        '<div class="form-grid"><div class="field"><label>من مخزن</label><select id="stFrom">' + warehouses.map(function (w) { return '<option value="' + w.id + '">' + w.name + '</option>'; }).join('') + '</select></div>' +
        '<div class="field"><label>إلى مخزن</label><select id="stTo">' + warehouses.map(function (w) { return '<option value="' + w.id + '">' + w.name + '</option>'; }).join('') + '</select></div></div>' +
        '<div class="field" style="margin-top:10px;"><label>كود الصنف</label><input type="text" id="stVariantCode" placeholder="مثال: 21001-AH-M"></div>' +
        '<div class="field" style="margin-top:10px;"><label>الكمية</label><input type="number" id="stQty"></div>' +
        '<div class="field" style="margin-top:10px;"><label>ملاحظة</label><input type="text" id="stNotes"></div>' +
        '<button class="btn block" style="margin-top:16px;" onclick="submitStockTransfer_()">🔁 نقل</button></div>';
    }

    setContent_(html);
  } catch (err) { showErrorToast_(err); }
}

async function submitStockTransfer_() {
  const fromId = document.getElementById('stFrom').value, toId = document.getElementById('stTo').value;
  const variantCode = document.getElementById('stVariantCode').value.trim(), qty = Number(document.getElementById('stQty').value);
  if (fromId === toId) { showToast_('اختاري مخزنين مختلفين', 'error'); return; }
  if (!variantCode || !qty) { showToast_('كود الصنف والكمية مطلوبين', 'error'); return; }
  try {
    await api.transferStock({ username: state.user.username }, {
      fromWarehouseId: fromId, toWarehouseId: toId, items: [{ variant_code: variantCode, qty: qty }],
      notes: document.getElementById('stNotes').value
    });
    showToast_('تم النقل ✅', 'success');
    renderWarehousesPage();
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
      const isSelf = u.username === state.user.username;
      html += '<tr><td>' + u.username + '</td><td>' + u.fullName + '</td><td><span class="pill info">' + u.role + '</span></td>' +
        '<td><span class="pill ' + (u.active === 'نعم' ? 'success' : 'danger') + '">' + u.active + '</span></td>' +
        '<td style="display:flex; gap:6px;">' +
        (u.role !== 'أدمن' ? '<button class="btn sm secondary" onclick=\'openEditPermissionsModal_(' + JSON.stringify(u.username) + ', ' + JSON.stringify(u.permissions) + ')\'>الصلاحيات</button>' : '') +
        (!isSelf ? '<button class="btn sm danger" onclick=\'confirmDeleteUser_(' + JSON.stringify(u.id) + ', ' + JSON.stringify(u.username) + ')\'>حذف</button>' : '') +
        '</td></tr>';
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
    '<div class="field" style="margin-top:12px;"><label>الدور</label><input type="text" id="newUserRole" list="rolesList" placeholder="اختاري من القائمة أو اكتبي أي مسمى تاني" value="بائع"><datalist id="rolesList"><option value="بائع"><option value="كاشير"><option value="محاسب"><option value="شريك"><option value="أدمن"></datalist></div>' +
    '<div class="hint" style="margin-top:6px; font-size:12px; color:var(--text-dim);">"أدمن" بياخد كل الصلاحيات تلقائي، و"شريك" بيشوف كل حاجة (عرض) افتراضيًا. أي دور تاني (محاسب، بائع، أو أي مسمى تكتبيه) بيبدأ مخفي بالكامل وإنتي اللي بتفتحيله الصلاحيات المطلوبة بعدين.</div>',
    '<button class="btn secondary" onclick="closeModal()">إلغاء</button><button class="btn" onclick="submitNewUser_()">إضافة</button>');
}

async function submitNewUser_() {
  const roleValue = document.getElementById('newUserRole').value.trim();
  const payload = { username: document.getElementById('newUserUsername').value.trim(), fullName: document.getElementById('newUserFullName').value, password: document.getElementById('newUserPassword').value, role: roleValue || 'بائع', permissions: {} };
  if (!payload.username || !payload.password) { showToast_('اليوزرنيم وكلمة المرور مطلوبين', 'error'); return; }
  try { await api.createUser(state.user.username, payload); closeModal(); showToast_('تم إضافة المستخدم ✅', 'success'); renderUsersPage(); }
  catch (err) { showErrorToast_(err); }
}

function confirmDeleteUser_(userId, username) {
  openModal('حذف المستخدم', 'متأكدة إنك عايزة تمسحي "' + username + '"؟ الحساب هيتمسح نهائيًا ومش هيقدر يدخل تاني.', '',
    '<button class="btn secondary" onclick="closeModal()">إلغاء</button><button class="btn danger" onclick="submitDeleteUser_(\'' + userId + '\')">حذف نهائي</button>');
}

async function submitDeleteUser_(userId) {
  try { await api.deleteUser(userId); closeModal(); showToast_('تم حذف المستخدم ✅', 'success'); renderUsersPage(); }
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
    currency: document.getElementById('setCurrency').value,
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
    const computed = await api.getNotifications();
    let dbNotifs = [];
    try { dbNotifs = await api.getDbNotifications(); } catch (e) { /* الجدول لسه مش موجود لو الدفعة 4 مش اتشغلت */ }
    const merged = dbNotifs.map(function (n) { return { type: 'db', severity: 'info', message: n.title + (n.body ? ' — ' + n.body : ''), time: n.time, id: n.id, linkPage: n.linkPage }; }).concat(computed);
    const badge = document.getElementById('notifBadge');
    if (merged.length > 0) { badge.style.display = 'flex'; badge.textContent = merged.length > 9 ? '9+' : merged.length; }
    else badge.style.display = 'none';
    window.__notifications = merged;
  } catch (err) { /* صامت — التنبيهات مش حرجة */ }
}

function toggleNotifications() {
  const dropdown = document.getElementById('notifDropdown');
  if (dropdown.style.display === 'block') { dropdown.style.display = 'none'; return; }
  const notifs = window.__notifications || [];
  dropdown.style.display = 'block';
  dropdown.innerHTML = '<div class="notif-header">🔔 التنبيهات</div>' + (
    notifs.length === 0 ? '<div class="empty-state" style="padding:24px;"><span class="emoji" style="font-size:22px;">✅</span><div class="msg" style="font-size:12px;">مفيش تنبيهات جديدة</div></div>' :
    notifs.map(function (n) {
      const clickable = n.id ? ' style="cursor:pointer;" onclick="onNotifClick_(\'' + n.id + '\', ' + (n.linkPage ? '\'' + n.linkPage + '\'' : 'null') + ')"' : '';
      return '<div class="notif-item"' + clickable + '><div class="notif-dot ' + n.severity + '"></div><div><div class="notif-text">' + n.message + '</div>' + (n.time ? '<div class="notif-time">' + formatDate_(n.time) + '</div>' : '') + '</div></div>';
    }).join('')
  );
}

async function onNotifClick_(id, linkPage) {
  try { await api.markNotificationRead(id); } catch (e) {}
  document.getElementById('notifDropdown').style.display = 'none';
  refreshNotifications();
  if (linkPage) navigate(linkPage);
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
  applyPublicBranding();
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

    const firstOfMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().slice(0, 10);
    const today = new Date().toISOString().slice(0, 10);
    html += '<div class="section-title">📊 تقرير الأداء حسب المركز</div><div class="card">' +
      '<div class="form-grid"><div class="field"><label>من تاريخ</label><input type="date" id="ccRepStart" value="' + firstOfMonth + '"></div>' +
      '<div class="field"><label>إلى تاريخ</label><input type="date" id="ccRepEnd" value="' + today + '"></div></div>' +
      '<button class="btn info-btn" style="margin-top:14px;" onclick="loadCostCenterReport_()">📊 عرض</button>' +
      '<div id="costCenterReportResult" style="margin-top:14px;"></div></div>';

    setContent_(html);
  } catch (err) { showErrorToast_(err); }
}

async function loadCostCenterReport_() {
  const start = document.getElementById('ccRepStart').value, end = document.getElementById('ccRepEnd').value;
  const cur = state.settings.currency || 'جنيه';
  try {
    const rows = await api.getCostCenterReport(start, end);
    document.getElementById('costCenterReportResult').innerHTML = (rows || []).length === 0 ? emptyRow_('📊', 'لا يوجد بيانات في الفترة دي') :
      rows.map(function (r) {
        return '<div class="list-item" style="display:block; padding:12px 4px;"><b>' + r.costCenter + '</b>' +
          '<div style="margin-top:6px; font-size:12px; color:var(--text-dim);">مبيعات: ' + formatMoney_(r.sales, cur) + ' · مصروفات: ' + formatMoney_(r.expenses, cur) + ' · الصافي: ' + formatMoney_(r.net, cur) + '</div></div>';
      }).join('');
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

// ============================================================
// طلبات الشراء والاعتماد
// ============================================================
let prItemsCart = [];

async function renderPurchaseRequestsPage() {
  try {
    prItemsCart = [];
    const requests = await api.listPurchaseRequests();
    let html = '<div class="grid grid-2">';
    html += '<div class="card"><div class="card-heading">📝 طلب شراء جديد</div>' +
      '<div class="field"><label>اسم المورد (اختياري)</label><input type="text" id="prSupplierName"></div>' +
      '<div class="form-grid" style="margin-top:10px;"><div class="field"><label>كود الصنف (اختياري)</label><input type="text" id="prVariantCode"></div>' +
      '<div class="field"><label>أو وصف صنف حر</label><input type="text" id="prFreeText"></div></div>' +
      '<div class="form-grid" style="margin-top:10px;"><div class="field"><label>الكمية</label><input type="number" id="prQty"></div>' +
      '<div class="field"><label>السعر المتوقع</label><input type="number" id="prPrice"></div></div>' +
      '<button class="btn secondary block" style="margin-top:12px;" onclick="addItemToPrCart_()">➕ إضافة للسلة</button>' +
      '<div id="prCartList" style="margin-top:12px;"></div>' +
      '<div class="field" style="margin-top:10px;"><label>ملاحظة عامة</label><input type="text" id="prNotes"></div>' +
      '<button class="btn success block" style="margin-top:16px;" onclick="submitPurchaseRequest_()">✅ إرسال الطلب للاعتماد</button></div>';

    html += '<div class="card"><div class="card-heading">📋 الطلبات الحالية</div><div style="margin-top:10px;">';
    html += requests.length === 0 ? emptyRow_('📝', 'لسه مفيش طلبات شراء') :
      requests.map(function (r) {
        const pill = r.status === 'معتمد' ? 'success' : (r.status === 'مرفوض' ? 'danger' : 'warning');
        const actions = r.status === 'بانتظار الاعتماد'
          ? '<button class="btn success" style="padding:4px 10px; font-size:11px;" onclick="approvePr_(\'' + r.id + '\', true)">اعتماد</button>' +
            '<button class="btn danger" style="padding:4px 10px; font-size:11px;" onclick="approvePr_(\'' + r.id + '\', false)">رفض</button>'
          : '';
        return '<div class="list-item"><span><b>' + r.requestNumber + '</b>' + (r.supplierName ? ' — ' + r.supplierName : '') +
          '<br><span style="color:var(--text-faint); font-size:11px;">' + formatDate_(r.date) + '</span></span>' +
          '<span style="display:flex; align-items:center; gap:6px;"><span class="pill ' + pill + '">' + r.status + '</span>' + actions + '</span></div>';
      }).join('');
    html += '</div></div></div>';
    setContent_(html);
  } catch (err) { showErrorToast_(err); }
}

function addItemToPrCart_() {
  const variantCode = document.getElementById('prVariantCode').value.trim();
  const freeText = document.getElementById('prFreeText').value.trim();
  const qty = Number(document.getElementById('prQty').value);
  const price = Number(document.getElementById('prPrice').value) || 0;
  if (!variantCode && !freeText) { showToast_('لازم كود صنف أو وصف حر', 'error'); return; }
  if (!qty) { showToast_('الكمية مطلوبة', 'error'); return; }
  prItemsCart.push({ variant_code: variantCode, freeText: freeText, qty: qty, estimatedPrice: price });
  document.getElementById('prVariantCode').value = ''; document.getElementById('prFreeText').value = '';
  document.getElementById('prQty').value = ''; document.getElementById('prPrice').value = '';
  renderPrCart_();
}

function renderPrCart_() {
  const el = document.getElementById('prCartList');
  if (!el) return;
  el.innerHTML = prItemsCart.length === 0 ? '' : prItemsCart.map(function (it, idx) {
    return '<div class="list-item" style="padding:8px 12px;"><span>' + (it.variant_code || it.freeText) + ' × ' + it.qty + '</span>' +
      '<button class="btn secondary" style="padding:2px 8px; font-size:11px;" onclick="removeFromPrCart_(' + idx + ')">✕</button></div>';
  }).join('');
}

function removeFromPrCart_(idx) { prItemsCart.splice(idx, 1); renderPrCart_(); }

async function submitPurchaseRequest_() {
  if (prItemsCart.length === 0) { showToast_('ضيفي صنف واحد على الأقل للسلة', 'error'); return; }
  try {
    await api.createPurchaseRequest({ username: state.user.username }, {
      supplierName: document.getElementById('prSupplierName').value, items: prItemsCart, notes: document.getElementById('prNotes').value
    });
    showToast_('تم إرسال طلب الشراء ✅', 'success');
    renderPurchaseRequestsPage();
  } catch (err) { showErrorToast_(err); }
}

async function approvePr_(id, approve) {
  try {
    await api.approvePurchaseRequest({ username: state.user.username }, id, approve);
    showToast_(approve ? 'تم الاعتماد ✅' : 'تم الرفض', approve ? 'success' : 'warning');
    renderPurchaseRequestsPage();
  } catch (err) { showErrorToast_(err); }
}

// ============================================================
// الربحية الحقيقية (تُستدعى من صفحة التقارير)
// ============================================================
async function loadProfitabilityByProduct_() {
  const start = document.getElementById('repStart').value, end = document.getElementById('repEnd').value;
  try {
    const rows = await api.getProfitabilityByProduct(start, end);
    const cur = state.settings.currency || 'جنيه';
    let html = '<div class="table-wrap"><table><thead><tr><th>الصنف</th><th>الكمية</th><th>الإيراد</th><th>التكلفة</th><th>الربح</th><th>الهامش%</th></tr></thead><tbody>';
    html += rows.length === 0 ? '<tr><td colspan="6">لا توجد بيانات في الفترة دي</td></tr>' :
      rows.map(function (r) {
        return '<tr><td>' + r.productName + ' (' + r.variantCode + ')</td><td>' + r.qtySold + '</td><td>' + formatMoney_(r.revenue, cur) + '</td><td>' + formatMoney_(r.cost, cur) + '</td><td><b>' + formatMoney_(r.profit, cur) + '</b></td><td>' + r.marginPercent + '%</td></tr>';
      }).join('');
    html += '</tbody></table></div>';
    document.getElementById('profitabilityResult').innerHTML = html;
  } catch (err) { showErrorToast_(err); }
}

async function loadProfitabilityByCustomer_() {
  const start = document.getElementById('repStart').value, end = document.getElementById('repEnd').value;
  try {
    const rows = await api.getProfitabilityByCustomer(start, end);
    const cur = state.settings.currency || 'جنيه';
    let html = '<div class="table-wrap"><table><thead><tr><th>العميل</th><th>عدد الفواتير</th><th>الإيراد</th><th>التكلفة</th><th>الربح</th></tr></thead><tbody>';
    html += rows.length === 0 ? '<tr><td colspan="5">لا توجد بيانات في الفترة دي</td></tr>' :
      rows.map(function (r) {
        return '<tr><td>' + r.customerName + '</td><td>' + r.ordersCount + '</td><td>' + formatMoney_(r.revenue, cur) + '</td><td>' + formatMoney_(r.cost, cur) + '</td><td><b>' + formatMoney_(r.profit, cur) + '</b></td></tr>';
      }).join('');
    html += '</tbody></table></div>';
    document.getElementById('profitabilityResult').innerHTML = html;
  } catch (err) { showErrorToast_(err); }
}

// ============================================================
// العملات وأسعار الصرف
// ============================================================
async function renderCurrenciesPage() {
  try {
    const currencies = await api.listCurrencies();
    const rates = await api.listExchangeRates();
    let html = '<div class="grid grid-2">';
    html += '<div class="card"><div class="card-heading">💱 عملة جديدة</div>' +
      '<div class="form-grid"><div class="field"><label>كود العملة (مثال: USD)</label><input type="text" id="curCode" maxlength="6"></div>' +
      '<div class="field"><label>الاسم</label><input type="text" id="curName"></div></div>' +
      '<button class="btn success block" style="margin-top:16px;" onclick="submitCurrency_()">➕ إضافة</button></div>';

    html += '<div class="card"><div class="card-heading">📈 تحديث سعر صرف</div>' +
      '<div class="field"><label>العملة</label><select id="rateCurrency">' + currencies.filter(function (c) { return !c.is_base; }).map(function (c) { return '<option value="' + c.code + '">' + c.code + ' - ' + c.name + '</option>'; }).join('') + '</select></div>' +
      '<div class="field" style="margin-top:10px;"><label>السعر مقابل ' + (currencies.find(function (c) { return c.is_base; }) || {}).code + '</label><input type="number" step="0.0001" id="rateValue"></div>' +
      '<button class="btn block" style="margin-top:16px;" onclick="submitExchangeRate_()">📈 حفظ السعر</button></div>';
    html += '</div>';

    html += '<div class="section-title">آخر أسعار الصرف</div><div class="card">';
    html += rates.length === 0 ? emptyRow_('💱', 'لسه مفيش أسعار صرف مسجلة') :
      rates.map(function (r) { return '<div class="list-item"><span>' + r.currencyCode + ' — ' + formatDate_(r.date) + '</span><b>' + r.rate + '</b></div>'; }).join('');
    html += '</div>';
    setContent_(html);
  } catch (err) { showErrorToast_(err); }
}

async function submitCurrency_() {
  const code = document.getElementById('curCode').value.trim().toUpperCase();
  const name = document.getElementById('curName').value.trim();
  if (!code || !name) { showToast_('الكود والاسم مطلوبين', 'error'); return; }
  try {
    await api.addCurrency({ username: state.user.username }, code, name);
    showToast_('تم إضافة العملة ✅', 'success');
    renderCurrenciesPage();
  } catch (err) { showErrorToast_(err); }
}

async function submitExchangeRate_() {
  const code = document.getElementById('rateCurrency').value;
  const rate = Number(document.getElementById('rateValue').value);
  if (!rate) { showToast_('السعر مطلوب', 'error'); return; }
  try {
    await api.setExchangeRate({ username: state.user.username }, code, rate);
    showToast_('تم حفظ سعر الصرف ✅', 'success');
    renderCurrenciesPage();
  } catch (err) { showErrorToast_(err); }
}

// ============================================================
// الشيكات
// ============================================================
async function renderChecksPage() {
  try {
    const checks = await api.listChecks();
    const cur = state.settings.currency || 'جنيه';
    let html = '<div class="card"><div class="card-heading">📑 شيك جديد</div>' +
      '<div class="form-grid"><div class="field"><label>رقم الشيك</label><input type="text" id="chkNumber"></div>' +
      '<div class="field"><label>النوع</label><select id="chkDirection"><option value="واردة">واردة (من عميل)</option><option value="صادرة">صادرة (لمورد)</option></select></div></div>' +
      '<div class="form-grid" style="margin-top:10px;"><div class="field"><label>اسم الطرف</label><input type="text" id="chkParty"></div>' +
      '<div class="field"><label>المبلغ</label><input type="number" id="chkAmount"></div></div>' +
      '<div class="form-grid" style="margin-top:10px;"><div class="field"><label>تاريخ الاستحقاق</label><input type="date" id="chkDueDate"></div>' +
      '<div class="field"><label>اسم البنك</label><input type="text" id="chkBank"></div></div>' +
      '<button class="btn success block" style="margin-top:16px;" onclick="submitCheck_()">✅ إضافة الشيك</button></div>';

    html += '<div class="section-title">الشيكات الحالية</div><div class="card">';
    html += checks.length === 0 ? emptyRow_('📑', 'لسه مفيش شيكات مسجلة') :
      checks.map(function (c) {
        const pill = c.status === 'تم التحصيل' ? 'success' : (c.status === 'مرتجعة/مرفوضة' ? 'danger' : (c.status === 'ملغاة' ? 'secondary' : 'warning'));
        const actions = c.status === 'تحت التحصيل'
          ? '<button class="btn success" style="padding:4px 10px; font-size:11px;" onclick="openCollectCheckModal_(\'' + c.id + '\')">تحصيل</button>' +
            '<button class="btn danger" style="padding:4px 10px; font-size:11px;" onclick="updateCheck_(\'' + c.id + '\', \'مرتجعة/مرفوضة\')">ارتجاع</button>'
          : '';
        return '<div class="list-item"><span>' + (c.direction === 'واردة' ? '⬇️' : '⬆️') + ' <b>' + c.checkNumber + '</b> — ' + c.partyName +
          '<br><span style="color:var(--text-faint); font-size:11px;">استحقاق: ' + c.dueDate + ' — ' + formatMoney_(c.amount, cur) + '</span></span>' +
          '<span style="display:flex; align-items:center; gap:6px;"><span class="pill ' + pill + '">' + c.status + '</span>' + actions + '</span></div>';
      }).join('');
    html += '</div>';
    setContent_(html);
  } catch (err) { showErrorToast_(err); }
}

async function submitCheck_() {
  const payload = {
    checkNumber: document.getElementById('chkNumber').value.trim(), direction: document.getElementById('chkDirection').value,
    partyName: document.getElementById('chkParty').value.trim(), amount: Number(document.getElementById('chkAmount').value),
    dueDate: document.getElementById('chkDueDate').value, bankName: document.getElementById('chkBank').value
  };
  if (!payload.checkNumber || !payload.partyName || !payload.amount || !payload.dueDate) { showToast_('كل الحقول الأساسية مطلوبة', 'error'); return; }
  try {
    await api.addCheck(state.user, payload);
    showToast_('تم إضافة الشيك ✅', 'success');
    renderChecksPage();
  } catch (err) { showErrorToast_(err); }
}

async function openCollectCheckModal_(id) {
  const accounts = await getTreasuryAccountsCached_().catch(function () { return []; });
  openModal('تحصيل شيك', '', '<div class="field"><label>هيتضاف/يتخصم من حساب</label><select id="modalCheckTreasuryAccount">' + treasuryAccountOptionsHtml_(accounts) + '</select></div>',
    '<button class="btn secondary" onclick="closeModal()">إلغاء</button><button class="btn success" onclick="confirmCollectCheck_(\'' + id + '\')">✅ تأكيد التحصيل</button>');
}

async function confirmCollectCheck_(id) {
  const treasuryAccountId = document.getElementById('modalCheckTreasuryAccount').value || null;
  closeModal();
  await updateCheck_(id, 'تم التحصيل', treasuryAccountId);
}

async function updateCheck_(id, status, treasuryAccountId) {
  try {
    await api.updateCheckStatus({ username: state.user.username }, id, status, treasuryAccountId);
    showToast_('تم تحديث حالة الشيك ✅', 'success');
    renderChecksPage();
  } catch (err) { showErrorToast_(err); }
}

// ============================================================
// ميزان المراجعة
// ============================================================
async function renderTrialBalancePage() {
  const today = new Date().toISOString().slice(0, 10);
  setContent_(
    '<div class="card"><div class="card-heading">⚖️ ميزان المراجعة</div><div class="card-desc">كل الحسابات ومجاميعها المدينة والدائنة من دفتر اليومية حتى تاريخ معيّن</div>' +
      '<div class="field"><label>حتى تاريخ</label><input type="date" id="tbEndDate" value="' + today + '"></div>' +
      '<button class="btn info-btn" style="margin-top:14px;" onclick="loadTrialBalance_()">📊 عرض</button></div>' +
    '<div id="trialBalanceResult" style="margin-top:18px;"></div>'
  );
  loadTrialBalance_();
}

async function loadTrialBalance_() {
  const endDate = document.getElementById('tbEndDate').value;
  const cur = state.settings.currency || 'جنيه';
  try {
    const rows = await api.getTrialBalance(endDate);
    let totalDebit = 0, totalCredit = 0;
    let html = '<div class="card">';
    if (rows.length === 0) {
      html += emptyRow_('⚖️', 'لا يوجد قيود محاسبية لغاية التاريخ ده');
    } else {
      rows.forEach(function (r) {
        totalDebit += Number(r.debit); totalCredit += Number(r.credit);
        html += '<div class="list-item"><span><b>' + r.accountCode + '</b> — ' + r.accountName + ' <span class="pill">' + r.accountType + '</span></span>' +
          '<span>مدين: ' + formatMoney_(r.debit, cur) + ' &nbsp; دائن: ' + formatMoney_(r.credit, cur) + '</span></div>';
      });
      html += '<div class="list-item" style="font-weight:900; border-top:2px solid var(--border); margin-top:6px; padding-top:12px;"><span>الإجمالي</span>' +
        '<span>مدين: ' + formatMoney_(totalDebit, cur) + ' &nbsp; دائن: ' + formatMoney_(totalCredit, cur) + '</span></div>';
      if (Math.abs(totalDebit - totalCredit) > 0.01) {
        html += '<div class="hint" style="color:var(--danger); margin-top:10px;">⚠️ الميزان مش متزن! فرق ' + formatMoney_(Math.abs(totalDebit - totalCredit), cur) + '</div>';
      } else {
        html += '<div class="hint" style="color:var(--success); margin-top:10px;">✅ الميزان متزن</div>';
      }
    }
    html += '</div>';
    document.getElementById('trialBalanceResult').innerHTML = html;
  } catch (err) { showErrorToast_(err); }
}

// ============================================================
// الميزانية العمومية
// ============================================================
async function renderBalanceSheetPage() {
  const today = new Date().toISOString().slice(0, 10);
  setContent_(
    '<div class="card"><div class="card-heading">🏛️ الميزانية العمومية</div><div class="card-desc">الأصول والخصوم وحقوق الملكية حتى تاريخ معيّن</div>' +
      '<div class="field"><label>حتى تاريخ</label><input type="date" id="bsAsOf" value="' + today + '"></div>' +
      '<button class="btn info-btn" style="margin-top:14px;" onclick="loadBalanceSheet_()">📊 عرض</button></div>' +
    '<div id="balanceSheetResult" style="margin-top:18px;"></div>'
  );
  loadBalanceSheet_();
}

function bsSection_(title, items, cur) {
  const total = (items || []).reduce(function (s, i) { return s + Number(i.balance); }, 0);
  let html = '<div class="card"><div class="card-heading">' + title + '</div>';
  html += (items || []).length === 0 ? emptyRow_('📄', 'لا يوجد أرصدة') :
    items.map(function (i) { return '<div class="list-item"><span>' + i.name + '</span><b>' + formatMoney_(i.balance, cur) + '</b></div>'; }).join('');
  html += '<div class="list-item" style="font-weight:900; border-top:2px solid var(--border); margin-top:6px; padding-top:10px;"><span>الإجمالي</span><b>' + formatMoney_(total, cur) + '</b></div></div>';
  return { html: html, total: total };
}

async function loadBalanceSheet_() {
  const asOf = document.getElementById('bsAsOf').value;
  const cur = state.settings.currency || 'جنيه';
  try {
    const data = await api.getBalanceSheet(asOf);
    const assets = bsSection_('💰 الأصول', data.assets, cur);
    const liabilities = bsSection_('📉 الخصوم', data.liabilities, cur);
    const equity = bsSection_('🏦 حقوق الملكية', data.equity, cur);
    const totalEquityWithEarnings = equity.total + Number(data.retainedEarnings || 0);
    let html = '<div class="grid grid-2">' + assets.html + '<div>' + liabilities.html +
      '<div style="margin-top:16px;">' + equity.html + '</div></div></div>';
    html += '<div class="card" style="margin-top:16px;"><div class="list-item"><span>الأرباح المحتجزة (صافي الربح التراكمي)</span><b>' + formatMoney_(data.retainedEarnings, cur) + '</b></div>' +
      '<div class="list-item" style="font-weight:900;"><span>إجمالي الخصوم + حقوق الملكية</span><b>' + formatMoney_(liabilities.total + totalEquityWithEarnings, cur) + '</b></div>' +
      (Math.abs(assets.total - (liabilities.total + totalEquityWithEarnings)) > 0.5
        ? '<div class="hint" style="color:var(--danger); margin-top:8px;">⚠️ الميزانية مش متوازنة — فرق ' + formatMoney_(Math.abs(assets.total - (liabilities.total + totalEquityWithEarnings)), cur) + '</div>'
        : '<div class="hint" style="color:var(--success); margin-top:8px;">✅ متوازنة</div>') + '</div>';
    document.getElementById('balanceSheetResult').innerHTML = html;
  } catch (err) { showErrorToast_(err); }
}

// ============================================================
// قفل الفترات المحاسبية
// ============================================================
async function renderPeriodsPage() {
  const now = new Date();
  const currentLabel = now.getFullYear() + '-' + String(now.getMonth() + 1).padStart(2, '0');
  try {
    const periods = await api.listAccountingPeriods();
    let html = '<div class="card"><div class="card-heading">🔒 قفل / فتح فترة</div><div class="card-desc">بعد قفل شهر، محدش يقدر يضيف بيعة أو مصروف بتاريخ فيه</div>' +
      '<div class="field"><label>الفترة (YYYY-MM)</label><input type="text" id="periodLabel" value="' + currentLabel + '" placeholder="2026-08"></div>' +
      '<div class="card-row" style="gap:10px; margin-top:14px;">' +
      '<button class="btn danger" onclick="submitClosePeriod_()">🔒 قفل الفترة</button>' +
      '<button class="btn secondary" onclick="submitReopenPeriod_()">🔓 فتح الفترة تاني</button></div></div>';

    html += '<div class="section-title">الفترات المسجّلة</div><div class="card">';
    html += periods.length === 0 ? emptyRow_('🔒', 'لسه مفيش أي فترة اتقفلت') :
      periods.map(function (p) {
        return '<div class="list-item"><span>' + p.periodLabel + '</span><span class="pill ' + (p.closed ? 'danger' : 'success') + '">' + (p.closed ? 'مقفولة' : 'مفتوحة') + '</span></div>';
      }).join('');
    html += '</div>';
    setContent_(html);
  } catch (err) { showErrorToast_(err); }
}

async function submitClosePeriod_() {
  const label = document.getElementById('periodLabel').value.trim();
  if (!label) { showToast_('اكتب الفترة', 'error'); return; }
  openConfirmModal('تأكيد قفل الفترة', 'هتقفلي فترة ' + label + ' — محدش هيقدر يضيف بيانات بتاريخ فيها بعد كده', async function () {
    try { await api.closeAccountingPeriod({ username: state.user.username }, label); showToast_('تم قفل الفترة ✅', 'success'); renderPeriodsPage(); }
    catch (err) { showErrorToast_(err); }
  });
}

async function submitReopenPeriod_() {
  const label = document.getElementById('periodLabel').value.trim();
  if (!label) { showToast_('اكتب الفترة', 'error'); return; }
  try { await api.reopenAccountingPeriod({ username: state.user.username }, label); showToast_('تم فتح الفترة ✅', 'success'); renderPeriodsPage(); }
  catch (err) { showErrorToast_(err); }
}

// ============================================================
// الأصول الثابتة والإهلاك
// ============================================================
async function renderFixedAssetsPage() {
  try {
    const assets = await api.listFixedAssets();
    const cur = state.settings.currency || 'جنيه';
    let html = '<div class="card"><div class="card-heading">🏗️ الأصول الثابتة</div><div class="card-desc">الإهلاك بيتحسب تلقائيًا خطي على مدة العمر الافتراضي (بالشهور)</div>' +
      '<button class="btn" style="margin-top:6px;" onclick="submitRunDepreciation_()">📉 تشغيل إهلاك الشهر الحالي</button></div>';

    html += '<div class="section-title">الأصول المسجّلة</div><div class="card">';
    html += assets.length === 0 ? emptyRow_('🏗️', 'لا يوجد أصول ثابتة مسجّلة (تُضاف تلقائيًا عند تسجيل مصروف كـ"أصل ثابت")') :
      assets.map(function (a) {
        const net = Number(a.amount) - Number(a.accumulatedDepreciation);
        return '<div class="list-item" style="display:block; padding:14px 4px;"><b>' + (a.description || 'أصل') + '</b>' +
          '<div style="margin-top:6px; font-size:12px; color:var(--text-dim);">التكلفة: ' + formatMoney_(a.amount, cur) +
          ' · مجمع الإهلاك: ' + formatMoney_(a.accumulatedDepreciation, cur) + ' · صافي القيمة: ' + formatMoney_(net, cur) +
          ' · العمر الافتراضي: ' + a.usefulLifeMonths + ' شهر</div></div>';
      }).join('');
    html += '</div>';
    setContent_(html);
  } catch (err) { showErrorToast_(err); }
}

async function submitRunDepreciation_() {
  try { await api.runMonthlyDepreciation({ username: state.user.username }); showToast_('تم تشغيل الإهلاك الشهري ✅', 'success'); renderFixedAssetsPage(); }
  catch (err) { showErrorToast_(err); }
}

// ============================================================
// أرصدة أول مدة
// ============================================================
async function renderOpeningBalancesPage() {
  try {
    const [balances, accounts] = await Promise.all([api.listOpeningBalances(), api.getAccounts()]);
    const cur = state.settings.currency || 'جنيه';
    const today = new Date().toISOString().slice(0, 10);
    let html = '<div class="card"><div class="card-heading">📂 رصيد افتتاحي جديد</div>' +
      '<div class="field"><label>الحساب</label><select id="obAccount">' + accounts.map(function (a) { return '<option value="' + a.id + '">' + a.code + ' — ' + a.name + '</option>'; }).join('') + '</select></div>' +
      '<div class="form-grid" style="margin-top:10px;"><div class="field"><label>المبلغ</label><input type="number" id="obAmount"></div>' +
      '<div class="field"><label>كتاريخ</label><input type="date" id="obDate" value="' + today + '"></div></div>' +
      '<div class="field" style="margin-top:10px;"><label>وصف</label><input type="text" id="obDesc"></div>' +
      '<button class="btn success block" style="margin-top:14px;" onclick="submitOpeningBalance_()">➕ إضافة</button>' +
      '<button class="btn block" style="margin-top:10px;" onclick="submitPostOpeningBalances_()">📮 ترحيل كل الأرصدة المفتوحة لدفتر اليومية</button>' +
      '<div class="hint" style="margin-top:8px;">الترحيل بيقفل الرصيد بحيث محدش يقدر يعدله تاني، وبيسجله كقيد رسمي في دفتر اليومية</div></div>';

    html += '<div class="section-title">الأرصدة المسجّلة</div><div class="card">';
    html += balances.length === 0 ? emptyRow_('📂', 'لسه مفيش أرصدة أول مدة مضافة') :
      balances.map(function (b) {
        return '<div class="list-item"><span>' + b.accountName + (b.description ? ' — ' + b.description : '') + '</span>' +
          '<span>' + formatMoney_(b.amount, cur) + ' <span class="pill ' + (b.locked ? 'success' : 'warning') + '">' + (b.locked ? 'مُرحّل' : 'لسه') + '</span></span></div>';
      }).join('');
    html += '</div>';
    setContent_(html);
  } catch (err) { showErrorToast_(err); }
}

async function submitOpeningBalance_() {
  const payload = {
    accountId: document.getElementById('obAccount').value, amount: Number(document.getElementById('obAmount').value),
    asOfDate: document.getElementById('obDate').value, description: document.getElementById('obDesc').value
  };
  if (!payload.accountId || !payload.amount) { showToast_('الحساب والمبلغ مطلوبين', 'error'); return; }
  try { await api.addOpeningBalance({ username: state.user.username }, payload); showToast_('تم الإضافة ✅', 'success'); renderOpeningBalancesPage(); }
  catch (err) { showErrorToast_(err); }
}

async function submitPostOpeningBalances_() {
  openConfirmModal('تأكيد الترحيل', 'هيترحّل كل الأرصدة المفتوحة لدفتر اليومية ويتقفلوا نهائيًا', async function () {
    try { await api.postOpeningBalances({ username: state.user.username }); showToast_('تم الترحيل ✅', 'success'); renderOpeningBalancesPage(); }
    catch (err) { showErrorToast_(err); }
  });
}

// ============================================================
// البحث الموحّد (Smart Search)
// ============================================================
let globalSearchDebounce_;
function onGlobalSearchInput_(value) {
  clearTimeout(globalSearchDebounce_);
  const dropdown = document.getElementById('globalSearchDropdown');
  if (!value || value.trim().length < 2) { dropdown.style.display = 'none'; return; }
  globalSearchDebounce_ = setTimeout(async function () {
    try {
      const result = await api.globalSearch(value.trim());
      const groups = [
        { key: 'products', label: '🏷️ منتجات' }, { key: 'customers', label: '👤 عملاء' },
        { key: 'suppliers', label: '🚚 موردون' }, { key: 'invoices', label: '📄 فواتير' }
      ];
      let html = '';
      groups.forEach(function (g) {
        const items = result[g.key] || [];
        if (items.length === 0) return;
        html += '<div style="padding:8px 12px 4px; font-size:11px; font-weight:800; color:var(--text-faint);">' + g.label + '</div>';
        html += items.map(function (it) {
          return '<div class="list-item" style="padding:8px 12px; cursor:pointer;" onclick="onGlobalSearchResultClick_(\'' + it.page + '\')"><span>' + it.label + '</span></div>';
        }).join('');
      });
      if (!html) html = '<div class="empty-state" style="padding:20px;"><span class="emoji" style="font-size:20px;">🔍</span><div class="msg" style="font-size:12px;">مفيش نتائج</div></div>';
      dropdown.innerHTML = html;
      dropdown.style.display = 'block';
    } catch (err) { /* صامت */ }
  }, 350);
}

function onGlobalSearchResultClick_(page) {
  document.getElementById('globalSearchDropdown').style.display = 'none';
  document.getElementById('globalSearchInput').value = '';
  if (page) navigate(page);
}

document.addEventListener('click', function (e) {
  const dropdown = document.getElementById('globalSearchDropdown');
  if (!dropdown) return;
  if (dropdown.style.display === 'block' && !dropdown.contains(e.target) && e.target.id !== 'globalSearchInput') dropdown.style.display = 'none';
});

// ============================================================
// المرفقات — Modal عام يُستخدم من أي شاشة
// ============================================================
let attachmentsModalCtx_ = null;

async function openAttachmentsModal_(entityType, entityId, label) {
  attachmentsModalCtx_ = { entityType: entityType, entityId: entityId };
  openModal('📎 مرفقات — ' + (label || ''), '', '<div id="attachmentsModalBody">جاري التحميل...</div>',
    '<button class="btn secondary" onclick="closeModal()">إغلاق</button>');
  await refreshAttachmentsModal_();
}

async function refreshAttachmentsModal_() {
  try {
    const files = await api.listAttachments(attachmentsModalCtx_.entityType, attachmentsModalCtx_.entityId);
    let html = '<div class="field"><input type="file" id="attachmentFileInput"></div>' +
      '<button class="btn success block" style="margin-top:10px;" onclick="submitAttachmentUpload_()">⬆️ رفع الملف</button>' +
      '<div style="margin-top:16px;">';
    html += files.length === 0 ? emptyRow_('📎', 'لسه مفيش مرفقات') :
      files.map(function (f) {
        return '<div class="list-item"><a href="' + f.fileUrl + '" target="_blank" style="color:var(--info); text-decoration:none;">📄 ' + f.fileName + '</a>' +
          '<button class="btn secondary" style="padding:2px 8px; font-size:11px;" onclick="deleteAttachment_(\'' + f.id + '\')">🗑️</button></div>';
      }).join('');
    html += '</div>';
    document.getElementById('attachmentsModalBody').innerHTML = html;
  } catch (err) { showErrorToast_(err); }
}

async function submitAttachmentUpload_() {
  const input = document.getElementById('attachmentFileInput');
  if (!input.files || input.files.length === 0) { showToast_('اختاري ملف الأول', 'error'); return; }
  try {
    await api.uploadAttachment(state.user, attachmentsModalCtx_.entityType, attachmentsModalCtx_.entityId, input.files[0]);
    showToast_('تم رفع الملف ✅', 'success');
    refreshAttachmentsModal_();
  } catch (err) { showErrorToast_(err); }
}

async function deleteAttachment_(id) {
  try {
    await api.deleteAttachment(id);
    showToast_('تم الحذف', 'success');
    refreshAttachmentsModal_();
  } catch (err) { showErrorToast_(err); }
}

// ============================================================
// اختصارات لوحة المفاتيح
// ============================================================
const KEYBOARD_SHORTCUTS_HELP = [
  { keys: 'Ctrl + K', desc: 'التركيز على البحث الشامل' },
  { keys: 'Esc', desc: 'إغلاق أي نافذة منبثقة' },
  { keys: 'Ctrl + Enter', desc: 'تأكيد بيعة الكاشير (لو السلة فيها أصناف)' },
  { keys: 'Alt + D', desc: 'الذهاب للداشبورد' },
  { keys: 'Alt + P', desc: 'الذهاب لشاشة الكاشير' },
  { keys: 'Alt + I', desc: 'الذهاب لشاشة المخزون' },
  { keys: 'Alt + S', desc: 'الذهاب لشاشة المبيعات' },
  { keys: '?', desc: 'عرض قائمة الاختصارات دي' }
];

document.addEventListener('keydown', function (e) {
  const tag = (e.target.tagName || '').toLowerCase();
  const typing = tag === 'input' || tag === 'textarea' || tag === 'select';

  if (e.key === 'Escape') {
    const overlay = document.getElementById('modalOverlay');
    if (overlay && overlay.style.display !== 'none') { closeModal(); return; }
    const dropdown = document.getElementById('globalSearchDropdown');
    if (dropdown) dropdown.style.display = 'none';
    const notifDropdown = document.getElementById('notifDropdown');
    if (notifDropdown) notifDropdown.style.display = 'none';
    return;
  }

  if (e.ctrlKey && e.key.toLowerCase() === 'k') {
    e.preventDefault();
    const input = document.getElementById('globalSearchInput');
    if (input) input.focus();
    return;
  }

  if (e.ctrlKey && e.key === 'Enter') {
    if (state.currentPage === 'pos' && typeof submitPosSale_ === 'function' && posCart.length > 0) { e.preventDefault(); submitPosSale_(); }
    return;
  }

  if (!typing && e.altKey) {
    const map = { d: 'dashboard', p: 'pos', i: 'inventory', s: 'sales' };
    const target = map[e.key.toLowerCase()];
    if (target) { e.preventDefault(); navigate(target); }
    return;
  }

  if (!typing && e.key === '?') { e.preventDefault(); showKeyboardShortcutsHelp_(); }
});

function showKeyboardShortcutsHelp_() {
  const rows = KEYBOARD_SHORTCUTS_HELP.map(function (s) {
    return '<div class="list-item"><span>' + s.desc + '</span><span class="pill info" style="font-family:monospace;">' + s.keys + '</span></div>';
  }).join('');
  openModal('⌨️ اختصارات لوحة المفاتيح', '', '<div>' + rows + '</div>', '<button class="btn secondary" onclick="closeModal()">إغلاق</button>');
}

// ============================================================
// الذكاء الاصطناعي — أصناف راكدة + توقع مبيعات + تحليل Gemini
// ============================================================
async function loadStagnantStock_() {
  document.getElementById('aiResult').innerHTML = '<div class="empty-state" style="padding:20px;"><span class="emoji">⏳</span></div>';
  try {
    const rows = await api.getStagnantStock(60);
    let html = '<div class="card-heading" style="font-size:13px; margin-bottom:8px;">📦 أصناف مالهاش حركة بيع من 60 يوم</div>';
    html += rows.length === 0 ? emptyRow_('✅', 'مفيش أصناف راكدة، الوضع تمام') :
      '<div class="table-wrap"><table><thead><tr><th>الصنف</th><th>الكمية المتاحة</th><th>آخر بيعة</th></tr></thead><tbody>' +
      rows.map(function (r) {
        return '<tr><td>' + r.productName + ' (' + r.variantCode + ')</td><td>' + r.quantity + '</td><td>' + (r.daysSinceLastSale ? 'من ' + r.daysSinceLastSale + ' يوم' : 'لسه معملهاش بيعة خالص') + '</td></tr>';
      }).join('') + '</tbody></table></div>';
    document.getElementById('aiResult').innerHTML = html;
  } catch (err) { showErrorToast_(err); }
}

async function loadSalesForecast_() {
  document.getElementById('aiResult').innerHTML = '<div class="empty-state" style="padding:20px;"><span class="emoji">⏳</span></div>';
  try {
    const f = await api.getSalesForecast();
    const cur = state.settings.currency || 'جنيه';
    let html = '<div class="card-heading" style="font-size:13px; margin-bottom:8px;">📈 توقع مبيعات الأسبوع الجاي</div>';
    html += rowLine_('متوسط المبيعات الأسبوعي (آخر 8 أسابيع)', formatMoney_(f.averageWeekly, cur));
    html += rowLine_('الاتجاه (فرق آخر أسبوعين)', (f.trend >= 0 ? '↑ +' : '↓ ') + formatMoney_(Math.abs(f.trend), cur));
    html += rowLine_('التوقع للأسبوع الجاي', formatMoney_(f.nextWeekForecast, cur), true);
    document.getElementById('aiResult').innerHTML = html;
  } catch (err) { showErrorToast_(err); }
}

async function loadAiInsights_() {
  document.getElementById('aiResult').innerHTML = '<div class="empty-state" style="padding:20px;"><span class="emoji">✨</span><div class="msg" style="font-size:12px;">بيفكر...</div></div>';
  try {
    const income = await api.getIncomeStatement(document.getElementById('repStart').value, document.getElementById('repEnd').value);
    const stagnant = await api.getStagnantStock(60);
    const forecast = await api.getSalesForecast();
    const cur = state.settings.currency || 'جنيه';
    const context = 'إجمالي المبيعات: ' + formatMoney_(income.totalSales, cur) + '\nصافي الربح: ' + formatMoney_(income.netProfitBeforeTax, cur) +
      '\nعدد الأصناف الراكدة (60 يوم بدون بيع): ' + stagnant.length +
      '\nمتوسط المبيعات الأسبوعي: ' + formatMoney_(forecast.averageWeekly, cur) + '\nالتوقع للأسبوع الجاي: ' + formatMoney_(forecast.nextWeekForecast, cur);
    const insight = await api.getAiInsights(context);
    document.getElementById('aiResult').innerHTML = '<div class="card" style="background:var(--surface-2); white-space:pre-wrap; line-height:1.9; font-size:13px;">' + insight + '</div>';
  } catch (err) { showErrorToast_(err); }
}
