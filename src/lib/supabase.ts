import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabasePublishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

export const isSupabaseConfigured = Boolean(supabaseUrl && supabasePublishableKey)

// Placeholders keep the app renderable before local configuration is provided.
// They are not credentials and must not be used to make requests.
export const supabase = createClient(
  supabaseUrl || 'https://configuration-required.supabase.co',
  supabasePublishableKey || 'configuration-required',
  { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } },
)
