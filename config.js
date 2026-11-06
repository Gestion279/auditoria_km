/* Configuración de conexión — Auditoría de km
   SUPABASE_ANON_KEY: "anon public key" del proyecto, la misma de indicadores_gv/config.js
   (Supabase > Project Settings > API > Project API keys > anon public).
   Nunca pegues acá la service_role key. */
window.APP_CONFIG = {
  SUPABASE_URL: "https://oixzkvkybqexvrzwzwis.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9peHprdmt5YnFleHZyend6d2lzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg4NTUxNzEsImV4cCI6MjEwNDQzMTE3MX0.BTghtY8mZkyrK2y-kZXMb1aIecptX3OHOpNFqUBMzP4",
  // Tolerancia inicial para marcar desvíos (en %). Se puede cambiar en pantalla.
  TOLERANCIA_PCT: 15
};
