// ============================================================
// api.js
// طبقة وسيطة بين الواجهة وSupabase — كل فنكشن هنا Async وبترجع
// Promise. الأسماء نفسها زي النظام القديم عشان سهولة الفهم.
// ============================================================

const api = {};

// ------------------------------------------------------------
// المصادقة (Auth)
// ------------------------------------------------------------
api.login = async function (username, password) {
  let email = username;
  if (!email.includes('@')) {
    const { data: resolvedEmail, error: lookupErr } = await supabaseClient.rpc('rpc_get_email_by_username', { p_username: username });
    if (lookupErr || !resolvedEmail) return { success: false, error: 'اليوزر غير موجود' };
    email = resolvedEmail;
  }

  const { data, error } = await supabaseClient.auth.signInWithPassword({ email, password });
  if (error) return { success: false, error: 'كلمة المرور غلط أو اليوزر غير موجود' };

  const { data: profile } = await supabaseClient.from('profiles').select('*').eq('id', data.user.id).single();
  if (!profile || !profile.active) { await supabaseClient.auth.signOut(); return { success: false, error: 'الحساب غير مفعّل' }; }

  return {
    success: true,
    token: data.session.access_token,
    user: { username: profile.username, fullName: profile.full_name, role: profile.role, isCashier: profile.role === 'كاشير' }
  };
};

api.logout = async function () { await supabaseClient.auth.signOut(); return { success: true }; };

api.getAppShellData = async function () {
  const { data: { user } } = await supabaseClient.auth.getUser();
  if (!user) throw new Error('الجلسة منتهية');

  const { data: profile } = await supabaseClient.from('profiles').select('*').eq('id', user.id).single();
  const { data: settingsRows } = await supabaseClient.from('settings').select('*');
  const { data: warehouses } = await supabaseClient.from('warehouses').select('id');

  const settings = {};
  (settingsRows || []).forEach(function (r) { settings[r.key] = r.value; });

  return {
    user: { username: profile.username, fullName: profile.full_name, role: profile.role, isCashier: profile.role === 'كاشير', permissions: profile.permissions || {} },
    settings: {
      brandName: settings.brandName, logoUrl: settings.logoUrl, primaryColor: settings.primaryColor,
      accentColor: settings.accentColor, currency: settings.currency, darkMode: settings.darkMode === 'true',
      operatingMode: settings.operatingMode, taxEnabled: settings.taxEnabled === 'true',
      multiWarehouse: (warehouses || []).length > 1
    }
  };
};

// ------------------------------------------------------------
// الداشبورد + التقارير
// ------------------------------------------------------------
api.getDashboardData = async function () {
  const { data, error } = await supabaseClient.rpc('rpc_get_dashboard_data');
  if (error) throw error;
  return data;
};

api.getIncomeStatement = async function (start, end) {
  const { data, error } = await supabaseClient.rpc('rpc_income_statement', { p_start: start, p_end: end });
  if (error) throw error;
  return data;
};

api.listSeasons = async function () {
  const { data, error } = await supabaseClient.from('seasons').select('*').order('start_date', { ascending: false });
  if (error) throw error;
  return (data || []).map(function (s) { return { name: s.name, startDate: s.start_date, endDate: s.end_date, notes: s.notes }; });
};

api.addSeason = async function (session, payload) {
  const { error } = await supabaseClient.from('seasons').insert({ name: payload.name, start_date: payload.startDate, end_date: payload.endDate, notes: payload.notes || '' });
  if (error) throw error;
  return { success: true };
};

api.getNotifications = async function () {
  const notifications = [];
  const { data: lowStock } = await supabaseClient.from('product_variants').select('code,color,size,quantity,low_stock_threshold,products(name)').eq('status', 'نشط').lte('quantity', 999999);
  (lowStock || []).filter(function (v) { return v.quantity <= v.low_stock_threshold; }).slice(0, 10).forEach(function (v) {
    notifications.push({ type: 'low_stock', severity: 'warning', message: 'مخزون منخفض: ' + (v.products ? v.products.name : '') + ' (' + v.color + ' ' + v.size + ') — الكمية: ' + v.quantity, time: null });
  });

  const { data: overdueInvoices } = await supabaseClient.from('invoices').select('*').eq('status', 'متأخرة');
  (overdueInvoices || []).forEach(function (inv) {
    notifications.push({ type: 'overdue_invoice', severity: 'danger', message: 'فاتورة متأخرة: ' + inv.invoice_number + ' — العميل: ' + inv.customer_name, time: inv.invoice_date });
  });

  return notifications.slice(0, 30);
};

// ------------------------------------------------------------
// المخزون: الفئات + المنتجات + المتغيرات
// ------------------------------------------------------------
api.getProductTree = async function () {
  const { data, error } = await supabaseClient.from('product_tree').select('*').eq('active', true);
  if (error) throw error;
  const main = data.filter(function (c) { return c.type === 'رئيسية'; }).map(function (c) { return { code: c.code, name: c.name, type: c.type }; });
  const sub = data.filter(function (c) { return c.type === 'فرعية'; }).map(function (c) {
    const parent = data.find(function (p) { return p.id === c.parent_id; });
    return { code: c.code, name: c.name, type: c.type, parent: parent ? parent.code : null };
  });
  return { mainCategories: main, subCategories: sub };
};

api.createCategory = async function (session, payload) {
  const { data, error } = await supabaseClient.rpc('rpc_create_category', { p_name: payload.name, p_type: payload.type, p_parent_code: payload.parentCode || null });
  if (error) throw error;
  return data[0];
};

api.addProduct = async function (session, payload) {
  const { data, error } = await supabaseClient.rpc('rpc_add_product', {
    p_name: payload.name, p_sub_category_code: payload.subCategory, p_base_price: payload.basePrice,
    p_image: payload.image || '', p_description: payload.description || '', p_manual_code: payload.manualCode || null
  });
  if (error) throw error;
  return { success: true, code: data[0].code };
};

// إضافة سريعة Inline من شاشة أمر الشراء — بتحط المنتج تلقائيًا تحت فئة "عام"
// لو مش موجودة بتتعمل مرة واحدة بس، وبترجع كود المتغير الجاهز للإضافة للسلة فورًا
api.quickAddProduct = async function (session, name, price, manualCode) {
  const tree = await api.getProductTree();
  let generalMain = tree.mainCategories.find(function (c) { return c.name === 'عام'; });
  if (!generalMain) {
    generalMain = await api.createCategory(session, { name: 'عام', type: 'رئيسية' });
  }
  const freshTree = await api.getProductTree();
  let generalSub = freshTree.subCategories.find(function (c) { return c.name === 'عام' && c.parent === generalMain.code; });
  if (!generalSub) {
    generalSub = await api.createCategory(session, { name: 'عام', type: 'فرعية', parentCode: generalMain.code });
  }

  const product = await api.addProduct(session, {
    name: name, subCategory: generalSub.code, basePrice: price, manualCode: manualCode || null
  });
  const variant = await api.addVariant(session, {
    productCode: product.code, color: '', size: '', quantity: 0, cost: price
  });
  return { productCode: product.code, variantCode: variant.variantCode };
};

api.addVariant = async function (session, payload) {
  const { data, error } = await supabaseClient.rpc('rpc_add_variant', {
    p_product_code: payload.productCode, p_color: payload.color || '', p_size: payload.size || '',
    p_quantity: payload.quantity, p_cost: payload.cost, p_special_price: payload.specialPrice || null,
    p_warehouse_id: payload.warehouseId || null, p_low_stock_threshold: payload.lowStockThreshold || 5
  });
  if (error) throw error;
  return { success: true, variantCode: data[0].code };
};

api.getInventoryIndex = async function () {
  const { data: products, error } = await supabaseClient.from('products').select('*, product_variants(*), sub_category:sub_category_id(name)');
  if (error) throw error;
  const result = { products: {} };
  products.forEach(function (p) {
    result.products[p.code] = {
      code: p.code, name: p.name, basePrice: p.base_price, image: p.image_url, hasVariants: p.has_variants, status: p.status,
      subCategoryName: p.sub_category ? p.sub_category.name : '',
      variants: (p.product_variants || []).map(function (v) {
        return { code: v.code, productCode: p.code, color: v.color, size: v.size, quantity: v.quantity, cost: v.cost, specialPrice: v.special_price, warehouseId: v.warehouse_id, lowStockThreshold: v.low_stock_threshold, status: v.status };
      })
    };
  });
  return { products: result.products };
};

api.searchProducts = async function (query) {
  const { data, error } = await supabaseClient.from('products').select('*, product_variants(*)').ilike('name', '%' + query + '%').eq('status', 'نشط').limit(15);
  if (error) throw error;
  return (data || []).map(function (p) {
    return {
      code: p.code, name: p.name, basePrice: p.base_price, hasVariants: p.has_variants,
      variants: (p.product_variants || []).filter(function (v) { return v.status === 'نشط'; }).map(function (v) {
        return { code: v.code, color: v.color, size: v.size, quantity: v.quantity, cost: v.cost, specialPrice: v.special_price };
      })
    };
  });
};

api.getWarehouses = async function () {
  const { data, error } = await supabaseClient.from('warehouses').select('*');
  if (error) throw error;
  return (data || []).map(function (w) { return { id: w.id, name: w.name, description: w.description, location: w.location, isDefaultOnline: w.is_default_online }; });
};

api.addWarehouse = async function (session, payload) {
  const { error } = await supabaseClient.from('warehouses').insert({ name: payload.name, description: payload.description || '', location: payload.location || '', is_default_online: !!payload.isDefaultOnline });
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// المبيعات + الكاشير
// ------------------------------------------------------------
api.recordSale = async function (session, payload) {
  const { data, error } = await supabaseClient.rpc('rpc_record_sale', {
    p_source: payload.source, p_items: payload.items.map(function (i) { return { variant_code: i.variantCode, qty: i.qty, price: i.price }; }),
    p_discount: payload.discount || 0, p_payment_method: payload.paymentMethod || null,
    p_customer_name: payload.customerName || '', p_customer_phone: payload.customerPhone || '',
    p_sale_date: payload.date ? new Date(payload.date).toISOString() : new Date().toISOString()
  });
  if (error) throw error;
  return { success: true, saleId: data[0].sale_id, saleNumber: data[0].sale_number, total: data[0].total };
};

api.posSale = async function (session, cart, discount, paymentMethod) {
  return api.recordSale(session, { source: 'محل', items: cart, discount: discount, paymentMethod: paymentMethod });
};

api.recordReturn = async function (session, saleId, items, isFull) {
  const { error } = await supabaseClient.rpc('rpc_record_return', {
    p_sale_id: saleId, p_items: items.map(function (i) { return { variant_code: i.variantCode, qty: i.qty, price: i.price }; }), p_is_full: isFull
  });
  if (error) throw error;
  return { success: true };
};

api.listSales = async function (filters) {
  filters = filters || {};
  const { data, error } = await supabaseClient.from('sales').select('*, sale_items(*, product_variants(code))').order('sale_date', { ascending: false }).limit(filters.limit || 50);
  if (error) throw error;
  return (data || []).map(function (s) {
    return {
      saleId: s.sale_number, date: s.sale_date, source: s.source, total: s.total, status: s.status,
      paymentMethod: s.payment_method, customerName: s.customer_name,
      items: (s.sale_items || []).map(function (it) { return { variantCode: it.product_variants ? it.product_variants.code : '', qty: it.qty, price: it.unit_price }; })
    };
  });
};

api.posSearchSaleForReturn = async function (query) {
  const { data, error } = await supabaseClient.from('sales').select('*, sale_items(*, product_variants(code))').or('sale_number.ilike.%' + query + '%,customer_name.ilike.%' + query + '%').neq('status', 'مرتجع كلي').limit(10);
  if (error) throw error;
  return (data || []).map(function (s) {
    return {
      saleId: s.sale_number, date: s.sale_date, total: s.total, customerName: s.customer_name,
      items: (s.sale_items || []).map(function (it) { return { variantCode: it.product_variants ? it.product_variants.code : '', qty: it.qty, price: it.unit_price }; })
    };
  });
};

api.posReturn = async function (session, saleNumber, items) {
  const { data: sale } = await supabaseClient.from('sales').select('id').eq('sale_number', saleNumber).single();
  return api.recordReturn(session, sale.id, items, true);
};

api.getPosTodaySummary = async function () {
  const today = new Date().toISOString().slice(0, 10);
  const { data, error } = await supabaseClient.from('sales').select('total,payment_method').eq('source', 'محل').gte('sale_date', today).neq('status', 'مرتجع كلي');
  if (error) throw error;
  let totalSales = 0, totalCash = 0;
  (data || []).forEach(function (s) { totalSales += Number(s.total); if (s.payment_method === 'كاش') totalCash += Number(s.total); });
  return { count: (data || []).length, totalSales: totalSales, totalCash: totalCash };
};

// ------------------------------------------------------------
// المصروفات
// ------------------------------------------------------------
api.listExpenseCategories = async function () {
  const { data, error } = await supabaseClient.from('expenses').select('main_category, sub_category');
  if (error) throw error;
  const mainSet = {}; const subByMain = {};
  (data || []).forEach(function (e) {
    if (!e.main_category) return;
    mainSet[e.main_category] = true;
    if (e.sub_category) { subByMain[e.main_category] = subByMain[e.main_category] || {}; subByMain[e.main_category][e.sub_category] = true; }
  });
  return {
    mainCategories: Object.keys(mainSet),
    subCategoriesByMain: Object.keys(subByMain).reduce(function (acc, m) { acc[m] = Object.keys(subByMain[m]); return acc; }, {})
  };
};

api.addExpense = async function (session, payload) {
  const { error } = await supabaseClient.from('expenses').insert({
    expense_date: payload.date ? new Date(payload.date).toISOString() : new Date().toISOString(),
    main_category: payload.mainCategory, sub_category: payload.subCategory || '', description: payload.description || '',
    amount: payload.amount, is_recurring: !!payload.isRecurring, recurrence_days: payload.recurrenceDays || null,
    is_fixed_asset: !!payload.isFixedAsset, payment_method: payload.paymentMethod || 'كاش',
    employee_id: payload.employeeId || null, bonus: payload.bonus || null
  });
  if (error) throw error;

  if (payload.paymentMethod !== 'آجل') {
    await supabaseClient.rpc('fn_append_cash_flow', { p_direction: 'خارج', p_source: payload.description || 'مصروف', p_amount: payload.amount, p_is_cash: payload.paymentMethod === 'كاش' });
  }
  return { success: true };
};

// ------------------------------------------------------------
// الموردون والمشتريات
// ------------------------------------------------------------
api.getSuppliers = async function () {
  const { data, error } = await supabaseClient.from('suppliers').select('*');
  if (error) throw error;
  return (data || []).map(function (s) { return { name: s.name, contact: s.contact, notes: s.notes }; });
};

api.addSupplier = async function (session, payload) {
  const { error } = await supabaseClient.from('suppliers').insert({ name: payload.name, contact: payload.contact || '' });
  if (error) { if (error.code === '23505') throw new Error('فيه مورد بنفس الاسم ده بالفعل'); throw error; }
  return { success: true };
};

api.createPurchaseOrder = async function (session, payload) {
  const { data, error } = await supabaseClient.rpc('rpc_create_purchase_order', {
    p_supplier_name: payload.supplierName, p_items: payload.items.map(function (i) { return { variant_code: i.variantCode, qty: i.qty, price: i.price }; }),
    p_payment_status: payload.paymentStatus, p_amount_paid: payload.amountPaid || 0
  });
  if (error) throw error;
  return { success: true, orderId: data[0].order_id, total: data[0].total };
};

api.listPurchaseOrders = async function () {
  const { data, error } = await supabaseClient.from('purchase_orders').select('*, suppliers(name)').order('order_date', { ascending: false }).limit(30);
  if (error) throw error;
  return (data || []).map(function (o) {
    return { orderId: o.id, supplierName: o.suppliers ? o.suppliers.name : '', total: o.total, paymentStatus: o.payment_status, amountPaid: o.amount_paid, remaining: o.remaining };
  });
};

api.paySupplierInstallment = async function (session, orderId, amount) {
  const { error } = await supabaseClient.rpc('rpc_pay_supplier_installment', { p_order_id: orderId, p_amount: amount });
  if (error) throw error;
  return { success: true };
};

api.getSupplierStatement = async function (supplierName) {
  const { data: supplier } = await supabaseClient.from('suppliers').select('id').eq('name', supplierName).single();
  if (!supplier) throw new Error('المورد غير موجود');
  const { data, error } = await supabaseClient.rpc('rpc_get_supplier_statement', { p_supplier_id: supplier.id });
  if (error) throw error;
  return data;
};

// ------------------------------------------------------------
// الأوردرات والعملاء
// ------------------------------------------------------------
api.listOrders = async function (filters) {
  filters = filters || {};
  let q = supabaseClient.from('orders').select('*').order('order_date', { ascending: false }).limit(30);
  if (filters.status) q = q.eq('status', filters.status);
  const { data, error } = await q;
  if (error) throw error;
  return (data || []).map(function (o) { return { orderId: o.easy_orders_id || o.id, customerName: o.customer_name, total: o.total, status: o.status, confirmed: o.confirmed }; });
};

api.confirmOrder = async function (session, orderId) {
  const { error } = await supabaseClient.from('orders').update({ confirmed: true }).or('easy_orders_id.eq.' + orderId + ',id.eq.' + orderId);
  if (error) throw error;
  return { success: true };
};

api.listCustomers = async function () {
  const { data, error } = await supabaseClient.from('customers').select('*').order('total_purchases', { ascending: false }).limit(50);
  if (error) throw error;
  return (data || []).map(function (c) { return { phone: c.phone, name: c.name, orderCount: c.order_count, totalPurchases: c.total_purchases }; });
};

api.getCustomerOrderHistory = async function (phone) {
  const { data: customer } = await supabaseClient.from('customers').select('*').eq('phone', phone).single();
  const { data: sales } = await supabaseClient.from('sales').select('sale_number,total').eq('customer_phone', phone);
  return {
    customer: customer ? { name: customer.name, orderCount: customer.order_count } : null,
    onlineOrders: [],
    storeSales: (sales || []).map(function (s) { return { saleId: s.sale_number, total: s.total }; })
  };
};

// ------------------------------------------------------------
// الفواتير
// ------------------------------------------------------------
api.createInvoice = async function (session, payload) {
  const remaining = payload.total - payload.paid;
  let status = 'متأخرة';
  if (payload.isCOD) status = 'تم التحصيل COD';
  else if (remaining === 0) status = 'مدفوعة بالكامل';
  else if (payload.paid > 0) status = 'مدفوعة جزئيًا';

  const { error } = await supabaseClient.from('invoices').insert({
    invoice_number: 'INV-' + Date.now(), customer_name: payload.customerName, total: payload.total, paid: payload.paid, remaining: remaining, status: status
  });
  if (error) throw error;
  return { success: true };
};

api.listInvoices = async function (filters) {
  filters = filters || {};
  let q = supabaseClient.from('invoices').select('*').order('invoice_date', { ascending: false });
  if (filters.status) q = q.eq('status', filters.status);
  const { data, error } = await q;
  if (error) throw error;
  return (data || []).map(function (i) { return { invoiceId: i.id, invoiceNumber: i.invoice_number, customerName: i.customer_name, total: i.total, paid: i.paid, remaining: i.remaining, status: i.status }; });
};

api.payInvoiceInstallment = async function (session, invoiceId, amount) {
  const { error } = await supabaseClient.rpc('rpc_pay_invoice_installment', { p_invoice_id: invoiceId, p_amount: amount });
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// رأس المال والشركاء + العهدة
// ------------------------------------------------------------
api.getCapitalSummary = async function () {
  const { data, error } = await supabaseClient.from('partners').select('*');
  if (error) throw error;
  const partners = (data || []).map(function (p) {
    return { name: p.name, balance: p.balance, ownershipPercent: p.ownership_percent, profitSharePercent: p.profit_share_percent, adminRate: p.admin_rate, adminRateType: p.admin_rate_type };
  });
  return { partners: partners, totalCapital: partners.reduce(function (s, p) { return s + Number(p.balance); }, 0) };
};

api.addCapitalMovement = async function (session, payload) {
  const { data, error } = await supabaseClient.rpc('rpc_add_capital_movement', { p_partner_name: payload.partnerName, p_type: payload.type, p_amount: payload.amount, p_notes: payload.notes || '' });
  if (error) throw error;
  return { success: true, newBalance: data };
};

api.setPartnerProfitShare = async function (session, partnerName, percent) {
  const { data: partner } = await supabaseClient.from('partners').select('admin_rate, admin_rate_type').eq('name', partnerName).single();
  const { error } = await supabaseClient.rpc('rpc_set_partner_rates', { p_partner_name: partnerName, p_profit_share: percent, p_admin_rate: partner ? partner.admin_rate : null, p_admin_rate_type: partner ? partner.admin_rate_type : null });
  if (error) throw error;
  return { success: true };
};

api.setPartnerAdminRate = async function (session, partnerName, rate, rateType) {
  const { data: partner } = await supabaseClient.from('partners').select('profit_share_percent').eq('name', partnerName).single();
  const { error } = await supabaseClient.rpc('rpc_set_partner_rates', { p_partner_name: partnerName, p_profit_share: partner ? partner.profit_share_percent : null, p_admin_rate: rate, p_admin_rate_type: rateType });
  if (error) throw error;
  return { success: true };
};

api.getPettyCashBalance = async function () {
  const { data } = await supabaseClient.from('petty_cash').select('balance_after').order('movement_date', { ascending: false }).limit(1);
  return data && data[0] ? Number(data[0].balance_after) : 0;
};

api.getPettyCashHistory = async function (limit) {
  const { data, error } = await supabaseClient.from('petty_cash').select('*').order('movement_date', { ascending: false }).limit(limit || 20);
  if (error) throw error;
  return (data || []).map(function (h) { return { date: h.movement_date, type: h.type, amount: h.amount, description: h.description, balance: h.balance_after }; });
};

api.addPettyCashMovement = async function (session, type, amount, description) {
  const { error } = await supabaseClient.rpc('rpc_add_petty_cash', { p_type: type, p_amount: amount, p_description: description || '' });
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// الموارد البشرية
// ------------------------------------------------------------
api.addEmployee = async function (session, payload) {
  const { error } = await supabaseClient.from('employees').insert({ name: payload.name, job_title: payload.jobTitle || '', base_salary: payload.baseSalary, phone: payload.phone || '' });
  if (error) throw error;
  return { success: true };
};

api.listEmployees = async function (activeOnly) {
  let q = supabaseClient.from('employees').select('*');
  if (activeOnly) q = q.eq('status', 'نشط');
  const { data, error } = await q;
  if (error) throw error;
  return (data || []).map(function (e) { return { id: e.id, name: e.name, jobTitle: e.job_title, baseSalary: e.base_salary, phone: e.phone, status: e.status }; });
};

api.recordAttendance = async function (session, employeeName, status) {
  const { data: emp } = await supabaseClient.from('employees').select('id').eq('name', employeeName).single();
  const { error } = await supabaseClient.from('attendance').insert({ employee_id: emp.id, status: status });
  if (error) throw error;
  return { success: true };
};

api.addEmployeeAdvance = async function (session, employeeName, amount) {
  const { data: emp } = await supabaseClient.from('employees').select('id').eq('name', employeeName).single();
  const { error } = await supabaseClient.from('advances').insert({ employee_id: emp.id, amount: amount });
  if (error) throw error;
  await supabaseClient.rpc('fn_append_cash_flow', { p_direction: 'خارج', p_source: 'سلفة ' + employeeName, p_amount: amount, p_is_cash: true });
  return { success: true };
};

api.runMonthlySalaries = async function (session, monthLabel) {
  const { data: employees } = await supabaseClient.from('employees').select('*').eq('status', 'نشط');
  const rows = (employees || []).map(function (e) { return { month_label: monthLabel, employee_id: e.id, base_salary: e.base_salary, net: e.base_salary }; });
  const { error } = await supabaseClient.from('salaries').upsert(rows, { onConflict: 'month_label,employee_id' });
  if (error) throw error;
  return { success: true, count: rows.length };
};

api.listSalaries = async function (monthLabel) {
  const { data, error } = await supabaseClient.from('salaries').select('*, employees(name)').eq('month_label', monthLabel);
  if (error) throw error;
  return (data || []).map(function (s) { return { employeeName: s.employees ? s.employees.name : '', net: s.net, paid: s.paid ? 'نعم' : 'لا' }; });
};

api.paySalary = async function (session, monthLabel, employeeName) {
  const { data: emp } = await supabaseClient.from('employees').select('id').eq('name', employeeName).single();
  const { data: sal } = await supabaseClient.from('salaries').select('net').eq('month_label', monthLabel).eq('employee_id', emp.id).single();
  const { error } = await supabaseClient.from('salaries').update({ paid: true }).eq('month_label', monthLabel).eq('employee_id', emp.id);
  if (error) throw error;
  await supabaseClient.rpc('fn_append_cash_flow', { p_direction: 'خارج', p_source: 'راتب ' + employeeName, p_amount: sal.net, p_is_cash: true });
  return { success: true };
};

// ------------------------------------------------------------
// المستخدمون والصلاحيات
// ------------------------------------------------------------
api.listUsers = async function () {
  const { data, error } = await supabaseClient.from('profiles').select('*');
  if (error) throw error;
  return (data || []).map(function (u) { return { username: u.username, fullName: u.full_name, role: u.role, active: u.active ? 'نعم' : 'لا', permissions: u.permissions || {} }; });
};

api.createUser = async function (adminUsername, payload) {
  const fakeEmail = payload.username.includes('@') ? payload.username : payload.username + '@internal.local';
  const { data, error } = await supabaseClient.auth.admin.createUser({ email: fakeEmail, password: payload.password, email_confirm: true });
  if (error) throw new Error('محتاجة صلاحية Admin API — راجعي ملاحظة الإعداد في دليل التشغيل');
  const { error: profileErr } = await supabaseClient.from('profiles').insert({ id: data.user.id, username: payload.username, full_name: payload.fullName || payload.username, role: payload.role || 'بائع', permissions: payload.permissions || {} });
  if (profileErr) throw profileErr;
  return { success: true };
};

api.updateUserPermissions = async function (adminUsername, targetUsername, newPermissions) {
  const { error } = await supabaseClient.from('profiles').update({ permissions: newPermissions }).eq('username', targetUsername);
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// الإعدادات
// ------------------------------------------------------------
api.getSettings = async function () {
  const { data, error } = await supabaseClient.from('settings').select('*');
  if (error) throw error;
  const settings = {};
  (data || []).forEach(function (r) { settings[r.key] = r.value; });
  return settings;
};

api.updateSetting = async function (session, key, value) {
  const { error } = await supabaseClient.from('settings').upsert({ key: key, value: String(value) });
  if (error) throw error;
  return { success: true };
};

api.updateSettingsBulk = async function (session, settingsObject) {
  const rows = Object.keys(settingsObject).map(function (k) { return { key: k, value: String(settingsObject[k]) }; });
  const { error } = await supabaseClient.from('settings').upsert(rows);
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// شجرة الحسابات (Chart of Accounts)
// ------------------------------------------------------------
api.getAccounts = async function () {
  const { data, error } = await supabaseClient.from('accounts').select('*').eq('active', true).order('code');
  if (error) throw error;
  return (data || []).map(function (a) {
    return { code: a.code, name: a.name, type: a.type, isGroup: a.is_group, parentId: a.parent_id };
  });
};

api.addAccount = async function (session, payload) {
  const { data, error } = await supabaseClient.rpc('rpc_add_account', {
    p_name: payload.name, p_type: payload.type, p_parent_code: payload.parentCode || null, p_is_group: !!payload.isGroup
  });
  if (error) throw error;
  return { success: true, code: data[0].code };
};

// ------------------------------------------------------------
// أرصدة أول مدة (Opening Balances)
// ------------------------------------------------------------
api.listOpeningBalances = async function () {
  const { data, error } = await supabaseClient.from('opening_balances').select('*, accounts(name,code), product_variants(code)').order('created_at', { ascending: false });
  if (error) throw error;
  return (data || []).map(function (o) {
    return {
      id: o.id, asOfDate: o.as_of_date, accountName: o.accounts ? (o.accounts.code + ' - ' + o.accounts.name) : '',
      variantCode: o.product_variants ? o.product_variants.code : '', amount: o.amount, quantity: o.quantity,
      description: o.description, locked: o.locked
    };
  });
};

api.addOpeningBalance = async function (session, payload) {
  let accountId = null, variantId = null;
  if (payload.accountCode) {
    const { data: acc } = await supabaseClient.from('accounts').select('id').eq('code', payload.accountCode).single();
    accountId = acc ? acc.id : null;
  }
  if (payload.variantCode) {
    const { data: v } = await supabaseClient.from('product_variants').select('id').eq('code', payload.variantCode).single();
    variantId = v ? v.id : null;
  }
  const { error } = await supabaseClient.from('opening_balances').insert({
    as_of_date: payload.asOfDate, account_id: accountId, variant_id: variantId,
    amount: payload.amount || 0, quantity: payload.quantity || null, description: payload.description || ''
  });
  if (error) throw error;
  return { success: true };
};

api.lockOpeningBalances = async function (session) {
  const { error } = await supabaseClient.rpc('rpc_lock_opening_balances');
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// الخزنة والبنوك المتعددة
// ------------------------------------------------------------
api.listTreasuryAccounts = async function () {
  const { data, error } = await supabaseClient.from('treasury_accounts').select('*').eq('active', true).order('type');
  if (error) throw error;
  return (data || []).map(function (t) {
    return { id: t.id, name: t.name, type: t.type, bankName: t.bank_name, accountNumber: t.account_number, currentBalance: t.current_balance };
  });
};

api.addTreasuryAccount = async function (session, payload) {
  const { error } = await supabaseClient.from('treasury_accounts').insert({
    name: payload.name, type: payload.type, bank_name: payload.bankName || '', account_number: payload.accountNumber || '',
    opening_balance: payload.openingBalance || 0, current_balance: payload.openingBalance || 0
  });
  if (error) throw error;
  return { success: true };
};

api.transferBetweenTreasuries = async function (session, fromId, toId, amount, notes) {
  const { error } = await supabaseClient.rpc('rpc_transfer_between_treasuries', { p_from_id: fromId, p_to_id: toId, p_amount: amount, p_notes: notes || '' });
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// سلة المحذوفات
// ------------------------------------------------------------
api.listDeletedRecords = async function () {
  const results = [];
  const { data: products } = await supabaseClient.from('products').select('id,name,code,deleted_at').not('deleted_at', 'is', null);
  (products || []).forEach(function (p) { results.push({ table: 'products', tableLabel: 'منتج', id: p.id, label: p.name + ' (' + p.code + ')', deletedAt: p.deleted_at }); });

  const { data: variants } = await supabaseClient.from('product_variants').select('id,code,deleted_at').not('deleted_at', 'is', null);
  (variants || []).forEach(function (v) { results.push({ table: 'product_variants', tableLabel: 'متغير منتج', id: v.id, label: v.code, deletedAt: v.deleted_at }); });

  const { data: customers } = await supabaseClient.from('customers').select('phone,name,deleted_at').not('deleted_at', 'is', null);
  (customers || []).forEach(function (c) { results.push({ table: 'customers', tableLabel: 'عميل', id: c.phone, label: (c.name || c.phone), deletedAt: c.deleted_at }); });

  const { data: suppliers } = await supabaseClient.from('suppliers').select('id,name,deleted_at').not('deleted_at', 'is', null);
  (suppliers || []).forEach(function (s) { results.push({ table: 'suppliers', tableLabel: 'مورد', id: s.id, label: s.name, deletedAt: s.deleted_at }); });

  const { data: employees } = await supabaseClient.from('employees').select('id,name,deleted_at').not('deleted_at', 'is', null);
  (employees || []).forEach(function (e) { results.push({ table: 'employees', tableLabel: 'موظف', id: e.id, label: e.name, deletedAt: e.deleted_at }); });

  results.sort(function (a, b) { return new Date(b.deletedAt) - new Date(a.deletedAt); });
  return results;
};

api.softDeleteRecord = async function (session, table, id) {
  const { error } = await supabaseClient.rpc('rpc_soft_delete', { p_table: table, p_id: String(id) });
  if (error) throw error;
  return { success: true };
};

api.restoreDeletedRecord = async function (session, table, id) {
  const { error } = await supabaseClient.rpc('rpc_restore_deleted', { p_table: table, p_id: String(id) });
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// مراكز التكلفة
// ------------------------------------------------------------
api.listCostCenters = async function () {
  const { data, error } = await supabaseClient.from('cost_centers').select('*').eq('active', true).order('name');
  if (error) throw error;
  return (data || []).map(function (c) { return { id: c.id, name: c.name, description: c.description }; });
};

api.addCostCenter = async function (session, payload) {
  const { error } = await supabaseClient.from('cost_centers').insert({ name: payload.name, description: payload.description || '' });
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// نقل مخزون بين المخازن/الفروع
// ------------------------------------------------------------
api.transferStock = async function (session, payload) {
  const { data, error } = await supabaseClient.rpc('rpc_transfer_stock', {
    p_from_warehouse_id: payload.fromWarehouseId, p_to_warehouse_id: payload.toWarehouseId,
    p_items: payload.items, p_notes: payload.notes || ''
  });
  if (error) throw error;
  return { success: true, transferNumber: data[0].transfer_number };
};

api.listStockTransfers = async function (limit) {
  const { data, error } = await supabaseClient.from('stock_transfers')
    .select('*, from:warehouses!stock_transfers_from_warehouse_id_fkey(name), to:warehouses!stock_transfers_to_warehouse_id_fkey(name)')
    .order('transfer_date', { ascending: false }).limit(limit || 20);
  if (error) throw error;
  return (data || []).map(function (t) {
    return { transferNumber: t.transfer_number, date: t.transfer_date, fromName: t.from ? t.from.name : '', toName: t.to ? t.to.name : '', notes: t.notes };
  });
};

// ------------------------------------------------------------
// طلبات الشراء والاعتماد
// ------------------------------------------------------------
api.createPurchaseRequest = async function (session, payload) {
  const { data, error } = await supabaseClient.rpc('rpc_create_purchase_request', {
    p_supplier_name: payload.supplierName || '', p_items: payload.items, p_notes: payload.notes || ''
  });
  if (error) throw error;
  return { success: true, requestNumber: data[0].request_number };
};

api.listPurchaseRequests = async function () {
  const { data, error } = await supabaseClient.from('purchase_requests').select('*').order('request_date', { ascending: false });
  if (error) throw error;
  return (data || []).map(function (r) {
    return { id: r.id, requestNumber: r.request_number, date: r.request_date, supplierName: r.supplier_name, notes: r.notes, status: r.status };
  });
};

api.approvePurchaseRequest = async function (session, requestId, approve) {
  const { error } = await supabaseClient.rpc('rpc_approve_purchase_request', { p_request_id: requestId, p_approve: approve });
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// الربحية الحقيقية
// ------------------------------------------------------------
api.getProfitabilityByProduct = async function (start, end) {
  const { data, error } = await supabaseClient.rpc('rpc_profitability_by_product', { p_start: start, p_end: end });
  if (error) throw error;
  return data || [];
};

api.getProfitabilityByCustomer = async function (start, end) {
  const { data, error } = await supabaseClient.rpc('rpc_profitability_by_customer', { p_start: start, p_end: end });
  if (error) throw error;
  return data || [];
};

// ------------------------------------------------------------
// العملات وأسعار الصرف
// ------------------------------------------------------------
api.listCurrencies = async function () {
  const { data, error } = await supabaseClient.from('currencies').select('*').order('is_base', { ascending: false });
  if (error) throw error;
  return data || [];
};

api.addCurrency = async function (session, code, name) {
  const { error } = await supabaseClient.from('currencies').insert({ code: code, name: name, is_base: false });
  if (error) throw error;
  return { success: true };
};

api.listExchangeRates = async function () {
  const { data, error } = await supabaseClient.from('exchange_rates').select('*, currencies(name)').order('rate_date', { ascending: false }).limit(30);
  if (error) throw error;
  return (data || []).map(function (r) { return { currencyCode: r.currency_code, currencyName: r.currencies ? r.currencies.name : '', date: r.rate_date, rate: r.rate_to_base }; });
};

api.setExchangeRate = async function (session, currencyCode, rate, date) {
  const { error } = await supabaseClient.rpc('rpc_set_exchange_rate', { p_currency_code: currencyCode, p_rate: rate, p_date: date || new Date().toISOString().slice(0, 10) });
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// الشيكات
// ------------------------------------------------------------
api.listChecks = async function () {
  const { data, error } = await supabaseClient.from('checks').select('*').order('due_date');
  if (error) throw error;
  return (data || []).map(function (c) {
    return { id: c.id, checkNumber: c.check_number, direction: c.direction, partyName: c.party_name, amount: c.amount, dueDate: c.due_date, bankName: c.bank_name, status: c.status };
  });
};

api.addCheck = async function (session, payload) {
  const { error } = await supabaseClient.from('checks').insert({
    check_number: payload.checkNumber, direction: payload.direction, party_name: payload.partyName,
    amount: payload.amount, due_date: payload.dueDate, bank_name: payload.bankName || '', notes: payload.notes || '', created_by: session.id || null
  });
  if (error) throw error;
  return { success: true };
};

api.updateCheckStatus = async function (session, checkId, status) {
  const { error } = await supabaseClient.rpc('rpc_update_check_status', { p_check_id: checkId, p_status: status });
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// البحث الموحّد (Smart Search)
// ------------------------------------------------------------
api.globalSearch = async function (query) {
  const { data, error } = await supabaseClient.rpc('rpc_global_search', { p_query: query });
  if (error) throw error;
  return data || {};
};

// ------------------------------------------------------------
// الإشعارات الداخلية (جدول notifications الحقيقي)
// ------------------------------------------------------------
api.getDbNotifications = async function () {
  const { data: { user } } = await supabaseClient.auth.getUser();
  if (!user) return [];
  const { data, error } = await supabaseClient.from('notifications').select('*')
    .or('user_id.eq.' + user.id + ',user_id.is.null').eq('is_read', false).order('created_at', { ascending: false }).limit(20);
  if (error) throw error;
  return (data || []).map(function (n) { return { id: n.id, title: n.title, body: n.body, linkPage: n.link_page, time: n.created_at }; });
};

api.markNotificationRead = async function (id) {
  const { error } = await supabaseClient.from('notifications').update({ is_read: true }).eq('id', id);
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// المرفقات
// ------------------------------------------------------------
api.listAttachments = async function (entityType, entityId) {
  const { data, error } = await supabaseClient.from('attachments').select('*').eq('entity_type', entityType).eq('entity_id', String(entityId)).order('uploaded_at', { ascending: false });
  if (error) throw error;
  return (data || []).map(function (a) { return { id: a.id, fileName: a.file_name, fileUrl: a.file_url, uploadedAt: a.uploaded_at }; });
};

api.uploadAttachment = async function (session, entityType, entityId, file) {
  const { data: { user } } = await supabaseClient.auth.getUser();
  const path = entityType + '/' + entityId + '/' + Date.now() + '_' + file.name;
  const { error: upErr } = await supabaseClient.storage.from('attachments').upload(path, file);
  if (upErr) throw upErr;
  const { data: urlData } = supabaseClient.storage.from('attachments').getPublicUrl(path);
  const { error } = await supabaseClient.from('attachments').insert({
    entity_type: entityType, entity_id: String(entityId), file_name: file.name, file_url: urlData.publicUrl, uploaded_by: user ? user.id : null
  });
  if (error) throw error;
  return { success: true, url: urlData.publicUrl };
};

api.deleteAttachment = async function (id, filePath) {
  const { error } = await supabaseClient.from('attachments').delete().eq('id', id);
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// الذكاء الاصطناعي — تحليلات إحصائية + رأي Gemini النصي (اختياري)
// ------------------------------------------------------------
api.getStagnantStock = async function (days) {
  const { data, error } = await supabaseClient.rpc('rpc_stagnant_stock', { p_days: days || 60 });
  if (error) throw error;
  return data || [];
};

api.getSalesForecast = async function () {
  const { data, error } = await supabaseClient.rpc('rpc_sales_forecast');
  if (error) throw error;
  return data || {};
};

api.getAiInsights = async function (contextText) {
  const { data: { session } } = await supabaseClient.auth.getSession();
  const res = await fetch(SUPABASE_URL + '/functions/v1/ai-insights', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + (session ? session.access_token : SUPABASE_ANON_KEY) },
    body: JSON.stringify({ contextText: contextText })
  });
  const data = await res.json();
  if (data.error) throw new Error(data.error);
  return data.text || 'مفيش رد من الـAI حاليًا، جربي تاني.';
};
