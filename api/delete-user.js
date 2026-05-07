// api/delete-user.js
// Vercel serverless function — deletes a Supabase auth user (admin only)

import { createClient } from '@supabase/supabase-js';

export default async function handler(req, res) {
  if (req.method !== 'DELETE') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const authHeader = req.headers.authorization || '';
  const callerToken = authHeader.replace('Bearer ', '');
  if (!callerToken) return res.status(401).json({ error: 'Unauthorised' });

  const adminClient = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY
  );
  const userClient = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_ANON_KEY,
    { global: { headers: { Authorization: `Bearer ${callerToken}` } } }
  );

  const { data: { user: caller } } = await userClient.auth.getUser();
  if (!caller) return res.status(401).json({ error: 'Invalid session' });

  const { data: profile } = await adminClient
    .from('profiles').select('role').eq('id', caller.id).single();
  if (!profile || profile.role !== 'admin') {
    return res.status(403).json({ error: 'Admin access required' });
  }

  const { userId } = req.body;
  if (!userId) return res.status(400).json({ error: 'userId required' });

  const { error } = await adminClient.auth.admin.deleteUser(userId);
  if (error) return res.status(400).json({ error: error.message });

  return res.status(200).json({ ok: true });
}
