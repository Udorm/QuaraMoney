// delete-account — App Store Guideline 5.1.1(v): users must be able to delete
// their account from inside the app.
//
// Auth: invoked by the signed-in user (supabase-swift attaches the JWT). The
// target user is ALWAYS resolved from that JWT — the client cannot pass an id.
// Deletion order: storage objects first (no FK cascade covers Storage), then
// the auth user, which cascades to every public.* table via
// `references auth.users(id) on delete cascade`.
import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "unauthorized" }, 401);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  );

  const { data: userData, error: userError } = await admin.auth.getUser(jwt);
  if (userError || !userData?.user) return json({ error: "unauthorized" }, 401);
  const uid = userData.user.id;

  // 1. Remove everything under receipts/{uid}/ (receipts + profile avatar).
  //    `list` is per-folder, so walk subfolders recursively.
  async function deleteFolder(prefix: string): Promise<void> {
    const { data: entries, error } = await admin.storage
      .from("receipts")
      .list(prefix, { limit: 1000 });
    if (error || !entries) return;
    const files = entries.filter((e) => e.id !== null).map((e) => `${prefix}/${e.name}`);
    if (files.length > 0) await admin.storage.from("receipts").remove(files);
    for (const folder of entries.filter((e) => e.id === null)) {
      await deleteFolder(`${prefix}/${folder.name}`);
    }
  }
  await deleteFolder(uid);

  // 2. Delete the auth user; public.* rows cascade.
  const { error: deleteError } = await admin.auth.admin.deleteUser(uid);
  if (deleteError) return json({ error: deleteError.message }, 500);

  return json({ success: true }, 200);
});

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
