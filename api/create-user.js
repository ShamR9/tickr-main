// api/create-user.js
// Vercel serverless function — creates a Supabase auth user (admin only)
// Called from the Users management UI when admin creates a new organiser

import { createClient } from '@supabase/supabase-js';

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // Verify the caller is an authenticated admin
  const authHeader = req.headers.authorization || '';
  const callerToken = authHeader.replace('Bearer ', '');
  if (!callerToken) {
    return res.status(401).json({ error: 'Unauthorised' });
  }

  // Admin client uses SERVICE ROLE key — never expose this to the browser
  const adminClient = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY
  );

  // Verify caller is an admin by checking their profile
  const userClient = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_ANON_KEY,
    { global: { headers: { Authorization: `Bearer ${callerToken}` } } }
  );
  const { data: { user: caller } } = await userClient.auth.getUser();
  if (!caller) return res.status(401).json({ error: 'Invalid session' });

  const { data: profile } = await adminClient
    .from('profiles')
    .select('role')
    .eq('id', caller.id)
    .single();

  if (!profile || profile.role !== 'admin') {
    return res.status(403).json({ error: 'Admin access required' });
  }

  // Create the new user
  const { email, password, meta } = req.body;
  if (!email || !password) {
    return res.status(400).json({ error: 'email and password required' });
  }

  const { data, error } = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,   // skip email verification
    user_metadata: {
      username: meta?.username || email.split('@')[0],
      name:     meta?.name    || '',
      role:     'organiser'
    }
  });

  if (error) return res.status(400).json({ error: error.message });

  // Update profile with bank details if provided
  if (meta?.bank_name || meta?.bank_account) {
    await adminClient.from('profiles').update({
      bank_name:    meta.bank_name    || '',
      bank_account: meta.bank_account || '',
      bank_holder:  meta.bank_holder  || '',
      phone:        meta.phone        || ''
    }).eq('id', data.user.id);
  }

  return res.status(200).json({ ok: true, userId: data.user.id });
}
