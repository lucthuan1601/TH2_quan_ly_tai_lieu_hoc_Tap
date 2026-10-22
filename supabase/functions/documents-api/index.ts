import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { decodeProtectedHeader, importX509, importPKCS8, jwtVerify, SignJWT } from "npm:jose@5.10.0";

const projectId = Deno.env.get("FIREBASE_PROJECT_ID")!;
const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  serviceRole,
);

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type, x-firebase-token, x-api-path",
  "access-control-allow-methods": "GET, POST, DELETE, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });

async function authenticate(request: Request) {
  const token = request.headers.get("x-firebase-token") ??
    request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) throw new Error("Missing Firebase token");
  const certs = await fetch(
    "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com",
  ).then((response) => response.json());
  const header = decodeProtectedHeader(token);
  const certificate = certs[header.kid];
  if (!certificate) throw new Error("Unknown Firebase signing key");
  const key = await importX509(certificate, "RS256");
  const { payload } = await jwtVerify(token, key, {
    issuer: `https://securetoken.google.com/${projectId}`,
    audience: projectId,
  });
  if (typeof payload.sub !== "string" || payload.sub.length === 0) {
    throw new Error("Invalid Firebase subject");
  }
  return {
    id: payload.sub,
    email: typeof payload.email === "string" ? payload.email : null,
    name: typeof payload.name === "string" ? payload.name : null,
    picture: typeof payload.picture === "string" ? payload.picture : null,
  };
}

async function ensureUser(user: { id: string; email: string | null; name: string | null; picture: string | null }) {
  const { error } = await supabase.from("users").upsert({
    id: user.id,
    email: user.email,
    display_name: user.name,
    avatar_url: user.picture,
    updated_at: new Date().toISOString(),
  });
  if (error) throw error;
}

async function canAccess(userId: string, documentId: string, edit = false) {
  const { data, error } = await supabase
    .from("documents")
    .select("*")
    .eq("id", documentId)
    .maybeSingle();
  if (error) throw error;
  if (!data) return { document: null, allowed: false, owner: false };
  const { data: permissions, error: permissionsError } = await supabase
    .from("document_permissions")
    .select("user_id, permission")
    .eq("document_id", documentId);
  if (permissionsError) throw permissionsError;
  const owner = data.owner_id === userId;
  const permission = (permissions ?? []).find(
    (item: { user_id: string }) => item.user_id === userId,
  )?.permission;
  return {
    document: data,
    owner,
    allowed: owner || permission === "editor" || (!edit && permission === "viewer"),
  };
}

function storageSignedUrl(path: string) {
  return supabase.storage.from("documents").createSignedUrl(path, 900)
    .then(({ data, error }) => {
      if (error) throw error;
      return data.signedUrl;
    });
}

function normalizeTags(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.filter((tag): tag is string => typeof tag === "string")
    .map((tag) => tag.trim().toLowerCase()).filter((tag) => tag.length > 0 && tag.length <= 40))].slice(0, 20);
}

async function sendFcm(userId: string, title: string, documentId: string) {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!raw) return;
  const account = JSON.parse(raw);
  const key = await importPKCS8(account.private_key, "RS256");
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256" }).setIssuer(account.client_email)
    .setAudience("https://oauth2.googleapis.com/token").setIssuedAt(now)
    .setExpirationTime(now + 3600).sign(key);
  const oauth = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!oauth.ok) throw new Error(`FCM OAuth failed: ${oauth.status}`);
  const { access_token } = await oauth.json();
  const { data: tokens, error } = await supabase.from("user_fcm_tokens").select("token").eq("user_id", userId);
  if (error) throw error;
  for (const { token } of tokens ?? []) {
    const response = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
      method: "POST",
      headers: { authorization: `Bearer ${access_token}`, "content-type": "application/json" },
      body: JSON.stringify({ message: { token, notification: { title, body: "Mở ứng dụng để xem tài liệu." }, data: { document_id: documentId } } }),
    });
    if (response.status === 404) await supabase.from("user_fcm_tokens").delete().eq("token", token);
    else if (!response.ok) console.error("FCM send failed", response.status);
  }
}

async function handle(request: Request) {
  const user = await authenticate(request);
  await ensureUser(user);
  const url = new URL(request.url);
  const path = request.headers.get("x-api-path") ??
    (url.pathname.replace(/^\/documents-api/, "").replace(/\/+$/, "") || "/");
  const method = request.method;

  if (method === "POST" && path === "/fcm-token") {
    const body = await request.json();
    if (typeof body.token !== "string" || body.token.length < 20 || body.token.length > 4096) return json({ error: "Invalid FCM token" }, 400);
    const { error } = await supabase.from("user_fcm_tokens").upsert({ token: body.token, user_id: user.id, updated_at: new Date().toISOString() });
    if (error) throw error;
    return json({ ok: true });
  }
  if (method === "DELETE" && path === "/fcm-token") {
    const body = await request.json();
    if (typeof body.token !== "string") return json({ error: "Invalid FCM token" }, 400);
    const { error } = await supabase.from("user_fcm_tokens").delete().eq("token", body.token).eq("user_id", user.id);
    if (error) throw error;
    return json({ ok: true });
  }

  if (method === "GET" && path === "/recommendations") {
    const { data: documents, error } = await supabase.from("documents").select("*").order("updated_at", { ascending: false });
    if (error) throw error;
    const ids = (documents ?? []).map((document) => document.id);
    if (!ids.length) return json([]);
    const [permissionsResult, tagsResult, historyResult] = await Promise.all([
      supabase.from("document_permissions").select("document_id").eq("user_id", user.id).in("document_id", ids),
      supabase.from("document_tags").select("document_id,tag").in("document_id", ids),
      supabase.from("document_interactions").select("document_id,action,created_at").eq("user_id", user.id).order("created_at", { ascending: false }).limit(500),
    ]);
    if (permissionsResult.error) throw permissionsResult.error;
    if (tagsResult.error) throw tagsResult.error;
    if (historyResult.error) throw historyResult.error;
    const shared = new Set((permissionsResult.data ?? []).map((row) => row.document_id));
    const tags = new Map<string, string[]>();
    for (const row of tagsResult.data ?? []) tags.set(row.document_id, [...(tags.get(row.document_id) ?? []), row.tag]);
    const weights: Record<string, number> = { view: 1, search: 1, save: 3, borrow: 4 };
    const preferences = new Map<string, number>();
    const viewed = new Set<string>();
    for (const item of historyResult.data ?? []) {
      if (item.action === "view") viewed.add(item.document_id);
      for (const tag of tags.get(item.document_id) ?? []) preferences.set(tag, (preferences.get(tag) ?? 0) + weights[item.action]);
    }
    return json((documents ?? [])
      .filter((document) => document.owner_id === user.id || shared.has(document.id))
      .map((document) => ({ ...document, tags: tags.get(document.id) ?? [], score: (tags.get(document.id) ?? []).reduce((sum, tag) => sum + (preferences.get(tag) ?? 0), 0) - (viewed.has(document.id) ? 2 : 0) }))
      .sort((a, b) => b.score - a.score || b.updated_at.localeCompare(a.updated_at)).slice(0, 20));
  }

  if (method === "POST" && path === "/interactions") {
    const body = await request.json();
    if (!["view", "search", "save", "borrow"].includes(body.action)) return json({ error: "Invalid action" }, 400);
    const access = await canAccess(user.id, String(body.document_id));
    if (!access.allowed) return json({ error: "Access denied" }, 403);
    const { error } = await supabase.from("document_interactions").insert({ user_id: user.id, document_id: body.document_id, action: body.action });
    if (error) throw error;
    return json({ ok: true });
  }

  const tagsMatch = path.match(/^\/documents\/([^/]+)\/tags$/);
  if (method === "GET" && tagsMatch) {
    const access = await canAccess(user.id, tagsMatch[1]);
    if (!access.allowed) return json({ error: "Access denied" }, 403);
    const { data, error } = await supabase.from("document_tags").select("tag").eq("document_id", tagsMatch[1]);
    if (error) throw error;
    return json((data ?? []).map((row) => row.tag));
  }

  if (method === "GET" && path === "/documents") {
    const query = url.searchParams.get("q")?.trim() ?? "";
    const type = url.searchParams.get("type");
    let requestQuery = supabase
      .from("documents")
      .select("*")
      .order("updated_at", { ascending: false });
    if (type) requestQuery = requestQuery.eq("type", type);
    const { data, error } = await requestQuery;
    if (error) throw error;
    const documentIds = (data ?? []).map((document) => document.id);
    const { data: permissions, error: permissionsError } = documentIds.length
      ? await supabase
        .from("document_permissions")
        .select("document_id, user_id, permission")
        .in("document_id", documentIds)
      : { data: [], error: null };
    if (permissionsError) throw permissionsError;
    const sharedIds = new Set(
      (permissions ?? [])
        .filter((permission: { user_id: string }) => permission.user_id === user.id)
        .map((permission: { document_id: string }) => permission.document_id),
    );
    const visible = (data ?? []).filter((document) => {
      const shared = sharedIds.has(document.id);
      const text = `${document.title} ${document.description ?? ""} ${document.file_name ?? ""}`.toLocaleLowerCase();
      return (document.owner_id === user.id || shared) &&
        (!query || text.includes(query.toLocaleLowerCase()));
    });
    return json(visible);
  }

  if (method === "POST" && path === "/documents") {
    const body = await request.json();
    const id = body.id ?? crypto.randomUUID();
    const existing = await canAccess(user.id, id, true);
    if (existing.document && !existing.allowed) {
      return json({ error: "Editor permission required" }, 403);
    }
    const { data, error } = await supabase.from("documents").upsert({
      id,
      owner_id: existing.document?.owner_id ?? user.id,
      title: String(body.title).trim(),
      description: body.description ?? null,
      type: body.type,
      storage_path: body.storage_path ?? null,
      file_name: body.file_name ?? null,
      mime_type: body.mime_type ?? null,
      size_bytes: body.size_bytes ?? null,
      updated_at: new Date().toISOString(),
    }).select().single();
    if (error) throw error;
    if (body.tags !== undefined) {
      const tags = normalizeTags(body.tags);
      const { error: deleteError } = await supabase.from("document_tags").delete().eq("document_id", id);
      if (deleteError) throw deleteError;
      if (tags.length) {
        const { error: tagError } = await supabase.from("document_tags").insert(tags.map((tag) => ({ document_id: id, tag })));
        if (tagError) throw tagError;
      }
    }
    return json(data);
  }

  const uploadMatch = path.match(/^\/documents\/([^/]+)\/file$/);
  if (uploadMatch && method === "POST") {
    const access = await canAccess(user.id, uploadMatch[1], true);
    if (access.document && !access.owner && !access.allowed) {
      return json({ error: "Editor permission required" }, 403);
    }
    const body = await request.json();
    const fileName = String(body.file_name ?? "file");
    const safeName = fileName.replace(/[^a-zA-Z0-9._-]/g, "_");
    const storagePath = `${access.document?.owner_id ?? user.id}/${uploadMatch[1]}/${safeName}`;
    const bytes = Uint8Array.from(atob(String(body.base64)), (char) => char.charCodeAt(0));
    const { error } = await supabase.storage.from("documents").upload(
      storagePath,
      bytes,
      { contentType: body.mime_type ?? "application/octet-stream", upsert: true },
    );
    if (error) throw error;
    return json({ storage_path: storagePath });
  }

  const removeMatch = path.match(/^\/documents\/([^/]+)\/file$/);
  if (removeMatch && method === "DELETE") {
    const access = await canAccess(user.id, removeMatch[1], true);
    if (!access.document || !access.allowed) return json({ error: "Editor permission required" }, 403);
    if (access.document.storage_path) {
      const { error } = await supabase.storage.from("documents")
        .remove([access.document.storage_path]);
      if (error) throw error;
    }
    return json({ ok: true });
  }

  const documentMatch = path.match(/^\/documents\/([^/]+)$/);
  if (documentMatch && method === "DELETE") {
    const access = await canAccess(user.id, documentMatch[1], true);
    if (!access.document || !access.allowed) return json({ error: "Editor permission required" }, 403);
    const { error } = await supabase.from("documents").delete().eq("id", documentMatch[1]);
    if (error) throw error;
    return json({ ok: true });
  }

  if (method === "POST" && path === "/share") {
    const body = await request.json();
    const access = await canAccess(user.id, body.document_id, true);
    if (!access.document || !access.allowed) return json({ error: "Editor permission required" }, 403);
    const email = String(body.email ?? "").trim().toLowerCase();
    if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return json({ error: "A valid recipient email is required" }, 400);
    }
    if (!["viewer", "editor"].includes(body.permission)) return json({ error: "Invalid permission" }, 400);
    const { data: recipient } = await supabase
      .from("users")
      .select("id, email")
      .ilike("email", email)
      .maybeSingle();
    if (!recipient) return json({ error: "Recipient must sign in before sharing" }, 404);
    if (recipient.id === user.id) return json({ error: "You cannot share with yourself" }, 400);
    const { error } = await supabase.from("document_permissions").upsert({
      document_id: body.document_id,
      user_id: recipient.id,
      permission: body.permission,
    });
    if (error) throw error;
    try { await sendFcm(recipient.id, "Tài liệu được chia sẻ", body.document_id); } catch (notificationError) { console.error(notificationError); }
    return json({ ok: true });
  }

  const shareMatch = path.match(/^\/share\/([^/]+)\/([^/]+)$/);
  if (shareMatch && method === "DELETE") {
    const access = await canAccess(user.id, shareMatch[1], true);
    if (!access.document || !access.owner) return json({ error: "Owner permission required" }, 403);
    const { error } = await supabase.from("document_permissions")
      .delete().eq("document_id", shareMatch[1]).eq("user_id", shareMatch[2]);
    if (error) throw error;
    return json({ ok: true });
  }

  const fileMatch = path.match(/^\/documents\/([^/]+)\/file-url$/);
  if (fileMatch && method === "GET") {
    const access = await canAccess(user.id, fileMatch[1]);
    if (!access.document?.storage_path || !access.allowed) return json({ error: "Access denied" }, 403);
    return json({ url: await storageSignedUrl(access.document.storage_path) });
  }
  return json({ error: "Not found" }, 404);
}

Deno.serve(async (request) => {
  try {
    if (request.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }
    return await handle(request);
  } catch (error) {
    console.error(error);
    return json(
      { error: error instanceof Error ? error.message : "Request failed" },
      500,
    );
  }
});
