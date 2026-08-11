// Edge Function: delete-employee
// بتمسح حساب الـ Auth بتاع الموظف، وده بيسحب معاه تلقائيًا (on delete cascade)
// صف profiles بتاعه. بس لو الطالب أدمن أو عنده صلاحية "تعديل" على قسم
// المستخدمين (Users)، ومتقدرش تمسحي حسابك بنفسك.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) throw new Error("لازم تكوني مسجلة دخول");

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userErr } = await callerClient.auth.getUser();
    if (userErr || !user) throw new Error("جلسة الدخول مش صحيحة");

    const adminClient = createClient(supabaseUrl, serviceKey);

    const { data: callerProfile } = await adminClient
      .from("profiles")
      .select("role, permissions")
      .eq("id", user.id)
      .single();

    const canManageUsers = callerProfile && (
      callerProfile.role === "أدمن" ||
      (callerProfile.permissions && callerProfile.permissions["Users"] === "تعديل")
    );
    if (!canManageUsers) throw new Error("مسموح للأدمن أو اللي عنده صلاحية إدارة المستخدمين بس");

    const { employee_id } = await req.json();
    if (!employee_id) throw new Error("لازم تحددي المستخدم اللي هيتمسح");
    if (employee_id === user.id) throw new Error("متقدريش تمسحي حسابك بنفسك");

    const { error: deleteErr } = await adminClient.auth.admin.deleteUser(employee_id);
    if (deleteErr) throw new Error(deleteErr.message);

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: e.message }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
