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

// إعدادات البراند العامة (اسم، لوجو، ألوان) — بتتقرا من غير تسجيل دخول
// عشان تتطبق على شاشة تسجيل الدخول نفسها والتاب
api.getPublicBranding = async function () {
  try {
    const { data } = await supabaseClient.from('settings').select('key,value').in('key', ['brandName', 'logoUrl', 'accentColor']);
    const s = {};
    (data || []).forEach(function (r) { s[r.key] = r.value; });
    return s;
  } catch (e) {
    return {};
  }
};

api.getAppShellData = async function () {
  const { data: { user } } = await supabaseClient.auth.getUser();
  if (!user) throw new Error('الجلسة منتهية');

  const { data: profile } = await supabaseClient.from('profiles').select('*').eq('id', user.id).single();
  const { data: settingsRows } = await supabaseClient.from('settings').select('*');
  const { data: warehouses } = await supabaseClient.from('warehouses').select('id');

  const settings = {};
  (settingsRows || []).forEach(function (r) { settings[r.key] = r.value; });

  if (profile.role === 'أدمن') {
    supabaseClient.rpc('rpc_seed_default_chart_of_accounts').then(function () {}).catch(function () {});
  }

  return {
    user: { username: profile.username, fullName: profile.full_name, role: profile.role, isCashier: profile.role === 'كاشير', permissions: profile.permissions || {} },
    settings: {
      brandName: settings.brandName, logoUrl: settings.logoUrl, productIcon: settings.productIcon || '📦', primaryColor: settings.primaryColor,
      defaultTreasuryAccountId: settings.defaultTreasuryAccountId,
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
  const { data, error } = await supabaseClient.from('product_tree').select('*').eq('active', true).is('deleted_at', null);
  if (error) throw error;
  const main = data.filter(function (c) { return c.type === 'رئيسية'; }).map(function (c) { return { id: c.id, code: c.code, name: c.name, type: c.type }; });
  const sub = data.filter(function (c) { return c.type === 'فرعية'; }).map(function (c) {
    const parent = data.find(function (p) { return p.id === c.parent_id; });
    return { id: c.id, code: c.code, name: c.name, type: c.type, parent: parent ? parent.code : null };
  });
  return { mainCategories: main, subCategories: sub };
};

api.createCategory = async function (session, payload) {
  const { data, error } = await supabaseClient.rpc('rpc_create_category', { p_name: payload.name, p_type: payload.type, p_parent_code: payload.parentCode || null });
  if (error) throw error;
  return data[0];
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
  const { data: products, error } = await supabaseClient.from('products').select('*, product_variants(*), sub_category:sub_category_id(code, name), main_category:main_category_id(code, name)').is('deleted_at', null);
  if (error) throw error;
  const result = { products: {} };
  products.forEach(function (p) {
    result.products[p.code] = {
      id: p.id, code: p.code, name: p.name, basePrice: p.base_price, image: p.image_url, hasVariants: p.has_variants, status: p.status,
      subCategoryCode: p.sub_category ? p.sub_category.code : '',
      subCategoryName: p.sub_category ? p.sub_category.name : '',
      mainCategoryName: p.main_category ? p.main_category.name : '',
      variants: (p.product_variants || []).filter(function (v) { return !v.deleted_at; }).map(function (v) {
        return { code: v.code, productCode: p.code, color: v.color, size: v.size, quantity: v.quantity, cost: v.cost, specialPrice: v.special_price, warehouseId: v.warehouse_id, lowStockThreshold: v.low_stock_threshold, status: v.status };
      })
    };
  });
  return { products: result.products };
};

// تعديل اسم فئة (رئيسية أو فرعية)
api.updateCategory = async function (session, code, newName) {
  const { error } = await supabaseClient.rpc('rpc_update_category', { p_code: code, p_new_name: newName });
  if (error) throw error;
  return { success: true };
};

// تعديل بيانات منتج موجود (الاسم/السعر/الفئة الفرعية)
api.updateProduct = async function (session, payload) {
  const { error } = await supabaseClient.rpc('rpc_update_product', {
    p_code: payload.code, p_name: payload.name, p_base_price: payload.basePrice,
    p_sub_category_code: payload.subCategory, p_image: payload.image || null, p_description: payload.description || null
  });
  if (error) throw error;
  return { success: true };
};

// إضافة منتج + كل متغيراته (ألوان/مقاسات) دفعة واحدة في نداء واحد Atomic
api.addProductWithVariants = async function (session, payload) {
  const { data, error } = await supabaseClient.rpc('rpc_add_product_with_variants', {
    p_name: payload.name, p_sub_category_code: payload.subCategory, p_base_price: payload.basePrice,
    p_variants: payload.variants || [], p_image: payload.image || '', p_description: payload.description || '',
    p_manual_code: payload.manualCode || null
  });
  if (error) throw error;
  return { productCode: data.productCode, variantCodes: data.variantCodes || [] };
};

api.searchProducts = async function (query, limit) {
  let req = supabaseClient.from('products').select('*, product_variants(*)').eq('status', 'نشط').order('name').limit(limit || 15);
  if (query) req = req.ilike('name', '%' + query + '%');
  const { data, error } = await req;
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
    p_sale_date: payload.date ? new Date(payload.date).toISOString() : new Date().toISOString(),
    p_treasury_account_id: payload.treasuryAccountId || null
  });
  if (error) throw error;
  return { success: true, saleId: data[0].sale_id, saleNumber: data[0].sale_number, total: data[0].total };
};

api.posSale = async function (session, cart, discount, paymentMethod, treasuryAccountId, customerName, customerPhone) {
  return api.recordSale(session, { source: 'محل', items: cart, discount: discount, paymentMethod: paymentMethod, treasuryAccountId: treasuryAccountId, customerName: customerName, customerPhone: customerPhone });
};

api.recordReturn = async function (session, saleId, items, isFull, treasuryAccountId) {
  const { error } = await supabaseClient.rpc('rpc_record_return', {
    p_sale_id: saleId, p_items: items.map(function (i) { return { variant_code: i.variantCode, qty: i.qty, price: i.price }; }), p_is_full: isFull,
    p_treasury_account_id: treasuryAccountId || null
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

api.recordPartialReturn = async function (session, saleNumber, items, isFull, treasuryAccountId) {
  const { data: sale, error: e1 } = await supabaseClient.from('sales').select('id').eq('sale_number', saleNumber).single();
  if (e1) throw e1;
  return api.recordReturn(session, sale.id, items, isFull, treasuryAccountId);
};

api.recordStandaloneReturn = async function (session, items, paymentMethod, treasuryAccountId, notes, saleReference) {
  const { error } = await supabaseClient.rpc('rpc_record_standalone_return', {
    p_items: items.map(function (i) { return { variant_code: i.variantCode, qty: i.qty, price: i.price }; }),
    p_payment_method: paymentMethod || 'كاش', p_treasury_account_id: treasuryAccountId || null,
    p_notes: notes || '', p_sale_reference: saleReference || null
  });
  if (error) throw error;
  return { success: true };
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

api.getExpenses = async function (limit) {
  const { data, error } = await supabaseClient.from('expenses')
    .select('id, expense_date, main_category, sub_category, description, amount, payment_method, treasury_accounts(name)')
    .order('expense_date', { ascending: false }).limit(limit || 50);
  if (error) throw error;
  return (data || []).map(function (e) {
    return {
      id: e.id, date: e.expense_date, mainCategory: e.main_category, subCategory: e.sub_category,
      description: e.description, amount: e.amount, paymentMethod: e.payment_method,
      treasuryAccountName: e.treasury_accounts ? e.treasury_accounts.name : (e.payment_method === 'آجل' ? 'آجل (لسه متدفعش)' : '—')
    };
  });
};

api.getExpensesInRange = async function (startDate, endDate) {
  const { data, error } = await supabaseClient.from('expenses')
    .select('id, expense_date, main_category, sub_category, description, amount, payment_method, treasury_accounts(name)')
    .gte('expense_date', startDate).lte('expense_date', endDate + 'T23:59:59')
    .order('expense_date', { ascending: false });
  if (error) throw error;
  return (data || []).map(function (e) {
    return {
      id: e.id, date: e.expense_date, mainCategory: e.main_category, subCategory: e.sub_category,
      description: e.description, amount: e.amount, paymentMethod: e.payment_method,
      treasuryAccountName: e.treasury_accounts ? e.treasury_accounts.name : (e.payment_method === 'آجل' ? 'آجل (لسه متدفعش)' : '—')
    };
  });
};

api.addExpense = async function (session, payload) {
  const { data, error } = await supabaseClient.rpc('rpc_add_expense', {
    p_main_category: payload.mainCategory, p_amount: payload.amount, p_sub_category: payload.subCategory || '', p_description: payload.description || '',
    p_is_recurring: !!payload.isRecurring, p_recurrence_days: payload.recurrenceDays || null,
    p_is_fixed_asset: !!payload.isFixedAsset, p_payment_method: payload.paymentMethod || 'كاش',
    p_employee_id: payload.employeeId || null, p_bonus: payload.bonus || null,
    p_expense_date: payload.date ? new Date(payload.date).toISOString() : new Date().toISOString(),
    p_treasury_account_id: payload.treasuryAccountId || null,
    p_useful_life_months: payload.usefulLifeMonths || 36, p_depreciation_method: payload.depreciationMethod || 'شهري'
  });
  if (error) throw error;
  return { success: true, expenseId: data };
};

api.convertCategoryToSub = async function (session, code, newParentCode) {
  const { error } = await supabaseClient.rpc('rpc_convert_category_to_sub', { p_code: code, p_new_parent_code: newParentCode });
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// الموردون والمشتريات
// ------------------------------------------------------------
api.getSuppliers = async function () {
  const { data, error } = await supabaseClient.from('suppliers').select('id, name, contact, notes, purchase_orders(remaining, amount_paid, total)');
  if (error) throw error;
  return (data || []).map(function (s) {
    const orders = s.purchase_orders || [];
    const totalRemaining = orders.reduce(function (sum, o) { return sum + Number(o.remaining); }, 0);
    const totalPaid = orders.reduce(function (sum, o) { return sum + Number(o.amount_paid); }, 0);
    let dueStatus = 'لا مشتريات';
    if (orders.length > 0) {
      if (totalRemaining <= 0) dueStatus = 'مدفوع بالكامل';
      else if (totalPaid > 0) dueStatus = 'مدفوع جزئيًا';
      else dueStatus = 'غير مدفوع';
    }
    return { name: s.name, contact: s.contact, notes: s.notes, totalRemaining: totalRemaining, dueStatus: dueStatus };
  });
};

api.setVariantSalePrice = async function (session, variantCode, price) {
  const { error } = await supabaseClient.from('product_variants').update({ special_price: price }).eq('code', variantCode);
  if (error) throw error;
  return { success: true };
};

api.updateVariant = async function (session, variantCode, payload) {
  const { error } = await supabaseClient.from('product_variants').update({
    cost: payload.cost, quantity: payload.quantity, special_price: payload.specialPrice || null, low_stock_threshold: payload.lowStockThreshold
  }).eq('code', variantCode);
  if (error) throw error;
  return { success: true };
};

api.addSupplier = async function (session, payload) {
  const { error } = await supabaseClient.from('suppliers').insert({ name: payload.name, contact: payload.contact || '' });
  if (error) { if (error.code === '23505') throw new Error('فيه مورد بنفس الاسم ده بالفعل'); throw error; }
  return { success: true };
};

api.createPurchaseOrder = async function (session, payload) {
  const { data, error } = await supabaseClient.rpc('rpc_create_purchase_order', {
    p_supplier_name: payload.supplierName, p_items: payload.items.map(function (i) { return { variant_code: i.variantCode, qty: i.qty, price: i.price }; }),
    p_payment_status: payload.paymentStatus, p_amount_paid: payload.amountPaid || 0, p_treasury_account_id: payload.treasuryAccountId || null
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

api.paySupplierInstallment = async function (session, orderId, amount, treasuryAccountId) {
  const { error } = await supabaseClient.rpc('rpc_pay_supplier_installment', { p_order_id: orderId, p_amount: amount, p_treasury_account_id: treasuryAccountId || null });
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
  const { data: sales } = await supabaseClient.from('sales').select('sale_number,total,sale_date').eq('customer_phone', phone).order('sale_date', { ascending: false });
  const { data: orders } = await supabaseClient.from('orders').select('id,easy_orders_id,total,status,order_date').eq('customer_phone', phone).order('order_date', { ascending: false });
  return {
    customer: customer ? { name: customer.name, phone: customer.phone, orderCount: customer.order_count, totalPurchases: customer.total_purchases, notes: customer.notes } : null,
    onlineOrders: (orders || []).map(function (o) { return { orderId: o.easy_orders_id || o.id, total: o.total, status: o.status, date: o.order_date }; }),
    storeSales: (sales || []).map(function (s) { return { saleId: s.sale_number, total: s.total, date: s.sale_date }; })
  };
};

// ------------------------------------------------------------
// الفواتير
// ------------------------------------------------------------
api.createInvoice = async function (session, payload) {
  const { data, error } = await supabaseClient.rpc('rpc_create_quick_invoice', {
    p_customer_name: payload.customerName, p_total: payload.total, p_paid: payload.paid || 0, p_is_cod: !!payload.isCOD
  });
  if (error) throw error;
  return { success: true, invoiceNumber: data };
};

api.addCustomerOpeningBalance = async function (session, payload) {
  const { data, error } = await supabaseClient.rpc('rpc_add_customer_opening_balance', {
    p_customer_name: payload.customerName, p_customer_phone: payload.customerPhone || '', p_amount: payload.amount,
    p_as_of_date: payload.asOfDate, p_description: payload.description || ''
  });
  if (error) throw error;
  return { success: true, invoiceNumber: data };
};

api.addOpeningInventory = async function (session, payload) {
  const { data, error } = await supabaseClient.rpc('rpc_add_opening_inventory', {
    p_supplier_name: payload.supplierName,
    p_items: payload.items.map(function (i) { return { variant_code: i.variantCode, qty: i.qty, price: i.price }; }),
    p_owed_amount: payload.owedAmount || 0
  });
  if (error) throw error;
  const row = (data && data[0]) || {};
  return { total: row.total, owed: row.owed, settledFromCapital: row.settled_from_capital, orderNumber: row.order_number };
};

api.addOpeningFixedAsset = async function (session, payload) {
  const { data, error } = await supabaseClient.rpc('rpc_add_opening_fixed_asset', {
    p_description: payload.description, p_amount: payload.amount, p_useful_life_months: payload.usefulLifeMonths,
    p_already_elapsed_months: payload.alreadyElapsedMonths || 0, p_depreciation_method: payload.depreciationMethod || 'شهري'
  });
  if (error) throw error;
  return { id: data };
};

api.finalizeOpeningBalanceToCapitalMulti = async function (session, partners) {
  const { data, error } = await supabaseClient.rpc('rpc_finalize_opening_balance_to_capital_multi', { p_partners: partners });
  if (error) throw error;
  return { amount: data };
};

api.addTreasuryOpeningBalance = async function (session, payload) {
  const { error } = await supabaseClient.rpc('rpc_add_treasury_opening_balance', {
    p_treasury_account_id: payload.treasuryAccountId, p_amount: payload.amount,
    p_as_of_date: payload.asOfDate, p_description: payload.description || ''
  });
  if (error) throw error;
  return { success: true };
};

// فتح فاتورة عميل كـ"حساب مفتوح" فاضي — تُضاف عليها أصناف بعد كده على أكتر من دفعة
api.openInvoice = async function (session, payload) {
  const { data, error } = await supabaseClient.rpc('rpc_open_invoice', {
    p_customer_name: payload.customerName, p_customer_phone: payload.customerPhone || '', p_notes: payload.notes || ''
  });
  if (error) throw error;
  return { invoiceId: data[0].invoice_id, invoiceNumber: data[0].invoice_number };
};

// إضافة أصناف حقيقية من المخزون لفاتورة موجودة (بتخصم من المخزون وتحدّث الإجمالي/المتبقي فورًا)
api.addItemsToInvoice = async function (session, invoiceId, items) {
  const { data, error } = await supabaseClient.rpc('rpc_add_items_to_invoice', {
    p_invoice_id: invoiceId,
    p_items: items.map(function (i) { return { variant_code: i.variantCode, qty: i.qty, price: i.price }; })
  });
  if (error) throw error;
  return data;
};

// تفاصيل فاتورة كاملة: البيانات + كل الأصناف اللي اتضافت عليها من كل الدفعات
api.getInvoiceDetails = async function (invoiceId) {
  const { data, error } = await supabaseClient.rpc('rpc_get_invoice_details', { p_invoice_id: invoiceId });
  if (error) throw error;
  return data;
};

api.listInvoices = async function (filters) {
  filters = filters || {};
  let q = supabaseClient.from('invoices').select('*').order('invoice_date', { ascending: false });
  if (filters.status) q = q.eq('status', filters.status);
  const { data, error } = await q;
  if (error) throw error;
  return (data || []).map(function (i) { return { invoiceId: i.id, invoiceNumber: i.invoice_number, customerName: i.customer_name, total: i.total, paid: i.paid, remaining: i.remaining, status: i.status }; });
};

api.payInvoiceInstallment = async function (session, invoiceId, amount, treasuryAccountId) {
  const { error } = await supabaseClient.rpc('rpc_pay_invoice_installment', { p_invoice_id: invoiceId, p_amount: amount, p_treasury_account_id: treasuryAccountId || null });
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
    return { name: p.name, balance: p.balance, ownershipPercent: p.ownership_percent, profitSharePercent: p.profit_share_percent, adminRate: p.admin_rate, adminRateType: p.admin_rate_type, active: p.active !== false };
  });
  return { partners: partners, totalCapital: partners.reduce(function (s, p) { return s + Number(p.balance); }, 0) };
};

api.addCapitalMovement = async function (session, payload) {
  const { data, error } = await supabaseClient.rpc('rpc_add_capital_movement', {
    p_partner_name: payload.partnerName, p_type: payload.type, p_amount: payload.amount, p_notes: payload.notes || '',
    p_treasury_account_id: payload.treasuryAccountId || null
  });
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

api.setPartnerActive = async function (session, partnerName, active) {
  const { error } = await supabaseClient.rpc('rpc_set_partner_active', { p_partner_name: partnerName, p_active: active });
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

api.addPettyCashMovement = async function (session, type, amount, description, treasuryAccountId) {
  const { error } = await supabaseClient.rpc('rpc_add_petty_cash', { p_type: type, p_amount: amount, p_description: description || '', p_treasury_account_id: treasuryAccountId || null });
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

api.addEmployeeAdvance = async function (session, employeeName, amount, treasuryAccountId) {
  const { error } = await supabaseClient.rpc('rpc_add_employee_advance', { p_employee_name: employeeName, p_amount: amount, p_treasury_account_id: treasuryAccountId || null });
  if (error) throw error;
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
  let q = supabaseClient.from('salaries').select('*, employees(name)').order('month_label', { ascending: false });
  if (monthLabel) q = q.eq('month_label', monthLabel);
  const { data, error } = await q;
  if (error) throw error;
  return (data || []).map(function (s) { return { employeeName: s.employees ? s.employees.name : '', monthLabel: s.month_label, net: s.net, netAmount: s.net, paid: s.paid ? 'نعم' : 'لا' }; });
};

api.paySalary = async function (session, monthLabel, employeeName, treasuryAccountId) {
  const { error } = await supabaseClient.rpc('rpc_pay_salary', { p_month_label: monthLabel, p_employee_name: employeeName, p_treasury_account_id: treasuryAccountId || null });
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// المستخدمون والصلاحيات
// ------------------------------------------------------------
api.listUsers = async function () {
  const { data, error } = await supabaseClient.from('profiles').select('*');
  if (error) throw error;
  return (data || []).map(function (u) { return { id: u.id, username: u.username, fullName: u.full_name, role: u.role, active: u.active ? 'نعم' : 'لا', permissions: u.permissions || {} }; });
};

api.createUser = async function (adminUsername, payload) {
  const { data: { session } } = await supabaseClient.auth.getSession();
  const res = await fetch(SUPABASE_URL + '/functions/v1/create-employee', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + (session ? session.access_token : SUPABASE_ANON_KEY) },
    body: JSON.stringify(payload)
  });
  const data = await res.json();
  if (data.error) throw new Error(data.error);
  return { success: true };
};

api.deleteUser = async function (employeeId) {
  const { data: { session } } = await supabaseClient.auth.getSession();
  const res = await fetch(SUPABASE_URL + '/functions/v1/delete-employee', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + (session ? session.access_token : SUPABASE_ANON_KEY) },
    body: JSON.stringify({ employee_id: employeeId })
  });
  const data = await res.json();
  if (data.error) throw new Error(data.error);
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
// نسخة احتياطية كاملة من البيانات (تصدير/استرجاع) — من الإعدادات
// ------------------------------------------------------------
const BACKUP_TABLES_ORDER = [
  'settings', 'accounts', 'cost_centers', 'currencies', 'exchange_rates', 'seasons', 'accounting_periods',
  'warehouses', 'product_tree', 'products', 'product_variants', 'cost_history',
  'suppliers', 'purchase_orders', 'purchase_order_items', 'supplier_payments', 'purchase_requests', 'purchase_request_items',
  'customers', 'orders', 'order_items', 'sales', 'sale_items', 'invoices',
  'treasury_accounts', 'cash_flow', 'checks', 'petty_cash',
  'partners', 'capital_movements', 'admin_rights', 'profits_distribution',
  'employees', 'salaries', 'advances', 'attendance', 'fixed_assets',
  'expenses', 'other_revenue', 'journal_entries', 'opening_balances',
  'stock_transfers', 'stock_transfer_items', 'notifications', 'operations_log', 'webhooks_log', 'backup_log', 'attachments',
  'profiles' // بيانات مرجعية بس — مش بترجع تلقائي عند الاسترجاع (مرتبطة بحسابات الدخول)
];

api.exportFullBackup = async function () {
  const result = { exportedAt: new Date().toISOString(), tables: {} };
  for (const t of BACKUP_TABLES_ORDER) {
    try {
      const { data, error } = await supabaseClient.from(t).select('*');
      result.tables[t] = error ? [] : (data || []);
    } catch (e) { result.tables[t] = []; }
  }
  return result;
};

api.restoreFromBackup = async function (backupData) {
  const report = [];
  for (const t of BACKUP_TABLES_ORDER) {
    if (t === 'profiles') continue; // لازم تتضاف يدويًا من "المستخدمون" — مرتبطة بحسابات الدخول
    const rows = (backupData.tables && backupData.tables[t]) || [];
    if (rows.length === 0) { report.push({ table: t, status: 'تخطي (فاضي)' }); continue; }
    try {
      const { error } = await supabaseClient.from(t).upsert(rows);
      report.push({ table: t, status: error ? ('خطأ: ' + error.message) : ('تم (' + rows.length + ' صف)') });
    } catch (e) { report.push({ table: t, status: 'خطأ: ' + e.message }); }
  }
  return report;
};
api.getAccounts = async function () {
  const { data, error } = await supabaseClient.from('accounts').select('*').eq('active', true).order('code');
  if (error) throw error;
  return (data || []).map(function (a) {
    return { id: a.id, code: a.code, name: a.name, type: a.type, isGroup: a.is_group, parentId: a.parent_id };
  });
};

api.addAccount = async function (session, payload) {
  const { data, error } = await supabaseClient.rpc('rpc_add_account', {
    p_name: payload.name, p_type: payload.type, p_parent_code: payload.parentCode || null, p_is_group: !!payload.isGroup, p_manual_code: payload.manualCode || null
  });
  if (error) throw error;
  return { success: true, code: data[0].code };
};

// ------------------------------------------------------------
// أرصدة أول مدة (Opening Balances)
// ------------------------------------------------------------

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
// نسب إدارة الشركاء (المستحقات)
// ------------------------------------------------------------
api.getAdminRights = async function () {
  const { data, error } = await supabaseClient.from('admin_rights').select('*, partners(name)').order('month_label', { ascending: false });
  if (error) throw error;
  return (data || []).map(function (r) {
    return { partnerName: r.partners ? r.partners.name : '', monthLabel: r.month_label, earned: r.earned, withdrawn: r.withdrawn, available: r.available };
  });
};

api.runMonthlyAdminFee = async function (session) {
  const { error } = await supabaseClient.rpc('rpc_run_monthly_admin_fee');
  if (error) throw error;
  return { success: true };
};

api.withdrawAdminRight = async function (session, partnerName, amount, treasuryAccountId) {
  const { error } = await supabaseClient.rpc('rpc_withdraw_admin_right', { p_partner_name: partnerName, p_amount: amount, p_treasury_account_id: treasuryAccountId || null });
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// الإيرادات الأخرى
// ------------------------------------------------------------
api.listOtherRevenue = async function (limit) {
  const { data, error } = await supabaseClient.from('other_revenue').select('*').order('revenue_date', { ascending: false }).limit(limit || 20);
  if (error) throw error;
  return (data || []).map(function (r) { return { id: r.id, source: r.source, description: r.description, amount: r.amount, date: r.revenue_date }; });
};

api.addOtherRevenue = async function (session, payload) {
  const { error } = await supabaseClient.rpc('rpc_add_other_revenue', {
    p_source: payload.source, p_amount: payload.amount, p_description: payload.description || '', p_treasury_account_id: payload.treasuryAccountId || null
  });
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// التقارير المحاسبية: ميزان المراجعة + الميزانية العمومية
// ------------------------------------------------------------
api.getTrialBalance = async function (startDate, endDate) {
  const { data, error } = await supabaseClient.rpc('rpc_trial_balance', { p_start_date: startDate || null, p_end_date: endDate });
  if (error) throw error;
  return data || { rows: [], totals: {}, balanced: true };
};

api.reparentSubcategory = async function (session, code, newParentCode) {
  const { error } = await supabaseClient.rpc('rpc_reparent_subcategory', { p_code: code, p_new_parent_code: newParentCode });
  if (error) throw error;
  return { success: true };
};

api.bulkMoveCategoryProducts = async function (session, oldCode, newCode) {
  const { data, error } = await supabaseClient.rpc('rpc_bulk_move_category_products', { p_old_sub_category_code: oldCode, p_new_sub_category_code: newCode });
  if (error) throw error;
  return { moved: data };
};

api.searchSalesByCode = async function (query) {
  const { data, error } = await supabaseClient.from('sales').select('*, sale_items(*, product_variants(code))')
    .or('sale_number.ilike.%' + query + '%,customer_name.ilike.%' + query + '%')
    .order('sale_date', { ascending: false }).limit(20);
  if (error) throw error;
  return (data || []).map(function (s) {
    return {
      saleId: s.sale_number, date: s.sale_date, source: s.source, total: s.total, status: s.status,
      paymentMethod: s.payment_method, customerName: s.customer_name,
      items: (s.sale_items || []).map(function (it) { return { variantCode: it.product_variants ? it.product_variants.code : '', qty: it.qty, price: it.unit_price }; })
    };
  });
};

api.getBalanceSheet = async function (asOfDate) {
  const { data, error } = await supabaseClient.rpc('rpc_balance_sheet', { p_as_of: asOfDate });
  if (error) throw error;
  return data;
};

// ------------------------------------------------------------
// الفترات المحاسبية (قفل/فتح)
// ------------------------------------------------------------
api.listAccountingPeriods = async function () {
  const { data, error } = await supabaseClient.from('accounting_periods').select('*').order('period_label', { ascending: false });
  if (error) throw error;
  return (data || []).map(function (p) { return { periodLabel: p.period_label, closed: p.closed, closedAt: p.closed_at }; });
};

api.closeAccountingPeriod = async function (session, periodLabel) {
  const { error } = await supabaseClient.rpc('rpc_close_period', { p_period_label: periodLabel });
  if (error) throw error;
  return { success: true };
};

api.reopenAccountingPeriod = async function (session, periodLabel) {
  const { error } = await supabaseClient.rpc('rpc_reopen_period', { p_period_label: periodLabel });
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// الأصول الثابتة والإهلاك
// ------------------------------------------------------------
api.listFixedAssets = async function () {
  const { data, error } = await supabaseClient.from('fixed_assets').select('*').order('acquired_at', { ascending: false });
  if (error) throw error;
  return (data || []).map(function (a) {
    return { id: a.id, description: a.description, amount: a.amount, acquiredAt: a.acquired_at, usefulLifeMonths: a.useful_life_months, accumulatedDepreciation: a.accumulated_depreciation, depreciationMethod: a.depreciation_method };
  });
};

api.runMonthlyDepreciation = async function (session) {
  const { error } = await supabaseClient.rpc('rpc_run_monthly_depreciation');
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// أرصدة أول مدة — الترحيل الفعلي لدفتر اليومية
// ------------------------------------------------------------
api.listOpeningBalances = async function () {
  const { data, error } = await supabaseClient.from('opening_balances').select('*, accounts(name)').order('created_at', { ascending: false });
  if (error) throw error;
  return (data || []).map(function (o) { return { id: o.id, accountName: o.accounts ? o.accounts.name : '', amount: o.amount, description: o.description, locked: o.locked, asOfDate: o.as_of_date }; });
};

api.addOpeningBalance = async function (session, payload) {
  const { error } = await supabaseClient.rpc('rpc_add_opening_balance', {
    p_account_id: payload.accountId, p_amount: payload.amount, p_description: payload.description || '', p_as_of_date: payload.asOfDate
  });
  if (error) throw error;
  return { success: true };
};

api.postOpeningBalances = async function (session) {
  const { error } = await supabaseClient.rpc('rpc_post_opening_balances');
  if (error) throw error;
  return { success: true };
};

// ------------------------------------------------------------
// تقرير مراكز التكلفة
// ------------------------------------------------------------
api.getCostCenterReport = async function (start, end) {
  const { data, error } = await supabaseClient.rpc('rpc_cost_center_report', { p_start: start, p_end: end });
  if (error) throw error;
  return data;
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

api.updateCheckStatus = async function (session, checkId, status, treasuryAccountId) {
  const { error } = await supabaseClient.rpc('rpc_update_check_status', { p_check_id: checkId, p_status: status, p_treasury_account_id: treasuryAccountId || null });
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
