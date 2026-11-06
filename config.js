/* Configuración de conexión — Auditoría de km
   SUPABASE_ANON_KEY: copiá la misma "anon public key" que usa indicadores_gv/config.js
   (Supabase > Project Settings > API > Project API keys > anon public).
   Nunca pegues acá la service_role key. */
window.APP_CONFIG = {
  SUPABASE_URL: "https://oixzkvkybqexvrzwzwis.supabase.co",
  SUPABASE_ANON_KEY: "PEGAR_ACA_TU_ANON_KEY",
  // Tolerancia inicial para marcar desvíos (en %). Se puede cambiar en pantalla.
  TOLERANCIA_PCT: 15
};
