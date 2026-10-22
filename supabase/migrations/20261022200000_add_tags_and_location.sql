-- Migration: Bổ sung tags và vị trí cho bảng documents
-- Người đề xuất: Nguyễn Khắc Minh Hiếu (Checklist 2 & 3)
-- Người duyệt: Lục Văn Thuận (Nhóm trưởng)

-- 1. Bổ sung trường tags (mảng text)
alter table public.documents 
add column if not exists tags text[] default '{}'::text[];

-- 2. Bổ sung địa chỉ lưu trữ vật lý (sách, giáo trình in, phòng học, kệ thư viện)
alter table public.documents 
add column if not exists physical_address text;

-- 3. Bổ sung tọa độ vị trí (latitude, longitude) để hiển thị trên bản đồ
alter table public.documents 
add column if not exists latitude double precision;

alter table public.documents 
add column if not exists longitude double precision;

-- 4. Tạo index hỗ trợ tìm kiếm nhanh theo tags bằng GIN
create index if not exists idx_documents_tags on public.documents using gin(tags);
