-- ============================================
-- HELPER: is the current user an admin?
-- ============================================
create function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- ============================================
-- PROFILES
-- ============================================
alter table public.profiles enable row level security;

create policy "Users can view their own profile"
  on public.profiles for select
  using (auth.uid() = id or public.is_admin());

create policy "Users can update their own profile"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id and role = 'customer'); -- can't self-promote to admin

create policy "Admins can update any profile"
  on public.profiles for update
  using (public.is_admin());

-- No insert policy needed — the trigger (security definer) handles profile creation.
-- No delete policy — profiles are deleted via cascade when auth.users is deleted.

-- ============================================
-- ADDRESSES
-- ============================================
alter table public.addresses enable row level security;

create policy "Users manage their own addresses"
  on public.addresses for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Admins view all addresses"
  on public.addresses for select
  using (public.is_admin());

-- ============================================
-- VENDORS (admin-only, not customer-facing)
-- ============================================
alter table public.vendors enable row level security;

create policy "Only admins access vendors"
  on public.vendors for all
  using (public.is_admin())
  with check (public.is_admin());

-- ============================================
-- CATEGORIES (public read, admin write)
-- ============================================
alter table public.categories enable row level security;

create policy "Anyone can view categories"
  on public.categories for select
  using (true);

create policy "Only admins modify categories"
  on public.categories for insert
  with check (public.is_admin());

create policy "Only admins update categories"
  on public.categories for update
  using (public.is_admin());

create policy "Only admins delete categories"
  on public.categories for delete
  using (public.is_admin());

-- ============================================
-- PRODUCTS (public read active items, admin full access)
-- ============================================
alter table public.products enable row level security;

create policy "Anyone can view active products"
  on public.products for select
  using (is_active = true or public.is_admin());

create policy "Only admins insert products"
  on public.products for insert
  with check (public.is_admin());

create policy "Only admins update products"
  on public.products for update
  using (public.is_admin());

create policy "Only admins delete products"
  on public.products for delete
  using (public.is_admin());

-- ============================================
-- PRODUCT IMAGES (follows product visibility)
-- ============================================
alter table public.product_images enable row level security;

create policy "Anyone can view images of visible products"
  on public.product_images for select
  using (
    public.is_admin()
    or exists (
      select 1 from public.products
      where products.id = product_images.product_id
        and products.is_active = true
    )
  );

create policy "Only admins manage product images"
  on public.product_images for insert
  with check (public.is_admin());

create policy "Only admins update product images"
  on public.product_images for update
  using (public.is_admin());

create policy "Only admins delete product images"
  on public.product_images for delete
  using (public.is_admin());

-- ============================================
-- REVIEWS
-- ============================================
alter table public.reviews enable row level security;

create policy "Anyone can view reviews"
  on public.reviews for select
  using (true);

create policy "Users can create their own reviews"
  on public.reviews for insert
  with check (auth.uid() = user_id);

create policy "Users can update their own reviews"
  on public.reviews for update
  using (auth.uid() = user_id);

create policy "Users can delete their own reviews"
  on public.reviews for delete
  using (auth.uid() = user_id or public.is_admin());

-- ============================================
-- WISHLISTS
-- ============================================
alter table public.wishlists enable row level security;

create policy "Users manage their own wishlist"
  on public.wishlists for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ============================================
-- ORDERS
-- ============================================
alter table public.orders enable row level security;

create policy "Users view their own orders"
  on public.orders for select
  using (auth.uid() = user_id or public.is_admin());

-- Orders are created via a server-side function/route using the service role,
-- not directly from the client — so no client-facing insert policy.
-- This prevents customers from crafting arbitrary "orders" with fake totals.

create policy "Only admins update orders"
  on public.orders for update
  using (public.is_admin());

-- No delete policy for anyone — orders are never hard-deleted, only status-changed.

-- ============================================
-- ORDER ITEMS
-- ============================================
alter table public.order_items enable row level security;

create policy "Users view items from their own orders"
  on public.order_items for select
  using (
    public.is_admin()
    or exists (
      select 1 from public.orders
      where orders.id = order_items.order_id
        and orders.user_id = auth.uid()
    )
  );

-- Inserted only via the server-side checkout function (service role). No client insert policy.

-- ============================================
-- SUPPORT TICKETS
-- ============================================
alter table public.support_tickets enable row level security;

create policy "Users view their own tickets"
  on public.support_tickets for select
  using (auth.uid() = user_id or public.is_admin());

create policy "Users create their own tickets"
  on public.support_tickets for insert
  with check (auth.uid() = user_id);

create policy "Users update their own open tickets"
  on public.support_tickets for update
  using (auth.uid() = user_id or public.is_admin());

-- ============================================
-- SUPPORT MESSAGES
-- ============================================
alter table public.support_messages enable row level security;

create policy "Participants view ticket messages"
  on public.support_messages for select
  using (
    public.is_admin()
    or exists (
      select 1 from public.support_tickets
      where support_tickets.id = support_messages.ticket_id
        and support_tickets.user_id = auth.uid()
    )
  );

create policy "Participants send ticket messages"
  on public.support_messages for insert
  with check (
    sender_id = auth.uid()
    and (
      public.is_admin()
      or exists (
        select 1 from public.support_tickets
        where support_tickets.id = support_messages.ticket_id
          and support_tickets.user_id = auth.uid()
      )
    )
  );

-- ============================================
-- PROMO CODES (admin-managed, but customers need to validate one at checkout)
-- ============================================
alter table public.promo_codes enable row level security;

create policy "Anyone can check an active promo code"
  on public.promo_codes for select
  using (is_active = true or public.is_admin());

create policy "Only admins manage promo codes"
  on public.promo_codes for insert
  with check (public.is_admin());

create policy "Only admins update promo codes"
  on public.promo_codes for update
  using (public.is_admin());

create policy "Only admins delete promo codes"
  on public.promo_codes for delete
  using (public.is_admin());

-- ============================================
-- FLASH SALES (public read, admin write)
-- ============================================
alter table public.flash_sales enable row level security;

create policy "Anyone views active flash sales"
  on public.flash_sales for select
  using (true);

create policy "Only admins manage flash sales"
  on public.flash_sales for insert
  with check (public.is_admin());

create policy "Only admins update flash sales"
  on public.flash_sales for update
  using (public.is_admin());

create policy "Only admins delete flash sales"
  on public.flash_sales for delete
  using (public.is_admin());

alter table public.flash_sale_products enable row level security;

create policy "Anyone views flash sale products"
  on public.flash_sale_products for select
  using (true);

create policy "Only admins manage flash sale products"
  on public.flash_sale_products for all
  using (public.is_admin())
  with check (public.is_admin());

-- ============================================
-- STORE SETTINGS (admin-only)
-- ============================================
alter table public.store_settings enable row level security;

create policy "Only admins access store settings"
  on public.store_settings for all
  using (public.is_admin())
  with check (public.is_admin());