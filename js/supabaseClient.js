// ============================================================
// supabaseClient.js
// إعداد الاتصال بمشروع Supabase
// بعد ما تعملي مشروع على supabase.com، هتلاقي القيم دي في:
// Project Settings → API
// ============================================================

const SUPABASE_URL = 'https://krqmpnputyatfnphuzmm.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_b0E_u0rLbzZX15O9JZVNpA_BAZMbPr0';

const supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
