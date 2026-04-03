// Safe Supabase client — gracefully handles missing package or env vars
// Auth strategy:
//   Development (no Supabase): checks VITE_ADMIN_EMAIL + VITE_ADMIN_PIN env vars
//   Production (Supabase configured): checks Supabase auth + app_metadata.role === 'admin'

let _supabase = null;
let _initialized = false;

async function getSupabase() {
  if (_initialized) return _supabase;
  _initialized = true;
  try {
    const { createClient } = await import("@supabase/supabase-js");
    const url = import.meta.env?.VITE_SUPABASE_URL || "";
    const key = import.meta.env?.VITE_SUPABASE_ANON_KEY || "";
    if (url && key) _supabase = createClient(url, key);
  } catch (e) {
    console.warn("[BirthdayMe] @supabase/supabase-js not available. Run: npm install");
  }
  return _supabase;
}

export async function signInAdmin(email, password) {
  const supabase = await getSupabase();

  // ── Development / pre-Supabase mode ──────────────────────────────────────
  // Reads from .env — never hardcoded in source. Safe to commit .env.example.
  // To use: set VITE_ADMIN_EMAIL and VITE_ADMIN_PIN in your .env file.
  if (!supabase) {
    const adminEmail = import.meta.env.VITE_ADMIN_EMAIL || "";
    const adminPin   = import.meta.env.VITE_ADMIN_PIN   || "";
    if (!adminEmail || !adminPin) {
      throw new Error(
        "Admin credentials not configured.\n\n" +
        "Add to your .env file:\n" +
        "VITE_ADMIN_EMAIL=your@email.com\n" +
        "VITE_ADMIN_PIN=yourpin"
      );
    }
    if (email.trim().toLowerCase() !== adminEmail.toLowerCase()) {
      throw new Error("Incorrect email address.");
    }
    if (password.trim() !== adminPin) {
      throw new Error("Incorrect PIN or password.");
    }
    // Return a mock user object matching the shape the app expects
    return {
      session: null,
      user: {
        id: "admin-root",
        email: adminEmail,
        app_metadata: { role: "admin" },
        user_metadata: { name: "Admin" },
      },
    };
  }

  // ── Production mode — Supabase auth ──────────────────────────────────────
  // Admin users must have app_metadata.role = "admin" set in Supabase dashboard.
  // To create an admin: Supabase Dashboard → Authentication → Users → Edit user
  // → Add to app_metadata: { "role": "admin" }
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw new Error(error.message);

  const role = data.user?.app_metadata?.role;
  if (role !== "admin") {
    await supabase.auth.signOut();
    throw new Error("Access denied. This account does not have admin privileges.");
  }
  return { session: data.session, user: data.user };
}

export async function signOutAdmin() {
  const supabase = await getSupabase();
  if (supabase) await supabase.auth.signOut();
}
