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
    .select("user_id, permission, expires_at")
    .eq("document_id", documentId);
  if (permissionsError) throw permissionsError;
  const now = Date.now();
  const owner = data.owner_id === userId;
  const permission = (permissions ?? []).find(
    (item: { user_id: string; expires_at: string | null }) =>
      item.user_id === userId &&
      (!item.expires_at || new Date(item.expires_at).getTime() > now),
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

<<<<<<< HEAD
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
=======
async function revokeBorrowPermission(req: { document_id: string; requester_id: string }) {
  // Chỉ xóa quyền do mượn tạo ra, không đụng vào quyền chia sẻ thường.
  const { error } = await supabase.from("document_permissions").delete()
    .eq("document_id", req.document_id)
    .eq("user_id", req.requester_id)
    .eq("source", "borrow");
  if (error) throw error;
}

// Tự động thu hồi quyền khi hết hạn mượn.
async function expireBorrows() {
  const now = new Date().toISOString();
  const { data } = await supabase.from("borrow_requests")
    .select("id, document_id, requester_id")
    .eq("status", "approved").lte("borrow_until", now);
  for (const req of data ?? []) {
    await revokeBorrowPermission(req);
    await supabase.from("borrow_requests")
      .update({ status: "expired", updated_at: now }).eq("id", req.id);
>>>>>>> origin/main
  }
}

async function handle(request: Request) {
  const user = await authenticate(request);
  await ensureUser(user);
  await expireBorrows();
  const url = new URL(request.url);
  // Flutter gửi đường dẫn trong header x-api-path (có thể kèm ?query).
  const rawPath = request.headers.get("x-api-path") ??
    (url.pathname.replace(/^\/documents-api/, "").replace(/\/+$/, "") || "/");
  const [path, rawQuery] = rawPath.split("?");
  const params = new URLSearchParams(rawQuery ?? url.search);
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
    const query = params.get("q")?.trim() ?? "";
    const type = params.get("type");
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
        .select("document_id, user_id, permission, expires_at")
        .in("document_id", documentIds)
      : { data: [], error: null };
    if (permissionsError) throw permissionsError;
    const sharedIds = new Set(
      (permissions ?? [])
        .filter((permission: { user_id: string; expires_at: string | null }) =>
          permission.user_id === user.id &&
          (!permission.expires_at || new Date(permission.expires_at).getTime() > Date.now())
        )
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

  // ===== Mục 4: mượn tài liệu =====
  // Danh sách người đang được chia sẻ (chỉ chủ sở hữu)
  const shareListMatch = path.match(/^\/share\/([^/]+)$/);
  if (shareListMatch && method === "GET") {
    const access = await canAccess(user.id, shareListMatch[1]);
    if (!access.document || !access.owner) return json({ error: "Owner permission required" }, 403);
    const { data, error } = await supabase
      .from("document_permissions")
      .select("user_id, permission, source, expires_at, created_at")
      .eq("document_id", shareListMatch[1]);
    if (error) throw error;
    const ids = (data ?? []).map((row) => row.user_id);
    const { data: users } = ids.length
      ? await supabase.from("users").select("id, email, display_name").in("id", ids)
      : { data: [] };
    const byId = new Map((users ?? []).map((u) => [u.id, u]));
    return json((data ?? []).map((row) => ({
      ...row,
      email: byId.get(row.user_id)?.email ?? null,
      display_name: byId.get(row.user_id)?.display_name ?? null,
    })));
  }

  // Tài liệu của người khác mà mình chưa có quyền -> để gửi yêu cầu mượn
  if (method === "GET" && path === "/borrowable") {
    const { data: docs, error } = await supabase
      .from("documents").select("id, owner_id, title, description, type")
      .neq("owner_id", user.id).order("updated_at", { ascending: false });
    if (error) throw error;
    const ids = (docs ?? []).map((d) => d.id);
    const { data: perms } = ids.length
      ? await supabase.from("document_permissions")
        .select("document_id, expires_at").eq("user_id", user.id).in("document_id", ids)
      : { data: [] };
    const hasAccess = new Set((perms ?? [])
      .filter((p) => !p.expires_at || new Date(p.expires_at).getTime() > Date.now())
      .map((p) => p.document_id));
    const { data: pending } = await supabase.from("borrow_requests")
      .select("document_id").eq("requester_id", user.id).eq("status", "pending");
    const pendingIds = new Set((pending ?? []).map((r) => r.document_id));
    const owners = [...new Set((docs ?? []).map((d) => d.owner_id))];
    const { data: ownerRows } = owners.length
      ? await supabase.from("users").select("id, email, display_name").in("id", owners)
      : { data: [] };
    const ownerById = new Map((ownerRows ?? []).map((u) => [u.id, u]));
    return json((docs ?? [])
      .filter((d) => !hasAccess.has(d.id))
      .map((d) => ({
        ...d,
        owner_email: ownerById.get(d.owner_id)?.email ?? null,
        owner_name: ownerById.get(d.owner_id)?.display_name ?? null,
        pending: pendingIds.has(d.id),
      })));
  }

  // Gửi yêu cầu mượn
  if (method === "POST" && path === "/borrow") {
    const body = await request.json();
    const { data: document } = await supabase.from("documents")
      .select("id, owner_id, title").eq("id", body.document_id).maybeSingle();
    if (!document) return json({ error: "Document not found" }, 404);
    if (document.owner_id === user.id) return json({ error: "Bạn là chủ sở hữu tài liệu này" }, 400);
    const access = await canAccess(user.id, document.id);
    if (access.allowed) return json({ error: "Bạn đã có quyền truy cập tài liệu này" }, 400);
    const until = new Date(String(body.borrow_until));
    const maxMs = 30 * 24 * 60 * 60 * 1000;
    if (Number.isNaN(until.getTime()) || until.getTime() <= Date.now()) {
      return json({ error: "Thời hạn mượn phải ở tương lai" }, 400);
    }
    if (until.getTime() - Date.now() > maxMs) {
      return json({ error: "Thời hạn mượn tối đa 30 ngày" }, 400);
    }
    const { data, error } = await supabase.from("borrow_requests").insert({
      document_id: document.id,
      requester_id: user.id,
      owner_id: document.owner_id,
      message: body.message ? String(body.message).slice(0, 500) : null,
      borrow_until: until.toISOString(),
    }).select().single();
    if (error) {
      if (error.code === "23505") return json({ error: "Bạn đã gửi yêu cầu mượn tài liệu này rồi" }, 409);
      throw error;
    }
    return json(data);
  }

  // Danh sách yêu cầu: role=incoming (chủ sở hữu nhận) | outgoing (mình đã gửi)
  if (method === "GET" && path === "/borrow") {
    const role = params.get("role") === "incoming" ? "incoming" : "outgoing";
    const column = role === "incoming" ? "owner_id" : "requester_id";
    const { data, error } = await supabase.from("borrow_requests")
      .select("*").eq(column, user.id).order("created_at", { ascending: false });
    if (error) throw error;
    const docIds = [...new Set((data ?? []).map((r) => r.document_id))];
    const userIds = [...new Set((data ?? []).flatMap((r) => [r.requester_id, r.owner_id]))];
    const { data: docs } = docIds.length
      ? await supabase.from("documents").select("id, title").in("id", docIds) : { data: [] };
    const { data: us } = userIds.length
      ? await supabase.from("users").select("id, email, display_name").in("id", userIds) : { data: [] };
    const docById = new Map((docs ?? []).map((d) => [d.id, d]));
    const userById = new Map((us ?? []).map((u) => [u.id, u]));
    return json((data ?? []).map((r) => ({
      ...r,
      document_title: docById.get(r.document_id)?.title ?? "(đã xóa)",
      requester_email: userById.get(r.requester_id)?.email ?? null,
      owner_email: userById.get(r.owner_id)?.email ?? null,
    })));
  }

  // Phê duyệt / từ chối / trả
  const decisionMatch = path.match(/^\/borrow\/([^/]+)\/(approve|reject|return)$/);
  if (decisionMatch && method === "POST") {
    const [, requestId, action] = decisionMatch;
    const { data: req } = await supabase.from("borrow_requests")
      .select("*").eq("id", requestId).maybeSingle();
    if (!req) return json({ error: "Request not found" }, 404);
    const now = new Date().toISOString();

    if (action === "return") {
      if (req.requester_id !== user.id && req.owner_id !== user.id) {
        return json({ error: "Forbidden" }, 403);
      }
      if (req.status !== "approved") return json({ error: "Chỉ trả được yêu cầu đã duyệt" }, 409);
      await revokeBorrowPermission(req);
      const { error } = await supabase.from("borrow_requests")
        .update({ status: "returned", updated_at: now }).eq("id", requestId);
      if (error) throw error;
      return json({ ok: true });
    }

    if (req.owner_id !== user.id) return json({ error: "Owner permission required" }, 403);
    if (req.status !== "pending") return json({ error: "Yêu cầu đã được xử lý" }, 409);

    if (action === "reject") {
      const { error } = await supabase.from("borrow_requests")
        .update({ status: "rejected", decided_at: now, updated_at: now }).eq("id", requestId);
      if (error) throw error;
      return json({ ok: true });
    }

    // approve: cấp quyền viewer có thời hạn
    if (new Date(req.borrow_until).getTime() <= Date.now()) {
      return json({ error: "Yêu cầu đã quá hạn mượn" }, 409);
    }
    const { error: permError } = await supabase.from("document_permissions").upsert({
      document_id: req.document_id,
      user_id: req.requester_id,
      permission: "viewer",
      source: "borrow",
      expires_at: req.borrow_until,
    });
    if (permError) throw permError;
    const { error } = await supabase.from("borrow_requests")
      .update({ status: "approved", decided_at: now, updated_at: now }).eq("id", requestId);
    if (error) throw error;
    return json({ ok: true });
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
