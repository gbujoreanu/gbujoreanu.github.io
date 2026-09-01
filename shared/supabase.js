(function () {
  "use strict";

  const projectUrl = "https://fciurxzxdkaznxcvciry.supabase.co";
  const publishableKey = "sb_publishable_X3PwTE-Mfe2iIhhTZS5N6g_sp3sul9J";

  if (!window.supabase?.createClient) {
    console.error("Supabase could not be loaded.");
    return;
  }

  window.AppAuth = {
    client: window.supabase.createClient(projectUrl, publishableKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true
      }
    })
  };
})();
