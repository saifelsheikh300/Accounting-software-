// Service Worker بسيط عشان يخلي البرنامج "قابل للتثبيت" على الموبايل
// (مش بيعمل تخزين مؤقت للملفات دلوقتي — النظام محتاج اتصال إنترنت شغال
// لأنه بيتكلم مع Supabase على طول)
self.addEventListener('install', function (e) { self.skipWaiting(); });
self.addEventListener('activate', function (e) { self.clients.claim(); });
self.addEventListener('fetch', function (e) {
  e.respondWith(fetch(e.request));
});
