#!/usr/bin/env node
const fs   = require('fs');
const path = require('path');

const HTML_PATH = path.join(__dirname, '../src/index.html');

const url     = process.env.SUPABASE_URL     || '';
const anonKey = process.env.SUPABASE_ANON_KEY || '';

if (!url || !anonKey) {
  console.warn('WARNING: SUPABASE_URL or SUPABASE_ANON_KEY not set — skipping injection.');
  process.exit(0);  // exit 0 so build doesn't fail
}

let html = fs.readFileSync(HTML_PATH, 'utf8');

html = html.replace(
  "window.__TICKR_SUPABASE_URL__ || ''",
  JSON.stringify(url)
);
html = html.replace(
  "window.__TICKR_SUPABASE_ANON_KEY__ || ''",
  JSON.stringify(anonKey)
);

fs.writeFileSync(HTML_PATH, html);
console.log('✓ Supabase config injected into src/index.html');
